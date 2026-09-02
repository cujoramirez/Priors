import Testing
import SpriteKit
@testable import Priors
import PriorsEngine

@Suite("VillageMapBuilder decision locations")
struct VillageMapBuilderTests {
    @MainActor
    @Test func exactlyNineteenSpatialAndElevenSocialLocations() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let spatial = result.decisionLocations.filter { $0.trait == .thetaE }
        let social = result.decisionLocations.filter { $0.trait == .thetaI }
        #expect(spatial.count == 19)
        #expect(social.count == 11)
        #expect(result.decisionLocations.count == 30)
    }

    /// Closes the loop the other two tests leave open: the map's trait
    /// histogram must equal `Scenarios.traitSchedule`'s. VillageCoordinator
    /// consumes each location at most once per session (`usedLocationIDs`),
    /// so the budget is exactly balanced with zero slack -- an edit to either
    /// side alone would leave the last decisions of a session unable to arm,
    /// which fails an assertion in debug and stalls silently in release.
    @MainActor
    @Test func locationTraitBudgetMatchesTheDecisionSchedule() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)

        for trait in Trait.allCases {
            let scheduled = Scenarios.traitSchedule.filter { $0 == trait }.count
            let available = result.decisionLocations.filter { $0.trait == trait }.count
            #expect(scheduled == available, "\(trait): \(scheduled) scheduled vs \(available) locations")
        }

        #expect(Scenarios.traitSchedule.count == Scenarios.decisionCount)
        #expect(result.decisionLocations.count == Scenarios.decisionCount)
    }

    @MainActor
    @Test func allLocationIDsAreUnique() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let ids = Set(result.decisionLocations.map(\.id))
        #expect(ids.count == result.decisionLocations.count)
    }
}
