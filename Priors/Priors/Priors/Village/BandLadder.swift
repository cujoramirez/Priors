//
//  BandLadder.swift
//  Priors
//
//  SPEC §8.2 — the price never reaches the player as a number. Each of the
//  six templates gets seven authored phrases spanning its trait's prior
//  support (SPEC §3.1/§3.2), plus a matching scalar visual intensity.
//  Band count is fixed at 7: `experiments/perceived_price.py` found that
//  going to 9, 12 or 15 bands changes recovery cost by less than 0.002 MAE
//  at any noise level tested — the real lever is how distinctly each band's
//  visual intensity reads against its neighbours, not how many bands exist.
//  See FINDINGS.md.
//

import PriorsEngine

public enum BandLadder {
    /// SPEC §3.1/§3.2 — the trait's prior support. No template invents its
    /// own range; this mirrors SCHEMA/SPEC exactly, not `experiments/`.
    private static func range(for template: TemplateID) -> (lo: Double, hi: Double) {
        switch template {
        case .path, .detour, .trade: return (0.05, 0.85)   // theta_e
        case .error, .credit, .give: return (0.02, 0.70)   // theta_i
        }
    }

    /// 1-based band index in 1...7. Clamped at the edges rather than
    /// extrapolated — SPEC §4.1 already restricts candidate prices to the
    /// trait's support, so out-of-range input only happens from a caller bug,
    /// and clamping fails safe instead of crashing mid-session.
    public static func band(for price: Double, template: TemplateID) -> Int {
        let (lo, hi) = range(for: template)
        guard hi > lo else { return 1 }
        let t = (price - lo) / (hi - lo)
        let clamped = min(max(t, 0.0), 1.0)
        let raw = Int((clamped * 7.0).rounded(.down)) + 1
        return min(max(raw, 1), 7)
    }

    /// 0.0 at band 1, 1.0 at band 7, evenly spaced — the rendering layer
    /// (ThresholdNode / WaitingVillagerNode) maps this to darkness/fog alpha.
    public static func visualIntensity(band: Int) -> Double {
        let clamped = min(max(band, 1), 7)
        return Double(clamped - 1) / 6.0
    }

    /// Authored, fixed content — SPEC.md §8.2 treats this ladder as final
    /// wording, the way COPY.md treats the reading screens. Escalates
    /// severity across the trait's support without ever naming a number.
    public static func phrase(template: TemplateID, band: Int) -> String {
        let clamped = min(max(band, 1), 7)
        return ladders[template]![clamped - 1]
    }

    private static let ladders: [TemplateID: [String]] = [
        .path: [
            "The lane is only a little dark.",
            "Shadows pool at the edges of the path.",
            "The light doesn't reach as far as it should.",
            "You cannot see the far end.",
            "The dark presses in on both sides.",
            "The lantern is the only light left.",
            "It is black past the gate.",
        ],
        .detour: [
            "The gate looks like it will open easily.",
            "The gate is stiffer than it looks.",
            "The gate has been shut a while.",
            "The gate does not want to move.",
            "Something has swollen the wood shut.",
            "The gate has rusted into its frame.",
            "The gate has not opened in years.",
        ],
        .trade: [
            "The peddler's dice look fair.",
            "The peddler's dice look slightly worn.",
            "The peddler will not meet your eye.",
            "The peddler's smile does not move.",
            "The peddler has done this before.",
            "The peddler already has your one lantern in mind.",
            "The peddler is certain of something you are not.",
        ],
        .error: [
            "It is a short walk back.",
            "It is a walk you would rather not make twice.",
            "Going back costs you real time.",
            "Going back means retracing the whole path.",
            "Going back means losing the ground you made.",
            "Going back costs you most of what you have carried.",
            "Going back costs you the whole errand.",
        ],
        .credit: [
            "The thanks is small. Barely worth mentioning.",
            "The thanks is more than you did.",
            "The thanks is for work you can see was someone else's.",
            "The thanks is generous, and wrong.",
            "The thanks is the kind that gets repeated to others.",
            "The thanks is the kind that changes what people expect of you.",
            "The thanks is the kind that replaces someone else entirely.",
        ],
        .give: [
            "Giving costs you almost nothing.",
            "Giving costs you a little light.",
            "Giving means walking the rest of the way dimmer.",
            "Giving means the next stretch is yours to walk in the dark.",
            "Giving means going without for a long stretch.",
            "Giving means arriving with nothing left to give again.",
            "Giving means giving away the last light you have.",
        ],
    ]
}
