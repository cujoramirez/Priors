//  ADOSelectorGoldenTests.swift
//  SPEC §5: "Ported Swift version must match Python's chosen design on a fixed
//  seed within one grid step."
//
//  In practice we hold it to far tighter than one grid step: the whole 30-slot
//  session must reproduce exactly. Accepting only the SPEC bar would let a
//  systematic one-step drift pass unnoticed.

import XCTest
@testable import PriorsEngine

private let tol = 1e-9

final class ADOSelectorGoldenTests: XCTestCase {

    func testEIGMatchesPython() throws {
        let g = try Golden.load()
        var p = Posterior()
        for step in g.choiceOnly.sequence {
            p.update(price: step.price, trait: step.trait.asTrait, engaged: step.engaged)
        }
        for (name, entry) in g.eig.afterChoiceOnlySequence {
            let trait = name.asTrait
            let prices = Scenarios.candidatePrices(for: trait)
            for (a, b) in zip(prices, entry.prices) {
                XCTAssertEqual(a, b, accuracy: tol, "\(name) candidate prices")
            }
            let ours = ADOSelector.expectedInformationGain(posterior: p, prices: prices, trait: trait)
            for (k, (a, b)) in zip(ours, entry.eig).enumerated() {
                XCTAssertEqual(a, b, accuracy: tol, "\(name) EIG at index \(k)")
            }
        }
    }

    func testEIGIsIdenticalAcrossTemplatesOfOneTrait() {
        // The degeneracy ADOSelector is built around: under SPEC §3.4 the
        // likelihood never sees the template's identity, only its trait.
        var p = Posterior()
        p.update(price: 0.35, trait: .thetaE, engaged: true)
        let prices = [0.2, 0.45, 0.7]
        let reference = ADOSelector.expectedInformationGain(posterior: p, prices: prices, trait: .thetaE)
        for id in Scenarios.templatesByTrait[.thetaE]! {
            let t = Scenarios.templates[id]!
            let got = ADOSelector.expectedInformationGain(posterior: p, prices: prices, trait: t.trait)
            for (a, b) in zip(got, reference) { XCTAssertEqual(a, b, accuracy: 1e-15) }
        }
    }

    func testEIGIsBoundedByOneBit() {
        var p = Posterior()
        p.update(price: 0.4, trait: .thetaE, engaged: true)
        for v in ADOSelector.expectedInformationGain(
            posterior: p, prices: Scenarios.candidatePrices(for: .thetaE), trait: .thetaE) {
            XCTAssertGreaterThanOrEqual(v, -1e-12)
            XCTAssertLessThanOrEqual(v, log(2.0) + 1e-12)
        }
    }

    /// The whole 30-slot session, reproduced design for design.
    func testFullSessionMatchesPython() throws {
        let g = try Golden.load()
        var p = Posterior()
        var state = SelectionState()

        for expected in g.adoSession.designs {
            let d = ADOSelector.selectDesign(posterior: p, slot: expected.slot,
                                             state: state, jitter: { _ in 0.0 })
            XCTAssertEqual(d.template.rawValue, expected.template, "slot \(expected.slot) template")
            XCTAssertEqual(d.trait.rawValue, expected.trait, "slot \(expected.slot) trait")
            XCTAssertEqual(d.instance, expected.instance, "slot \(expected.slot) instance")
            XCTAssertEqual(d.skin, expected.skin, "slot \(expected.slot) skin")
            XCTAssertEqual(d.priceRule.rawValue, expected.priceRule, "slot \(expected.slot) price rule")
            XCTAssertEqual(d.curiosityOverride, expected.curiosityOverride,
                           "slot \(expected.slot) curiosity override")
            XCTAssertEqual(d.isRepeatOf, expected.isRepeatOf, "slot \(expected.slot) is_repeat_of")
            XCTAssertEqual(d.price, expected.price, accuracy: tol, "slot \(expected.slot) price")
            XCTAssertEqual(d.eig, expected.eig, accuracy: tol, "slot \(expected.slot) EIG")

            state.commit(d)
            p.update(price: d.price, trait: d.trait, engaged: expected.engaged)
        }

        let (me, se) = p.meanSD(.thetaE)
        XCTAssertEqual(me, g.adoSession.final.thetaEMean, accuracy: tol)
        XCTAssertEqual(se, g.adoSession.final.thetaESD, accuracy: tol)
    }

    // MARK: - Structural properties

