//  PosteriorGoldenTests.swift
//  SPEC §5: "Ported Swift version must match Python's chosen design on a fixed
//  seed within one grid step."
//
//  These are the tests that make the port trustworthy. The expected values come
//  from `priors-research`, which is itself validated against ADOpy, so this
//  chain runs: ADOpy → Python → Swift. Tolerances are tight on purpose — the
//  two implementations compute the same arithmetic, so anything beyond
//  floating-point noise is a real divergence, not a rounding difference.

import XCTest
@testable import PriorsEngine

/// Grids and summaries should agree to near machine precision. NumPy and Swift
/// order a few operations differently, so this is not literally exact.
private let tol = 1e-9

final class PosteriorGoldenTests: XCTestCase {

    func testGridsMatchPython() throws {
        let g = try Golden.load()
        let p = Posterior()
        XCTAssertEqual(p.thetaE.count, g.grids.thetaE.count)
        for (a, b) in zip(p.thetaE, g.grids.thetaE) { XCTAssertEqual(a, b, accuracy: tol) }
        for (a, b) in zip(p.thetaI, g.grids.thetaI) { XCTAssertEqual(a, b, accuracy: tol) }
        for (a, b) in zip(p.beta, g.grids.beta) { XCTAssertEqual(a, b, accuracy: tol) }
    }

    func testGridSizesMatchSpec() {
        XCTAssertEqual(Grids.thetaE.n, 33)
        XCTAssertEqual(Grids.thetaI.n, 25)
        XCTAssertEqual(Grids.beta.n, 15)
        XCTAssertEqual(Grids.cellCount, 12_375)
    }

    func testPriorMatchesPython() throws {
        let g = try Golden.load()
        let p = Posterior()
        assertSummary(p, g.prior, "prior")
        XCTAssertEqual(p.entropy(), g.prior.entropy!, accuracy: tol)
        XCTAssertEqual(p.joint.reduce(0, +), 1.0, accuracy: 1e-12)
    }

    /// The headline cross-language test: 12 updates, every intermediate value
    /// compared. A divergence at step k localises the bug to that update.
    func testChoiceSequenceMatchesPythonStepByStep() throws {
        let g = try Golden.load()
        var p = Posterior()
        for (k, step) in g.choiceOnly.sequence.enumerated() {
            let trait = step.trait.asTrait
            // SCHEMA §1 — recorded before the update, while the choice is unknown.
            XCTAssertEqual(p.predictedEngage(price: step.price, trait: trait),
                           step.predictedEngageBefore, accuracy: tol,
                           "predicted_engage diverged at step \(k)")
            p.update(price: step.price, trait: trait, engaged: step.engaged)
            assertSummary(p, step.after, "step \(k)")
            XCTAssertEqual(p.entropy(), step.after.entropy!, accuracy: tol,
                           "entropy diverged at step \(k)")
        }
    }

    func testPosteriorStaysNormalisedThroughout() throws {
        let g = try Golden.load()
        var p = Posterior()
        for step in g.choiceOnly.sequence {
            p.update(price: step.price, trait: step.trait.asTrait, engaged: step.engaged)
            XCTAssertEqual(p.joint.reduce(0, +), 1.0, accuracy: 1e-12)
        }
    }

    /// SPEC §10 — the argument screen refits with a disputed decision
    /// down-weighted. The machine concedes uncertainty, never the observation.
    func testRefitWeightsMatchPython() throws {
        let g = try Golden.load()
        let obs = g.refit.observations.map {
            (price: $0.price, trait: $0.trait.asTrait, engaged: $0.engaged)
        }
        assertSummary(Posterior.from(observations: obs), g.refit.full, "refit full")

        var wSituation = [Double](repeating: 1.0, count: obs.count); wSituation[2] = 0.5
        assertSummary(Posterior.from(observations: obs, weights: wSituation),
                      g.refit.situation, "refit situation")

        var wMisread = [Double](repeating: 1.0, count: obs.count); wMisread[2] = 0.2
        assertSummary(Posterior.from(observations: obs, weights: wMisread),
                      g.refit.misread, "refit misread")
    }

    func testRefitWidensTheBand() throws {
        let g = try Golden.load()
        let obs = g.refit.observations.map {
            (price: $0.price, trait: $0.trait.asTrait, engaged: $0.engaged)
        }
        var w = [Double](repeating: 1.0, count: obs.count); w[2] = 0.5
        let full = Posterior.from(observations: obs).meanSD(.thetaE).sd
        let refit = Posterior.from(observations: obs, weights: w).meanSD(.thetaE).sd
        XCTAssertGreaterThan(refit, full, "a refit must widen the band, not narrow it")
    }

    // MARK: - Structural properties

    func testTraitsAreIndependentGivenTheirOwnDecisions() {
        var p = Posterior()
        let before = p.marginal(.thetaI)
        for price in [0.2, 0.5, 0.75] {
            p.update(price: price, trait: .thetaE, engaged: true)
        }
        for (a, b) in zip(p.marginal(.thetaI), before) { XCTAssertEqual(a, b, accuracy: 1e-12) }
    }

    func testZeroWeightIsANoOp() {
        var p = Posterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true)
        let before = p.logPost
        p.update(price: 0.9, trait: .thetaE, engaged: false, weight: 0.0)
        for (a, b) in zip(p.logPost, before) { XCTAssertEqual(a, b, accuracy: 1e-12) }
    }

    func testTraitBetaMarginalSumsToTheTraitMarginal() {
        var p = Posterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true)
        let w = p.traitBetaMarginal(.thetaE)
        let m = p.marginal(.thetaE)
        for e in 0..<Grids.thetaE.n {
            var s = 0.0
            for b in 0..<Grids.beta.n { s += w[e * Grids.beta.n + b] }
            XCTAssertEqual(s, m[e], accuracy: 1e-12)
        }
    }

    func testSnapshotIsRoundTrippable() throws {
        let snap = Posterior().snapshot()
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(PosteriorSnapshot.self, from: data)
        XCTAssertEqual(snap, back)
    }

    // MARK: - Helper

    private func assertSummary(_ p: Posterior, _ g: GoldenSummary, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let (me, se) = p.meanSD(.thetaE)
        let (mi, si) = p.meanSD(.thetaI)
        let (bm, bs) = p.betaMeanSD()
        XCTAssertEqual(me, g.thetaEMean, accuracy: tol, "\(label) θ_e mean", file: file, line: line)
        XCTAssertEqual(se, g.thetaESD, accuracy: tol, "\(label) θ_e sd", file: file, line: line)
        XCTAssertEqual(mi, g.thetaIMean, accuracy: tol, "\(label) θ_i mean", file: file, line: line)
        XCTAssertEqual(si, g.thetaISD, accuracy: tol, "\(label) θ_i sd", file: file, line: line)
        XCTAssertEqual(bm, g.betaMean, accuracy: tol, "\(label) β mean", file: file, line: line)
        XCTAssertEqual(bs, g.betaSD, accuracy: tol, "\(label) β sd", file: file, line: line)
    }
}
