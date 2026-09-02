import Testing
import SpriteKit
@testable import Priors
import PriorsEngine

@Suite("VillageMapBuilder decision locations")
struct VillageMapBuilderTests {
    @Test func exactlyNineteenSpatialAndElevenSocialLocations() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let spatial = result.decisionLocations.filter { $0.trait == .thetaE }
        let social = result.decisionLocations.filter { $0.trait == .thetaI }
        #expect(spatial.count == 19)
        #expect(social.count == 11)
        #expect(result.decisionLocations.count == 30)
    }

    @Test func allLocationIDsAreUnique() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let ids = Set(result.decisionLocations.map(\.id))
        #expect(ids.count == result.decisionLocations.count)
    }
}
