//
//  LiveDecision.swift
//  Priors
//
//  Replaces ScenarioPromptData/ScenarioDialogView. SPEC §8.2/§8.3: no modal,
//  no printed number. This is the data the world renders — a phrase and a
//  scalar intensity — attached to whichever single pre-built location is
//  currently armed (VillageMapBuilder, VillageCoordinator).
//

import PriorsEngine

public struct LiveDecision: Sendable {
    public let design: Design
    public let band: Int
    public let phrase: String
    public let visualIntensity: Double

    /// SPEC §3.1/§3.2 — spatial templates are a threshold you cross; social
    /// templates are a villager who waits. The two sets are exactly the two
    /// traits (theta_e / theta_i), so this is a straight lookup, not a new
    /// design axis.
    public let isSpatial: Bool

    public init(design: Design) {
        self.design = design
        self.band = BandLadder.band(for: design.price, template: design.template)
        self.phrase = BandLadder.phrase(template: design.template, band: band)
        self.visualIntensity = BandLadder.visualIntensity(band: band)
        switch design.template {
        case .path, .detour, .trade: self.isSpatial = true
        case .error, .credit, .give: self.isSpatial = false
        }
    }
}
