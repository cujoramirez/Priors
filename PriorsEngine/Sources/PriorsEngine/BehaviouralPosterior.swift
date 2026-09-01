//  BehaviouralPosterior.swift
//  Grid posterior over (θ_e, θ_i, β, rt_base, peak, σ). Extends SPEC §3.4 with
//  the channel that was always in the log and never read.
//
//  Choice tells you the **direction** of θ relative to the price. Hesitation
//  tells you the **distance**: SCHEMA §7 makes response time peak exactly at the
//  player's line, and that peak is symmetric in θ around p, so it localises
//  |p − θ| without saying which side. The two are complementary, and together
//  they cut MAE θ_e at decision 15 from 0.065 to 0.018.
//
//  **The RT law is inferred, never assumed.** This is the whole reason the type
//  is shaped the way it is. `experiments/rt_robustness.py` fixed SCHEMA §7's RT
//  parameters and varied the world: when the true near-line effect is absent,
//  MAE goes to 0.139 with calibration 0.26 — worse than ignoring hesitation
//  entirely, while claiming four times more precision than it has. That is a
//  machine confidently asserting a line the player does not have, which SPEC §0
//  and non-negotiable §2.1 forbid outright.
//
//  So `peak`, `sigma` and `rt_base` are carried as nuisance dimensions. A player
//  whose hesitation says nothing drives the `peak` posterior toward 0 and the RT
//  term stops contributing on its own: misspecification degrades into
//  uncertainty rather than into a confident wrong answer. None of the three is
//  ever reported. They exist to be marginalised away.
//
//  Port of `priors-research/priors/rt_posterior.py`. `BehaviouralPosteriorGoldenTests`
//  asserts this file reproduces that reference step by step, so the two must not
//  drift. Axis order is fixed and load-bearing for those fixtures.

import Foundation

/// What the model concluded about how this player hesitates.
///
/// Diagnostic only — never a report claim. SPEC §2.8 makes the grid posterior
/// over θ the sole source of what the report says, and these three parameters
/// exist to be integrated out of it.
public struct RTLawSummary: Sendable, Equatable {
    public let peakMean: Double
    public let peakSD: Double
    public let sigmaMean: Double
    public let rtBaseMean: Double

    /// True when hesitation is informative enough to lean on — the peak is
    /// separated from zero by more than its own spread.
    public var carriesSignal: Bool { peakMean - peakSD > 0.0 }
}

public struct BehaviouralPosterior: Sendable, ChoicePosterior {

    // MARK: - Nuisance grids

    /// Prior width on the per-player baseline response time, in log space.
    ///
    /// SCHEMA §7 gives LogNormal(log 2000, **0.4**), and that prior is
    /// deliberately not reused. It is informative enough to do harm: it is what
    /// lets a uniformly slow response be read as "near the line" rather than
    /// "slow player", so a population slower than SCHEMA §7 assumes would be
    /// systematically misread. `experiments/rt_base_prior.py` sweeps it — at
    /// sd 0.4 a 2.5×-slower population costs accuracy (0.0221, calibration
    /// 1.03); at sd 0.8 the channel is flat across every population tested
    /// (0.0176–0.0183, calibration ≥ 1.28) at no cost when SCHEMA §7 is right.
    ///
    /// Vaguer is strictly better here. `rt_base` is a nuisance parameter we have
    /// no verified knowledge of, and nothing is gained by pretending otherwise.
    /// A test guards against tightening this casually.
    public static let rtBasePriorSD = 0.8

    /// SCHEMA §7's median, and the centre of the `rt_base` prior.
    public static let rtBaseMedianMs = 2000.0

    /// Near-line RT inflation. SCHEMA §7 asserts 2.5; we infer it.
    ///
    /// **0.0 is on this grid on purpose.** Without it, "this player's hesitation
    /// says nothing" is not representable and the channel cannot switch itself
    /// off — which is the single property that makes reading RT safe.
    public static let peakGrid: [Double] = [0.0, 0.6, 1.3, 2.2, 3.4]

    /// Trial-level RT scatter, in log space. SCHEMA §7.1 assumes 0.25.
    public static let sigmaGrid: [Double] = [0.22, 0.38, 0.62]

    /// Width of the near-line band, shared with SCHEMA §7.1's generator.
    /// Held fixed: robustness testing showed misspecifying it costs little once
    /// `peak` is free (0.0197–0.0269 MAE).
    public static let bandWidth = 0.08

