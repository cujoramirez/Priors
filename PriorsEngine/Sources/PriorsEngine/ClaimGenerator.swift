//  ClaimGenerator.swift
//  Turns the final posterior plus the session log into Claims. SPEC §9.
//
//  Every claim here is assembled from logged values and the posterior. Nothing
//  is invented, nothing is phrased — phrasing is COPY.md's job, and Foundation
//  Models may only render a Claim this file produced (SPEC §2.8, §9.3).
//
//  A claim that the data cannot support is not made. `Claim.make` returns nil
//  on empty receipts and every builder below propagates that, so the hard
//  assert in `Claim.init` is a development guarantee rather than a crash path.

import Foundation

public enum ClaimGenerator {

    /// SPEC §9.2 ordering, in the order the sections are listed.
    private static let baseOrder: [ClaimKind] = [
        .opening,
        .confirmLowPrice, .confirmQuick, .temperament,   // 1. match self-image
        .theLine,
        .selfPredictionGap,                              // 2. the gap
        .nearMiss,                                       // 3. the near-miss
        .pointlessDetail,                                // 4. the pointless detail
        .moralLine,                                      // 5. the moral line
        .repeatDivergence,
        .eyeComparison, .eyeApproach,                    // 6. the eye
        .consentNumber,                                  // 7. the consent number
        .gamingBreak, .gamingUnknown,                    // 8. conditional
    ]

    public static func generate(
        session: SessionRecord,
        objectiveRegions: Set<String> = []
    ) -> [Claim] {
        let d = session.decisions.sorted { $0.index < $1.index }
        guard !d.isEmpty else { return [] }
        let post = session.finalPosterior

        var claims: [Claim] = []
        func add(_ c: Claim?) { if let c { claims.append(c) } }

        add(opening(d))
        add(confirmLowPrice(d, post))
        add(confirmQuick(d, post))
        add(temperament(d, session, post))
        add(theLine(d, post))
        add(selfPredictionGap(d, session, post))
        add(nearMiss(d, post))
        add(pointlessDetail(d, session, objectiveRegions, post))
        add(moralLine(d, post))
        add(repeatDivergence(d, post))
        for c in eyeClaims(d, session, post) { claims.append(c) }
        add(consentNumber(d, session, post))
        for c in gamingClaims(d, post) { claims.append(c) }

        return order(claims)
    }

    // MARK: - Ordering

    /// SPEC §9.2 order, then: "Hardest claim is placed third from last, never last."
    ///
    /// SPEC does not define which claim is hardest, so `hardness` below is an
    /// interpretation: the largest measured gap between what the player said or
    /// implied about themselves and what they did. That is the claim the report
    /// exists to deliver, and burying it last would let it be skipped past.
    static func order(_ claims: [Claim]) -> [Claim] {
        var sorted = claims.sorted {
            (baseOrder.firstIndex(of: $0.kind) ?? .max) < (baseOrder.firstIndex(of: $1.kind) ?? .max)
        }
        guard sorted.count >= 3,
              let pick = hardest(sorted),
              let from = sorted.firstIndex(where: { $0.id == pick.id })
        else { return sorted }

        let target = sorted.count - 3
        guard from != target else { return sorted }
        let claim = sorted.remove(at: from)
        sorted.insert(claim, at: target)
        return sorted
    }

    /// The claim to place third from last. Exposed so callers (and tests) use
    /// the same rule the ordering used, rather than recomputing it and
    /// disagreeing on ties.
    ///
    /// Ties are broken by claim-kind order. Two claims can genuinely score the
    /// same hardness — a repeat divergence and a halved giving rate both come
    /// out at 0.5 — and letting iteration order decide made the generator and
    /// its own test pick different claims.
    public static func hardest(_ claims: [Claim]) -> Claim? {
        claims
            .filter { hardness($0) > 0 }
            .min { lhs, rhs in
                let (a, b) = (hardness(lhs), hardness(rhs))
                if a != b { return a > b }                       // hardest first
                return kindRank(lhs.kind) < kindRank(rhs.kind)   // then stable
            }
    }

    static func kindRank(_ k: ClaimKind) -> Int {
        baseOrder.firstIndex(of: k) ?? .max
    }

