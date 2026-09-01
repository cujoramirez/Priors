//
//  AudioManager.swift
//  Priors
//
//  5-Layer interactive stem decay engine for the village phase.
//  SPEC §8.1 & NOTES-audio.md.
//

import Foundation
import AVFoundation
import CoreGraphics

/// The five distinct musical layers composing the village soundscape (SPEC §8.1).
public enum AudioStem: String, CaseIterable, Sendable {
    case bells
    case perc
    case melody
    case bass
    case pad
}

/// Manages multi-track synchronized stem playback, procedural synthesis in D Dorian at 84 BPM,
/// and monotonic one-way stem removal driven by posterior uncertainty (mean posterior SD).
public final class AudioManager: @unchecked Sendable {
    public static let shared = AudioManager()

    // MARK: - Constants
    public static let masterTempoBPM: Double = 84.0
    public static let loopBarCount: Int = 16
    public static let sampleRate: Double = 48000.0
    public static let channelCount: AVAudioChannelCount = 2
    public static let loopSampleCount: AVAudioFrameCount = 2_194_286 // 16 bars @ 84 BPM at 48kHz
    public static let fadeDurationSeconds: Double = 2.5 // 2,500 ms equal-power cosine fade

    // MARK: - Audio Engine Properties
    private let engine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    private var playerNodes: [AudioStem: AVAudioPlayerNode] = [:]
    private var stemBuffers: [AudioStem: AVAudioPCMBuffer] = [:]

    // MARK: - State
    public private(set) var currentStep: Int = 0
    public private(set) var highestStepReached: Int = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var mutedStems: Set<AudioStem> = []
    public private(set) var stemVolumes: [AudioStem: Float] = [
        .bells: 1.0,
        .perc: 1.0,
        .melody: 1.0,
        .bass: 1.0,
        .pad: 1.0
    ]

    private let stateLock = NSLock()
    private var activeFadeTasks: [AudioStem: Task<Void, Never>] = [:]

    public init() {
        setupAudioSession()
        setupEngine()
        prepareBuffers()
    }

    deinit {
        stop()
    }

