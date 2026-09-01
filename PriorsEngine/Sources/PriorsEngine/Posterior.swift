//  Posterior.swift
//  Grid posterior over (θ_e, θ_i, β). SPEC §3.4.
//
//      P(engage | p, θ, β) = 1 / (1 + exp(β · (p − θ)))
//
//  Joint over 33 × 25 × 15 = 12,375 cells. Multiplicative update after every
//  decision, renormalise. That is the whole model.
//
//  Port of `priors-research/priors/posterior.py`, which is validated against
//  ADOpy. `PosteriorGoldenTests` asserts this file reproduces that reference on
//  a fixed decision sequence, so the two must not drift.
//
//  Everything is done in log space: β reaches 30 and prices reach 0.85, so
//  β·(p−θ) reaches ~24 and a naive exp() loses precision well before that.

import Foundation

/// Numerically stable `log(sigmoid(-z))`, i.e. `-log(1 + exp(z))`.
@inlinable
func negLogAddExpZero(_ z: Double) -> Double {
    z >= 0 ? -(z + log1p(exp(-z))) : -log1p(exp(z))
}

public struct Posterior: Sendable, ChoicePosterior {
    public let thetaE: [Double]
    public let thetaI: [Double]
    public let beta: [Double]

    /// Flat log-posterior. Index order is `(e, i, b)` — the same axis order as
    /// the Python reference, and load-bearing for the golden fixtures.
    public private(set) var logPost: [Double]

    @usableFromInline let nE: Int
    @usableFromInline let nI: Int
    @usableFromInline let nB: Int

    public init() {
        thetaE = Grids.thetaE.values()
        thetaI = Grids.thetaI.values()
        beta = Grids.beta.values()
        nE = thetaE.count
        nI = thetaI.count
        nB = beta.count
        // SPEC §3.1/§3.2 — uniform prior over each grid's support.
        let count = nE * nI * nB
        logPost = [Double](repeating: -log(Double(count)), count: count)
    }

    @inlinable
    public func index(_ e: Int, _ i: Int, _ b: Int) -> Int { (e * nI + i) * nB + b }

    // MARK: - Update

    /// Multiplicative update, then renormalise. SPEC §3.4.
    ///
    /// `weight` supports the argument screen (SPEC §10), which refits with a
    /// disputed decision down-weighted to 0.5 (`situation`) or 0.2 (`misread`).
    /// `weight` 1.0 is the ordinary in-play update.
    public mutating func update(price: Double, trait: Trait, engaged: Bool, weight: Double = 1.0) {
        // The likelihood is constant along the other trait's axis, so it is
        // computed once per (θ, β) pair rather than per cell.
        let theta = trait == .thetaE ? thetaE : thetaI
        var table = [Double](repeating: 0, count: theta.count * nB)
        for t in 0..<theta.count {
            for b in 0..<nB {
                let z = beta[b] * (price - theta[t])
                table[t * nB + b] = weight * (engaged ? negLogAddExpZero(z) : negLogAddExpZero(-z))
            }
        }

        if trait == .thetaE {
            for e in 0..<nE {
                for i in 0..<nI {
                    let base = (e * nI + i) * nB
                    for b in 0..<nB { logPost[base + b] += table[e * nB + b] }
                }
            }
        } else {
            for e in 0..<nE {
                for i in 0..<nI {
                    let base = (e * nI + i) * nB
                    for b in 0..<nB { logPost[base + b] += table[i * nB + b] }
                }
            }
        }
        normalise()
    }

    private mutating func normalise() {
        let m = logPost.max() ?? 0
        guard m.isFinite else { return }
        var sum = 0.0
        for v in logPost { sum += exp(v - m) }
        let offset = m + log(sum)
        for k in 0..<logPost.count { logPost[k] -= offset }
    }