    static func hardness(_ c: Claim) -> Double {
        switch c.kind {
        case .selfPredictionGap:
            return abs(c.parameters["gap"] ?? 0)
        case .eyeComparison:
            // Behaviour changing under two white dots is the most confronting
            // thing the log can show, so it scales with the size of the shift.
            let b = c.parameters["gave_before_rate"] ?? 0
            let a = c.parameters["gave_after_rate"] ?? 0
            return abs(a - b)
        case .repeatDivergence:
            return 0.5   // same price, different answer
        default:
            return 0
        }
    }

    // MARK: - Builders

    static func opening(_ d: [DecisionRecord]) -> Claim? {
        Claim.make(id: "opening", kind: .opening,
                   parameters: ["n_decisions": Double(d.count)],
                   supportingDecisionIDs: d.map(\.index), confidence: 0)
    }

    /// COPY R2 — "You explored every path below {low_price_pct}% risk."
    static func confirmLowPrice(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        let cut = p.thetaEMean
        let low = d.filter { $0.trait == .thetaE && $0.price < cut }
        guard !low.isEmpty else { return nil }
        let explored = low.filter(\.engaged)
        return Claim.make(
            id: "explore_below_line", kind: .confirmLowPrice,
            parameters: [
                "low_price_pct": cut * 100,
                "n_low_explored": Double(explored.count),
                "n_low_offered": Double(low.count),
            ],
            supportingDecisionIDs: low.map(\.index), confidence: p.thetaESD)
    }

    /// COPY R3 — "You were quick about it. Median {median_rt_low} seconds."
    static func confirmQuick(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        let low = d.filter { $0.trait == .thetaE && $0.price < p.thetaEMean && $0.engaged }
        guard let m = EventTriggers.median(low.map(\.rtSeconds)) else { return nil }
        return Claim.make(
            id: "quick_when_cheap", kind: .confirmQuick,
            parameters: ["median_rt_low": m],
            supportingDecisionIDs: low.map(\.index), confidence: p.thetaESD)
    }

    /// COPY R4 — "Above {high_price_pct}%, you explored {n} in {m}. Your line is at {theta_e_pct}%."
    static func theLine(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        let cut = p.thetaEMean
        let high = d.filter { $0.trait == .thetaE && $0.price >= cut }
        guard !high.isEmpty else { return nil }
        return Claim.make(
            id: "the_line", kind: .theLine,
            parameters: [
                "high_price_pct": cut * 100,
                "n_high_explored": Double(high.filter(\.engaged).count),
                "n_high_offered": Double(high.count),
                "theta_e_pct": p.thetaEMean * 100,
                "theta_e_sd_pct": p.thetaESD * 100,
            ],
            supportingDecisionIDs: high.map(\.index), confidence: p.thetaESD)
    }

    /// COPY R5 — the gap between what they said and what they did.
    static func selfPredictionGap(_ d: [DecisionRecord], _ s: SessionRecord,
                                  _ p: PosteriorSnapshot) -> Claim? {
        let e = d.filter { $0.trait == .thetaE }
        guard !e.isEmpty else { return nil }
        return Claim.make(
            id: "self_prediction_gap", kind: .selfPredictionGap,
            parameters: [
                "self_pred_pct": s.selfPredictedThetaE * 100,
                "theta_e_pct": p.thetaEMean * 100,
                "gap": abs(s.selfPredictedThetaE - p.thetaEMean),
            ],
            supportingDecisionIDs: e.map(\.index), confidence: p.thetaESD)
    }

    /// COPY R6 — "You almost did it. I recorded that too."
    /// The longest hesitation that also involved turning back.
    static func nearMiss(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        let candidates = d.filter { $0.backtracks > 0 && !$0.engaged }
        guard let best = candidates.max(by: { $0.idleMs < $1.idleMs }) else { return nil }
        return Claim.make(
            id: "near_miss", kind: .nearMiss,
            parameters: [
                "ordinal": Double(best.index + 1),
                "approach_pct": best.approachFrac * 100,
                "idle_seconds": Double(best.idleMs) / 1000.0,
                "backtracks": Double(best.backtracks),
            ],
            supportingDecisionIDs: [best.index], confidence: p.thetaESD)
    }

