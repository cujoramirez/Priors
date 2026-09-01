import Testing
@testable import Priors
import PriorsEngine

@Suite("BandLadder")
struct BandLadderTests {
    @Test func sevenBandsCoverTheFullRangePerTrait() async throws {
        // theta_e templates: PATH, DETOUR, TRADE
        #expect(BandLadder.band(for: 0.05, template: .path) == 1)
        #expect(BandLadder.band(for: 0.85, template: .path) == 7)
        #expect(BandLadder.band(for: 0.45, template: .path) >= 3)
        #expect(BandLadder.band(for: 0.45, template: .path) <= 5)

        // theta_i templates: ERROR, CREDIT, GIVE
        #expect(BandLadder.band(for: 0.02, template: .error) == 1)
        #expect(BandLadder.band(for: 0.70, template: .error) == 7)
    }

    @Test func bandIsMonotonicInPrice() async throws {
        let prices = stride(from: 0.05, through: 0.85, by: 0.02).map { $0 }
        var lastBand = 0
        for p in prices {
            let b = BandLadder.band(for: p, template: .detour)
            #expect(b >= lastBand)
            lastBand = b
        }
    }

    @Test func everyTemplateHasSevenDistinctNonEmptyPhrases() async throws {
        for template: TemplateID in [.path, .detour, .error, .credit, .give, .trade] {
            let phrases = (1...7).map { BandLadder.phrase(template: template, band: $0) }
            #expect(phrases.count == Set(phrases).count, "duplicate phrase in \(template)")
            for phrase in phrases {
                #expect(!phrase.isEmpty)
                #expect(!phrase.contains("%"))
                #expect(!phrase.contains(where: { $0.isNumber }))
            }
        }
    }

    @Test func visualIntensityIsMonotonicAndNormalised() async throws {
        let values = (1...7).map { BandLadder.visualIntensity(band: $0) }
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
        for (a, b) in zip(values, values.dropFirst()) {
            #expect(b > a)
        }
    }

    @Test func priceOutsideRangeClampsToTheEdgeBand() async throws {
        #expect(BandLadder.band(for: -0.1, template: .path) == 1)
        #expect(BandLadder.band(for: 1.5, template: .path) == 7)
    }
}