    /// Log-spaced, ±2.4 prior SDs either side of the median.
    public static let rtBaseSpec = GridSpec(
        lo: rtBaseMedianMs * exp(-2.4 * rtBasePriorSD),
        hi: rtBaseMedianMs * exp(2.4 * rtBasePriorSD),
        n: 11, isLog: true)

    /// 33 · 25 · 15 · 11 · 5 · 3 = 2,041,875 cells — 16.3 MB of `Double`, and a
    /// handful of passes per decision. FINDINGS.md asked for this sizing
    /// decision explicitly; `Double` rather than `Float` is what buys agreement
    /// with the Python reference to 1e-9.
    public static let cellCount =
        Grids.thetaE.n * Grids.thetaI.n * Grids.beta.n
        * rtBaseSpec.n * peakGrid.count * sigmaGrid.count

    // MARK: - Axes

    public let thetaE: [Double]
    public let thetaI: [Double]
    public let beta: [Double]
    public let rtBase: [Double]
    public let peak: [Double]
    public let sigma: [Double]

    /// Flat log-posterior. Index order is `(e, i, b, r, pk, s)` — the same axis
    /// order as the Python reference, and load-bearing for the golden fixtures.
    public private(set) var logPost: [Double]

    private let nE, nI, nB, nR, nP, nS: Int
    /// Cells spanned by the three nuisance axes, i.e. the stride of one β step.
    private let block: Int
    private let strideE, strideI, strideB, strideR, strideP: Int

    // Marginals are recomputed once per update rather than per query. Every
    // summary below wants a contraction of the same 2-million-cell array, and
    // walking it once for all of them is the difference between a few
    // milliseconds and a few hundred.
    private var marginalE: [Double] = []
    private var marginalI: [Double] = []
    private var marginalB: [Double] = []
    private var marginalR: [Double] = []
    private var marginalP: [Double] = []
    private var marginalS: [Double] = []
    private var marginalEB: [Double] = []
    private var marginalIB: [Double] = []
    private var cachedEntropy: Double = 0

    // MARK: - Init

    public init() {
        thetaE = Grids.thetaE.values()
        thetaI = Grids.thetaI.values()
        beta = Grids.beta.values()
        rtBase = Self.rtBaseSpec.values()
        peak = Self.peakGrid
        sigma = Self.sigmaGrid

        nE = thetaE.count; nI = thetaI.count; nB = beta.count
        nR = rtBase.count; nP = peak.count; nS = sigma.count

        block = nR * nP * nS
        strideP = nS
        strideR = nP * nS
        strideB = block
        strideI = nB * block
        strideE = nI * nB * block

        // Weak prior on rt_base; uniform on everything else, matching SPEC
        // §3.1/§3.2's deliberately conservative choice.
        var lp = [Double](repeating: 0, count: nE * strideE)
        var rtPrior = [Double](repeating: 0, count: nR)
        for r in 0..<nR {
            let z = (log(rtBase[r]) - log(Self.rtBaseMedianMs)) / Self.rtBasePriorSD
            rtPrior[r] = -0.5 * z * z
        }
        // The prior varies only along rt_base, so it is written one nuisance
        // block at a time rather than with a division per cell.
        let blockSize = block, sR = strideR, countR = nR, sP = strideP, countP = nP, countS = nS
        lp.withUnsafeMutableBufferPointer { buf in
            var start = 0
            while start < buf.count {
                for r in 0..<countR {
                    let v = rtPrior[r]
                    let rBase = start + r * sR
                    for pk in 0..<countP {
                        let pBase = rBase + pk * sP
                        for s in 0..<countS { buf[pBase + s] = v }
                    }
                }
                start += blockSize
            }
        }
        logPost = lp
        normalise()
        refreshMarginals()
    }

    public func index(_ e: Int, _ i: Int, _ b: Int, _ r: Int, _ pk: Int, _ s: Int) -> Int {
        (((e * nI + i) * nB + b) * nR + r) * nP * nS + pk * nS + s
    }

    // MARK: - Likelihoods

