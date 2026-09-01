//  BehaviouralPosteriorGoldenTests.swift
//  Cross-language tests for the posterior that reads hesitation.
//
//  Two kinds of test live here, and both matter.
//
//  The golden tests assert this port reproduces `priors/rt_posterior.py` step by
//  step. They are what makes the arithmetic trustworthy.
//
//  The rest assert the properties FINDINGS.md says make the channel *safe*.
//  `experiments/rt_robustness.py` showed that a version with the RT law fixed at
//  SCHEMA §7's values reaches MAE 0.139 with calibration 0.26 when a real player
//  hesitates differently — worse than ignoring hesitation, while claiming four
//  times more precision than it has. A machine confidently asserting a line the
//  player does not have is the one failure SPEC §0 and §2.1 forbid outright.
//  The tests below are what stop that version from being reintroduced.

import XCTest
@testable import PriorsEngine

private let tol = 1e-9

final class BehaviouralPosteriorGoldenTests: XCTestCase {

    // MARK: - Grids and sizing

    func testNuisanceGridsMatchPython() throws {
        let g = try Golden.load()
        let p = BehaviouralPosterior()
        XCTAssertEqual(p.rtBase.count, g.behavioural.grids.rtBase.count)
        for (a, b) in zip(p.rtBase, g.behavioural.grids.rtBase) {
            XCTAssertEqual(a, b, accuracy: 1e-6)   // values reach 13,641 ms
        }
        for (a, b) in zip(p.peak, g.behavioural.grids.peak) { XCTAssertEqual(a, b, accuracy: tol) }
        for (a, b) in zip(p.sigma, g.behavioural.grids.sigma) { XCTAssertEqual(a, b, accuracy: tol) }
    }

    /// 33 · 25 · 15 · 11 · 5 · 3. The sizing decision FINDINGS.md asked for.
    func testCellCountMatchesTheSizingDecision() {
        XCTAssertEqual(BehaviouralPosterior.cellCount, 2_041_875)
    }

    /// 0.0 must be on the peak grid, or "this player's hesitation says nothing"
    /// is not representable and the channel cannot switch itself off.
    func testZeroIsOnThePeakGrid() {
        XCTAssertEqual(BehaviouralPosterior().peak.first, 0.0)
    }

    func testPriorIsNormalised() {
        let p = BehaviouralPosterior()
        var sum = 0.0
        for v in p.logPost { sum += exp(v) }
        XCTAssertEqual(sum, 1.0, accuracy: 1e-9)
    }

    /// The trait priors stay uniform (SPEC §3.1/§3.2) — only `rt_base` carries a
    /// prior, and it lives on an axis of its own.
    func testTraitPriorsAreUnaffectedByTheRTBasePrior() {
        let b = BehaviouralPosterior()
        let c = Posterior()
        XCTAssertEqual(b.meanSD(.thetaE).mean, c.meanSD(.thetaE).mean, accuracy: tol)
        XCTAssertEqual(b.meanSD(.thetaE).sd, c.meanSD(.thetaE).sd, accuracy: tol)
        XCTAssertEqual(b.meanSD(.thetaI).mean, c.meanSD(.thetaI).mean, accuracy: tol)
        XCTAssertEqual(b.betaMeanSD().mean, c.betaMeanSD().mean, accuracy: tol)
    }

    // MARK: - The headline cross-language test

    /// Six updates carrying hesitation, every intermediate value compared
    /// against Python. A divergence at step k localises the bug to that update.
    func testBehaviouralSequenceMatchesPython() throws {
        let g = try Golden.load()
        var p = BehaviouralPosterior()

        for (k, step) in g.behavioural.sequence.enumerated() {
            let trait = step.trait.asTrait

            // SCHEMA §1 — recorded before the choice is known.
            let pred = p.predictedEngage(price: step.price, trait: trait)
            XCTAssertEqual(pred, step.predictedEngageBefore, accuracy: tol,
                           "step \(k): predicted_engage before update")

            p.update(price: step.price, trait: trait,
                     engaged: step.engaged, rtMs: step.rtMs)

            let (me, se) = p.meanSD(.thetaE)
            let (mi, si) = p.meanSD(.thetaI)
            let (bm, bs) = p.betaMeanSD()
            XCTAssertEqual(me, step.after.thetaEMean, accuracy: tol, "step \(k): θ_e mean")
            XCTAssertEqual(se, step.after.thetaESD, accuracy: tol, "step \(k): θ_e sd")
            XCTAssertEqual(mi, step.after.thetaIMean, accuracy: tol, "step \(k): θ_i mean")
            XCTAssertEqual(si, step.after.thetaISD, accuracy: tol, "step \(k): θ_i sd")
            XCTAssertEqual(bm, step.after.betaMean, accuracy: tol, "step \(k): β mean")
            XCTAssertEqual(bs, step.after.betaSD, accuracy: tol, "step \(k): β sd")

            let law = p.rtLaw()
            XCTAssertEqual(law.peakMean, step.rtLaw.peakMean, accuracy: tol, "step \(k): peak mean")
            XCTAssertEqual(law.peakSD, step.rtLaw.peakSD, accuracy: tol, "step \(k): peak sd")
            XCTAssertEqual(law.sigmaMean, step.rtLaw.sigmaMean, accuracy: tol, "step \(k): σ mean")
            XCTAssertEqual(law.rtBaseMean, step.rtLaw.rtBaseMean, accuracy: 1e-6,
                           "step \(k): rt_base mean")
        }
    }

