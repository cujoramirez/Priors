import Foundation
import AVFoundation

let sampleRate: Double = 48000.0
let channelCount: AVAudioChannelCount = 2
let masterTempoBPM: Double = 84.0
let loopBarCount: Int = 16
let loopSampleCount: AVAudioFrameCount = 2_194_286

guard let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: sampleRate,
    channels: channelCount,
    interleaved: false
) else {
    fatalError("Failed to create audio format")
}

func generateStem(name: String) -> AVAudioPCMBuffer {
    let frameCount = loopSampleCount
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        fatalError("Failed to allocate buffer")
    }
    buffer.frameLength = frameCount

    guard let left = buffer.floatChannelData?[0],
          let right = buffer.floatChannelData?[1] else {
        return buffer
    }

    for i in 0..<Int(frameCount) {
        left[i] = 0.0
        right[i] = 0.0
    }

    let beatDuration = 60.0 / masterTempoBPM
    let barDuration = 4.0 * beatDuration

    let freqD2 = 73.42, freqE2 = 82.41, freqF2 = 87.31, freqG2 = 98.00, freqA2 = 110.00, freqB2 = 123.47, freqC3 = 130.81
    let freqD3 = 146.83, freqE3 = 164.81, freqF3 = 174.61, freqG3 = 196.00, freqA3 = 220.00, freqB3 = 246.94, freqC4 = 261.63
    let freqD4 = 293.66, freqE4 = 329.63, freqF4 = 349.23, freqG4 = 392.00, freqA4 = 440.00, freqB4 = 493.88, freqC5 = 523.25
    let freqD5 = 587.33, freqE5 = 659.25, freqF5 = 698.46, freqG5 = 783.99, freqA5 = 880.00, freqB5 = 987.77, freqC6 = 1046.50
    let freqD6 = 1174.66, freqE6 = 1318.51

    switch name {
    case "pad":
        let chordVoicings: [[[Double]]] = [
            [[freqD2, freqA2, freqF3, freqC4, freqE4]],
            [[freqG2, freqD3, freqF3, freqB3, freqD4, freqE4]],
            [[freqC3, freqG3, freqE4, freqB4, freqD5]],
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
                let env = sin(Double.pi * localT) * 0.15

                var sampleL = 0.0
                var sampleR = 0.0

                for (idx, freq) in freqs.enumerated() {
                    let pan = (Double(idx) / Double(freqs.count - 1)) * 0.6 + 0.2
                    let wave = sin(2.0 * Double.pi * freq * t) * 0.65 +
                               sin(2.0 * Double.pi * freq * 2.0 * t) * 0.22 +
                               sin(2.0 * Double.pi * freq * 3.0 * t) * 0.09 +
                               sin(2.0 * Double.pi * freq * 4.0 * t) * 0.04
                    sampleL += wave * (1.0 - pan) * env
                    sampleR += wave * pan * env
                }

                left[f] += Float(sampleL)
                right[f] += Float(sampleR)
            }
        }

    case "bass":
        let bassRoots: [(beat1: Double, beat3: Double)] = [
            (freqD2, freqA2), (freqG2, freqD3), (freqC3, freqG2), (freqA2, freqE2)
        ]
        for bar in 0..<16 {
            let chordGroup = (bar / 4) % 4
            let roots = bassRoots[chordGroup]

            for beat in [0, 2] {
                let freq = (beat == 0) ? roots.beat1 : roots.beat3
                let beatStart = (Double(bar) * 4.0 + Double(beat)) * beatDuration
                let startFrame = Int(beatStart * sampleRate)
                let pluckDuration = beatDuration * 1.85
                let endFrame = min(startFrame + Int(pluckDuration * sampleRate), Int(frameCount))

                for f in startFrame..<endFrame {
                    let t = Double(f - startFrame) / sampleRate
                    let decay = exp(-3.2 * t) * 0.36
                    let wave = (sin(2.0 * Double.pi * freq * t) * 0.72 +
                                sin(2.0 * Double.pi * freq * 2.0 * t) * 0.20 +
                                sin(2.0 * Double.pi * freq * 3.0 * t) * 0.08) * decay
                    left[f] += Float(wave * 0.5)
                    right[f] += Float(wave * 0.5)
                }
            }
        }

    case "melody":
        let melodyNotes: [(beat: Double, dur: Double, freq: Double)] = [
            (0.0, 1.0, freqD4), (1.0, 0.5, freqE4), (1.5, 0.5, freqF4), (2.0, 1.0, freqA4), (3.0, 1.0, freqC5),
            (4.0, 2.0, freqD5), (6.0, 1.0, freqC5), (7.0, 1.0, freqA4),
            (8.0, 1.5, freqG4), (9.5, 0.5, freqE4), (10.0, 2.0, freqD4),
            (12.0, 1.0, freqE4), (13.0, 1.0, freqF4), (14.0, 2.0, freqD4),

            (16.0, 1.0, freqG4), (17.0, 1.0, freqB4), (18.0, 2.0, freqD5),
            (20.0, 1.5, freqE5), (21.5, 0.5, freqD5), (22.0, 1.0, freqB4), (23.0, 1.0, freqG4),
            (24.0, 1.0, freqA4), (25.0, 1.0, freqB4), (26.0, 2.0, freqG4),
            (28.0, 1.0, freqD4), (29.0, 1.0, freqE4), (30.0, 2.0, freqG4),

            (32.0, 1.0, freqE4), (33.0, 1.0, freqG4), (34.0, 1.0, freqB4), (35.0, 1.0, freqC5),
            (36.0, 2.0, freqD5), (38.0, 1.0, freqB4), (39.0, 1.0, freqG4),
            (40.0, 1.5, freqE4), (41.5, 0.5, freqD4), (42.0, 2.0, freqC4),
            (44.0, 1.0, freqD4), (45.0, 1.0, freqE4), (46.0, 2.0, freqG4),

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
                let attack = min(1.0, t / 0.035)
                let release = min(1.0, (noteDuration - t) / 0.07)
                let env = attack * max(0.0, release) * 0.20

                let vibrato = (t > 0.35) ? sin(2.0 * Double.pi * 5.0 * t) * (min(0.6, (t - 0.35) * 1.2) * 0.002) : 0.0
                let freq = note.freq * (1.0 + vibrato)

                let wave = sin(2.0 * Double.pi * freq * t) * 0.70 +
                           sin(2.0 * Double.pi * (freq * 2.0) * t) * 0.20 +
                           sin(2.0 * Double.pi * (freq * 3.0) * t) * 0.08 +
                           sin(2.0 * Double.pi * (freq * 4.0) * t) * 0.02

                left[f] += Float(wave * env * 0.52)
                right[f] += Float(wave * env * 0.48)
            }
        }

    case "perc":
        var rng = 123456789
        func nextNoise() -> Double {
            rng = (rng &* 1103515245 &+ 12345) & 0x7fffffff
            return Double(rng) / Double(0x7fffffff) * 2.0 - 1.0
        }

        for beat in 0..<64 {
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
                    left[f] += Float(noise * env * 0.55)
                    right[f] += Float(noise * env * 0.45)
                }
            }

            if beat % 4 == 1 || beat % 4 == 3 {
                let clickStart = Double(beat) * beatDuration
                let startFrame = Int(clickStart * sampleRate)
                let clickLen = Int(0.050 * sampleRate)
                let endFrame = min(startFrame + clickLen, Int(frameCount))

                for f in startFrame..<endFrame {
                    let t = Double(f - startFrame) / sampleRate
                    let env = exp(-70.0 * t) * 0.065
                    let tone = sin(2.0 * Double.pi * 920.0 * t) * 0.40 + nextNoise() * 0.60
                    left[f] += Float(tone * env * 0.5)
                    right[f] += Float(tone * env * 0.5)
                }
            }
        }

    case "bells":
        let bellArpeggios: [(beat: Double, freq: Double)] = [
            (0.5, freqD5), (1.5, freqA5), (2.5, freqF5), (3.5, freqC6),
            (4.5, freqD6), (5.5, freqA5), (6.5, freqE5),
            (8.5, freqF5), (9.5, freqD5), (10.5, freqA5), (11.5, freqC6),

            (16.5, freqG5), (17.5, freqD6), (18.5, freqB5), (19.5, freqG5),
            (20.5, freqB5), (21.5, freqD6), (22.5, freqA5),
            (24.5, freqB5), (25.5, freqG5), (26.5, freqD5),

            (32.5, freqE5), (33.5, freqB5), (34.5, freqG5), (35.5, freqC6),
            (36.5, freqD6), (37.5, freqE6), (38.5, freqB5),
            (40.5, freqG5), (41.5, freqE5), (42.5, freqD5),

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
                let env = exp(-6.8 * t) * 0.085

                let partial1 = sin(2.0 * Double.pi * bell.freq * t)
                let partial2 = sin(2.0 * Double.pi * (bell.freq * 2.756) * t) * 0.35
                let partial3 = sin(2.0 * Double.pi * (bell.freq * 5.404) * t) * 0.12
                let wave = (partial1 + partial2 + partial3) * env

                left[f] += Float(wave * 0.45)
                right[f] += Float(wave * 0.55)
            }
        }

    default:
        break
    }

    let edgeSamples = min(100, Int(frameCount) / 2)
    for i in 0..<edgeSamples {
        let fade = Float(i) / Float(edgeSamples)
        left[i] *= fade
        right[i] *= fade

        let tailIdx = Int(frameCount) - 1 - i
        left[tailIdx] *= fade
        right[tailIdx] *= fade
    }

    return buffer
}

