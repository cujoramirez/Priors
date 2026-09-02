//
//  LiveDecision.swift
//  Priors
//
//  Replaces ScenarioPromptData/ScenarioDialogView. SPEC §8.2/§8.3: no modal,
//  no printed number. This is the data the world renders — a phrase and a
//  scalar intensity — attached to whichever single pre-built location is
//  currently armed (VillageMapBuilder, VillageCoordinator).
//

import CoreGraphics
import SpriteKit
import UIKit
import PriorsEngine

public struct LiveDecision: Sendable {
    /// SCHEMA §1 — the four `posterior_*` fields and `predicted_engage`, as
    /// they stood **before** the player's choice was known.
    ///
    /// SCHEMA §1: "`predicted_engage` must be stored before the choice is
    /// known. This is what makes the prediction ledger honest." Capturing it
    /// here, at arm time, makes that structural rather than incidental: the
    /// numbers travel with the armed decision, so no future edit to
    /// `resolveLiveDecision` can quietly start scoring the model against a
    /// posterior that has already seen the answer.
    public struct PriorSnapshot: Sendable {
        public let meanE: Double
        public let sdE: Double
        public let meanI: Double
        public let sdI: Double
        public let predictedEngage: Double
        /// False only for `unrecorded` — see below.
        public let isRecorded: Bool

        public init(meanE: Double, sdE: Double, meanI: Double, sdI: Double, predictedEngage: Double) {
            self.meanE = meanE
            self.sdE = sdE
            self.meanI = meanI
            self.sdI = sdI
            self.predictedEngage = predictedEngage
            self.isRecorded = true
        }

        private init(unrecorded: Void) {
            self.meanE = 0.0
            self.sdE = 0.0
            self.meanI = 0.0
            self.sdI = 0.0
            self.predictedEngage = 0.5
            self.isRecorded = false
        }

        /// For call sites that only render a decision and never log it
        /// (previews, node-construction tests). `VillageCoordinator` asserts
        /// against this before writing a `DecisionRecord`, so it can never
        /// reach a session file unnoticed.
        public static let unrecorded = PriorSnapshot(unrecorded: ())
    }

    public let design: Design
    public let band: Int
    public let phrase: String
    public let visualIntensity: Double
    public let priorSnapshot: PriorSnapshot
    public let narrative: DilemmaNarrative?

    /// SPEC §3.1/§3.2 — spatial templates are a threshold you cross; social
    /// templates are a villager who waits. The two sets are exactly the two
    /// traits (theta_e / theta_i), so this is a straight lookup, not a new
    /// design axis.
    public let isSpatial: Bool

    public init(
        design: Design,
        priorSnapshot: PriorSnapshot = .unrecorded,
        narrative: DilemmaNarrative? = nil
    ) {
        self.design = design
        self.band = BandLadder.band(for: design.price, template: design.template)
        self.phrase = narrative?.bandPhrase ?? BandLadder.phrase(template: design.template, band: band)
        self.visualIntensity = BandLadder.visualIntensity(band: band)
        self.priorSnapshot = priorSnapshot
        self.narrative = narrative
        switch design.template {
        case .path, .detour, .trade: self.isSpatial = true
        case .error, .credit, .give: self.isSpatial = false
        }
    }

    /// Captures the posterior as it stands right now — call this at ARM time,
    /// never at resolution.
    public init(
        design: Design,
        capturedFrom posterior: BehaviouralPosterior,
        narrative: DilemmaNarrative? = nil
    ) {
        let (meanE, sdE) = posterior.meanSD(.thetaE)
        let (meanI, sdI) = posterior.meanSD(.thetaI)
        self.init(
            design: design,
            priorSnapshot: PriorSnapshot(
                meanE: meanE,
                sdE: sdE,
                meanI: meanI,
                sdI: sdI,
                predictedEngage: posterior.predictedEngage(price: design.price, trait: design.trait)
            ),
            narrative: narrative
        )
    }
}

/// SPEC §8.2 — "one fixed phrase **and** one matching visual intensity per
/// band," for both halves of §8.3: the threshold you cross and the villager
/// who waits. One mapping, used by `ThresholdNode` and `WaitingVillagerNode`
/// alike, so a band reads the same whichever way the decision arrives.
///
/// FINDINGS.md (`experiments/perceived_price.py`) is the reason this is a
/// three-channel mapping rather than one alpha ramp: band *count* is nearly
/// free, band *distinctness* is the entire cost. Darkness, size and rim all
/// co-vary with the same scalar, because a stimulus that differs on several
/// dimensions at once is discriminated far more reliably than one that
/// differs on a single dimension by the same amount.
public enum DecisionIntensityStyle {
    /// Seven bands means adjacent bands are 1/6 apart in intensity.
    public static let adjacentBandStep: Double = 1.0 / 6.0

    private static func clamp(_ intensity: Double) -> CGFloat {
        CGFloat(min(max(intensity, 0.0), 1.0))
    }

    /// Opacity of the darkness pool. Spans 0.10 → 0.92 (adjacent bands differ
    /// by 0.137), where the first pass spanned 0.08 → 0.63 (0.092 apart).
    public static func poolAlpha(_ intensity: Double) -> CGFloat {
        0.10 + clamp(intensity) * 0.82
    }

    /// The pool also grows, from 46% to 100% of the node's base radius, so
    /// darkness and area rise together.
    public static func poolRadiusFraction(_ intensity: Double) -> CGFloat {
        0.46 + clamp(intensity) * 0.54
    }

    /// A hard rim on the pool. A crisp edge is easier to compare across
    /// bands than the soft interior of a translucent fill, and it survives
    /// the dusk palette shift (SPEC §8.1) better than fill alpha alone.
    public static func rimAlpha(_ intensity: Double) -> CGFloat {
        0.35 + clamp(intensity) * 0.60
    }

    public static func rimWidth(_ intensity: Double) -> CGFloat {
        1.0 + clamp(intensity) * 4.0
    }

    /// Soft radial falloff used as the pool's `fillTexture`.
    ///
    /// The pool was a flat shape with a hard edge on every side, which on
    /// grass read as a hole cut in the ground rather than as gathering
    /// shadow — the "shadow blob". Only the FILL is softened here: the rim
    /// above stays crisp deliberately, because a hard edge is what makes two
    /// adjacent bands comparable (SPEC §8.2), and blurring that would trade
    /// away the channel to fix the look.
    ///
    /// Multiplied by the node's `fillColor`, so the shape keeps carrying its
    /// own alpha and every intensity function above still applies unchanged.
    public static func poolFillTexture() -> SKTexture {
        if let cached = cachedPoolFill { return cached }
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            let colors = [
                UIColor(white: 1.0, alpha: 1.00).cgColor,
                UIColor(white: 1.0, alpha: 0.92).cgColor,
                UIColor(white: 1.0, alpha: 0.55).cgColor,
                UIColor(white: 1.0, alpha: 0.00).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors,
                                            locations: [0.0, 0.55, 0.82, 1.0]) else { return }
            let centre = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(gradient,
                                             startCenter: centre, startRadius: 0,
                                             endCenter: centre, endRadius: side / 2,
                                             options: [])
        }
        let tex = SKTexture(image: image)
        cachedPoolFill = tex
        return tex
    }

    nonisolated(unsafe) private static var cachedPoolFill: SKTexture?

    /// How far the villager's own sprite is pushed toward black. The figure
    /// stands deeper in the pool as the price rises. Never reaches full
    /// black — the villager must stay legible as a person.
    public static func figureShading(_ intensity: Double) -> CGFloat {
        clamp(intensity) * 0.45
    }
}
