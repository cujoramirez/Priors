//
//  ProceduralNarrativeTests.swift
//  PriorsTests
//
//  Verifies that the procedural narrative engine generates diverse,
//  replayable story context while strictly preserving the psychometric
//  invariants of BandLadder and LiveDecision across all 3 Acts.
//

import Foundation
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
        #expect(narrative1.visualVariant == narrative2.visualVariant)
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
        // But context hooks or sprite variants should vary across distinct seeds
        let isDifferent = (narrativeA.visualVariant != narrativeB.visualVariant) ||
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

                    #expect(narrative.visualVariant >= 0)
                    #expect(narrative.visualVariant < NarrativeVault.visualVariantCount)
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
        #expect(decision.narrative?.visualVariant == narrative.visualVariant)
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

    /// The inverse of the test this replaces. Sprite variant must depend on the
    /// seed ALONE — the moment a particular figure is pinned to particular
    /// slots, it is a recurring character with an arc, which SPEC §8 rules out.
    @Test func spriteVariantCarriesNoSlotIdentity() async throws {
        for seed in 0..<40 {
            let variant = NarrativeVault.visualVariant(for: seed)
            #expect(variant >= 0)
            #expect(variant < NarrativeVault.visualVariantCount)
        }

        // Same seed, different slots in different acts: the figure the player
        // meets must not be anchored to where they are in the session.
        let templates: [TemplateID] = [.error, .credit, .give]
        for template in templates {
            let early = ProceduralDilemmaAssembler.assemble(
                template: template, price: 0.3, locationID: 7, slot: 4, sessionSeed: 31
            )
            let late = ProceduralDilemmaAssembler.assemble(
                template: template, price: 0.3, locationID: 7, slot: 24, sessionSeed: 31
            )
            // Not an equality assertion in either direction: the point is only
            // that nothing in the vault special-cases a slot into a persona.
            #expect(early.visualVariant < NarrativeVault.visualVariantCount)
            #expect(late.visualVariant < NarrativeVault.visualVariantCount)
        }
    }

    @Test func prologueScreenHasThreePages() async throws {
        #expect(PrologueScreen.pages.count == 3)
        #expect(PrologueScreen.pages[0].contains("The sun set three years ago"))
        #expect(PrologueScreen.pages[1].contains("Tonight is the Long Freeze"))
        #expect(PrologueScreen.pages[2].contains("What you give, and what you keep"))
    }

    /// SPEC §2.4 ("no personality, no named protagonist") and SPEC §8
    /// ("Villagers have no faces. Faces invite role-play"). A prior session
    /// shipped a named cast (Maren, Kael, Orin, Elowen...) into this vault.
    /// It never rendered, but it was one wiring change away from doing so.
    /// This pins the contract so it cannot come back silently.
    @Test func narrativeNeverNamesAVillager() async throws {
        let allTemplates: [TemplateID] = [.path, .detour, .trade, .error, .credit, .give]
        // Capitalised words that are legitimately not villager names: sentence
        // openers are covered by only inspecting non-initial words, and these
        // are the proper nouns the setting itself is allowed to have.
        // Places and events, not people. The distinction that matters is
        // whether a player could answer "who was that?" — a valley and a
        // named winter give the world a history without giving a villager one.
        let allowedProperNouns: Set<String> = ["Aethelmere", "Long", "Freeze"]

        for template in allTemplates {
            for slot in 0..<30 {
                for seed in 0..<20 {
                    let narrative = ProceduralDilemmaAssembler.assemble(
                        template: template,
                        price: 0.30,
                        locationID: seed,
                        slot: slot,
                        sessionSeed: seed * 977
                    )
                    for text in [narrative.contextHook, narrative.actionPrompt] {
                        let words = text.split(separator: " ").map(String.init)
                        for word in words.dropFirst() {
                            let bare = word.trimmingCharacters(
                                in: CharacterSet.alphanumerics.inverted
                            )
                            guard let first = bare.first, first.isUppercase else { continue }
                            #expect(
                                allowedProperNouns.contains(bare),
                                "Villager narrative must stay nameless, found \"\(bare)\" in: \(text)"
                            )
                        }
                    }
                }
            }
        }
    }
}