    /// SPEC §3.4, unchanged. Depends on (θ, β) only.
    func choiceLogLik(price: Double, trait: Trait, engaged: Bool) -> [Double] {
        let theta = trait == .thetaE ? thetaE : thetaI
        var out = [Double](repeating: 0, count: theta.count * nB)
        for t in 0..<theta.count {
            for b in 0..<nB {
                let z = beta[b] * (price - theta[t])
                out[t * nB + b] = engaged ? negLogAddExpZero(z) : negLogAddExpZero(-z)
            }
        }
        return out
    }

    /// `log N(log rt ; log rt_base + log1p(peak · near), σ²)`, over
    /// (θ, rt_base, peak, σ). Constant along β and along the other trait's axis.
    ///
    /// The `−log σ` normaliser matters: with σ inferred it is no longer a
    /// constant, and dropping it would make the widest σ win every time.
    func rtLogLik(price: Double, trait: Trait, rtMs: Double) -> [Double] {
        let theta = trait == .thetaE ? thetaE : thetaI
        let logRT = log(max(rtMs, 1.0))
        var out = [Double](repeating: 0, count: theta.count * block)
        for t in 0..<theta.count {
            let d = (price - theta[t]) / Self.bandWidth
            let near = exp(-(d * d))
            for r in 0..<nR {
                let logBase = log(rtBase[r])
                for pk in 0..<nP {
                    let mu = logBase + log1p(peak[pk] * near)
                    for s in 0..<nS {
                        let z = (logRT - mu) / sigma[s]
                        out[t * block + r * strideR + pk * strideP + s] =
                            -0.5 * z * z - log(sigma[s])
                    }
                }
            }
        }
        return out
    }

    // MARK: - Update

    /// Multiplicative update on choice, and on hesitation when it is available.
    ///
    /// `weight` carries the SPEC §10 argument-screen down-weighting (0.5 for
    /// `situation`, 0.2 for `misread`) across **both** channels: a decision the
    /// player disputes should lose its hesitation evidence too.
    ///
    /// `rtMs: nil` degrades exactly to the choice-only posterior — the nuisance
    /// axes stay at their prior and factor out of every trait marginal.
    public mutating func update(
        price: Double, trait: Trait, engaged: Bool,
        rtMs: Double? = nil, weight: Double = 1.0
    ) {
        let choice = choiceLogLik(price: price, trait: trait, engaged: engaged)
        let rt = rtMs.map { rtLogLik(price: price, trait: trait, rtMs: $0) }
        let isE = trait == .thetaE
        let (nE, nI, nB, block) = (nE, nI, nB, block)
        let (strideE, strideI, strideB) = (strideE, strideI, strideB)

        logPost.withUnsafeMutableBufferPointer { post in
            choice.withUnsafeBufferPointer { ch in
                for e in 0..<nE {
                    for i in 0..<nI {
                        let t = isE ? e : i
                        let rowBase = e * strideE + i * strideI
                        for b in 0..<nB {
                            let c = ch[t * nB + b]
                            let base = rowBase + b * strideB
                            if let rt {
                                let rtRow = t * block
                                rt.withUnsafeBufferPointer { rtp in
                                    for k in 0..<block {
                                        post[base + k] += weight * (c + rtp[rtRow + k])
                                    }
                                }
                            } else {
                                let add = weight * c
                                for k in 0..<block { post[base + k] += add }
                            }
                        }
                    }
                }
            }
        }
        normalise()
        refreshMarginals()
    }

    private mutating func normalise() {
        logPost.withUnsafeMutableBufferPointer { post in
            var m = -Double.infinity
            for k in 0..<post.count where post[k] > m { m = post[k] }
            guard m.isFinite else { return }
            var sum = 0.0
            for k in 0..<post.count { sum += exp(post[k] - m) }
            let offset = m + log(sum)
            for k in 0..<post.count { post[k] -= offset }
        }
    }

