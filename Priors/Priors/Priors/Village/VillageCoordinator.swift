//
//  VillageCoordinator.swift
//  Priors
//
//  Manages the 30-decision ADO loop, Posterior updates, monotonic timing,
//  in-village events (Shadow, Eye, Falsification), and SessionRecord assembly.
//

import SwiftUI
import Observation
import SpriteKit
import PriorsEngine

@Observable
public final class VillageCoordinator: @unchecked Sendable {
    public let sessionID: UUID
    public let consentLog: ConsentLog
    public let selfImageLabel: SelfImageLabel
    public let eyeEnabled: Bool

    // Bayesian Engine State
    public var posterior = BehaviouralPosterior()
    public var selectionState = SelectionState()
    public var currentSlot: Int = 0
    public var lanternCount: Int = 3
    /// SPEC §8.3 — the single decision currently live in the world, or nil
    /// between slots. Replaces the old `activePrompt`/`isPresentingScenario`
    /// pair: there is no modal to present, so presentation state collapses
    /// into "is something armed".
    public var liveDecision: LiveDecision?

    // Timing & Monotonic Clock
    //
    // There is no stored "presentation instant" any more. SPEC §8.3 defines
    // the clock that matters as "time between entering a threshold's zone and
    // resolving it", and arming happens the moment the *previous* decision
    // resolves, with the player still standing at the previous location. The
    // arm instant is therefore an internal event that is never logged:
    // `t_presented` is derived from the scene's measured in-zone dwell, so
    // SCHEMA §1's `rt_ms = t_decided − t_presented` stays exactly true.
    public private(set) var sessionStartInstant: ContinuousClock.Instant

    // Logged Data
    public private(set) var decisions: [DecisionRecord] = []
    public private(set) var shadowAppearances: [Double] = []
    public private(set) var shadowCorrect: [Bool] = []
    public private(set) var eyeTimestamp: Double?

    // Event Schedules
    public private(set) var eyeDecisionIndex: Int?
    private let shadowSlots: Set<Int> = [16, 20, 24, 28] // 4 moments after decision 15 (SPEC §6.2)
    /// Each pre-built location hosts at most one decision per session, so the
    /// player never sees the same spot light up twice. The map ships exactly
    /// 19 theta_e and 11 theta_i spots, matching `Scenarios.traitSchedule`.
    private var usedLocationIDs: Set<Int> = []
    /// SPEC §6.2 / SCHEMA §3 — the shadow spawns at ARM time, but the player
    /// then has to walk to the location, which routinely takes longer than the
    /// shadow's fixed 10s walk. Scoring on the shadow's arrival would compare
    /// the prediction against `decisions.last`, which by then is usually the
    /// PREVIOUS slot's outcome. So the prediction is parked here, keyed to the
    /// slot it was made for, and scored in `resolveLiveDecision` when that
    /// exact slot resolves.
    private var pendingShadowPrediction: (slot: Int, prediction: EventTriggers.ShadowPrediction)?

    @ObservationIgnored
    public var onSessionComplete: (@MainActor (SessionRecord) -> Void)?

    public init(
        sessionID: UUID = UUID(),
        consentLog: ConsentLog,
        selfImageLabel: SelfImageLabel,
        eyeEnabled: Bool = true
    ) {
        self.sessionID = sessionID
        self.consentLog = consentLog
        self.selfImageLabel = selfImageLabel
        self.eyeEnabled = eyeEnabled
        self.sessionStartInstant = ContinuousClock.now

        var rng = SystemRandomNumberGenerator()
        if let eyeSched = EventTriggers.scheduleEye(enabled: eyeEnabled, using: &rng) {
            self.eyeDecisionIndex = eyeSched.decisionIndex
        }
    }

    public var currentMeanPosteriorSD: Double {
        posterior.meanSD(.thetaE).sd
    }

