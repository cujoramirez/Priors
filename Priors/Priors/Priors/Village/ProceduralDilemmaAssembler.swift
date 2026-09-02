//
//  ProceduralDilemmaAssembler.swift
//  Priors
//
//  Assembles a 3-tier procedural dilemma narrative for an in-world decision:
//  Tier 1: Context Hook (procedural story situation across 3 Acts)
//  Tier 2: BandLadder Phrase (invariant severity anchor across 7 bands)
//  Tier 3: Action Prompt (diegetic choice call-to-action)
//

import PriorsEngine

public struct DilemmaNarrative: Sendable, Equatable {
    /// Which interchangeable villager sprite to show. Not an identity —
    /// SPEC §8 keeps villagers faceless, so this carries appearance variety
    /// and nothing a player could recognise across decisions.
    public let visualVariant: Int
    public let contextHook: String
    public let bandPhrase: String
    public let actionPrompt: String

    public init(
        visualVariant: Int,
        contextHook: String,
        bandPhrase: String,
        actionPrompt: String
    ) {
        self.visualVariant = visualVariant
        self.contextHook = contextHook
        self.bandPhrase = bandPhrase
        self.actionPrompt = actionPrompt
    }

    /// Formatted text combining the context hook and the invariant BandLadder phrase.
    public var fullDisplayText: String {
        if contextHook.isEmpty {
            return bandPhrase
        }
        return "\(contextHook) \(bandPhrase)"
    }
}

public enum ProceduralDilemmaAssembler: Sendable {
    /// Deterministically assembles a procedural dilemma narrative based on template, price,
    /// location, slot, and session seed while strictly preserving the BandLadder phrase.
    public static func assemble(
        template: TemplateID,
        price: Double,
        locationID: Int,
        slot: Int = 0,
        sessionSeed: Int
    ) -> DilemmaNarrative {
        let band = BandLadder.band(for: price, template: template)
        let corePhrase = BandLadder.phrase(template: template, band: band)

        // Derive deterministic index hashes from sessionSeed + locationID + slot
        let combinedHash = abs(sessionSeed ^ (locationID * 31) ^ (slot * 17) ^ template.rawValue.hashValue)
        let snippet = NarrativeVault.context(for: template, slot: slot, index: combinedHash)

        return DilemmaNarrative(
            visualVariant: NarrativeVault.visualVariant(for: combinedHash),
            contextHook: snippet.storyHook,
            bandPhrase: corePhrase,
            actionPrompt: snippet.actionPrompt
        )
    }

    /// Overload accepting a complete Design from ADOSelector with slot.
    public static func assemble(
        design: Design,
        slot: Int,
        locationID: Int,
        sessionSeed: Int
    ) -> DilemmaNarrative {
        assemble(
            template: design.template,
            price: design.price,
            locationID: locationID,
            slot: slot,
            sessionSeed: sessionSeed
        )
    }

    /// Overload accepting a complete Design from ADOSelector without slot.
    public static func assemble(
        design: Design,
        locationID: Int,
        sessionSeed: Int
    ) -> DilemmaNarrative {
        assemble(
            template: design.template,
            price: design.price,
            locationID: locationID,
            slot: 0,
            sessionSeed: sessionSeed
        )
    }
}
