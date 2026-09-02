//
//  PriorsApp.swift
//  Priors
//
//  Main application entry point managing the 7-phase session lifecycle state machine.
//  SPEC §7.
//

import SwiftUI
import SpriteKit
import GameplayKit
import PriorsEngine

public enum SessionPhase: Sendable {
    case splash
    case consent
    case temperament
    case prologue
    case village
    case selfPrediction
    case reading
    case argument
    case title
}

@main
struct PriorsApp: App {
    @State private var phase: SessionPhase = PriorsApp.initialPhase

    /// UI tests and the Barnum protocol both need to open a single screen
    /// without playing a whole session first. Off unless the launch argument is
    /// present, so it cannot affect a real run.
    static var initialPhase: SessionPhase {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startPhase"), i + 1 < args.count else {
            return .splash
        }
        switch args[i + 1] {
        case "consent": return .consent
        case "temperament": return .temperament
        case "prologue": return .prologue
        case "village": return .village
        case "selfPrediction": return .selfPrediction
        case "title": return .title
        default: return .splash
        }
    }
    @State private var consentLog: ConsentLog?
    @State private var selectedTemperament: SelfImageLabel?
    @State private var selfPredictedThetaE: Double?
    @State private var sessionRecord: SessionRecord?
    @State private var generatedClaims: [Claim] = []
    /// Optional: a session that produced no claim has no title. Defaulting this
    /// printed a line the player's data had not earned (SPEC §2.1).
    @State private var titleClaim: String?

    // Village State
    @State private var coordinator: VillageCoordinator?
    private let movementSampler = MovementSampler()

    var body: some Scene {
        WindowGroup {
            Group {
                switch phase {
                case .splash:
                    SplashScreen {
                        advance(to: .consent)
                    }

                case .consent:
                    ConsentScreen { log in
                        self.consentLog = log
                        advance(to: .temperament)
                    }

                case .temperament:
                    TemperamentScreen { label, durationMs in
                        self.selectedTemperament = label
                        let log = self.consentLog ?? ConsentLog()
                        let coord = VillageCoordinator(
                            consentLog: log,
                            selfImageLabel: label
                        )
                        self.coordinator = coord
                        advance(to: .prologue)
                    }

                case .prologue:
                    PrologueScreen {
                        advance(to: .village)
                    }

                case .village:
                    if let coord = coordinator ?? debugCoordinator() {
                        VillageContainerView(
                            coordinator: coord,
                            movementSampler: movementSampler,
                            onComplete: { record in
                                self.sessionRecord = record
                                advance(to: .selfPrediction)
                            }
                        )
                    } else {
                        Color.black.ignoresSafeArea()
                    }

                case .selfPrediction:
                    SelfPredictionScreen { prediction in
                        self.selfPredictedThetaE = prediction

                        if let oldRecord = self.sessionRecord {
                            let updatedRecord = SessionRecord(
                                sessionID: oldRecord.sessionID,
                                startedAt: oldRecord.startedAt,
                                consentDwellMs: oldRecord.consentDwellMs,
                                consentReadDetails: oldRecord.consentReadDetails,
                                detailsDwellMs: oldRecord.detailsDwellMs,
                                selfImageLabel: oldRecord.selfImageLabel,
                                selfPredictedThetaE: prediction,
                                eyeEnabled: oldRecord.eyeEnabled,
                                eyeTimestamp: oldRecord.eyeTimestamp,
                                eyeApproachMs: oldRecord.eyeApproachMs,
                                shadowAppearances: oldRecord.shadowAppearances,
                                shadowCorrect: oldRecord.shadowCorrect,
                                decisions: oldRecord.decisions,
                                movement: oldRecord.movement,
                                finalPosterior: oldRecord.finalPosterior,
                                argumentEvents: oldRecord.argumentEvents
                            )
                            self.sessionRecord = updatedRecord

                            // Generate claims for Reading & Argument
                            let claims = ClaimGenerator.generate(session: updatedRecord)
                            self.generatedClaims = claims
                            updateTitleClaim(from: claims)
                        }

                        advance(to: .reading)
                    }

                case .reading:
                    ReadingScreen(claims: generatedClaims) { _ in
                        advance(to: .argument)
                    }

                case .argument:
                    if let record = sessionRecord {
                        ArgumentScreen(
                            sessionRecord: record,
                            claims: generatedClaims,
                            onComplete: { updatedRecord in
                                self.sessionRecord = updatedRecord
                                let finalClaims = ClaimGenerator.generate(session: updatedRecord)
                                self.generatedClaims = finalClaims
                                updateTitleClaim(from: finalClaims)
                                advance(to: .title)
                            }
                        )
                    } else {
                        Color.black.ignoresSafeArea()
                    }

                case .title:
                    TitleScreen(title: titleClaim, onRestart: restart)
                }
            }
            // One crossfade for every phase change. Without it the app cut
            // between full-screen views with no transition at all.
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.45), value: phaseKey)
            .preferredColorScheme(.dark)
        }
    }

    /// A value that changes whenever the phase does, so SwiftUI has something
    /// to animate on. `SessionPhase` is not `Equatable`, and making it so would
    /// put an animation concern into the session model.
    private var phaseKey: Int {
        switch phase {
        case .splash: return 0
        case .consent: return 1
        case .temperament: return 2
        case .prologue: return 3
        case .village: return 4
        case .selfPrediction: return 5
        case .reading: return 6
        case .argument: return 7
        case .title: return 8
        }
    }

    /// Only reachable via `-startPhase village`; the real flow always builds a
    /// coordinator on the temperament tap.
    private func debugCoordinator() -> VillageCoordinator? {
        guard ProcessInfo.processInfo.arguments.contains("-startPhase") else { return nil }
        let coord = VillageCoordinator(consentLog: ConsentLog(), selfImageLabel: .curious)
        DispatchQueue.main.async { self.coordinator = coord }
        return coord
    }

    private func advance(to next: SessionPhase) {
        withAnimation(.easeInOut(duration: 0.45)) { phase = next }
    }

    /// Start a fresh session. Every piece of the previous one is dropped —
    /// nothing carries over into the next player's model.
    private func restart() {
        consentLog = nil
        selectedTemperament = nil
        selfPredictedThetaE = nil
        sessionRecord = nil
        generatedClaims = []
        titleClaim = nil
        coordinator = nil
        movementSampler.reset()
        advance(to: .consent)
    }

    /// SPEC §11 / COPY "Titles" — one line, composed from the
    /// strongest-confidence claim, from COPY's fixed list.
    ///
    /// There is no default. A claim kind COPY has no title for produces no
    /// title, exactly as a missing parameter produces no report line: the
    /// previous `default:` branch printed "The one who explored while it was
    /// free." for any unmapped claim and for an empty session, which is a
    /// sentence about the player that their log did not support (SPEC §2.1).
    private func updateTitleClaim(from claims: [Claim]) {
        guard let best = ClaimGenerator.titleClaim(from: claims) else {
            titleClaim = nil
            return
        }
        switch best.kind {
        case .confirmLowPrice:  titleClaim = "The one who explored while it was free."
        case .repeatDivergence: titleClaim = "The one who checked twice."
        case .theLine:          titleClaim = "The one who stopped deciding once he knew."
        case .moralLine:        titleClaim = "The one who never went back."
        case .nearMiss:         titleClaim = "The one who stood at the edge."
        case .consentNumber:    titleClaim = "The one who read it and did it anyway."
        default:                titleClaim = nil
        }
    }
}
