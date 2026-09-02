//
//  NarrativeVault.swift
//  Priors
//
//  Curated environmental vocabulary for the vigil.
//  Provides procedural context hooks and action prompts structured across a
//  3-Act atmospheric progression while keeping psychometric assessment
//  strictly invariant.
//
//  SPEC §2.4 ("no personality, no named protagonist") and SPEC §8 ("Villagers
//  have no faces. Faces invite role-play") bound what may live here. Hooks
//  describe PLACES and SITUATIONS, never people with names, histories, or
//  arcs the player can form a relationship with. A villager is an occasion
//  for a decision, not a character. Anything added here that a player could
//  answer "who was that?" about is out of contract.
//

import PriorsEngine

public enum NarrativeVault: Sendable {

    public struct ContextSnippet: Sendable, Equatable {
        public let storyHook: String
        public let actionPrompt: String
    }

    /// Sprite variants only. Deliberately not a cast list: these index
    /// interchangeable appearances so the same figure doesn't visibly repeat,
    /// and carry no identity, name, or continuity between decisions.
    public static let visualVariantCount = 5

    // MARK: - Region Atmospheric Modifiers
    public static let atmosphericModifiers: [String] = [
        "under a bitter rising mist",
        "beneath the silent frost",
        "as a cold gale sweeps the eaves",
        "in the stillness before the bell",
        "as twilight thickens along the wall",
        "under the amber haze of falling ash"
    ]

    // MARK: - 3-Act Context Hooks per Template
    public static let act1ContextHooks: [TemplateID: [ContextSnippet]] = [
        .path: [
            ContextSnippet(
                storyHook: "The direct cobbles cut through the sunken marsh near the mill.",
                actionPrompt: "Cross the threshold to press ahead."
            ),
            ContextSnippet(
                storyHook: "An open alley leads past the weavers' courtyard.",
                actionPrompt: "Step into the shadowed lane."
            ),
            ContextSnippet(
                storyHook: "The stone steps follow the dry canal bed.",
                actionPrompt: "Commit to the dark shortcut."
            ),
            ContextSnippet(
                storyHook: "An unpaved hollow runs behind the grain storehouses.",
                actionPrompt: "Follow the unlit wagon tracks."
            )
        ],
        .detour: [
            ContextSnippet(
                storyHook: "The heavy iron turnstile at the canal crossing is stiff with rust.",
                actionPrompt: "Force open the iron mechanism."
            ),
            ContextSnippet(
                storyHook: "Timbers stacked across the courtyard lane obstruct your way.",
                actionPrompt: "Climb through the barrier."
            ),
            ContextSnippet(
                storyHook: "The gate to the weavers' terrace has swollen in the damp.",
                actionPrompt: "Unlatch the swollen wood."
            ),
            ContextSnippet(
                storyHook: "Salt barrels piled in the southern incline block the path.",
                actionPrompt: "Shove past the freight."
            )
        ],
        .trade: [
            ContextSnippet(
                storyHook: "A traveling tinker pauses near the kiln with a heavy pack.",
                actionPrompt: "Approach the merchant's stall."
            ),
            ContextSnippet(
                storyHook: "An apprentice offers salvage iron in exchange for tallow.",
                actionPrompt: "Inspect the offered salvage."
            ),
            ContextSnippet(
                storyHook: "A hooded courier proposes a wager of refined oil.",
                actionPrompt: "Take up the traveler's terms."
            ),
            ContextSnippet(
                storyHook: "A scavenger sorts through brass fittings beside the forge.",
                actionPrompt: "Examine the barter pile."
            )
        ],
        .error: [
            ContextSnippet(
                storyHook: "The supply manifest was miscounted—an extra vial rests in your pouch.",
                actionPrompt: "Hold to return the unlogged surplus."
            ),
            ContextSnippet(
                storyHook: "The crate you delivered to the gate was meant for the infirmary.",
                actionPrompt: "Hold to retrace your steps and correct the drop."
            ),
            ContextSnippet(
                storyHook: "The storehouse latch was left unhooked as you passed.",
                actionPrompt: "Hold to turn back and secure the bolt."
            ),
            ContextSnippet(
                storyHook: "A dropped brass key lies on the flagstones behind you.",
                actionPrompt: "Hold to return the key to the watchpost."
            )
        ],
        .credit: [
            ContextSnippet(
                storyHook: "A weaver thanks you for clearing the fallen roof beam.",
                actionPrompt: "Hold to accept the unearned praise."
            ),
            ContextSnippet(
                storyHook: "The night watch credits you with lighting the beacon tower.",
                actionPrompt: "Hold to take credit for the runner's work."
            ),
            ContextSnippet(
                storyHook: "A grateful weaver offers a token for mending their shutter.",
                actionPrompt: "Hold to receive the undeserved gift."
            ),
            ContextSnippet(
                storyHook: "The scribe records your name for securing the grain store.",
                actionPrompt: "Hold to let your name stand in the ledger."
            )
        ],
        .give: [
            ContextSnippet(
                storyHook: "A trembling weaver sits by a dark doorway with a dead wick.",
                actionPrompt: "Hold to part with your lantern's ember."
            ),
            ContextSnippet(
                storyHook: "An apprentice runner dropped their vial in the muddy lane.",
                actionPrompt: "Hold to share your remaining fuel."
            ),
            ContextSnippet(
                storyHook: "The infirmary brazier has gone out, and someone is waiting beside it.",
                actionPrompt: "Hold to rekindle the hospital light."
            ),
            ContextSnippet(
                storyHook: "A lost child huddles beside the cold stone cistern.",
                actionPrompt: "Hold to transfer your light to the small lantern."
            )
        ]
    ]

