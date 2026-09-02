import Testing
import CoreGraphics
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

    /// SPEC §8.2 / FINDINGS.md -- band *count* is nearly free, band
    /// *distinctness* is the entire cost of the diegetic ladder. The first
    /// pass separated adjacent bands by ~0.09 of alpha on a flat black circle
    /// and nothing else. This pins the widened separation and, more
    /// importantly, pins that darkness is not the only channel: two bands must
    /// differ in size and rim weight too.
    @Test func adjacentBandsSeparateOnEveryIntensityChannel() async throws {
        let intensities = (1...7).map { BandLadder.visualIntensity(band: $0) }

        for (a, b) in zip(intensities, intensities.dropFirst()) {
            let alphaStep = DecisionIntensityStyle.poolAlpha(b) - DecisionIntensityStyle.poolAlpha(a)
            #expect(alphaStep > 0.13, "adjacent bands differ by \(alphaStep) alpha")

            let radiusStep = DecisionIntensityStyle.poolRadiusFraction(b)
                - DecisionIntensityStyle.poolRadiusFraction(a)
            #expect(radiusStep > 0.08)

            let rimStep = DecisionIntensityStyle.rimWidth(b) - DecisionIntensityStyle.rimWidth(a)
            #expect(rimStep > 0.5)
        }

        // Band 1 must still be visible at all, and band 7 must not be a
        // featureless black disc.
        #expect(DecisionIntensityStyle.poolAlpha(0.0) >= 0.08)
        #expect(DecisionIntensityStyle.poolAlpha(1.0) <= 0.95)
        #expect(DecisionIntensityStyle.figureShading(1.0) <= 0.5)
    }

    @Test func priceOutsideRangeClampsToTheEdgeBand() async throws {
        #expect(BandLadder.band(for: -0.1, template: .path) == 1)
        #expect(BandLadder.band(for: 1.5, template: .path) == 7)
    }
}
