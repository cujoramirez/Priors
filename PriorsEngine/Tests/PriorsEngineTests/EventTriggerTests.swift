//  EventTriggerTests.swift
//  SPEC §6. "Four. All are real; none are fictional."

import XCTest
@testable import PriorsEngine

final class EventTriggerTests: XCTestCase {

    // MARK: - §6.1

    func testFalsificationArmsOnlyBelowTheThreshold() {
        var p = Posterior()
        XCTAssertFalse(EventTriggers.falsificationArmed(posterior: p))
        for _ in 0..<40 {
            p.update(price: 0.30, trait: .thetaE, engaged: true)
            p.update(price: 0.50, trait: .thetaE, engaged: false)
        }
        XCTAssertTrue(EventTriggers.falsificationArmed(posterior: p))
    }

    // MARK: - §6.2

    /// "It must be genuinely predictive. If the model is wrong, the shadow walks
    /// the wrong way. Never script it correct."
    func testShadowFollowsThePosteriorEvenWhenItWillBeWrong() {
        var p = Posterior()
        // Teach it a low line, then ask about a cheap path: it should predict engage.
        for _ in 0..<10 { p.update(price: 0.20, trait: .thetaE, engaged: true) }
        let cheap = Design(slot: 0, template: .path, trait: .thetaE, price: 0.10,
                           skin: "unlit path", instance: 1, eig: 0, priceRule: .eig,
                           curiosityOverride: false, isRepeatOf: nil)
        let s = EventTriggers.shadowTarget(posterior: p, nextDesign: cheap)
        XCTAssertTrue(s.willEngage)
        XCTAssertEqual(s.probability, p.predictedEngage(price: 0.10, trait: .thetaE), accuracy: 1e-12)

        let dear = Design(slot: 1, template: .path, trait: .thetaE, price: 0.85,
                          skin: "cellar door", instance: 2, eig: 0, priceRule: .eig,
                          curiosityOverride: false, isRepeatOf: nil)
        XCTAssertFalse(EventTriggers.shadowTarget(posterior: p, nextDesign: dear).willEngage)
    }

    func testShadowReportsItsOwnUncertainty() {
        let p = Posterior()   // prior: P(engage) at the mean is exactly 0.5
        let d = Design(slot: 0, template: .path, trait: .thetaE, price: 0.45,
                       skin: "unlit path", instance: 1, eig: 0, priceRule: .eig,
                       curiosityOverride: false, isRepeatOf: nil)
        XCTAssertTrue(EventTriggers.shadowTarget(posterior: p, nextDesign: d).isUncertain)
    }

    // MARK: - §6.3

    func testEyeWindowIsPlusMinus240Seconds() {
        XCTAssertFalse(EventTriggers.eyeWindow(tPresented: 100, eyeTimestamp: nil).inWindow)
        let before = EventTriggers.eyeWindow(tPresented: 300, eyeTimestamp: 400)
        XCTAssertTrue(before.inWindow); XCTAssertEqual(before.side, .before)
        let after = EventTriggers.eyeWindow(tPresented: 500, eyeTimestamp: 400)
        XCTAssertTrue(after.inWindow); XCTAssertEqual(after.side, .after)
        XCTAssertTrue(EventTriggers.eyeWindow(tPresented: 640, eyeTimestamp: 400).inWindow)
        XCTAssertFalse(EventTriggers.eyeWindow(tPresented: 641, eyeTimestamp: 400).inWindow)
    }

    func testEyeIsNotScheduledWhenDisabled() {
        var g = SystemRandomNumberGenerator()
        XCTAssertNil(EventTriggers.scheduleEye(enabled: false, using: &g))
    }