    // MARK: - Audio Session & Engine Configuration

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            print("[AudioManager] AVAudioSession configuration failed: \(error)")
        }
        #endif
    }

    private func setupEngine() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: false
        ) else {
            return
        }

        engine.attach(mixerNode)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: format)

        for stem in AudioStem.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixerNode, format: format)
            playerNodes[stem] = player
            player.volume = 1.0
        }

        engine.prepare()
    }

    // MARK: - Buffer Preparation & Procedural Synthesis

    public func prepareBuffers() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: false
        ) else {
            return
        }

        for stem in AudioStem.allCases {
            if let bundledBuffer = loadBundledStem(stem: stem, format: format) {
                stemBuffers[stem] = bundledBuffer
            } else {
                stemBuffers[stem] = generateProceduralStem(stem: stem, format: format)
            }
        }
    }

    private func loadBundledStem(stem: AudioStem, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let extensions = ["caf", "wav", "m4a", "aif"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: stem.rawValue, withExtension: ext) {
                if let file = try? AVAudioFile(forReading: url),
                   let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) {
                    try? file.read(into: buffer)
                    return buffer
                }
            }
        }
        return nil
    }

    // MARK: - Playback Control

    public func startVillageAudio() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isPlaying else { return }

        // Ensure engine is running
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[AudioManager] Failed to start AVAudioEngine: \(error)")
                return
            }
        }

        // Schedule all buffers simultaneously to ensure perfect multi-track synchronization
        for stem in AudioStem.allCases {
            guard let player = playerNodes[stem], let buffer = stemBuffers[stem] else { continue }
            player.stop()
            player.volume = mutedStems.contains(stem) ? 0.0 : 1.0
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
        }

        isPlaying = true
    }

    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        for task in activeFadeTasks.values {
            task.cancel()
        }
        activeFadeTasks.removeAll()

        for player in playerNodes.values {
            player.stop()
        }

        if engine.isRunning {
            engine.stop()
        }

        isPlaying = false
    }

    public func reset() {
        stateLock.lock()
        for task in activeFadeTasks.values {
            task.cancel()
        }
        activeFadeTasks.removeAll()

        currentStep = 0
        highestStepReached = 0
        mutedStems.removeAll()
        for stem in AudioStem.allCases {
            stemVolumes[stem] = 1.0
            playerNodes[stem]?.volume = 1.0
        }
        stateLock.unlock()

        stop()
        startVillageAudio()
    }

    // MARK: - Decay Schedule & Monotonic Removal (SPEC §8.1)

    /// Computes the discrete decay step from mean posterior SD according to SPEC §8.1.
    /// Step 0 (> 0.20 SD): Full mix
    /// Step 1 (0.15–0.20 SD): Bells dropped
    /// Step 2 (0.10–0.15 SD): Perc dropped
    /// Step 3 (0.06–0.10 SD): Melody dropped
    /// Step 4 (< 0.06 SD): Bass dropped (Pad only)
    /// Step 5 (The Reading): Pad dropped (Room tone only)
    public static func step(forMeanPosteriorSD sd: Double) -> Int {
        if sd > 0.20 {
            return 0
        } else if sd > 0.15 {
            return 1
        } else if sd > 0.10 {
            return 2
        } else if sd >= 0.06 {
            return 3
        } else {
            return 4
        }
    }

    /// Set of active stems for a given decay step.
    public static func activeStems(forStep step: Int) -> Set<AudioStem> {
        switch step {
        case 0:
            return [.bells, .perc, .melody, .bass, .pad]
        case 1:
            return [.perc, .melody, .bass, .pad]
        case 2:
            return [.melody, .bass, .pad]
        case 3:
            return [.bass, .pad]
        case 4:
            return [.pad]
        case 5...:
            return []
        default:
            return [.bells, .perc, .melody, .bass, .pad]
        }
    }

    /// Equal-power cosine fade curve: V(t) = cos(π/2 * progress).
    /// Prevents perceived dip or clicking during volume changes.
    public static func fadeVolume(progress: Double) -> Float {
        if progress <= 0.0 { return 1.0 }
        if progress >= 1.0 { return 0.0 }
        return Float(cos(Double.pi * 0.5 * progress))
    }

    /// Updates the audio decay state based on the current mean posterior SD.
    /// Strictly adheres to the one-way rule: layers are never faded back in.
    public func updateDecay(meanPosteriorSD: Double) {
        let targetStep = Self.step(forMeanPosteriorSD: meanPosteriorSD)
        applyStep(targetStep)
    }

    /// Explicitly transitions audio to Step 5 (Room Tone / pure silence) for The Reading.
    public func enterReadingRoomTone() {
        applyStep(5)
    }

    /// Applies a decay step monotonically.
    public func applyStep(_ step: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        // One-Way Rule: Never step backwards
        guard step > highestStepReached else { return }

        let previousStep = highestStepReached
        highestStepReached = step
        currentStep = step

        let oldActive = Self.activeStems(forStep: previousStep)
        let newActive = Self.activeStems(forStep: step)
        let stemsToMute = oldActive.subtracting(newActive)

        for stem in stemsToMute {
            if !mutedStems.contains(stem) {
                mutedStems.insert(stem)
                startFadeOut(stem: stem)
            }
        }
    }

    private func startFadeOut(stem: AudioStem) {
        // Cancel any existing fade task for this stem
        activeFadeTasks[stem]?.cancel()

        let duration = Self.fadeDurationSeconds
        let interval: Double = 0.025 // 25ms update interval (40 Hz smooth volume ramp)
        let totalSteps = Int(duration / interval)

        activeFadeTasks[stem] = Task { [weak self] in
            for stepIndex in 1...totalSteps {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }

                let progress = Double(stepIndex) / Double(totalSteps)
                let volume = Self.fadeVolume(progress: progress)

                self?.setStemVolume(stem: stem, volume: volume)
            }

            // Ensure exact 0.0 at the end of fade
            self?.setStemVolume(stem: stem, volume: 0.0)
        }
    }

    private func setStemVolume(stem: AudioStem, volume: Float) {
        stateLock.lock()
        stemVolumes[stem] = volume
        playerNodes[stem]?.volume = volume
        stateLock.unlock()
    }

    // MARK: - Procedural Stem Generation (High Fidelity D Dorian Village Soundtrack @ 84 BPM)

    /// Generates a pristine, loopable 16-bar stereo PCM buffer for a given stem in D Dorian at 84 BPM.
    /// Composed with rich acoustic harmonics, natural ADSR physical envelopes, clean concert tuning,
    /// and seamless multi-track synchronization per SPEC §8.1 and NOTES-audio.md.
    public func generateProceduralStem(stem: AudioStem, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = Self.loopSampleCount
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            fatalError("Could not allocate AVAudioPCMBuffer for stem \(stem)")
        }
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            return buffer
        }

        let sampleRate = Self.sampleRate
        let beatDuration = 60.0 / Self.masterTempoBPM // ~0.7142857 seconds
        let barDuration = 4.0 * beatDuration // ~2.8571428 seconds

        // Exact equal-tempered frequency table in Hz (A4 = 440 Hz):
        let freqD2 = 73.42, freqE2 = 82.41, freqF2 = 87.31, freqG2 = 98.00, freqA2 = 110.00, freqB2 = 123.47, freqC3 = 130.81
        let freqD3 = 146.83, freqE3 = 164.81, freqF3 = 174.61, freqG3 = 196.00, freqA3 = 220.00, freqB3 = 246.94, freqC4 = 261.63
        let freqD4 = 293.66, freqE4 = 329.63, freqF4 = 349.23, freqG4 = 392.00, freqA4 = 440.00, freqB4 = 493.88, freqC5 = 523.25
        let freqD5 = 587.33, freqE5 = 659.25, freqF5 = 698.46, freqG5 = 783.99, freqA5 = 880.00, freqB5 = 987.77, freqC6 = 1046.50
        let freqD6 = 1174.66, freqE6 = 1318.51

        // Zero out stereo channels
        for i in 0..<Int(frameCount) {
            leftChannel[i] = 0.0
            rightChannel[i] = 0.0
        }

        switch stem {
        case .pad:
            // 1. Lush warm string / harmonium sustained chords in D Dorian
            // Progression: Dm9 (bars 0-3) -> G7/G11 (bars 4-7) -> Cmaj9 (bars 8-11) -> Am9 / Dm (bars 12-15)
            let chordVoicings: [[[Double]]] = [
                // Bars 0..3: Dm9 (D2, A2, F3, C4, E4)
                [[freqD2, freqA2, freqF3, freqC4, freqE4]],
                // Bars 4..7: G11 (G2, D3, F3, B3, D4, E4)
                [[freqG2, freqD3, freqF3, freqB3, freqD4, freqE4]],
                // Bars 8..11: Cmaj9 (C3, G3, E4, B4, D5)
                [[freqC3, freqG3, freqE4, freqB4, freqD5]],
                // Bars 12..15: Am9 -> Dm (A2, E3, C4, G4, B4)
                [[freqA2, freqE3, freqC4, freqG4, freqB4]]
            ]

            for bar in 0..<16 {
                let chordGroup = (bar / 4) % 4
                let freqs = chordVoicings[chordGroup][0]
                let barStartFrame = Int(Double(bar) * barDuration * sampleRate)
                let barEndFrame = min(Int(Double(bar + 1) * barDuration * sampleRate), Int(frameCount))
                let barLength = barEndFrame - barStartFrame

                for f in barStartFrame..<barEndFrame {
                    let t = Double(f) / sampleRate
                    let localT = Double(f - barStartFrame) / Double(barLength)

                    // Smooth raised-cosine breathing envelope across bar boundaries
                    let env = sin(Double.pi * localT) * 0.15

                    var sampleL = 0.0
                    var sampleR = 0.0

                    for (idx, freq) in freqs.enumerated() {
                        let pan = (Double(idx) / Double(freqs.count - 1)) * 0.6 + 0.2

                        // Warm multi-harmonic acoustic string tone (fundamental, 2nd, 3rd harmonics)
                        let wave = sin(2.0 * Double.pi * freq * t) * 0.65 +
                                   sin(2.0 * Double.pi * freq * 2.0 * t) * 0.22 +
                                   sin(2.0 * Double.pi * freq * 3.0 * t) * 0.09 +
                                   sin(2.0 * Double.pi * freq * 4.0 * t) * 0.04

                        sampleL += wave * (1.0 - pan) * env
                        sampleR += wave * pan * env
                    }

                    leftChannel[f] += Float(sampleL)
                    rightChannel[f] += Float(sampleR)
                }
            }

        case .bass:
            // 2. Warm acoustic upright bass pulse on beats 1 and 3 of each bar
            // Roots: D2/A2 (Dm9), G2/D3 (G11), C3/G2 (Cmaj9), A2/E2 (Am9)
            let bassRoots: [(beat1: Double, beat3: Double)] = [
                (freqD2, freqA2), // Dm9
                (freqG2, freqD3), // G11
                (freqC3, freqG2), // Cmaj9
                (freqA2, freqE2)  // Am9
            ]

            for bar in 0..<16 {
                let chordGroup = (bar / 4) % 4
                let roots = bassRoots[chordGroup]

                for beat in [0, 2] { // Beats 1 and 3
                    let freq = (beat == 0) ? roots.beat1 : roots.beat3
                    let beatStart = (Double(bar) * 4.0 + Double(beat)) * beatDuration
                    let startFrame = Int(beatStart * sampleRate)
                    let pluckDuration = beatDuration * 1.85
                    let endFrame = min(startFrame + Int(pluckDuration * sampleRate), Int(frameCount))

                    for f in startFrame..<endFrame {
                        let t = Double(f - startFrame) / sampleRate
                        let decay = exp(-3.2 * t) * 0.36

                        // Deep acoustic contrabass body resonance
                        let wave = (sin(2.0 * Double.pi * freq * t) * 0.72 +
                                    sin(2.0 * Double.pi * freq * 2.0 * t) * 0.20 +
                                    sin(2.0 * Double.pi * freq * 3.0 * t) * 0.08) * decay

                        leftChannel[f] += Float(wave * 0.5)
                        rightChannel[f] += Float(wave * 0.5)
                    }
                }
            }

        case .melody:
            // 3. Elegant, lyrical folk theme in D Dorian (Nylon guitar / soft wood flute tone)
            // (startBeat, durationBeats, frequency)
            let melodyNotes: [(beat: Double, dur: Double, freq: Double)] = [
                // Phrase 1 (Bars 0-3: The Opening Theme in D Dorian)
                (0.0, 1.0, freqD4), (1.0, 0.5, freqE4), (1.5, 0.5, freqF4), (2.0, 1.0, freqA4), (3.0, 1.0, freqC5),
                (4.0, 2.0, freqD5), (6.0, 1.0, freqC5), (7.0, 1.0, freqA4),
                (8.0, 1.5, freqG4), (9.5, 0.5, freqE4), (10.0, 2.0, freqD4),
                (12.0, 1.0, freqE4), (13.0, 1.0, freqF4), (14.0, 2.0, freqD4),

                // Phrase 2 (Bars 4-7: Luminous Ascent into G11)
                (16.0, 1.0, freqG4), (17.0, 1.0, freqB4), (18.0, 2.0, freqD5),
                (20.0, 1.5, freqE5), (21.5, 0.5, freqD5), (22.0, 1.0, freqB4), (23.0, 1.0, freqG4),
                (24.0, 1.0, freqA4), (25.0, 1.0, freqB4), (26.0, 2.0, freqG4),
                (28.0, 1.0, freqD4), (29.0, 1.0, freqE4), (30.0, 2.0, freqG4),

                // Phrase 3 (Bars 8-11: Peaceful Pastoral Theme in Cmaj9)
                (32.0, 1.0, freqE4), (33.0, 1.0, freqG4), (34.0, 1.0, freqB4), (35.0, 1.0, freqC5),
                (36.0, 2.0, freqD5), (38.0, 1.0, freqB4), (39.0, 1.0, freqG4),
                (40.0, 1.5, freqE4), (41.5, 0.5, freqD4), (42.0, 2.0, freqC4),
                (44.0, 1.0, freqD4), (45.0, 1.0, freqE4), (46.0, 2.0, freqG4),

                // Phrase 4 (Bars 12-15: Melancholic Am9 Resolution to D Dorian)
                (48.0, 1.0, freqA4), (49.0, 1.0, freqC5), (50.0, 2.0, freqE5),
                (52.0, 1.0, freqD5), (53.0, 1.0, freqC5), (54.0, 2.0, freqA4),
                (56.0, 1.5, freqF4), (57.5, 0.5, freqE4), (58.0, 2.0, freqD4),
                (60.0, 1.0, freqC4), (61.0, 1.0, freqE4), (62.0, 2.0, freqD4)
            ]

            for note in melodyNotes {
                let startFrame = Int(note.beat * beatDuration * sampleRate)
                let noteDuration = note.dur * beatDuration
                let endFrame = min(startFrame + Int(noteDuration * sampleRate), Int(frameCount))

                for f in startFrame..<endFrame {
                    let t = Double(f - startFrame) / sampleRate

                    // Natural acoustic ADSR envelope (fast attack, natural gentle decay)
                    let attack = min(1.0, t / 0.035)
                    let release = min(1.0, (noteDuration - t) / 0.07)
                    let env = attack * max(0.0, release) * 0.20

                    // Subtle natural woodwind/guitar vibrato starting after 350ms of hold
                    let vibrato = (t > 0.35) ? sin(2.0 * Double.pi * 5.0 * t) * (min(0.6, (t - 0.35) * 1.2) * 0.002) : 0.0
                    let freq = note.freq * (1.0 + vibrato)

                    // Warm acoustic tone with physical harmonic decay
                    let wave = sin(2.0 * Double.pi * freq * t) * 0.70 +
                               sin(2.0 * Double.pi * (freq * 2.0) * t) * 0.20 +
                               sin(2.0 * Double.pi * (freq * 3.0) * t) * 0.08 +
                               sin(2.0 * Double.pi * (freq * 4.0) * t) * 0.02

                    leftChannel[f] += Float(wave * env * 0.52)
                    rightChannel[f] += Float(wave * env * 0.48)
                }
            }

        case .perc:
            // 4. Gentle walking pulse: soft brush shakers on 8th notes and warm wood clicks on beats 2 and 4
            var rng = 123456789
            func nextNoise() -> Double {
                rng = (rng &* 1103515245 &+ 12345) & 0x7fffffff
                return Double(rng) / Double(0x7fffffff) * 2.0 - 1.0
            }

            for beat in 0..<64 {
                // 1. Soft shakers on 8th notes
                for sub in [0.0, 0.5] {
                    let shakerStart = (Double(beat) + sub) * beatDuration
                    let startFrame = Int(shakerStart * sampleRate)
                    let shakerLen = Int(0.040 * sampleRate)
                    let endFrame = min(startFrame + shakerLen, Int(frameCount))
                    let isDownbeat = (sub == 0.0)
                    let amp = isDownbeat ? 0.028 : 0.018

                    for f in startFrame..<endFrame {
                        let t = Double(f - startFrame) / sampleRate
                        let env = exp(-90.0 * t) * amp
                        let noise = nextNoise()
                        leftChannel[f] += Float(noise * env * 0.55)
                        rightChannel[f] += Float(noise * env * 0.45)
                    }
                }

                // 2. Soft wooden rim click on beats 2 and 4
                if beat % 4 == 1 || beat % 4 == 3 {
                    let clickStart = Double(beat) * beatDuration
                    let startFrame = Int(clickStart * sampleRate)
                    let clickLen = Int(0.050 * sampleRate)
                    let endFrame = min(startFrame + clickLen, Int(frameCount))

                    for f in startFrame..<endFrame {
                        let t = Double(f - startFrame) / sampleRate
                        let env = exp(-70.0 * t) * 0.065
                        let tone = sin(2.0 * Double.pi * 920.0 * t) * 0.40 + nextNoise() * 0.60
                        leftChannel[f] += Float(tone * env * 0.5)
                        rightChannel[f] += Float(tone * env * 0.5)
                    }
                }
            }

        case .bells:
            // 5. Crystalline Celesta / Glockenspiel arpeggios on upbeat accents
            let bellArpeggios: [(beat: Double, freq: Double)] = [
                // Bars 0-3: Dm9
                (0.5, freqD5), (1.5, freqA5), (2.5, freqF5), (3.5, freqC6),
                (4.5, freqD6), (5.5, freqA5), (6.5, freqE5),
                (8.5, freqF5), (9.5, freqD5), (10.5, freqA5), (11.5, freqC6),

                // Bars 4-7: G11
                (16.5, freqG5), (17.5, freqD6), (18.5, freqB5), (19.5, freqG5),
                (20.5, freqB5), (21.5, freqD6), (22.5, freqA5),
                (24.5, freqB5), (25.5, freqG5), (26.5, freqD5),

                // Bars 8-11: Cmaj9
                (32.5, freqE5), (33.5, freqB5), (34.5, freqG5), (35.5, freqC6),
                (36.5, freqD6), (37.5, freqE6), (38.5, freqB5),
                (40.5, freqG5), (41.5, freqE5), (42.5, freqD5),

                // Bars 12-15: Am9 -> Dm
                (48.5, freqA5), (49.5, freqE6), (50.5, freqC6), (51.5, freqG5),
                (52.5, freqF5), (53.5, freqD6), (54.5, freqC6),
                (56.5, freqA5), (58.5, freqE5), (60.5, freqD5)
            ]

            for bell in bellArpeggios {
                let startFrame = Int(bell.beat * beatDuration * sampleRate)
                let bellDuration = 0.60
                let endFrame = min(startFrame + Int(bellDuration * sampleRate), Int(frameCount))

                for f in startFrame..<endFrame {
                    let t = Double(f - startFrame) / sampleRate
                    let env = exp(-6.8 * t) * 0.085 // pure crystalline chime decay

                    // Inharmonic glockenspiel acoustic bar partials
                    let partial1 = sin(2.0 * Double.pi * bell.freq * t)
                    let partial2 = sin(2.0 * Double.pi * (bell.freq * 2.756) * t) * 0.35
                    let partial3 = sin(2.0 * Double.pi * (bell.freq * 5.404) * t) * 0.12
                    let wave = (partial1 + partial2 + partial3) * env

                    leftChannel[f] += Float(wave * 0.45)
                    rightChannel[f] += Float(wave * 0.55)
                }
            }
        }

        // Apply a gentle 100-sample fade-in and fade-out at buffer boundaries to ensure zero loop click
        let edgeSamples = min(100, Int(frameCount) / 2)
        for i in 0..<edgeSamples {
            let fade = Float(i) / Float(edgeSamples)
            leftChannel[i] *= fade
            rightChannel[i] *= fade

            let tailIdx = Int(frameCount) - 1 - i
            leftChannel[tailIdx] *= fade
            rightChannel[tailIdx] *= fade
        }

        return buffer
    }
}