    /// Rebuild from scratch. Backs the SPEC §10 refit, which re-runs the whole
    /// sequence with one decision down-weighted rather than dividing it back out.
    public static func from(
        observations: [(price: Double, trait: Trait, engaged: Bool)],
        weights: [Double]? = nil
    ) -> Posterior {
        let w = weights ?? [Double](repeating: 1.0, count: observations.count)
        precondition(w.count == observations.count,
                     "weights count \(w.count) != observations count \(observations.count)")
        var p = Posterior()
        for (o, wi) in zip(observations, w) {
            p.update(price: o.price, trait: o.trait, engaged: o.engaged, weight: wi)
        }
        return p
    }

    // MARK: - Summaries

    public var joint: [Double] { logPost.map(exp) }

    public func marginal(_ trait: Trait) -> [Double] {
        let n = trait == .thetaE ? nE : nI
        var out = [Double](repeating: 0, count: n)
        for e in 0..<nE {
            for i in 0..<nI {
                let base = (e * nI + i) * nB
                var s = 0.0
                for b in 0..<nB { s += exp(logPost[base + b]) }
                out[trait == .thetaE ? e : i] += s
            }
        }
        return out
    }

    public func betaMarginal() -> [Double] {
        var out = [Double](repeating: 0, count: nB)
        for e in 0..<nE {
            for i in 0..<nI {
                let base = (e * nI + i) * nB
                for b in 0..<nB { out[b] += exp(logPost[base + b]) }
            }
        }
        return out
    }

    /// The (θ, β) marginal the ADO EIG runs on. Exact, not an approximation:
    /// the choice likelihood is constant along the other trait's axis.
    public func traitBetaMarginal(_ trait: Trait) -> [Double] {
        let n = trait == .thetaE ? nE : nI
        var out = [Double](repeating: 0, count: n * nB)
        for e in 0..<nE {
            for i in 0..<nI {
                let base = (e * nI + i) * nB
                let row = (trait == .thetaE ? e : i) * nB
                for b in 0..<nB { out[row + b] += exp(logPost[base + b]) }
            }
        }
        return out
    }

    public func meanSD(_ trait: Trait) -> (mean: Double, sd: Double) {
        meanAndSD(grid: trait == .thetaE ? thetaE : thetaI, marginal: marginal(trait))
    }

    public func betaMeanSD() -> (mean: Double, sd: Double) {
        meanAndSD(grid: beta, marginal: betaMarginal())
    }

    /// Shannon entropy of the joint, in nats. Used by the ADO EIG (SPEC §5.3).
    public func entropy() -> Double {
        var h = 0.0
        for v in logPost {
            let p = exp(v)
            if p > 0 { h -= p * v }
        }
        return h
    }

    /// Posterior predictive P(engage), marginalising over (θ, β).
    ///
    /// SCHEMA §1: this must be recorded *before* the choice is known. That is
    /// what makes the prediction ledger honest.
    public func predictedEngage(price: Double, trait: Trait) -> Double {
        let theta = trait == .thetaE ? thetaE : thetaI
        let w = traitBetaMarginal(trait)
        var total = 0.0
        for t in 0..<theta.count {
            for b in 0..<nB {
                let z = beta[b] * (price - theta[t])
                total += w[t * nB + b] * exp(negLogAddExpZero(z))
            }
        }
        return total
    }

    public func snapshot() -> PosteriorSnapshot {
        let (me, se) = meanSD(.thetaE)
        let (mi, si) = meanSD(.thetaI)
        let (bm, bs) = betaMeanSD()
        return PosteriorSnapshot(
            thetaEMean: me, thetaESD: se,
            thetaEGrid: thetaE, thetaEMarginal: marginal(.thetaE),
            thetaIMean: mi, thetaISD: si,
            thetaIGrid: thetaI, thetaIMarginal: marginal(.thetaI),
            betaMean: bm, betaSD: bs
        )
    }
}

@usableFromInline
func meanAndSD(grid: [Double], marginal: [Double]) -> (mean: Double, sd: Double) {
    var mean = 0.0
    for k in 0..<grid.count { mean += grid[k] * marginal[k] }
    var variance = 0.0
    for k in 0..<grid.count {
        let d = grid[k] - mean
        variance += marginal[k] * d * d
    }
    return (mean, (max(variance, 0)).squareRoot())
}
