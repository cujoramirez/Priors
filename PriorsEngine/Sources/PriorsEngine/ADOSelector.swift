//  ADOSelector.swift
//  Adaptive Design Optimisation. SPEC §5, §5.1, §6.1.
//
//      EIG(d) = H[posterior] − E_y[ H[posterior | y, d] ]
//
//  Two things are worth knowing before reading this file.
//
//  **EIG cannot choose the template.** Under SPEC §3.4 the likelihood of a
//  response depends only on the price and which trait the template maps to —
//  never on the template's identity. So PATH, DETOUR and TRADE have *identical*
//  EIG at the same price, as do ERROR, CREDIT and GIVE. "ADO picks the
//  template" (SPEC §5.1) is therefore always an exact tie, and something
//  outside EIG has to break it. `templatePriority` breaks it by proportional
//  spread, which is what actually delivers the variety the curiosity override
//  is reaching for. That tie-break is an engineering decision, not a SPEC quote.
//
//  **EIG is computed as mutual information.** `H[posterior] − E_y H[posterior|y]`
//  equals `H[Y] − E_params H[Y|params]`, because mutual information is
//  symmetric. The second form needs no renormalisation per outcome and runs on
//  the 2-D (θ, β) marginal rather than all 12,375 cells — the likelihood is
//  constant along the other trait's axis, so the reduction is exact. The Python
//  reference asserts the two forms agree to 1e-12 and validates the result
//  against ADOpy.
//
//  Port of `priors-research/priors/ado.py`.

import Foundation

/// What the EIG needs from a posterior, and nothing more.
///
/// Under SPEC §3.4 the choice likelihood depends only on (θ, β), so the design
/// selector never has to know whether the posterior behind it also carries the
/// hesitation nuisance axes. `priors/ado.py` gets this for free from Python's
/// duck typing and runs unchanged on both `Posterior` and `BehaviouralPosterior`;
/// this protocol is what keeps the Swift port equally indifferent.
public protocol ChoicePosterior {
    var thetaE: [Double] { get }
    var thetaI: [Double] { get }
    var beta: [Double] { get }

    /// The (θ, β) marginal. Exact for both conformers: the choice likelihood is
    /// constant along every axis this drops.
    func traitBetaMarginal(_ trait: Trait) -> [Double]

    /// SPEC §6.1 falsification pricing reads the θ_e mean and SD to decide when
    /// to price the next `PATH` at the posterior mean.
    func meanSD(_ trait: Trait) -> (mean: Double, sd: Double)
}

public struct Design: Sendable, Equatable {
    public let slot: Int
    public let template: TemplateID
    public let trait: Trait
    public let price: Double
    public let skin: String
    public let instance: Int
    public let eig: Double
    public let priceRule: PriceRule
    public let curiosityOverride: Bool
    public let isRepeatOf: Int?

    public enum PriceRule: String, Sendable, Codable {
        case eig, repeatPrice = "repeat", falsification
    }
}

/// Mutable bookkeeping across a session's 30 slots.
public struct SelectionState: Sendable {
    public private(set) var remaining: [TemplateID: Int]
    public private(set) var used: [TemplateID: Int]
    public private(set) var lastSlot: [TemplateID: Int]
    public private(set) var recent: [TemplateID] = []
    public private(set) var repeatSourcePrice: Double?
    public private(set) var repeatSourceSlot: Int?
    public private(set) var falsificationFired = false

    public init() {
        remaining = Scenarios.templates.mapValues(\.instances)
        used = Dictionary(uniqueKeysWithValues: TemplateID.allCases.map { ($0, 0) })
        lastSlot = Dictionary(uniqueKeysWithValues: TemplateID.allCases.map { ($0, -1_000_000) })
    }

    public mutating func commit(_ d: Design) {
        remaining[d.template, default: 0] -= 1
        used[d.template, default: 0] += 1
        lastSlot[d.template] = d.slot
        recent.append(d.template)
        if d.template == Scenarios.repeatTemplate, d.instance == Scenarios.repeatSourceInstance {
            repeatSourcePrice = d.price
            repeatSourceSlot = d.slot
        }
        if d.priceRule == .falsification { falsificationFired = true }
    }

    /// SPEC §5.1 — a template is blocked once the previous two slots both used
    /// it. That caps any template at a run of two.
    var blockedByCuriosity: TemplateID? {
        guard recent.count >= Scenarios.curiosityRunLimit else { return nil }
        let tail = recent.suffix(Scenarios.curiosityRunLimit)
        return Set(tail).count == 1 ? tail.first : nil
    }
}

public enum ADOSelector {

    /// Entropy of a Bernoulli, in nats, safe at p ∈ {0, 1}.
    @inlinable
    static func binaryEntropy(_ p: Double) -> Double {
        let q = min(max(p, 1e-300), 1.0 - 1e-16)
        return -(q * log(q) + (1 - q) * log1p(-q))
    }

    /// Two candidate prices equidistant from the posterior mean have
    /// mathematically identical EIG — at the uniform prior, indices 5 and 6
    /// differ by 1.7e-16, pure float noise. NumPy and Swift disagree on which
    /// is larger, so a bare argmax makes this port diverge at slot 0 and
    /// cascade. The tie-break is therefore explicit and matches `ado.py`.
    public static let eigTieTolerance = 1e-12