    // MARK: - Reductions to the choice-only reference

    /// With no hesitation supplied the joint factorises — the nuisance axes stay
    /// at their prior and divide out — so the trait marginals must equal the
    /// choice-only posterior's exactly. This is what makes the new type a safe
    /// drop-in when `rt_ms` is missing.
    func testWithoutHesitationItReproducesTheChoiceOnlyPosterior() {
        let seq: [(Double, Trait, Bool)] = [
            (0.30, .thetaE, true), (0.62, .thetaE, false), (0.45, .thetaE, true),
            (0.18, .thetaI, true), (0.55, .thetaI, false), (0.72, .thetaE, false),
        ]
        var b = BehaviouralPosterior()
        var c = Posterior()
        for (price, trait, engaged) in seq {
            XCTAssertEqual(b.predictedEngage(price: price, trait: trait),
                           c.predictedEngage(price: price, trait: trait), accuracy: tol)
            b.update(price: price, trait: trait, engaged: engaged, rtMs: nil)
            c.update(price: price, trait: trait, engaged: engaged)
        }
        XCTAssertEqual(b.meanSD(.thetaE).mean, c.meanSD(.thetaE).mean, accuracy: tol)
        XCTAssertEqual(b.meanSD(.thetaE).sd, c.meanSD(.thetaE).sd, accuracy: tol)
        XCTAssertEqual(b.meanSD(.thetaI).mean, c.meanSD(.thetaI).mean, accuracy: tol)
        XCTAssertEqual(b.meanSD(.thetaI).sd, c.meanSD(.thetaI).sd, accuracy: tol)
        XCTAssertEqual(b.betaMeanSD().mean, c.betaMeanSD().mean, accuracy: tol)
    }

    /// SPEC §10 down-weighting reaches both channels: a decision the player
    /// disputes loses its hesitation evidence too.
    func testZeroWeightIsANoOp() {
        var p = BehaviouralPosterior()
        let before = p.meanSD(.thetaE)
        p.update(price: 0.4, trait: .thetaE, engaged: true, rtMs: 5_000, weight: 0.0)
        XCTAssertEqual(p.meanSD(.thetaE).mean, before.mean, accuracy: tol)
        XCTAssertEqual(p.meanSD(.thetaE).sd, before.sd, accuracy: tol)
    }

    func testDownWeightingMovesLessThanFullWeight() {
        let prior = BehaviouralPosterior().meanSD(.thetaE).mean
        var full = BehaviouralPosterior()
        var light = BehaviouralPosterior()
        full.update(price: 0.7, trait: .thetaE, engaged: true, rtMs: 6_000, weight: 1.0)
        light.update(price: 0.7, trait: .thetaE, engaged: true, rtMs: 6_000, weight: 0.2)
        XCTAssertGreaterThan(abs(full.meanSD(.thetaE).mean - prior),
                             abs(light.meanSD(.thetaE).mean - prior))
    }

    // MARK: - The safety properties (FINDINGS.md)

    /// The property the whole design rests on. A player whose hesitation carries
    /// no information about price must drive the `peak` posterior toward 0, so
    /// the RT term stops contributing on its own. Misspecification has to become
    /// uncertainty, never a confident wrong answer.
    func testPeakCollapsesTowardZeroWhenHesitationCarriesNoSignal() {
        var p = BehaviouralPosterior()
        let priorPeak = p.rtLaw().peakMean
        // Identical RT at every price: nothing about the timing tracks the line.
        for price in stride(from: 0.10, through: 0.80, by: 0.05) {
            p.update(price: price, trait: .thetaE, engaged: price < 0.45, rtMs: 2_000)
        }
        let law = p.rtLaw()
        XCTAssertLessThan(law.peakMean, priorPeak,
                          "flat hesitation must not support a near-line effect")
        XCTAssertFalse(law.carriesSignal,
                       "peak is not separated from zero, so RT must not be leaned on")
    }