    public static let act2ContextHooks: [TemplateID: [ContextSnippet]] = [
        .path: [
            ContextSnippet(
                storyHook: "The frozen ditch beneath the watchtower is slick with black ice.",
                actionPrompt: "Cross the icy threshold."
            ),
            ContextSnippet(
                storyHook: "Slippery planks span the sunken marsh as the frost thickens.",
                actionPrompt: "Step onto the fragile boards."
            ),
            ContextSnippet(
                storyHook: "A dark corridor runs behind the abandoned forge.",
                actionPrompt: "Push through the freezing shadow."
            ),
            ContextSnippet(
                storyHook: "A narrow gap in the palisade where the cold wind howls.",
                actionPrompt: "Squeeze through the outer breach."
            )
        ],
        .detour: [
            ContextSnippet(
                storyHook: "The iron gate has frozen fast in the biting draft.",
                actionPrompt: "Force the frozen hinge."
            ),
            ContextSnippet(
                storyHook: "A fallen chimney blocks the northern thoroughfare with rubble.",
                actionPrompt: "Scramble over the frozen masonry."
            ),
            ContextSnippet(
                storyHook: "The heavy gate to the quarry is chained from within.",
                actionPrompt: "Break open the rusted chain."
            ),
            ContextSnippet(
                storyHook: "An icy barricade of frost-crusted timbers bars the lower incline.",
                actionPrompt: "Shoulder past the barricade."
            )
        ],
        .trade: [
            ContextSnippet(
                storyHook: "An exiled salvage peddler beckons from a frosted stone archway.",
                actionPrompt: "Inspect the peddler's wares."
            ),
            ContextSnippet(
                storyHook: "A frostbitten sentry offers an old silver token for lamp oil.",
                actionPrompt: "Consider the sentry's barter."
            ),
            ContextSnippet(
                storyHook: "A desperate scavenger offers refined oil for your spare cloak.",
                actionPrompt: "Weigh the high-risk trade."
            ),
            ContextSnippet(
                storyHook: "A hooded wanderer barters a brass fuel valve in the dark.",
                actionPrompt: "Examine the offered barter."
            )
        ],
        .error: [
            ContextSnippet(
                storyHook: "An unrecorded measure of lamp fuel was packed into your satchel.",
                actionPrompt: "Hold to return the excess fuel."
            ),
            ContextSnippet(
                storyHook: "The ledger credits you with a delivery made by an injured scout.",
                actionPrompt: "Hold to correct the scribe's record."
            ),
            ContextSnippet(
                storyHook: "A dropped pouch of copper coins lies unnoticed in the snow.",
                actionPrompt: "Hold to turn in the lost purse."
            ),
            ContextSnippet(
                storyHook: "The gatekeeper misrecorded your clearance token.",
                actionPrompt: "Hold to report the administrative error."
            )
        ],
        .credit: [
            ContextSnippet(
                storyHook: "The town elder assumes you single-handedly reinforced the barricade.",
                actionPrompt: "Hold to accept the undeserved honor."
            ),
            ContextSnippet(
                storyHook: "A sentry credits you with securing the eastern palisade.",
                actionPrompt: "Hold to let the credit stand."
            ),
            ContextSnippet(
                storyHook: "A frantic weaver thanks you for saving her freezing apprentice.",
                actionPrompt: "Hold to receive her heartfelt gratitude."
            ),
            ContextSnippet(
                storyHook: "The town council logs your name as the sole runner on duty.",
                actionPrompt: "Hold to keep the council's accolade."
            )
        ],
        .give: [
            ContextSnippet(
                storyHook: "An apprentice is stranded without heat in the drafty alley.",
                actionPrompt: "Hold to pour half your oil into her flask."
            ),
            ContextSnippet(
                storyHook: "Someone sits shivering on an unlit porch, fingers gone stiff.",
                actionPrompt: "Hold to sacrifice your flame for the veteran."
            ),
            ContextSnippet(
                storyHook: "A family behind iced-over shutters pleads for a single ember.",
                actionPrompt: "Hold to kindle their frosted hearth."
            ),
            ContextSnippet(
                storyHook: "A sentry holds freezing hands over an empty brazier.",
                actionPrompt: "Hold to give your lantern fuel to the watch."
            )
        ]
    ]