    /// SPEC §8.3 — arms the next ADO slot's design at whichever pre-built
    /// location's trait matches, nearest to the player. Exactly one decision
    /// is live at a time: this keeps ADO fully adaptive, since the design for
    /// slot N+1 is only computed after slot N's response is known.
    @MainActor
    public func armNextDecision(scene: VillageScene) {
        guard currentSlot < Scenarios.decisionCount else { return }
        guard liveDecision == nil else { return }

        // The player has to exist before anything else happens: the view's
        // retry loop ticks at 20 Hz until the scene is presented, and
        // `selectDesign` is not free. Nothing below it may consume a slot or
        // mutate state on a tick that is going to bail out anyway.
        guard let player = scene.playerNode else { return }

        let design = ADOSelector.selectDesign(
            posterior: posterior,
            slot: currentSlot,
            state: selectionState
        )
        let wantedTrait = design.trait
        let candidates = scene.decisionLocations.filter {
            $0.trait == wantedTrait && !usedLocationIDs.contains($0.id)
        }
        guard let nearest = candidates.min(by: { a, b in
            let da = hypot(a.position.x - player.position.x, a.position.y - player.position.y)
            let db = hypot(b.position.x - player.position.x, b.position.y - player.position.y)
            return da < db
        }) else {
            assertionFailure("slot \(currentSlot): no unused \(wantedTrait) location left")
            return
        }
        usedLocationIDs.insert(nearest.id)

        let narrative = ProceduralDilemmaAssembler.assemble(
            design: design,
            slot: currentSlot,
            locationID: nearest.id,
            sessionSeed: sessionID.hashValue
        )
        // SCHEMA §1 — `predicted_engage` and the four `posterior_*` fields are
        // captured HERE, before the choice is known, and travel with the
        // armed decision. They used to be read at resolution: numerically the
        // same, because the posterior is untouched in between, but honest by
        // accident rather than by construction.
        let decision = LiveDecision(design: design, capturedFrom: posterior, narrative: narrative)

        liveDecision = decision
        scene.setLanternsCarried(lanternCount)
        scene.armDecision(decision, at: nearest)

        // Check if Shadow event should trigger before this decision (SPEC §6.2)
        if shadowSlots.contains(currentSlot) {
            triggerShadowPrediction(nextDesign: design, armedAt: nearest.position, in: scene)
        }

        // Check if Eye event should trigger at this decision index (SPEC §6.3)
        if currentSlot == eyeDecisionIndex && eyeTimestamp == nil {
            triggerEyeEvent(in: scene)
        }
    }

    /// SPEC §8.3 — the world resolved the armed decision (threshold crossed,
    /// or villager held/left). Logs the record, folds the response into the
    /// posterior, then arms the next slot — or finishes the session.
    @MainActor
    public func resolveLiveDecision(
        engaged: Bool,
        zoneDwellSeconds: TimeInterval,
        metrics: (approachFrac: Double, backtracks: Int, idleMs: Int),
        movementSampler: MovementSampler,
        scene: VillageScene
    ) {
        guard let decision = liveDecision else { return }
        let design = decision.design
        assert(decision.priorSnapshot.isRecorded,
               "a decision that reaches the log must carry the posterior captured when it was armed")

        // SPEC §8.3 — `rt_ms` is the hesitation at the decision, not the walk
        // to it. The scene measures it from the frame the player entered the
        // zone; `t_presented` is then derived backwards from it so SCHEMA §1's
        // `rt_ms = t_decided − t_presented` holds exactly. `eye_window`'s
        // ±240s tolerance is untouched at this scale.
        let now = ContinuousClock.now
        let dwell = max(0.0, zoneDwellSeconds)
        let rtMs = Int((dwell * 1000.0).rounded())
        let tDecided = monotonicSecondsSinceStart(at: now)
        let tPresented = tDecided - Double(rtMs) / 1000.0

        let snapshot = decision.priorSnapshot

        // Evaluate Eye Window (SCHEMA §1)
        let (inEyeWindow, eyeSide) = EventTriggers.eyeWindow(
            tPresented: tPresented,
            eyeTimestamp: eyeTimestamp
        )

        let record = DecisionRecord(
            index: currentSlot,
            template: design.template,
            trait: design.trait,
            skin: design.skin,
            price: design.price,
            engaged: engaged,
            tPresented: tPresented,
            tDecided: tDecided,
            rtMs: rtMs,
            approachFrac: metrics.approachFrac,
            backtracks: metrics.backtracks,
            idleMs: metrics.idleMs,
            eyeWindow: inEyeWindow,
            eyeSide: eyeSide,
            posteriorMeanE: snapshot.meanE,
            posteriorSDE: snapshot.sdE,
            posteriorMeanI: snapshot.meanI,
            posteriorSDI: snapshot.sdI,
            predictedEngage: snapshot.predictedEngage,
            isRepeatOf: design.isRepeatOf
        )

        decisions.append(record)

        // SPEC §6.2 — score the shadow against the slot it actually predicted,
        // not against whatever landed in `decisions` by the time it finished
        // walking.
        if let pending = pendingShadowPrediction, pending.slot == currentSlot {
            shadowCorrect.append(pending.prediction.willEngage == engaged)
            pendingShadowPrediction = nil
        }

        // Update Bayesian Engine
        posterior.update(price: design.price, trait: design.trait, engaged: engaged, rtMs: Double(rtMs))
        selectionState.commit(design)

        // Update Lantern Inventory
        updateLanternCount(for: design.template, engaged: engaged, price: design.price)
        scene.setLanternsCarried(lanternCount)

        // Update Dusk Effect on Scene
        let newSdE = posterior.meanSD(.thetaE).sd
        scene.updateDusk(forMeanPosteriorSD: newSdE)

        // Update Audio Stem Decay (SPEC §8.1)
        AudioManager.shared.updateDecay(meanPosteriorSD: newSdE)

        liveDecision = nil
        currentSlot += 1

        // Check if session completed (30 decisions)
        if currentSlot >= Scenarios.decisionCount {
            finishSession(movementSampler: movementSampler, scene: scene)
        } else {
            armNextDecision(scene: scene)
        }
    }