    /// COPY R7 — "You walked past {landmark} {n} times. There is nothing at {landmark}."
    ///
    /// The evidence is movement, but SPEC §9.1 requires decision receipts, so
    /// this cites the decisions that happened while the player was revisiting
    /// the region. If nothing was decided during that stretch there are no
    /// receipts and the claim is not made — which is the correct outcome, not
    /// a limitation to work around.
    static func pointlessDetail(_ d: [DecisionRecord], _ s: SessionRecord,
                                _ objectives: Set<String>, _ p: PosteriorSnapshot) -> Claim? {
        let counts = s.revisitCounts().filter { !objectives.contains($0.key) && $0.value >= 3 }
        guard let (region, visits) = counts.max(by: { $0.value < $1.value }) else { return nil }

        let times = s.movement.filter { $0.regionID == region }.map(\.t)
        guard let first = times.min(), let last = times.max() else { return nil }
        let receipts = d.filter { $0.tPresented >= first && $0.tPresented <= last }.map(\.index)

        return Claim.make(
            id: "pointless_detail", kind: .pointlessDetail,
            parameters: ["revisit_count": Double(visits)],
            stringParameters: ["landmark": region],
            supportingDecisionIDs: receipts, confidence: p.thetaESD)
    }

    /// COPY R9 — the moral line. SPEC forbids interpreting these beyond price.
    ///
    /// Two constraints from COPY v1.1, both of which the first version broke:
    ///
    /// The named surface comes from `subject.skin` — what the player was
    /// actually shown. It used to come from `skins.first` for the template,
    /// which names whichever skin was authored first and can describe a scene
    /// that never appeared in this session. A receipt that names the wrong
    /// scene is a fabricated receipt (SPEC §2.1).
    ///
    /// The subject is drawn only from `ERROR` and `CREDIT`. R9's second line is
    /// "Nothing here would have known", which is false of `GIVE` — a villager
    /// asked and was refused, and knew. `GIVE` still informs θ_i and stays in
    /// the receipts; it is never the decision this line names.
    static func moralLine(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        let moral = d.filter { $0.trait == .thetaI }
        guard !moral.isEmpty else { return nil }

        let unobserved = moral.filter { $0.template == .error || $0.template == .credit }
        guard !unobserved.isEmpty else { return nil }

        // The most expensive one they declined is the one with something to say.
        let subject = unobserved.filter { !$0.engaged }.max(by: { $0.price < $1.price })
            ?? unobserved[0]

        return Claim.make(
            id: "moral_line", kind: .moralLine,
            parameters: [
                "error_time": subject.tPresented,
                "error_cost": subject.price,
                "error_cost_pct": subject.price * 100,
                "theta_i_pct": p.thetaIMean * 100,
                "theta_i_sd_pct": p.thetaISD * 100,
            ],
            stringParameters: [
                "error_skin": subject.skin,
                "error_choice": subject.engaged ? "went back" : "kept walking",
            ],
            supportingDecisionIDs: moral.map(\.index), confidence: p.thetaISD)
    }

    /// COPY R10 — "You chose {self_image_label}."
    static func temperament(_ d: [DecisionRecord], _ s: SessionRecord,
                            _ p: PosteriorSnapshot) -> Claim? {
        let trait = s.selfImageLabel.claimedTrait
        let relevant = d.filter { $0.trait == trait }
        guard !relevant.isEmpty else { return nil }
        return Claim.make(
            id: "temperament", kind: .temperament,
            parameters: [
                "measured_pct": (trait == .thetaE ? p.thetaEMean : p.thetaIMean) * 100,
                "engaged_count": Double(relevant.filter(\.engaged).count),
                "offered_count": Double(relevant.count),
            ],
            stringParameters: ["self_image_label": s.selfImageLabel.rawValue],
            supportingDecisionIDs: relevant.map(\.index),
            confidence: trait == .thetaE ? p.thetaESD : p.thetaISD)
    }