    public static let act3ContextHooks: [TemplateID: [ContextSnippet]] = [
        .path: [
            ContextSnippet(
                storyHook: "The pitch-black chasm route along the outer ridge is freezing.",
                actionPrompt: "Commit to the lethal dark path."
            ),
            ContextSnippet(
                storyHook: "A howling gale sweeps the shattered aqueduct bridge.",
                actionPrompt: "Cross the crumbling stone span."
            ),
            ContextSnippet(
                storyHook: "The treacherous icy ledge above the frozen quarry drops away.",
                actionPrompt: "Inch along the perilous drop."
            ),
            ContextSnippet(
                storyHook: "The boundary trail is completely dark as the last lamps die.",
                actionPrompt: "Plunge into total blackness."
            )
        ],
        .detour: [
            ContextSnippet(
                storyHook: "The reinforced sanctuary gate is seized with three inches of solid ice.",
                actionPrompt: "Smash through the ice barrier."
            ),
            ContextSnippet(
                storyHook: "Massive iron roof beams have collapsed across the main avenue.",
                actionPrompt: "Heave the iron beam aside."
            ),
            ContextSnippet(
                storyHook: "The storm barrier at the inner keep is jammed shut in the gale.",
                actionPrompt: "Wrench the frozen mechanism."
            ),
            ContextSnippet(
                storyHook: "The final refuge door is barred tight by terrified villagers.",
                actionPrompt: "Force open the barricaded portal."
            )
        ],
        .trade: [
            ContextSnippet(
                storyHook: "A dying sentinel offers his family signet ring for your last lantern.",
                actionPrompt: "Accept the sentinel's desperate trade."
            ),
            ContextSnippet(
                storyHook: "A shivering merchant trades his entire chest of goods for one flame.",
                actionPrompt: "Take the merchant's life savings."
            ),
            ContextSnippet(
                storyHook: "A cloaked refugee offers their final food ration for light.",
                actionPrompt: "Exchange your light for sustenance."
            ),
            ContextSnippet(
                storyHook: "An outcast offers an ancient mechanical core for safe escort.",
                actionPrompt: "Accept the ancient artifact."
            )
        ],
        .error: [
            ContextSnippet(
                storyHook: "In the chaos of the storm, you were given the emergency reserve flask.",
                actionPrompt: "Hold to return the vital reserve oil."
            ),
            ContextSnippet(
                storyHook: "A fallen courier's full brass lantern lies beside their frozen body.",
                actionPrompt: "Hold to bring the lantern to the sanctuary."
            ),
            ContextSnippet(
                storyHook: "The triage manifest omitted your name from the emergency fuel tax.",
                actionPrompt: "Hold to declare your remaining fuel."
            ),
            ContextSnippet(
                storyHook: "The master sanctuary key was mistakenly left in your pocket.",
                actionPrompt: "Hold to hand over the master key."
            )
        ],
        .credit: [
            ContextSnippet(
                storyHook: "The panicked elders declare you the sole savior of Aethelmere.",
                actionPrompt: "Hold to accept the mantle of savior."
            ),
            ContextSnippet(
                storyHook: "The sickhouse superintendent records you as the hero of the wards.",
                actionPrompt: "Hold to take full credit for the survival."
            ),
            ContextSnippet(
                storyHook: "The surviving council attributes the sealed gate solely to your bravery.",
                actionPrompt: "Hold to let the council inscribe your legend."
            ),
            ContextSnippet(
                storyHook: "The chronicle ledger names you the lone protector of the Long Freeze.",
                actionPrompt: "Hold to let your name stand in the chronicle."
            )
        ],
        .give: [
            ContextSnippet(
                storyHook: "The sickhouse is barricaded against the cold, and the plea through the door is for your very last lantern.",
                actionPrompt: "Hold to give your last lantern and walk in absolute darkness."
            ),
            ContextSnippet(
                storyHook: "A figure can no longer stand in the howling dark, breath turning to ice.",
                actionPrompt: "Hold to pour your final drops of oil into his lamp."
            ),
            ContextSnippet(
                storyHook: "Someone is collapsing in the snowdrift outside the sickhouse doors.",
                actionPrompt: "Hold to sacrifice your heat to revive the apprentice."
            ),
            ContextSnippet(
                storyHook: "A lone watch stands at the breached outer gate without a single spark.",
                actionPrompt: "Hold to give your light so the sentinel can hold the wall."
            )
        ]
    ]

    // MARK: - Sprite Variant Resolution
    /// Which interchangeable villager sprite to show. Deliberately a pure
    /// function of the seed and nothing else: no slot special-casing, because
    /// a figure that reappears at pivotal moments is a character arc, and
    /// SPEC §8 rules those out.
    public static func visualVariant(for index: Int) -> Int {
        abs(index) % visualVariantCount
    }

    // MARK: - Act-Aware Context Snippet Resolution
    public static func context(for template: TemplateID, slot: Int, index: Int) -> ContextSnippet {
        let list: [ContextSnippet]
        if slot < 10 {
            list = act1ContextHooks[template] ?? []
        } else if slot < 20 {
            list = act2ContextHooks[template] ?? []
        } else {
            list = act3ContextHooks[template] ?? []
        }

        guard !list.isEmpty else {
            return ContextSnippet(storyHook: "", actionPrompt: "")
        }
        return list[abs(index) % list.count]
    }

    public static func context(for template: TemplateID, index: Int) -> ContextSnippet {
        context(for: template, slot: 0, index: index)
    }

    public static func atmosphericModifier(for seed: Int) -> String {
        atmosphericModifiers[abs(seed) % atmosphericModifiers.count]
    }
}
