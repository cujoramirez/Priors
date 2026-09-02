//
//  ProceduralNarrativeTests.swift
//  PriorsTests
//
//  Verifies that the procedural narrative engine generates diverse,
//  replayable story context while strictly preserving the psychometric
//  invariants of BandLadder and LiveDecision across all 3 Acts.
//

import Testing
import PriorsEngine
@testable import Priors

struct ProceduralNarrativeTests {
    @Test func deterministicGenerationForSameSeed() async throws {
        let narrative1 = ProceduralDilemmaAssembler.assemble(
            template: .error,
            price: 0.25,
            locationID: 10,
            slot: 2,
            sessionSeed: 12345
        )
        let narrative2 = ProceduralDilemmaAssembler.assemble(
            template: .error,
            price: 0.25,
            locationID: 10,
            slot: 2,
            sessionSeed: 12345
        )

        #expect(narrative1 == narrative2)
        #expect(narrative1.speakerName == narrative2.speakerName)
        #expect(narrative1.contextHook == narrative2.contextHook)
        #expect(narrative1.bandPhrase == narrative2.bandPhrase)
    }

    @Test func distinctNarrativesAcrossDifferentSeeds() async throws {
        let narrativeA = ProceduralDilemmaAssembler.assemble(
            template: .give,
            price: 0.35,
            locationID: 15,
            slot: 5,
            sessionSeed: 1001
        )
        let narrativeB = ProceduralDilemmaAssembler.assemble(
            template: .give,
            price: 0.35,
            locationID: 15,
            slot: 5,
            sessionSeed: 2002
        )

        // Both preserve the exact same BandLadder phrase for the same price
        #expect(narrativeA.bandPhrase == narrativeB.bandPhrase)
        // But context hooks or speakers should vary across distinct seeds
        let isDifferent = (narrativeA.speakerName != narrativeB.speakerName) ||
                          (narrativeA.contextHook != narrativeB.contextHook)
        #expect(isDifferent)
    }

    @Test func everyTemplateHasValidNarrativeContentAcrossAllActs() async throws {
        let allTemplates: [TemplateID] = [.path, .detour, .trade, .error, .credit, .give]
        let testSlots = [2, 12, 22] // Act I, Act II, Act III
        for template in allTemplates {
            for slot in testSlots {
                for seed in 0..<5 {
                    let narrative = ProceduralDilemmaAssembler.assemble(
                        template: template,
                        price: 0.30,
                        locationID: seed,
                        slot: slot,
                        sessionSeed: seed * 100
                    )

                    #expect(!narrative.speakerName.isEmpty)
                    #expect(!narrative.speakerRole.isEmpty)
                    #expect(!narrative.contextHook.isEmpty)
                    #expect(!narrative.bandPhrase.isEmpty)
                    #expect(!narrative.actionPrompt.isEmpty)
                    #expect(!narrative.fullDisplayText.isEmpty)
                }
            }
        }
    }

    @Test func bandLadderPhraseIsStrictlyPreserved() async throws {
        let allTemplates: [TemplateID] = [.path, .detour, .trade, .error, .credit, .give]
        for template in allTemplates {
            for band in 1...7 {
                let expectedPhrase = BandLadder.phrase(template: template, band: band)
                // Select a price that maps to this band
                let (lo, hi): (Double, Double) = (template == .path || template == .detour || template == .trade) ? (0.05, 0.85) : (0.02, 0.70)
                let price = lo + (Double(band) - 0.5) * ((hi - lo) / 7.0)

                let narrative = ProceduralDilemmaAssembler.assemble(
                    template: template,
                    price: price,
                    locationID: band,
                    slot: 3,
                    sessionSeed: 42
                )

                #expect(narrative.bandPhrase == expectedPhrase)
                #expect(narrative.fullDisplayText.contains(expectedPhrase))
            }
        }
    }

    @Test func liveDecisionCarriesAssembledNarrative() async throws {
        let post = BehaviouralPosterior()
        let state = SelectionState()
        let design = ADOSelector.selectDesign(posterior: post, slot: 0, state: state)

        let narrative = ProceduralDilemmaAssembler.assemble(
            design: design,
            slot: 0,
            locationID: 5,
            sessionSeed: 999
        )
        let decision = LiveDecision(design: design, narrative: narrative)

        #expect(decision.narrative != nil)
        #expect(decision.narrative?.speakerName == narrative.speakerName)
        #expect(decision.phrase == narrative.bandPhrase)
    }

    @Test func threeActProgressionEvolvesContext() async throws {
        let template: TemplateID = .give
        let price = 0.35
        let loc = 1
        let seed = 42

        let act1 = ProceduralDilemmaAssembler.assemble(template: template, price: price, locationID: loc, slot: 2, sessionSeed: seed)
        let act2 = ProceduralDilemmaAssembler.assemble(template: template, price: price, locationID: loc, slot: 14, sessionSeed: seed)
        let act3 = ProceduralDilemmaAssembler.assemble(template: template, price: price, locationID: loc, slot: 24, sessionSeed: seed)

        // All 3 share the invariant BandLadder phrase
        #expect(act1.bandPhrase == act2.bandPhrase)
        #expect(act2.bandPhrase == act3.bandPhrase)

        // But context hooks reflect the increasing atmospheric severity of each act
        #expect(act1.contextHook != act2.contextHook)
        #expect(act2.contextHook != act3.contextHook)
    }

    @Test func chapterBannerMessagesMatchSpec() async throws {
        #expect(VillageContainerView.bannerMessage(for: 0)?.contains("Act I: The Evening Bell") == true)
        #expect(VillageContainerView.bannerMessage(for: 10)?.contains("Act II: The Eye in the Frost") == true)
        #expect(VillageContainerView.bannerMessage(for: 15)?.contains("The Ancient Effigy opens its eyes") == true)
        #expect(VillageContainerView.bannerMessage(for: 20)?.contains("Act III: The Dying Flame") == true)

        #expect(VillageContainerView.bannerMessage(for: 1) == nil)
        #expect(VillageContainerView.bannerMessage(for: 5) == nil)
        #expect(VillageContainerView.bannerMessage(for: 29) == nil)
    }

    @Test func characterArcKeySlotsAnchorCentralNPCs() async throws {
        let marenArc = NarrativeVault.npc(for: 4, index: 0)
        #expect(marenArc.name == "Maren" || marenArc.name == "Sela")

        let orinArc = NarrativeVault.npc(for: 8, index: 0)
        #expect(orinArc.name == "Old Orin")

        let kaelArc = NarrativeVault.npc(for: 10, index: 0)
        #expect(kaelArc.name == "Kael")

        let elowenArc = NarrativeVault.npc(for: 6, index: 0)
        #expect(elowenArc.name == "Elowen")
    }

    @Test func prologueScreenHasThreePages() async throws {
        #expect(PrologueScreen.pages.count == 3)
        #expect(PrologueScreen.pages[0].contains("The sun set three years ago"))
        #expect(PrologueScreen.pages[1].contains("Tonight is the Long Freeze"))
        #expect(PrologueScreen.pages[2].contains("What you give, and what you keep"))
    }
}