    /// COPY R11 — only if the repeat pair diverged.
    static func repeatDivergence(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> Claim? {
        guard let target = d.first(where: { $0.isRepeatOf != nil }),
              let sourceIndex = target.isRepeatOf,
              let source = d.first(where: { $0.index == sourceIndex }),
              source.engaged != target.engaged
        else { return nil }
        return Claim.make(
            id: "repeat_divergence", kind: .repeatDivergence,
            parameters: [
                "a_ordinal": Double(source.index + 1),
                "b_ordinal": Double(target.index + 1),
                "a_price": source.price,
                "b_price": target.price,
            ],
            supportingDecisionIDs: [source.index, target.index], confidence: p.thetaESD)
    }

    /// COPY R8 — only if `eye_enabled` and a measurable difference exists.
    static func eyeClaims(_ d: [DecisionRecord], _ s: SessionRecord,
                          _ p: PosteriorSnapshot) -> [Claim] {
        guard s.eyeEnabled, let eyeTime = s.eyeTimestamp else { return [] }
        var out: [Claim] = []

        let cmp = EventTriggers.eyeComparison(decisions: d)
        if cmp.changed {
            let receipts = d.filter { $0.eyeWindow && ($0.template == .give || $0.template == .error) }
            if let c = Claim.make(
                id: "eye_comparison", kind: .eyeComparison,
                parameters: [
                    "eye_time": eyeTime,
                    "gave_before": Double(cmp.gaveBefore),
                    "gave_after": Double(cmp.gaveAfter),
                    "offered_before": Double(cmp.offeredBefore),
                    "offered_after": Double(cmp.offeredAfter),
                    "gave_before_rate": Double(cmp.gaveBefore) / Double(cmp.offeredBefore),
                    "gave_after_rate": Double(cmp.gaveAfter) / Double(cmp.offeredAfter),
                ],
                supportingDecisionIDs: receipts.map(\.index), confidence: p.thetaISD
            ) { out.append(c) }
        }

        // COPY R8b — "I don't have a name for that. I only have the seconds."
        if s.eyeApproachMs > 0 {
            let receipts = d.filter { $0.eyeWindow && $0.eyeSide == .after }.map(\.index)
            if let c = Claim.make(
                id: "eye_approach", kind: .eyeApproach,
                parameters: ["eye_approach_seconds": Double(s.eyeApproachMs) / 1000.0],
                supportingDecisionIDs: receipts, confidence: p.thetaISD
            ) { out.append(c) }
        }
        return out
    }

    /// COPY R12 — the consent number. SPEC §2.6: never accuse the player alone.
    static func consentNumber(_ d: [DecisionRecord], _ s: SessionRecord,
                              _ p: PosteriorSnapshot) -> Claim? {
        Claim.make(
            id: "consent_number", kind: .consentNumber,
            parameters: [
                "consent_seconds": Double(s.consentDwellMs) / 1000.0,
                "read_details": s.consentReadDetails ? 1 : 0,
            ],
            supportingDecisionIDs: d.map(\.index), confidence: 0)
    }

    /// COPY G1/G2 — only when both SPEC §6.4 conditions hold.
    static func gamingClaims(_ d: [DecisionRecord], _ p: PosteriorSnapshot) -> [Claim] {
        let m = EventTriggers.gamingMetrics(decisions: d)
        guard m.isGaming, let brk = m.fitBreak else { return [] }
        let after = d.filter { $0.index >= brk }
        let before = d.filter { $0.index < brk }
        let params: [String: Double] = [
            "fit_break": Double(brk),
            "rt_before": EventTriggers.median(before.map(\.rtSeconds)) ?? 0,
            "rt_after": EventTriggers.median(after.map(\.rtSeconds)) ?? 0,
            "rt_ratio": m.rtRatio,
            "reversal_rate": m.reversalRate,
        ]
        return [
            Claim.make(id: "gaming_break", kind: .gamingBreak, parameters: params,
                       supportingDecisionIDs: after.map(\.index), confidence: p.thetaESD),
            Claim.make(id: "gaming_unknown", kind: .gamingUnknown, parameters: params,
                       supportingDecisionIDs: after.map(\.index), confidence: p.thetaESD),
        ].compactMap { $0 }
    }

    /// SPEC §11 — one line, composed from the strongest-confidence claim.
    /// Lower posterior SD is stronger.
    public static func titleClaim(from claims: [Claim]) -> Claim? {
        claims.filter { $0.confidence > 0 }.min { $0.confidence < $1.confidence }
    }
}