    /// First index whose EIG exceeds the running best by more than the tie
    /// tolerance. Deterministic across languages.
    public static func argmaxEIG(_ eigs: [Double]) -> Int {
        var best = 0
        for k in 1..<eigs.count where eigs[k] > eigs[best] + eigTieTolerance { best = k }
        return best
    }

    /// EIG in nats for each candidate price. SPEC §5.3, mutual-information form.
    public static func expectedInformationGain(
        posterior: some ChoicePosterior, prices: [Double], trait: Trait
    ) -> [Double] {
        let theta = trait == .thetaE ? posterior.thetaE : posterior.thetaI
        let beta = posterior.beta
        let w = posterior.traitBetaMarginal(trait)
        let nB = beta.count

        return prices.map { price in
            var predictive = 0.0
            var expectedConditional = 0.0
            for t in 0..<theta.count {
                for b in 0..<nB {
                    let weight = w[t * nB + b]
                    if weight == 0 { continue }
                    let pe = exp(negLogAddExpZero(beta[b] * (price - theta[t])))
                    predictive += weight * pe
                    expectedConditional += weight * binaryEntropy(pe)
                }
            }
            return binaryEntropy(predictive) - expectedConditional
        }
    }

    /// Highest-averages (D'Hondt) spread: quota ÷ (times used + 1).
    ///
    /// Keeps each template's share of its trait's slots close to its quota share
    /// throughout the session, instead of front-loading the large quota and
    /// leaving a run of identical scenarios at the end.
    static func templatePriority(_ state: SelectionState, _ id: TemplateID) -> Double {
        Double(Scenarios.templates[id]!.instances) / (Double(state.used[id] ?? 0) + 1.0)
    }

    /// Choose the template and price for one slot. SPEC §5, §5.1, §6.1.
    ///
    /// `jitter` returns an offset in ±`Scenarios.priceJitter`; pass a constant
    /// zero to reproduce the Python fixtures, which are generated with jitter off.
    public static func selectDesign(
        posterior: some ChoicePosterior,
        slot: Int,
        state: SelectionState,
        jitter: (Double) -> Double = { Double.random(in: -$0...$0) }
    ) -> Design {
        let trait = Scenarios.traitSchedule[slot]

        var eligible = Scenarios.templatesByTrait[trait]!.filter { (state.remaining[$0] ?? 0) > 0 }
        precondition(!eligible.isEmpty, "slot \(slot): no template with quota left for \(trait)")

        // Curiosity override, unless honouring it would leave nothing to present.
        var overrideApplied = false
        if let blocked = state.blockedByCuriosity, eligible.contains(blocked), eligible.count > 1 {
            eligible.removeAll { $0 == blocked }
            overrideApplied = true
        }

        let prices = Scenarios.candidatePrices(for: trait)
        let eigs = expectedInformationGain(posterior: posterior, prices: prices, trait: trait)
        let best = argmaxEIG(eigs)
        let bestPrice = prices[best]
        let bestEIG = eigs[best]

        // Every eligible template shares `bestEIG`, so this is a pure tie-break.
        let template = eligible.max { a, b in
            let pa = templatePriority(state, a), pb = templatePriority(state, b)
            if pa != pb { return pa < pb }
            let la = slot - (state.lastSlot[a] ?? 0), lb = slot - (state.lastSlot[b] ?? 0)
            if la != lb { return la < lb }
            let ia = Scenarios.templateOrder.firstIndex(of: a)!
            let ib = Scenarios.templateOrder.firstIndex(of: b)!
            return ia > ib
        }!

        let instance = (state.used[template] ?? 0) + 1
        let t = Scenarios.templates[template]!
        var priceRule = Design.PriceRule.eig
        var isRepeatOf: Int? = nil
        var price: Double

        let sdE = posterior.meanSD(.thetaE).sd
        let meanE = posterior.meanSD(.thetaE).mean

        if template == Scenarios.repeatTemplate,
           instance == Scenarios.repeatTargetInstance,
           let source = state.repeatSourcePrice {
            // SPEC §4 — re-price within ±0.03 of the source instance for
            // test-retest. Takes precedence over falsification pricing, which is
            // not tied to a specific instance and simply fires at the next PATH.
            price = min(max(source + jitter(Scenarios.repeatTolerance), t.priceLo), t.priceHi)
            priceRule = .repeatPrice
            isRepeatOf = state.repeatSourceSlot
        } else if template == Scenarios.repeatTemplate,
                  !state.falsificationFired,
                  sdE < Scenarios.falsificationSDThreshold {
            // SPEC §6.1 — the hardest possible decision for this player.
            price = min(max(meanE, t.priceLo), t.priceHi)
            priceRule = .falsification
        } else {
            price = min(max(bestPrice + jitter(Scenarios.priceJitter), t.priceLo), t.priceHi)
        }

        return Design(
            slot: slot, template: template, trait: trait, price: price,
            skin: t.skins[(instance - 1) % t.skins.count],
            instance: instance, eig: bestEIG, priceRule: priceRule,
            curiosityOverride: overrideApplied, isRepeatOf: isRepeatOf
        )
    }
}