    func testSessionExhaustsEveryQuotaExactly() throws {
        let g = try Golden.load()
        var p = Posterior()
        var state = SelectionState()
        for expected in g.adoSession.designs {
            let d = ADOSelector.selectDesign(posterior: p, slot: expected.slot,
                                             state: state, jitter: { _ in 0.0 })
            state.commit(d)
            p.update(price: d.price, trait: d.trait, engaged: expected.engaged)
        }
        for (id, t) in Scenarios.templates {
            XCTAssertEqual(state.used[id], t.instances, "\(id) quota")
            XCTAssertEqual(state.remaining[id], 0, "\(id) leftover")
        }
    }

    func testNoTemplateAppearsThreeTimesRunning() throws {
        let g = try Golden.load()
        let templates = g.adoSession.designs.map(\.template)
        var run = 1
        for k in 1..<templates.count {
            run = templates[k] == templates[k - 1] ? run + 1 : 1
            XCTAssertLessThanOrEqual(run, 2, "template run at slot \(k)")
        }
    }

    func testRepeatInstanceIsRepricedWithinTolerance() throws {
        let g = try Golden.load()
        let paths = g.adoSession.designs.filter { $0.template == "PATH" }
        let source = paths.first { $0.instance == Scenarios.repeatSourceInstance }
        let target = paths.first { $0.instance == Scenarios.repeatTargetInstance }
        XCTAssertNotNil(source); XCTAssertNotNil(target)
        XCTAssertEqual(target!.priceRule, "repeat")
        XCTAssertEqual(target!.isRepeatOf, source!.slot)
        XCTAssertLessThanOrEqual(abs(target!.price - source!.price),
                                 Scenarios.repeatTolerance + 1e-12)
    }

    func testSlotTraitsFollowTheAuthoredSchedule() throws {
        let g = try Golden.load()
        for d in g.adoSession.designs {
            XCTAssertEqual(d.trait, Scenarios.traitSchedule[d.slot].rawValue)
            XCTAssertEqual(Scenarios.templates[TemplateID(rawValue: d.template)!]!.trait.rawValue,
                           d.trait)
        }
    }

    func testQuotasExactlyFillTheirTraitSlots() {
        // The feasibility invariant selection relies on: per trait, quotas sum
        // to exactly the slots of that trait, so any template with quota left
        // is always a safe pick.
        for (trait, ids) in Scenarios.templatesByTrait {
            let quota = ids.reduce(0) { $0 + Scenarios.templates[$1]!.instances }
            XCTAssertEqual(quota, Scenarios.traitSchedule.filter { $0 == trait }.count,
                           "\(trait) quota vs slots")
        }
    }

    func testJitterStaysWithinSpecBound() {
        let p = Posterior()
        let plain = ADOSelector.selectDesign(posterior: p, slot: 0, state: SelectionState(),
                                             jitter: { _ in 0.0 })
        for _ in 0..<50 {
            let d = ADOSelector.selectDesign(posterior: p, slot: 0, state: SelectionState())
            XCTAssertLessThanOrEqual(abs(d.price - plain.price), Scenarios.priceJitter + 1e-12)
        }
    }

    func testCuriosityOverrideBlocksOnlyARunOfThree() {
        var state = SelectionState()
        XCTAssertNil(state.blockedByCuriosity)
        state.commit(makeDesign(.path, slot: 0))
        XCTAssertNil(state.blockedByCuriosity)
        state.commit(makeDesign(.detour, slot: 1))
        XCTAssertNil(state.blockedByCuriosity)
        state.commit(makeDesign(.detour, slot: 2))
        XCTAssertEqual(state.blockedByCuriosity, .detour)
    }

    func testFalsificationPricesAtThePosteriorMean() {
        // SPEC §6.1 — once SD θ_e < 0.06, the next PATH is genuinely 50/50.
        var p = Posterior()
        for _ in 0..<40 {
            p.update(price: 0.30, trait: .thetaE, engaged: true)
            p.update(price: 0.50, trait: .thetaE, engaged: false)
        }
        let (mean, sd) = p.meanSD(.thetaE)
        XCTAssertLessThan(sd, Scenarios.falsificationSDThreshold)
        let d = ADOSelector.selectDesign(posterior: p, slot: 0, state: SelectionState(),
                                         jitter: { _ in 0.0 })
        XCTAssertEqual(d.template, .path)
        XCTAssertEqual(d.priceRule, .falsification)
        XCTAssertEqual(d.price, mean, accuracy: 1e-9)
        XCTAssertEqual(p.predictedEngage(price: d.price, trait: .thetaE), 0.5, accuracy: 0.02)
    }

    private func makeDesign(_ t: TemplateID, slot: Int) -> Design {
        Design(slot: slot, template: t, trait: Scenarios.templates[t]!.trait, price: 0.4,
               skin: Scenarios.templates[t]!.skins[0], instance: 1, eig: 0,
               priceRule: .eig, curiosityOverride: false, isRepeatOf: nil)
    }
}
