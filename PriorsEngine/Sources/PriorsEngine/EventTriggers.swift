//  EventTriggers.swift
//  SPEC §6. Four events. All are real; none are fictional.
//
//  This file computes *conditions and predictions only*. It never fabricates an
//  outcome. In particular `shadowTarget` returns whatever the posterior
//  actually predicts, including when that is wrong — SPEC §6.2 is explicit:
//  "It must be genuinely predictive. If the model is wrong, the shadow walks
//  the wrong way. Never script it correct."

import Foundation

public enum EventTriggers {

    // MARK: - §6.1 Falsification pricing

    /// True once posterior SD for θ_e drops below 0.06, at which point the next
    /// `PATH` is priced at the posterior mean — genuinely 50/50 for this player.
    ///
    /// The pricing itself lives in `ADOSelector`; this exposes the condition so
    /// the app can reason about it without duplicating the threshold.
    public static func falsificationArmed(posterior: Posterior) -> Bool {
        posterior.meanSD(.thetaE).sd < Scenarios.falsificationSDThreshold
    }

    // MARK: - §6.2 The shadow

    public struct ShadowPrediction: Sendable, Equatable {
        /// What the model expects the player to do at the upcoming decision.
        public let willEngage: Bool
        /// P(engage) that produced it. 0.5 means the model genuinely does not know.
        public let probability: Double
        /// True when the model is close to a coin flip. The app may still show
        /// the shadow — SPEC forbids hiding a wrong prediction, not an unsure one.
        public var isUncertain: Bool { abs(probability - 0.5) < 0.1 }
    }

    /// What `shadowTarget` needs from a posterior: `predictedEngage` alone.
    /// Not part of `ChoicePosterior` (whose EIG machinery never needs it), so
    /// this is its own minimal protocol — same shape as `ChoicePosterior` +
    /// `ADOSelector.selectDesign(posterior: some ChoicePosterior, ...)`.
    /// Both conformances are empty: `Posterior.predictedEngage` and
    /// `BehaviouralPosterior.predictedEngage` already share this signature.
    public protocol EngagementPredicting {
        func predictedEngage(price: Double, trait: Trait) -> Double
    }
    // Conformances are declared at file scope, below `EventTriggers`'s
    // closing brace — Swift doesn't allow an `extension` inside a type body.

    /// Where the shadow should walk, from the posterior alone.
    ///
    /// SPEC §6.2 — after decision 15, four randomised appearances. The
    /// prediction is recorded so `shadow_correct` (SCHEMA §3) can be scored
    /// honestly afterwards.
    public static func shadowTarget(posterior: some EngagementPredicting, nextDesign: Design) -> ShadowPrediction {
        let p = posterior.predictedEngage(price: nextDesign.price, trait: nextDesign.trait)
        return ShadowPrediction(willEngage: p > 0.5, probability: p)
    }

    /// SPEC §6.2 — appearances begin after decision 15.
    public static let shadowFirstDecisionIndex = 15

    // MARK: - §6.3 The eye

    public struct EyeSchedule: Sendable, Equatable {
        public let decisionIndex: Int
        public let durationSeconds: Double
    }

    /// SPEC §6.3 — two white 2×2 dots, three seconds, once per session, at a
    /// randomised decision index in [14, 20]. No sound, no reaction.
    ///
    /// A within-subject manipulation, so `eyeEnabled` gates it for the A/B half.
    public static func scheduleEye(
        enabled: Bool,
        using generator: inout some RandomNumberGenerator
    ) -> EyeSchedule? {
        guard enabled else { return nil }
        return EyeSchedule(
            decisionIndex: Int.random(in: Scenarios.eyeDecisionIndexRange, using: &generator),
            durationSeconds: 3.0
        )
    }

    /// SCHEMA §1 — `eye_window` is true within ±240s of `eye_timestamp`,
    /// and `eye_side` records which side of it the decision fell on.
    public static func eyeWindow(tPresented: Double, eyeTimestamp: Double?)
    -> (inWindow: Bool, side: EyeSide?) {
        guard let eye = eyeTimestamp else { return (false, nil) }
        let delta = tPresented - eye
        guard abs(delta) <= Scenarios.eyeWindowSeconds else { return (false, nil) }
        return (true, delta < 0 ? .before : .after)
    }

    /// SPEC §6.3 — the report compares prosocial behaviour (`GIVE`, `ERROR`) in
    /// the four minutes before against the four minutes after.
    public struct EyeComparison: Sendable, Equatable {
        public let gaveBefore: Int
        public let offeredBefore: Int
        public let gaveAfter: Int
        public let offeredAfter: Int