    /// One walk of the joint, every contraction the type exposes.
    private mutating func refreshMarginals() {
        var mE = [Double](repeating: 0, count: nE)
        var mI = [Double](repeating: 0, count: nI)
        var mB = [Double](repeating: 0, count: nB)
        var mR = [Double](repeating: 0, count: nR)
        var mP = [Double](repeating: 0, count: nP)
        var mS = [Double](repeating: 0, count: nS)
        var mEB = [Double](repeating: 0, count: nE * nB)
        var mIB = [Double](repeating: 0, count: nI * nB)
        var h = 0.0
        let (nE, nI, nB, nR, nP, nS) = (nE, nI, nB, nR, nP, nS)
        let (strideE, strideI, strideB, strideR, strideP) =
            (strideE, strideI, strideB, strideR, strideP)

        logPost.withUnsafeBufferPointer { post in
            for e in 0..<nE {
                for i in 0..<nI {
                    let rowBase = e * strideE + i * strideI
                    for b in 0..<nB {
                        let base = rowBase + b * strideB
                        // The (θ, β) cell total, reused by every contraction
                        // that keeps β — including the two the EIG runs on.
                        var cell = 0.0
                        for r in 0..<nR {
                            let rBase = base + r * strideR
                            var rSum = 0.0
                            for pk in 0..<nP {
                                let pBase = rBase + pk * strideP
                                var pSum = 0.0
                                for s in 0..<nS {
                                    let lp = post[pBase + s]
                                    let p = exp(lp)
                                    pSum += p
                                    mS[s] += p
                                    if p > 0 { h -= p * lp }
                                }
                                mP[pk] += pSum
                                rSum += pSum
                            }
                            mR[r] += rSum
                            cell += rSum
                        }
                        mE[e] += cell
                        mI[i] += cell
                        mB[b] += cell
                        mEB[e * nB + b] += cell
                        mIB[i * nB + b] += cell
                    }
                }
            }
        }

        marginalE = mE; marginalI = mI; marginalB = mB
        marginalR = mR; marginalP = mP; marginalS = mS
        marginalEB = mEB; marginalIB = mIB
        cachedEntropy = h
    }

    /// Rebuild from scratch. Backs the SPEC §10 refit, which re-runs the whole
    /// sequence with one decision down-weighted rather than dividing it back out.
    public static func from(
        observations: [(price: Double, trait: Trait, engaged: Bool, rtMs: Double?)],
        weights: [Double]? = nil
    ) -> BehaviouralPosterior {
        let w = weights ?? [Double](repeating: 1.0, count: observations.count)
        precondition(w.count == observations.count,
                     "weights count \(w.count) != observations count \(observations.count)")
        var p = BehaviouralPosterior()
        for (o, wi) in zip(observations, w) {
            p.update(price: o.price, trait: o.trait, engaged: o.engaged,
                     rtMs: o.rtMs, weight: wi)
        }
        return p
    }

    // MARK: - Summaries

    public func marginal(_ trait: Trait) -> [Double] {
        trait == .thetaE ? marginalE : marginalI
    }

    public func betaMarginal() -> [Double] { marginalB }

    /// The (θ, β) marginal the ADO EIG runs on. Exact, not an approximation:
    /// the choice likelihood is constant along every axis this drops.
    public func traitBetaMarginal(_ trait: Trait) -> [Double] {
        trait == .thetaE ? marginalEB : marginalIB
    }

    public func meanSD(_ trait: Trait) -> (mean: Double, sd: Double) {
        meanAndSD(grid: trait == .thetaE ? thetaE : thetaI, marginal: marginal(trait))
    }

    public func betaMeanSD() -> (mean: Double, sd: Double) {
        meanAndSD(grid: beta, marginal: marginalB)
    }

    /// What the model concluded about this player's hesitation. Diagnostic only.
    public func rtLaw() -> RTLawSummary {
        let (pkMean, pkSD) = meanAndSD(grid: peak, marginal: marginalP)
        return RTLawSummary(
            peakMean: pkMean,
            peakSD: pkSD,
            sigmaMean: meanAndSD(grid: sigma, marginal: marginalS).mean,
            rtBaseMean: meanAndSD(grid: rtBase, marginal: marginalR).mean)
    }

    /// Shannon entropy of the joint, in nats.
    public func entropy() -> Double { cachedEntropy }

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

    /// SCHEMA §4. Carries θ_e, θ_i and β only — the nuisance axes are never
    /// reported and never persisted.
    public func snapshot() -> PosteriorSnapshot {
        let (me, se) = meanSD(.thetaE)
        let (mi, si) = meanSD(.thetaI)
        let (bm, bs) = betaMeanSD()
        return PosteriorSnapshot(
            thetaEMean: me, thetaESD: se,
            thetaEGrid: thetaE, thetaEMarginal: marginalE,
            thetaIMean: mi, thetaISD: si,
            thetaIGrid: thetaI, thetaIMarginal: marginalI,
            betaMean: bm, betaSD: bs
        )
    }
}