    private func updateLanternCount(for template: TemplateID, engaged: Bool, price: Double) {
        switch template {
        case .give:
            if engaged { lanternCount = max(0, lanternCount - 1) }
        case .path:
            if engaged {
                // If path gamble lost
                if Double.random(in: 0...1) < price {
                    lanternCount = max(0, lanternCount - 1)
                }
            }
        case .trade:
            if engaged {
                // SPEC §4.2: win probability is 1 - price
                let pWin = 1.0 - price
                if Double.random(in: 0...1) < pWin {
                    lanternCount += 2 // Net +2 (total 3)
                } else {
                    lanternCount = max(0, lanternCount - 1)
                }
            }
        case .detour, .error, .credit:
            break
        }
    }

    @MainActor
    private func triggerShadowPrediction(nextDesign: Design, armedAt armedPosition: CGPoint, in scene: VillageScene) {
        let prediction = EventTriggers.shadowTarget(posterior: posterior, nextDesign: nextDesign)
        let t = monotonicSecondsSinceStart(at: ContinuousClock.now)
        shadowAppearances.append(t)

        // Predict destination point
        let targetPoint: CGPoint
        if prediction.willEngage {
            targetPoint = armedPosition
        } else {
            // Away from trigger
            targetPoint = CGPoint(x: scene.playerNode.position.x - 120, y: scene.playerNode.position.y - 120)
        }

        pendingShadowPrediction = (slot: currentSlot, prediction: prediction)

        // Arrival is purely cosmetic now: the prediction is scored when this
        // slot resolves, however long the player takes to get there.
        scene.spawnShadow(predictedDestination: targetPoint) {}
    }

    @MainActor
    private func triggerEyeEvent(in scene: VillageScene) {
        eyeTimestamp = monotonicSecondsSinceStart(at: ContinuousClock.now)
        scene.triggerEye(duration: 3.0)
    }

    @MainActor
    private func finishSession(movementSampler: MovementSampler, scene: VillageScene) {
        movementSampler.stop()
        AudioManager.shared.enterReadingRoomTone()

        let sessionRecord = SessionRecord(
            sessionID: sessionID,
            startedAt: Date(),
            consentDwellMs: consentLog.consentDwellMs,
            consentReadDetails: consentLog.consentReadDetails,
            detailsDwellMs: consentLog.detailsDwellMs,
            selfImageLabel: selfImageLabel,
            selfPredictedThetaE: 0.50, // Will be filled in selfPrediction screen
            eyeEnabled: eyeEnabled,
            eyeTimestamp: eyeTimestamp,
            eyeApproachMs: scene.eyeApproachDurationMs,
            shadowAppearances: shadowAppearances,
            shadowCorrect: shadowCorrect,
            decisions: decisions,
            movement: movementSampler.samples,
            finalPosterior: posterior.snapshot(),
            argumentEvents: []
        )

        onSessionComplete?(sessionRecord)
    }

    private func monotonicSecondsSinceStart(at instant: ContinuousClock.Instant) -> Double {
        let duration = instant - sessionStartInstant
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