    func testEyeIndexStaysInSpecRange() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let s = EventTriggers.scheduleEye(enabled: true, using: &g)!
            XCTAssertTrue(Scenarios.eyeDecisionIndexRange.contains(s.decisionIndex))
            XCTAssertEqual(s.durationSeconds, 3.0)
        }
    }

    /// COPY R8 fires "only if a measurable difference exists". A comparison
    /// against zero opportunities is not a measurement.
    func testEyeComparisonIsNotMeasurableWithoutBothSides() {
        let onlyBefore = [decision(0, .give, engaged: true, eye: .before)]
        XCTAssertFalse(EventTriggers.eyeComparison(decisions: onlyBefore).isMeasurable)

        let both = [decision(0, .give, engaged: true, eye: .before),
                    decision(1, .give, engaged: false, eye: .after)]
        let cmp = EventTriggers.eyeComparison(decisions: both)
        XCTAssertTrue(cmp.isMeasurable)
        XCTAssertTrue(cmp.changed)
        XCTAssertEqual(cmp.gaveBefore, 1)
        XCTAssertEqual(cmp.gaveAfter, 0)
    }

    func testEyeComparisonCountsOnlyProsocialTemplates() {
        // SPEC §6.3 names GIVE and ERROR. A PATH decision is not prosocial.
        let d = [decision(0, .path, engaged: true, eye: .before),
                 decision(1, .path, engaged: false, eye: .after)]
        XCTAssertEqual(EventTriggers.eyeComparison(decisions: d).offeredBefore, 0)
    }

    // MARK: - §6.4

    func testGamingNeedsBothConditions() {
        // A slow player is not a gaming player.
        var slow: [DecisionRecord] = []
        for k in 0..<30 {
            slow.append(decision(k, .path, engaged: true, eye: nil,
                                 rtMs: k < 20 ? 1000 : 5000, predicted: 0.9))
        }
        let m = EventTriggers.gamingMetrics(decisions: slow)
        XCTAssertGreaterThan(m.rtRatio, 2.0)
        XCTAssertNil(m.fitBreak, "a consistent player has no fit break")
        XCTAssertFalse(m.isGaming, "RT ratio alone must not trigger the gaming lines")
    }

    func testFitBreakNeedsThreeConsecutiveOutliers() {
        // Mostly matching predictions, then three flat contradictions.
        var d: [DecisionRecord] = []
        for k in 0..<20 {
            let contradict = (12...14).contains(k)
            d.append(decision(k, .path, engaged: !contradict, eye: nil,
                              rtMs: 1500, predicted: 0.97))
        }
        XCTAssertEqual(EventTriggers.fitBreak(decisions: d), 12)
    }

    func testFitBreakIsNilWhenTheFitHolds() {
        let d = (0..<20).map { decision($0, .path, engaged: true, eye: nil,
                                        rtMs: 1500, predicted: 0.95) }
        XCTAssertNil(EventTriggers.fitBreak(decisions: d))
    }

    func testReversalRateCountsContradictionsAfterOnset() {
        var d: [DecisionRecord] = []
        for k in 0..<20 {
            d.append(decision(k, .path, engaged: k < 15, eye: nil,
                              rtMs: 1500, predicted: 0.9))
        }
        // From index 15 on, every choice contradicts a 0.9 prediction.
        XCTAssertEqual(EventTriggers.reversalRate(decisions: d, from: 15), 1.0, accuracy: 1e-12)
    }

    func testMedianHandlesBothParities() {
        XCTAssertEqual(EventTriggers.median([3, 1, 2])!, 2, accuracy: 1e-12)
        XCTAssertEqual(EventTriggers.median([4, 1, 3, 2])!, 2.5, accuracy: 1e-12)
        XCTAssertNil(EventTriggers.median([]))
    }

    // MARK: - Helper

    private func decision(_ i: Int, _ t: TemplateID, engaged: Bool, eye: EyeSide?,
                          rtMs: Int = 2000, predicted: Double = 0.5) -> DecisionRecord {
        DecisionRecord(
            index: i, template: t, trait: Scenarios.templates[t]!.trait,
            skin: Scenarios.templates[t]!.skins[0], price: 0.4, engaged: engaged,
            tPresented: Double(i) * 20, tDecided: Double(i) * 20 + 1, rtMs: rtMs,
            approachFrac: 0.5, backtracks: 0, idleMs: 100,
            eyeWindow: eye != nil, eyeSide: eye,
            posteriorMeanE: 0.45, posteriorSDE: 0.1,
            posteriorMeanI: 0.36, posteriorSDI: 0.1,
            predictedEngage: predicted, isRepeatOf: nil, whyText: nil)
    }
}

