//  ClaimTests.swift
//  SPEC §9.1: "A claim with no supporting decisions must not render. Hard assert."
//  SPEC §2.1: nothing in the report is fictional.

import XCTest
@testable import PriorsEngine

final class ClaimTests: XCTestCase {

    func testMakeReturnsNilWithoutReceipts() {
        XCTAssertNil(Claim.make(id: "x", kind: .opening,
                                supportingDecisionIDs: [], confidence: 0.1))
    }

    func testMakeSucceedsWithReceipts() {
        XCTAssertNotNil(Claim.make(id: "x", kind: .opening,
                                   supportingDecisionIDs: [0], confidence: 0.1))
    }

    /// A claim persisted with empty receipts must not come back to life.
    func testDecodingRejectsAClaimWithoutReceipts() throws {
        let json = """
        {"id":"x","kind":"opening","parameters":{},"string_parameters":{},
         "supporting_decision_ids":[],"confidence":0.1}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Claim.self, from: json))
    }

    func testRoundTripsThroughCodable() throws {
        let c = Claim(id: "the_line", kind: .theLine,
                      parameters: ["theta_e_pct": 41.5],
                      stringParameters: ["landmark": "well"],
                      supportingDecisionIDs: [1, 4, 9], confidence: 0.031)
        let back = try JSONDecoder().decode(Claim.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(c, back)
    }

    func testEveryKindIsDistinctAndStable() {
        // Kind strings are persisted, so a rename is a migration, not a rename.
        let raws = ClaimKind.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
    }
}

final class ClaimGeneratorTests: XCTestCase {

    func testEveryGeneratedClaimHasReceipts() {
        let s = TestFixtures.session()
        let claims = ClaimGenerator.generate(session: s, objectiveRegions: ["house_a"])
        XCTAssertFalse(claims.isEmpty)
        for c in claims {
            XCTAssertFalse(c.supportingDecisionIDs.isEmpty, "\(c.id) shipped without receipts")
        }
    }

    func testReceiptsAlwaysPointAtRealDecisions() {
        let s = TestFixtures.session()
        let valid = Set(s.decisions.map(\.index))
        for c in ClaimGenerator.generate(session: s) {
            for id in c.supportingDecisionIDs {
                XCTAssertTrue(valid.contains(id), "\(c.id) cites decision \(id), which does not exist")
            }
        }
    }

    func testNoClaimIsGeneratedFromAnEmptySession() {
        var s = TestFixtures.session()
        s.decisions = []
        XCTAssertTrue(ClaimGenerator.generate(session: s).isEmpty)
    }

    /// SPEC §9.2 — confirm before disconfirm.
    func testConfirmingClaimsComeBeforeTheGap() {
        let claims = ClaimGenerator.generate(session: TestFixtures.session())
        guard let gap = claims.firstIndex(where: { $0.kind == .selfPredictionGap }),
              let confirm = claims.firstIndex(where: { $0.kind == .confirmLowPrice })
        else { return XCTFail("expected both a confirm and the gap") }
        XCTAssertLessThan(confirm, gap)
    }

    /// SPEC §9.2 — "Hardest claim is placed third from last, never last."
    func testHardestClaimIsThirdFromLast() {
        let claims = ClaimGenerator.generate(session: TestFixtures.session())
        guard claims.count >= 3 else { return XCTFail("too few claims to order") }
        guard let hardest = ClaimGenerator.hardest(claims) else { return }
        XCTAssertEqual(claims[claims.count - 3].id, hardest.id)
        XCTAssertNotEqual(claims.last?.id, hardest.id, "the hardest claim must never be last")
    }

    func testGamingClaimsAreAbsentForOrdinaryPlay() {
        let claims = ClaimGenerator.generate(session: TestFixtures.session())
        XCTAssertFalse(claims.contains { $0.kind == .gamingBreak })
    }

    func testEyeClaimAbsentWhenEyeDisabled() {
        var s = TestFixtures.session()
        s = TestFixtures.session(eyeEnabled: false)
        let claims = ClaimGenerator.generate(session: s)
        XCTAssertFalse(claims.contains { $0.kind == .eyeComparison })
        XCTAssertFalse(claims.contains { $0.kind == .eyeApproach })
    }

    func testRepeatClaimOnlyWhenThePairDiverged() {
        let agreeing = TestFixtures.session(repeatDiverges: false)
        XCTAssertFalse(ClaimGenerator.generate(session: agreeing)
            .contains { $0.kind == .repeatDivergence })
        let diverging = TestFixtures.session(repeatDiverges: true)
        XCTAssertTrue(ClaimGenerator.generate(session: diverging)
            .contains { $0.kind == .repeatDivergence })
    }

    /// SPEC §11 — the title comes from the strongest-confidence claim, and
    /// confidence is posterior SD, so lower is stronger.
    func testTitleClaimIsTheMostConfidentOne() {
        let claims = ClaimGenerator.generate(session: TestFixtures.session())
        guard let title = ClaimGenerator.titleClaim(from: claims) else {
            return XCTFail("expected a title claim")
        }
        for c in claims where c.confidence > 0 {
            XCTAssertLessThanOrEqual(title.confidence, c.confidence)
        }
    }

    /// COPY forbids population comparison; nothing in a claim may reference one.
    func testNoClaimCarriesAPopulationComparison() {
        let forbidden = ["percentile", "average", "compared", "other_players", "rank"]
        for c in ClaimGenerator.generate(session: TestFixtures.session()) {
            for key in Array(c.parameters.keys) + Array(c.stringParameters.keys) {
                for f in forbidden {
                    XCTAssertFalse(key.lowercased().contains(f), "\(c.id) exposes \(key)")
                }
            }
        }
    }

    /// The tie that broke the ordering once: a repeat divergence and a halved
    /// giving rate both score 0.5, so the winner must not depend on array order.
    func testHardestIsDeterministicUnderTies() {
        let a = Claim(id: "repeat_divergence", kind: .repeatDivergence,
                      supportingDecisionIDs: [1], confidence: 0.03)
        let b = Claim(id: "eye_comparison", kind: .eyeComparison,
                      parameters: ["gave_before_rate": 1.0, "gave_after_rate": 0.5],
                      supportingDecisionIDs: [2], confidence: 0.03)
        XCTAssertEqual(ClaimGenerator.hardness(a), ClaimGenerator.hardness(b), accuracy: 1e-12)
        XCTAssertEqual(ClaimGenerator.hardest([a, b])?.id, ClaimGenerator.hardest([b, a])?.id)
    }

    // MARK: - COPY v1.1 R9 receipts

    private static let uniformPosterior = Posterior().snapshot()

    /// COPY R9 names the surface the player saw. The generator was citing
    /// `skins.first` for the template, which can name a scene that never
    /// appeared in this session — a fabricated receipt.
    func testMoralLineCitesTheSkinThatWasActuallyShown() {
        let shown = "dropped lantern"
        let d = TestFixtures.decision(index: 3, template: .error, trait: .thetaI,
                                      price: 0.55, engaged: false, skin: shown)
        let claim = ClaimGenerator.moralLine([d], Self.uniformPosterior)
        XCTAssertEqual(claim?.stringParameters["error_skin"], shown)
    }

    /// COPY R9: "Nothing here would have known" is false of GIVE, where a
    /// villager asked and was refused. GIVE still informs θ_i; it is never the
    /// receipt this line names.
    func testMoralLineNeverNamesAGiveDecision() {
        let give = TestFixtures.decision(index: 2, template: .give, trait: .thetaI,
                                         price: 0.65, engaged: false)
        let err = TestFixtures.decision(index: 5, template: .error, trait: .thetaI,
                                        price: 0.20, engaged: false)
        let claim = ClaimGenerator.moralLine([give, err], Self.uniformPosterior)
        XCTAssertNotNil(claim)
        XCTAssertNotEqual(claim?.stringParameters["error_skin"],
                          Scenarios.templates[.give]!.skins.first)
    }

    /// With only GIVE decisions there is no ERROR or CREDIT surface to name, so
    /// R9 must not be made at all.
    func testMoralLineIsNotMadeFromGiveAlone() {
        let give = TestFixtures.decision(index: 2, template: .give, trait: .thetaI,
                                         price: 0.65, engaged: false)
        XCTAssertNil(ClaimGenerator.moralLine([give], Self.uniformPosterior))
    }

    /// COPY v1.1 renamed `{error_cost}` to `{error_cost_pct}%`, matching every
    /// other percentage placeholder in the file.
    func testMoralLineCarriesCostAsAPercentage() {
        let err = TestFixtures.decision(index: 5, template: .error, trait: .thetaI,
                                        price: 0.30, engaged: false)
        let claim = ClaimGenerator.moralLine([err], Self.uniformPosterior)
        XCTAssertEqual(claim?.parameters["error_cost_pct"] ?? 0, 30.0, accuracy: 1e-9)
    }

    /// Receipts stay the whole θ_i evidence base even though the named surface
    /// is drawn only from ERROR and CREDIT — GIVE informed the posterior.
    func testMoralLineReceiptsCoverAllThetaIDecisions() {
        let give = TestFixtures.decision(index: 2, template: .give, trait: .thetaI,
                                         price: 0.65, engaged: false)
        let err = TestFixtures.decision(index: 5, template: .error, trait: .thetaI,
                                        price: 0.20, engaged: false)
        let claim = ClaimGenerator.moralLine([give, err], Self.uniformPosterior)
        XCTAssertEqual(claim?.supportingDecisionIDs.sorted(), [2, 5])
    }
}