        /// Only report when both sides actually have decisions to compare.
        /// COPY R8 fires "only if a measurable difference exists"; a comparison
        /// against zero opportunities is not a measurement.
        public var isMeasurable: Bool { offeredBefore > 0 && offeredAfter > 0 }
        public var changed: Bool { isMeasurable && gaveBefore != gaveAfter }
    }

    public static func eyeComparison(decisions: [DecisionRecord]) -> EyeComparison {
        let prosocial: Set<TemplateID> = [.give, .error]
        var gb = 0, ob = 0, ga = 0, oa = 0
        for d in decisions where prosocial.contains(d.template) && d.eyeWindow {
            switch d.eyeSide {
            case .before: ob += 1; if d.engaged { gb += 1 }
            case .after:  oa += 1; if d.engaged { ga += 1 }
            case .none:   break
            }
        }
        return EyeComparison(gaveBefore: gb, offeredBefore: ob, gaveAfter: ga, offeredAfter: oa)
    }

    // MARK: - §6.4 Gaming detection

    /// SPEC §6.4 — not an event, a derived metric.
    public struct GamingMetrics: Sendable, Equatable {
        public let rtRatio: Double
        public let fitBreak: Int?
        public let reversalRate: Double

        /// SPEC §6.4 — report the gaming lines only when BOTH conditions hold.
        /// A slow player is not a gaming player, and a poor fit alone is not
        /// either; COPY G1/G2 assert that something *changed*, which needs both.
        public var isGaming: Bool { rtRatio > 2.0 && fitBreak != nil }
    }

    public static let gamingSplitIndex = 20

    public static func gamingMetrics(
        decisions: [DecisionRecord],
        shadowOnsetIndex: Int = shadowFirstDecisionIndex
    ) -> GamingMetrics {
        let before = decisions.filter { $0.index < gamingSplitIndex }.map(\.rtSeconds)
        let after = decisions.filter { $0.index >= gamingSplitIndex }.map(\.rtSeconds)
        let ratio: Double
        if let mb = median(before), let ma = median(after), mb > 0 {
            ratio = ma / mb
        } else {
            ratio = 1.0
        }

        return GamingMetrics(
            rtRatio: ratio,
            fitBreak: fitBreak(decisions: decisions),
            reversalRate: reversalRate(decisions: decisions, from: shadowOnsetIndex)
        )
    }

    /// SPEC §6.4 — the first index where residuals from the fitted curve exceed
    /// 2σ for three consecutive decisions.
    ///
    /// The residual is `engaged − predicted_engage`, using the prediction
    /// recorded *before* each choice (SCHEMA §1). Using a refitted curve would
    /// be circular: the later decisions would drag the fit toward themselves and
    /// hide the very break being looked for.
    public static func fitBreak(decisions: [DecisionRecord], run: Int = 3) -> Int? {
        let ordered = decisions.sorted { $0.index < $1.index }
        guard ordered.count >= run else { return nil }

        let residuals = ordered.map { ($0.engaged ? 1.0 : 0.0) - $0.predictedEngage }
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        let variance = residuals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(residuals.count)
        let sigma = variance.squareRoot()
        guard sigma > 0 else { return nil }

        var streak = 0
        for (k, r) in residuals.enumerated() {
            if abs(r - mean) > 2 * sigma {
                streak += 1
                if streak == run { return ordered[k - run + 1].index }
            } else {
                streak = 0
            }
        }
        return nil
    }

    /// SPEC §6.4 — choices contradicting the posterior prediction, after shadow onset.
    public static func reversalRate(decisions: [DecisionRecord], from index: Int) -> Double {
        let after = decisions.filter { $0.index >= index }
        guard !after.isEmpty else { return 0 }
        let contradictions = after.filter { $0.engaged != ($0.predictedEngage > 0.5) }.count
        return Double(contradictions) / Double(after.count)
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}

// `EngagementPredicting` conformances (Swift extensions can't nest inside
// `EventTriggers`, so they live here, next to the protocol's declaration
// above). Both are empty: `Posterior.predictedEngage` (Posterior.swift:180)
// and `BehaviouralPosterior.predictedEngage` (BehaviouralPosterior.swift:399)
// already match the protocol's signature exactly.
extension Posterior: EventTriggers.EngagementPredicting {}
extension BehaviouralPosterior: EventTriggers.EngagementPredicting {}
