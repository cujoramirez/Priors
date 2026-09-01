//  TestFixtures.swift
//  A synthetic but realistic SessionRecord, built by actually running the
//  selector and posterior rather than by hand-writing plausible numbers. Hand
//  numbers drift from what the engine really produces; this cannot.

import Foundation
@testable import PriorsEngine

enum TestFixtures {

    /// A simulated player: engages when the price sits below `trueThetaE` /
    /// `trueThetaI`, deterministically, so tests are reproducible.
    static func session(
        eyeEnabled: Bool = true,
        repeatDiverges: Bool = true,
        trueThetaE: Double = 0.42,
        trueThetaI: Double = 0.25,
        selfPredicted: Double = 0.70
    ) -> SessionRecord {
        var posterior = Posterior()
        var state = SelectionState()
        var decisions: [DecisionRecord] = []

        let eyeIndex = 16
        var eyeTimestamp: Double?
        var t = 4.0

        for slot in 0..<Scenarios.decisionCount {
            let d = ADOSelector.selectDesign(posterior: posterior, slot: slot,
                                             state: state, jitter: { _ in 0.0 })
            let threshold = d.trait == .thetaE ? trueThetaE : trueThetaI
            var engaged = d.price < threshold

            // Force the repeat pair to disagree (or agree) as the test asks.
            if repeatDiverges, d.isRepeatOf != nil { engaged.toggle() }

            let (meanE, sdE) = posterior.meanSD(.thetaE)
            let (meanI, sdI) = posterior.meanSD(.thetaI)
            let predicted = posterior.predictedEngage(price: d.price, trait: d.trait)

            // Hesitate near the line — the near-line inflation from SCHEMA §7.
            let near = exp(-pow((d.price - threshold) / 0.08, 2))
            let rt = Int(1800.0 * (1.0 + 2.5 * near))
            let idle = Int(200.0 + 2500.0 * near)

            if slot == eyeIndex, eyeEnabled { eyeTimestamp = t }
            let eye = EventTriggers.eyeWindow(tPresented: t, eyeTimestamp: eyeTimestamp)

            decisions.append(DecisionRecord(
                index: slot, template: d.template, trait: d.trait, skin: d.skin,
                price: d.price, engaged: engaged,
                tPresented: t, tDecided: t + Double(rt) / 1000.0, rtMs: rt,
                approachFrac: min(1.0, 0.35 + 0.5 * near),
                backtracks: near > 0.5 ? 2 : 0, idleMs: idle,
                eyeWindow: eye.inWindow, eyeSide: eye.side,
                posteriorMeanE: meanE, posteriorSDE: sdE,
                posteriorMeanI: meanI, posteriorSDI: sdI,
                predictedEngage: predicted,
                isRepeatOf: d.isRepeatOf, whyText: nil))

            state.commit(d)
            posterior.update(price: d.price, trait: d.trait, engaged: engaged)
            t += 22.0
        }

        // Backfill eye windows now that eyeTimestamp is known for the whole run.
        if let eyeTS = eyeTimestamp {
            decisions = decisions.map { d in
                let e = EventTriggers.eyeWindow(tPresented: d.tPresented, eyeTimestamp: eyeTS)
                return DecisionRecord(
                    index: d.index, template: d.template, trait: d.trait, skin: d.skin,
                    price: d.price, engaged: d.engaged, tPresented: d.tPresented,
                    tDecided: d.tDecided, rtMs: d.rtMs, approachFrac: d.approachFrac,
                    backtracks: d.backtracks, idleMs: d.idleMs,
                    eyeWindow: e.inWindow, eyeSide: e.side,
                    posteriorMeanE: d.posteriorMeanE, posteriorSDE: d.posteriorSDE,
                    posteriorMeanI: d.posteriorMeanI, posteriorSDI: d.posteriorSDI,
                    predictedEngage: d.predictedEngage, isRepeatOf: d.isRepeatOf,
                    whyText: nil)
            }
        }

        return SessionRecord(
            consentDwellMs: 2_400, consentReadDetails: false, detailsDwellMs: nil,
            selfImageLabel: .curious, selfPredictedThetaE: selfPredicted,
            eyeEnabled: eyeEnabled, eyeTimestamp: eyeTimestamp,
            eyeApproachMs: eyeEnabled ? 6_200 : 0,
            shadowAppearances: [400, 480, 560, 640],
            shadowCorrect: [true, false, true, true],
            decisions: decisions, movement: movement(),
            finalPosterior: posterior.snapshot(), argumentEvents: [])
    }

    /// One decision, for tests about a single claim rather than a whole run.
    /// Posterior fields are placeholders — no claim under test reads them.
    static func decision(
        index: Int, template: TemplateID, trait: Trait, price: Double,
        engaged: Bool, skin: String? = nil, tPresented: Double = 60.0
    ) -> DecisionRecord {
        DecisionRecord(
            index: index, template: template, trait: trait,
            skin: skin ?? Scenarios.templates[template]!.skins[0],
            price: price, engaged: engaged,
            tPresented: tPresented, tDecided: tPresented + 2.0, rtMs: 2_000,
            approachFrac: 0.5, backtracks: 0, idleMs: 500,
            eyeWindow: false, eyeSide: nil,
            posteriorMeanE: 0.42, posteriorSDE: 0.05,
            posteriorMeanI: 0.25, posteriorSDI: 0.05,
            predictedEngage: 0.5, isRepeatOf: nil, whyText: nil)
    }

    /// 4 Hz movement with a deliberately over-visited empty region.
    static func movement() -> [MovementSample] {
        var out: [MovementSample] = []
        var t = 0.0
        for lap in 0..<12 {
            let region = lap % 2 == 0 ? "well" : "house_a"
            for step in 0..<20 {
                out.append(MovementSample(t: t, x: Double(step), y: Double(lap),
                                          moving: step % 7 != 0, regionID: region))
                t += 0.25
            }
        }
        return out
    }
}