func exportWAV(buffer: AVAudioPCMBuffer, url: URL) {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    do {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        print("Exported: \(url.path)")
    } catch {
        print("Error exporting \(url.path): \(error)")
    }
}

func mixBuffers(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
    let frameCount = loopSampleCount
    guard let mix = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        fatalError("Cannot allocate mix buffer")
    }
    mix.frameLength = frameCount
    guard let outL = mix.floatChannelData?[0], let outR = mix.floatChannelData?[1] else {
        return mix
    }
    for i in 0..<Int(frameCount) {
        outL[i] = 0.0
        outR[i] = 0.0
    }

    for b in buffers {
        guard let inL = b.floatChannelData?[0], let inR = b.floatChannelData?[1] else { continue }
        for i in 0..<Int(frameCount) {
            outL[i] += inL[i]
            outR[i] += inR[i]
        }
    }
    return mix
}

print("Synthesizing stems...")
let pad = generateStem(name: "pad")
let bass = generateStem(name: "bass")
let melody = generateStem(name: "melody")
let perc = generateStem(name: "perc")
let bells = generateStem(name: "bells")

let outDir = URL(fileURLWithPath: "/Users/gading/Documents/Priors/AudioExports")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

exportWAV(buffer: pad, url: outDir.appendingPathComponent("stem_pad.wav"))
exportWAV(buffer: bass, url: outDir.appendingPathComponent("stem_bass.wav"))
exportWAV(buffer: melody, url: outDir.appendingPathComponent("stem_melody.wav"))
exportWAV(buffer: perc, url: outDir.appendingPathComponent("stem_perc.wav"))
exportWAV(buffer: bells, url: outDir.appendingPathComponent("stem_bells.wav"))

print("Generating decay step mixes...")
// Step 0: All 5 active
let step0 = mixBuffers([bells, perc, melody, bass, pad])
exportWAV(buffer: step0, url: outDir.appendingPathComponent("step0_full_mix.wav"))

// Step 1: Bells dropped
let step1 = mixBuffers([perc, melody, bass, pad])
exportWAV(buffer: step1, url: outDir.appendingPathComponent("step1_no_bells.wav"))

// Step 2: Perc dropped
let step2 = mixBuffers([melody, bass, pad])
exportWAV(buffer: step2, url: outDir.appendingPathComponent("step2_no_perc.wav"))

// Step 3: Melody dropped
let step3 = mixBuffers([bass, pad])
exportWAV(buffer: step3, url: outDir.appendingPathComponent("step3_no_melody.wav"))

// Step 4: Bass dropped (Pad only)
exportWAV(buffer: pad, url: outDir.appendingPathComponent("step4_pad_only.wav"))

print("Done! Audio exported to /Users/gading/Documents/Priors/AudioExports/")