final class EstimatorTests: XCTestCase {

    /// SPEC §2.8 — the app must behave identically with no model present.
    func testEstimatorIsOptional() {
        let e = Estimator(backend: nil)
        XCTAssertFalse(e.isAvailable)
        XCTAssertNil(e.estimate(decisions: TestFixtures.session().decisions,
                                comparedTo: TestFixtures.session().finalPosterior))
    }

    func testFeatureLayoutMatchesSchema8() {
        let s = TestFixtures.session()
        let f = Estimator.buildFeatures(from: s.decisions)
        XCTAssertEqual(f.count, 30 * 9)

        let d = s.decisions[3]
        let row = 3 * 9
        XCTAssertEqual(Double(f[row + EstimatorFeature.price.rawValue]), d.price, accuracy: 1e-6)
        XCTAssertEqual(f[row + EstimatorFeature.engaged.rawValue], d.engaged ? 1 : 0)
        XCTAssertEqual(Double(f[row + EstimatorFeature.logRTMs.rawValue]),
                       log(Double(d.rtMs)), accuracy: 1e-5)
        XCTAssertEqual(f[row + EstimatorFeature.templateOneHotE.rawValue]
                       + f[row + EstimatorFeature.templateOneHotI.rawValue], 1)
    }

    /// The network detects padding as an all-zero row, so a real decision must
    /// never look like padding.
    func testPaddedRowsAreZeroAndRealRowsAreNot() {
        let short = Array(TestFixtures.session().decisions.prefix(10))
        let f = Estimator.buildFeatures(from: short)
        for r in 0..<10 {
            let row = Array(f[(r * 9)..<((r + 1) * 9)])
            XCTAssertGreaterThan(row.reduce(0) { $0 + abs($1) }, 0, "row \(r) looks like padding")
        }
        for r in 10..<30 {
            let row = Array(f[(r * 9)..<((r + 1) * 9)])
            XCTAssertEqual(row.reduce(0) { $0 + abs($1) }, 0, "row \(r) should be padding")
        }
    }

    /// SCHEMA §8 — a disagreement beyond 2 SD is logged, never surfaced.
    func testDisagreementBeyond2SDIsLogged() {
        let s = TestFixtures.session()
        let far = StubBackend(thetaE: s.finalPosterior.thetaEMean + 5 * s.finalPosterior.thetaESD)
        let e = Estimator(backend: far)
        XCTAssertNotNil(e.estimate(decisions: s.decisions, comparedTo: s.finalPosterior))
        XCTAssertEqual(e.disagreements.count, 1)
        XCTAssertGreaterThan(e.disagreements[0].sigmas, 2.0)
    }

    func testAgreementIsNotLogged() {
        let s = TestFixtures.session()
        let near = StubBackend(thetaE: s.finalPosterior.thetaEMean)
        let e = Estimator(backend: near)
        _ = e.estimate(decisions: s.decisions, comparedTo: s.finalPosterior)
        XCTAssertTrue(e.disagreements.isEmpty)
    }

    private struct StubBackend: EstimatorBackend {
        let thetaE: Double
        func predict(features: [Float]) throws -> EstimatorOutput {
            EstimatorOutput(thetaEHat: thetaE, thetaIHat: 0.25,
                            logBetaHat: log(9), uncertaintyHat: 0.03)
        }
    }
}