    /// The converse: hesitation that really does peak at the line must be
    /// recognised, or the channel is worthless.
    func testPeakRisesWhenHesitationTracksTheLine() {
        let trueTheta = 0.42
        var p = BehaviouralPosterior()
        for price in stride(from: 0.10, through: 0.80, by: 0.05) {
            let near = exp(-pow((price - trueTheta) / 0.08, 2))
            p.update(price: price, trait: .thetaE, engaged: price < trueTheta,
                     rtMs: 2_000 * (1 + 2.5 * near))
        }
        let law = p.rtLaw()
        XCTAssertGreaterThan(law.peakMean, 1.0)
        XCTAssertTrue(law.carriesSignal)
    }

    /// The reason for the port. On the same decisions, reading hesitation must
    /// land closer to the player's true line than choice alone.
    func testHesitationRecoversTheLineBetterThanChoiceAlone() {
        let trueTheta = 0.42
        var b = BehaviouralPosterior()
        var c = Posterior()
        for price in stride(from: 0.10, through: 0.80, by: 0.05) {
            let near = exp(-pow((price - trueTheta) / 0.08, 2))
            let engaged = price < trueTheta
            b.update(price: price, trait: .thetaE, engaged: engaged,
                     rtMs: 2_000 * (1 + 2.5 * near))
            c.update(price: price, trait: .thetaE, engaged: engaged)
        }
        let behavioural = abs(b.meanSD(.thetaE).mean - trueTheta)
        let choiceOnly = abs(c.meanSD(.thetaE).mean - trueTheta)
        XCTAssertLessThan(behavioural, choiceOnly)
    }

    /// FINDINGS.md: at `RT_BASE_PRIOR_SD = 0.4` a uniformly slow response is
    /// read as "near the line" rather than "slow player", shifting θ_e by ~0.12
    /// on no evidence. The weak prior is load-bearing, not a tuning choice —
    /// this fails if someone tightens it.
    func testRTBasePriorIsWeakEnoughThatASlowPlayerIsNotMisread() {
        XCTAssertEqual(BehaviouralPosterior.rtBasePriorSD, 0.8, accuracy: 1e-12)

        // Same price throughout, uniformly slow: "slow player", not "on the line".
        var p = BehaviouralPosterior()
        let prior = p.meanSD(.thetaE).mean
        for _ in 0..<8 {
            p.update(price: 0.45, trait: .thetaE, engaged: true, rtMs: 6_000)
        }
        var choice = Posterior()
        for _ in 0..<8 { choice.update(price: 0.45, trait: .thetaE, engaged: true) }

        let drift = abs(p.meanSD(.thetaE).mean - choice.meanSD(.thetaE).mean)
        XCTAssertLessThan(drift, 0.02,
                          "a flat RT elevation moved θ_e by \(drift) beyond the choice-only fit")
        _ = prior
    }

    // MARK: - ADO runs on it unchanged

    /// `trait_beta_marginal` exists so the EIG can run on either posterior. The
    /// choice likelihood is constant along every nuisance axis, so the reduction
    /// is exact and the selector needs no special case.
    func testTraitBetaMarginalIsAProperDistribution() {
        var p = BehaviouralPosterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true, rtMs: 3_000)
        for trait in [Trait.thetaE, .thetaI] {
            let m = p.traitBetaMarginal(trait)
            XCTAssertEqual(m.reduce(0, +), 1.0, accuracy: 1e-9)
            XCTAssertFalse(m.contains { $0 < 0 })
        }
    }

    func testSelectorAcceptsTheBehaviouralPosterior() {
        var p = BehaviouralPosterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true, rtMs: 3_000)
        let d = ADOSelector.selectDesign(posterior: p, slot: 0,
                                         state: SelectionState(), jitter: { _ in 0 })
        XCTAssertEqual(d.trait, Scenarios.traitSchedule[0])
        XCTAssertTrue(d.price >= 0.0 && d.price <= 1.0)
    }

    func testSnapshotReportsOnlyTheThreeReportableParameters() {
        var p = BehaviouralPosterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true, rtMs: 3_000)
        let s = p.snapshot()
        XCTAssertEqual(s.thetaEGrid.count, 33)
        XCTAssertEqual(s.thetaIGrid.count, 25)
        XCTAssertEqual(s.thetaEMarginal.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertEqual(s.thetaEMean, p.meanSD(.thetaE).mean, accuracy: tol)
    }
}
