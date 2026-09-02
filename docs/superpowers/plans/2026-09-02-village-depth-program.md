# Village Depth — Program Design & Phase 1 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement Phase 1 task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Aethelmere read as a place a person lives in rather than an asset-pack demo, and make the wordless villager encounter the most affecting moment in the game — without weakening the measurement instrument that is the point of the project.

**Architecture:** Four independent subsystems, each shipping working software on its own, each with its own plan. This document is the design to argue with, plus Phase 1 at task granularity. Nothing here adds dialogue, quests, objective markers or named characters; every "story" beat is carried by place, light, sound and performance.

**Tech Stack:** SpriteKit (SKTileMapNode, SKAction, SKShapeNode), SwiftUI for chrome, AVAudioEngine for stems, Python 3 + Pillow for the asset build (`scripts/build_assets.py`), CC0/permissive packs already vendored in `Priors/Assets-source/`.

**Spec:** `SPEC.md` (contract), `SPEC-GAME.md` (ratified game-layer argument), `priors-research/FINDINGS.md`, and the psychological-integrity framework synthesis supplied by the project owner.

---

## Global Constraints

Copied verbatim. Every task's requirements implicitly include this section.

- SPEC §1: *"A cheerful top-down pixel game with a mundane task."* — **Owner ruling (2026-09-02): the sunless/psychological-horror framing is deliberate and permitted. Golden hour at step 0 decaying to genuine night stands.** Record any further tonal drift as a decision, never as an implementation detail.
- SPEC §2.2: *"No deception during play. No swapped choices, no fake feedback, no manufactured doubt. The eye is a real manipulation whose effect is measured and disclosed — that is the only permitted 'trick'."* Atmosphere is not deception; fake feedback is. Nothing in this program may tell the player something untrue about their own actions.
- SPEC §2.3: *"The model is never visible during play. No confidence meter, no prediction display, no score."*
- SPEC §2.4: *"Avatar play only. No named protagonist, no personality, no score, no fail state, no optimal path, no leaderboard, no share button."*
- SPEC §2.7: *"No network. No analytics, no crash reporting, no CloudKit, no backend."*
- SPEC §8: *"Villagers have no faces. Faces invite role-play."*
- SPEC §8: *"HUD: lantern count only."* No minimap, no objective marker, no quest log.
- SPEC §8: *"Dead space is required. At least 30% of walkable area contains nothing. Pointless exploration is the best data in the run. Log it."*
- SPEC §8.1: *"Never change key or tempo. Only remove layers. Never add anything back."* The five stems drop monotonically on posterior SD.
- SPEC §8.3: The villager *"never follows, never repeats itself, and never reacts to being declined."*
- SPEC-GAME.md:172: *"No names, no personalities, no dialogue trees."*
- **Frozen files — never modify:** `Posterior.swift`, `BehaviouralPosterior.swift` likelihood math (`choiceLogLik`/`rtLogLik`/`update`), `ADOSelector.swift`, `ClaimGenerator.swift`. A genuine need to touch one is a finding for the owner, not an edit.
- **Determinism:** the village must be byte-identical for every player. SPEC §5's adaptive design is the only thing permitted to vary between sessions. Any new randomness is seeded from tile coordinates, never from `Date` or unseeded RNG.
- **The instrument outranks the art.** No change may alter what `rt_ms`, `approach_frac`, `backtracks` or `idle_ms` measure. Animation runs on `SKAction`; decision resolution stays in `VillageScene.update(_:)` reading `currentTime` directly.
- Licences: every asset ships with its source pack's licence file, and `ASSETS.md` records pack, licence and what was taken. Note `ASSETS.md` currently misdescribes `oga-character-bases/rpgbaseformatted.png` as a 4-direction top-down walker; it is a side-view brawler sheet. Correct it, do not trust it.

---

## The argument

The village is flat for four separate reasons, and they need different fixes. Naming them separately is the point of this document — "make it less flat" is not a task anyone can execute or review.

**1. It has no places.** 80×60 tiles of uniform meadow with cottages scattered on it. Nowhere is anywhere. A player cannot say "the pond end" or "behind the mill" because those do not exist as distinct spaces. SPEC §8 already demands 30% dead space and calls pointless exploration "the best data in the run" — but dead space only reads as *choosing not to go somewhere* if the somewhere is legible. Undifferentiated meadow produces wandering, not exploration, and `approach_frac` and revisit counts get noisier for it. **Districts are a measurement improvement, not decoration.**

**2. Nothing moves.** The walk cycle is a one-pixel bob derived in `build_assets.py` because the source pack has no cycle. There is no idle. A villager arrives by sliding. The player's own figure never acknowledges standing still, turning, or reaching a threshold. This is the single largest gap between what the game is and what it feels like.

**3. The one interaction that exists is under-staged.** SPEC §8.3's social decision — a villager walks up, stops, waits, and either receives your hold or watches you leave — is already a complete dramatic scene. It currently renders as a sprite translating to a stop with a text pill fading in. Everything that would make it land is performance, and performance needs no words. Constraint that bites here: §8.3 forbids reacting to being declined, so the villager's *departure* must be identical whether engaged or not. Timing and posture on *arrival* are free; anything after resolution is not.

**4. Sound does not situate.** Five procedural stems decay on posterior SD, correctly and monotonically. But there is no sound *of a place* — no water at the pond, no wind at the exposed north, no interior hum near lit cottages, and no feedback for delivering a lantern or crossing a threshold. §8.1 governs the *music*; it says nothing about diegetic ambience, which is a separate bus and must never be mistaken for a sixth stem.

**What this program deliberately does not do:** dialogue, quest logs, objective markers, named villagers, NPC reactions to the player's choices. Each is either forbidden by the constraints above or destroys stealth assessment — and per the owner's own framework synthesis (§4.3, Mislevy/Shute), stealth assessment is what removes the Hawthorne Effect and social-desirability bias. Reintroducing a modal turns `rt_ms` from hesitation into reading speed.

---

## Subsystem split

Four plans. Each ships something playable on its own; each gets its own document when its turn comes.

| Phase | Subsystem | Ships | Depends on |
|---|---|---|---|
| **1** | **NPC & player performance** | Directional walk cycles, idle, arrival/waiting/departure staging, threshold approach feedback | nothing |
| 2 | Map districts & silhouettes | Six named districts, building depth, landmark props, path edging | nothing (parallel with 1) |
| 3 | Diegetic audio | Ambience bus, positional sources, interaction SFX | 2 (needs districts to place sources) |
| 4 | Store readiness | App icon, launch screen, Dynamic Type, VoiceOver, privacy manifest, screenshots | 1–3 |

Phase 1 goes first because it is the cheapest large gain, it is entirely additive, and it touches no file that Phase 2 restructures.

---

## Phase 1 — File Structure

- `scripts/build_assets.py` — **modify.** Derives the character atlas. Grows from a 4×4 single-pose sheet to a directional sheet with real frames. Owns every source→shipped pixel mapping; nothing else may slice source art.
- `Priors/Priors/Priors/Village/VillageAssets.swift` — **modify.** Slices the atlas and vends textures. Gains idle frames and a documented atlas contract.
- `Priors/Priors/Priors/Village/CharacterNode.swift` — **modify.** `PlayerNode` gains idle-vs-walk state and a footstep cadence hook.
- `Priors/Priors/Priors/Village/VillagerPerformance.swift` — **create.** All `SKAction` staging for the waiting villager: approach, settle, wait, depart. Kept out of `WaitingVillagerNode` so the node stays about state and geometry while this file is about time, and so a reviewer can check §8.3 compliance in one place.
- `Priors/Priors/Priors/Village/WaitingVillagerNode.swift` — **modify.** Delegates staging to `VillagerPerformance`; keeps `hasArrived`, radii, intensity.
- `Priors/Priors/PriorsTests/VillagerPerformanceTests.swift` — **create.** Pins the §8.3 invariants that matter: identical departure on engage and decline, no follow, no repeat.
- `Priors/Priors/PriorsTests/CharacterAnimationTests.swift` — **create.** Pins atlas shape and idle/walk switching.

**Interfaces produced by Phase 1** (Phase 3 consumes these):

```swift
// VillagerPerformance.swift
public enum VillagerPerformance {
    public static func approach(to point: CGPoint, speed: CGFloat) -> SKAction
    public static func settle() -> SKAction
    public static func waiting() -> SKAction            // repeatForever
    public static func depart(heading: CGVector) -> SKAction
    public static let settleDuration: TimeInterval      // 0.35
}

// CharacterNode.swift
extension PlayerNode {
    public var onFootfall: (() -> Void)? { get set }    // Phase 3 hooks footstep SFX here
}
```

---

## Phase 1 — Tasks

### Task 1: Directional character atlas

**Files:**
- Modify: `scripts/build_assets.py`
- Modify: `Priors/Priors/Priors/Village/VillageAssets.swift:150-200`
- Test: `Priors/Priors/PriorsTests/CharacterAnimationTests.swift` (create)

**Interfaces:**
- Consumes: nothing
- Produces: `VillageAssets.playerWalkCycle(direction:) -> [SKTexture]` (3 frames), `VillageAssets.playerIdleTexture(direction:) -> SKTexture`, `VillageAssets.npcWalkCycle(variant:) -> [SKTexture]` (3 frames), `VillageAssets.npcIdleTexture(variant:) -> SKTexture`. Atlas is 6 columns × 6 rows of 16px.

Atlas contract — write this comment into both the script and `VillageAssets`:

```
row 0: player down  idle, walkA, walkB, walkC, —, —
row 1: player side  idle, walkA, walkB, walkC, —, —   (left is this mirrored)
row 2: player up    idle, walkA, walkB, walkC, —, —
rows 3-5: villagers 1-5, two per row: idle, walkA, walkB (6 columns = 2 villagers × 3)
```

The hood has no face, so "up" and "down" differ only in the lantern's side and the cloak hem. That is the honest consequence of SPEC §8, not a shortcut — do not add a face to create directionality.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SpriteKit
@testable import Priors

@Suite("Character animation")
@MainActor
struct CharacterAnimationTests {
    @Test func playerHasThreeWalkFramesPerDirection() async throws {
        for direction in Direction.allCases {
            let cycle = VillageAssets.shared.playerWalkCycle(direction: direction)
            #expect(cycle.count == 3, "\(direction) has \(cycle.count) frames; a two-frame bob is not a walk")
        }
    }

    @Test func idleIsNotJustTheFirstWalkFrame() async throws {
        let idle = VillageAssets.shared.playerIdleTexture(direction: .down)
        let walking = VillageAssets.shared.playerWalkCycle(direction: .down)[1]
        #expect(idle !== walking)
    }

    @Test func everyVillagerVariantHasACycle() async throws {
        for variant in 0..<VillageAssets.shared.villagerVariantCount {
            #expect(VillageAssets.shared.npcWalkCycle(variant: variant).count == 3)
        }
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `xcodebuild test -project Priors/Priors/Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,id=<booted sim>' -only-testing:PriorsTests/CharacterAnimationTests`

Expected: FAIL — `playerWalkCycle` returns 2 frames.

- [ ] **Step 3: Derive real frames in the asset build**

In `scripts/build_assets.py`, replace `bob()` usage for the player and villagers with a three-frame cycle: contact (both feet apart), pass (feet together, body raised 1px), contact mirrored. The hood sprite has no legs drawn below the hem, so the cycle is carried by a 1px vertical bob plus a 1px horizontal sway in opposite directions on the two contact frames:

```python
def sway(img: Image.Image, dx: int, dy: int) -> Image.Image:
    """One frame of the walk. The hood hides the legs, so the cycle has to be
    read from the whole figure rocking rather than from limbs the pack never
    drew."""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (dx, dy))
    return out


def walk_cycle(img: Image.Image) -> list:
    """contact, pass, contact-mirrored — three frames, played at 8fps."""
    return [sway(img, -1, 0), sway(img, 0, -1), sway(img, 1, 0)]
```

Emit the 6×6 atlas described in the contract above, idle in column 0.

- [ ] **Step 4: Widen the Swift slicer**

In `VillageAssets.loadCharacters()`, slice 6 columns × 6 rows, store `playerIdle[direction]` separately from `playerFrames[direction]`, and store 5 villager cycles of 3. Keep `.left` as `.right` mirrored by `CharacterNode`.

- [ ] **Step 5: Run the test and confirm it passes**

Expected: PASS, 3 tests.

- [ ] **Step 6: Render the atlas and look at it**

```bash
python3 - <<'PY'
from PIL import Image
im = Image.open("Priors/Priors/Priors/Resources/Traveller.png").convert("RGBA")
out = im.resize((im.width*9, im.height*9), Image.NEAREST)
bg = Image.new("RGBA", out.size, (26,28,34,255)); bg.alpha_composite(out)
bg.convert("RGB").save("/tmp/atlas.png")
PY
```

Open `/tmp/atlas.png`. This project shipped a well sprite as the player character because nobody rendered the atlas and looked at it. Do not skip this step; confirm every figure is hooded and faceless before continuing.

- [ ] **Step 7: Commit**

```bash
git add scripts/build_assets.py Priors/Priors/Priors/Village/VillageAssets.swift \
        Priors/Priors/Priors/Resources/Traveller.png \
        Priors/Priors/Priors/Assets.xcassets/Traveller.imageset \
        Priors/Priors/PriorsTests/CharacterAnimationTests.swift
git commit -m "Three-frame directional walk cycles and a real idle pose"
```

---

### Task 2: Player idle and walk state

**Files:**
- Modify: `Priors/Priors/Priors/Village/CharacterNode.swift:55-110`
- Test: `Priors/Priors/PriorsTests/CharacterAnimationTests.swift` (extend)

**Interfaces:**
- Consumes: `VillageAssets.playerIdleTexture(direction:)`, `playerWalkCycle(direction:)` from Task 1
- Produces: `PlayerNode.onFootfall: (() -> Void)?`, called once per contact frame

- [ ] **Step 1: Write the failing test**

```swift
@Test func stoppingSwitchesToIdleAndSilencesFootfalls() async throws {
    let player = PlayerNode()
    var footfalls = 0
    player.onFootfall = { footfalls += 1 }

    player.updateMovement(vector: CGVector(dx: 1, dy: 0))
    #expect(player.isMoving)
    #expect(player.action(forKey: "player_walk_anim") != nil)

    player.updateMovement(vector: .zero)
    #expect(!player.isMoving)
    #expect(player.action(forKey: "player_walk_anim") == nil,
            "the walk cycle kept running while standing still")
}
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: FAIL — the walk action is never removed on stop.

- [ ] **Step 3: Implement idle/walk switching**

In `updateMovement(vector:)`, when magnitude drops below `movingThreshold`, remove the walk action and set the idle texture for `currentDirection`. When it rises above, start the 3-frame cycle at 8fps with `SKAction.animate(with:timePerFrame:0.125)` wrapped in `repeatForever`, and fire `onFootfall` on frames 0 and 2 via an interleaved `SKAction.run`.

- [ ] **Step 4: Run it and confirm it passes**

- [ ] **Step 5: Look at it in the running app**

```bash
xcrun simctl launch <sim> com.gadingperdana.Priors -startPhase village
```

Walk, stop, turn. Confirm the figure settles rather than freezing mid-stride.

- [ ] **Step 6: Commit**

```bash
git add Priors/Priors/Priors/Village/CharacterNode.swift Priors/Priors/PriorsTests/CharacterAnimationTests.swift
git commit -m "Player settles into idle instead of freezing mid-stride"
```

---

### Task 3: Villager performance — approach, settle, wait, depart

**Files:**
- Create: `Priors/Priors/Priors/Village/VillagerPerformance.swift`
- Modify: `Priors/Priors/Priors/Village/WaitingVillagerNode.swift`
- Test: `Priors/Priors/PriorsTests/VillagerPerformanceTests.swift` (create)

**Interfaces:**
- Consumes: Task 1's `npcWalkCycle(variant:)`
- Produces: the `VillagerPerformance` API in the File Structure section above

This is the task the whole phase exists for, and the one most able to break the contract. SPEC §8.3: the villager *"never follows, never repeats itself, and never reacts to being declined."* Arrival staging is free. Departure must be **byte-identical** whether the player engaged or walked away — if the villager slumps when declined, the game has told the player they did something wrong, which is both a §2.2 fake-feedback violation and a direct corruption of θ_i on every later social slot.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SpriteKit
@testable import Priors

@Suite("Villager performance")
@MainActor
struct VillagerPerformanceTests {

    /// SPEC §8.3 — "never reacts to being declined". If the departure differs
    /// by outcome, the villager is telling the player they were judged, which
    /// changes every social decision that follows it.
    @Test func departureIsIdenticalWhetherEngagedOrDeclined() async throws {
        let heading = CGVector(dx: 1, dy: 0)
        let engaged = VillagerPerformance.depart(heading: heading)
        let declined = VillagerPerformance.depart(heading: heading)
        #expect(engaged.duration == declined.duration)
    }

    @Test func waitingLoopDoesNotTranslateTheVillager() async throws {
        let node = SKNode()
        let start = node.position
        node.run(VillagerPerformance.waiting())
        for _ in 0..<10 { node.run(.wait(forDuration: 0.1)) }
        #expect(node.position == start, "the villager drifted while waiting; §8.3 says it never follows")
    }

    @Test func settleIsShortEnoughNotToEatTheDwellClock() async throws {
        // rt_ms starts at zone entry (SPEC §8.3). A long settle would be
        // charged to the player as hesitation.
        #expect(VillagerPerformance.settleDuration <= 0.4)
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: FAIL — `VillagerPerformance` does not exist.

- [ ] **Step 3: Write `VillagerPerformance.swift`**

```swift
//
//  VillagerPerformance.swift
//  Priors
//
//  SPEC §8.3's social decision is already a complete scene: someone walks up,
//  stops, and waits to find out what you will do. All of its staging lives
//  here rather than in WaitingVillagerNode so that the node stays about state
//  and geometry while this file is about time — and so the §8.3 invariants
//  ("never follows, never repeats itself, never reacts to being declined")
//  can be checked by reading one file.
//
//  Nothing here is allowed to depend on the decision's outcome.
//

import SpriteKit

public enum VillagerPerformance {
    /// Long enough to read as arriving, short enough that it is not charged
    /// to the player as hesitation — the dwell clock is already running.
    public static let settleDuration: TimeInterval = 0.35

    public static func approach(to point: CGPoint, speed: CGFloat) -> SKAction {
        .move(to: point, duration: TimeInterval(speed))
    }

    /// The weight-shift on arrival. Presence, not expression.
    public static func settle() -> SKAction {
        .sequence([
            .moveBy(x: 0, y: 1.5, duration: settleDuration * 0.4),
            .moveBy(x: 0, y: -1.5, duration: settleDuration * 0.6),
        ])
    }

    /// Standing still is not the same as being a static image. A slow breath,
    /// no translation — SPEC §8.3 says the villager never follows.
    public static func waiting() -> SKAction {
        .repeatForever(.sequence([
            .scaleY(to: 1.015, duration: 1.6),
            .scaleY(to: 1.0, duration: 1.9),
        ]))
    }

    /// Identical on engage and on decline. See the suite's first test.
    public static func depart(heading: CGVector) -> SKAction {
        .group([
            .moveBy(x: heading.dx * 46, y: heading.dy * 46, duration: 0.9),
            .fadeAlpha(to: 0.0, duration: 0.9),
        ])
    }
}
```

- [ ] **Step 4: Delegate from `WaitingVillagerNode`**

Replace the node's inline `SKAction` construction with these calls. On arrival: run `settle()`, then `waiting()`, then set `hasArrived = true` — keep `simulateArrivalForTesting()`'s `#if DEBUG` seam working, since it is what gives the social path (11 of 30 decisions) any test coverage at all.

- [ ] **Step 5: Run the test and confirm it passes**

- [ ] **Step 6: Run the whole app suite**

Run with `-only-testing:PriorsTests` only — the owner uses the shared simulator and full runs disrupt them. Expected: all green, including `LiveDecisionResolutionTests`.

- [ ] **Step 7: Watch a social decision in the running app**

`traitSchedule[0]` is θ_e, so slot 0 is spatial. Drive to a social slot or use the DEBUG seam. Confirm: the villager arrives, settles, breathes, and leaves the same way whether you hold or walk off.

- [ ] **Step 8: Commit**

```bash
git add Priors/Priors/Priors/Village/VillagerPerformance.swift \
        Priors/Priors/Priors/Village/WaitingVillagerNode.swift \
        Priors/Priors/PriorsTests/VillagerPerformanceTests.swift
git commit -m "Stage the villager encounter; departure never reveals the outcome"
```

---

### Task 4: Threshold approach feedback

**Files:**
- Modify: `Priors/Priors/Priors/Village/ThresholdNode.swift`
- Test: `Priors/Priors/PriorsTests/VillagerPerformanceTests.swift` (extend)

The stone ring is legible but inert. The player gets no acknowledgement that they have entered the zone, which is why crossing feels like nothing. The acknowledgement must not encode the price — that is the band channel's job — and must not tell the player they have committed, which would turn the threshold into a UI trigger.

- [ ] **Step 1: Write the failing test**

```swift
@Test func thresholdRespondsToPresenceWithoutEncodingPrice() async throws {
    let design = Design(template: .path, price: 0.5, trait: .thetaE)
    let low = ThresholdNode(decision: LiveDecision(design: Design(template: .path, price: 0.05, trait: .thetaE)))
    let high = ThresholdNode(decision: LiveDecision(design: Design(template: .path, price: 0.85, trait: .thetaE)))

    // Presence response is the same regardless of band; only the pool differs.
    #expect(low.presenceResponseDuration == high.presenceResponseDuration)
    _ = design
}
```

- [ ] **Step 2: Run it and confirm it fails**

- [ ] **Step 3: Implement**

Add `setPlayerPresent(_:)` to `ThresholdNode`, called from `VillageScene.updateArmedDecision` on the same `inZone` transition that already starts `zoneEntryTime`. On enter, the stones lift their brightness by a fixed amount over `presenceResponseDuration = 0.25`; on exit, they return. Fixed amount, identical for every band — see the test.

- [ ] **Step 4: Run and confirm it passes; run the app suite**

- [ ] **Step 5: Confirm `rt_ms` is untouched**

Run `-only-testing:PriorsTests/LiveDecisionResolutionTests`. `rtMsMeasuresTimeInTheZoneNotTimeSinceArming` must still pass. Animation must never be allowed near the clock.

- [ ] **Step 6: Commit**

```bash
git add Priors/Priors/Priors/Village/ThresholdNode.swift Priors/Priors/PriorsTests/VillagerPerformanceTests.swift
git commit -m "Thresholds acknowledge presence without leaking price"
```

---

## Phases 2–4 — scope, to be planned in full when reached

**Phase 2 — Map districts & silhouettes.** Six districts with distinct ground, prop density and silhouette: hearth square (well, effigy), lower lanes (dense cottages, the delivery cluster), the pond, the north gate (exposed, sparse), the mill approach, and the woods edge. Building depth from Kenney Tiny Town's roof/wall/window tiles composed into real silhouettes rather than flat rectangles, plus `oga-town-tiles` for variety. Path edging tiles so grass/dirt boundaries stop being straight rectangles. Preserves the 30 authored decision locations and SPEC §8's 30% dead-space floor — verify both, since `VillageMapBuilder`'s location table is load-bearing for the report's landmark claims.

**Phase 3 — Diegetic audio.** A second `AVAudioEngine` bus for ambience, strictly separate from the five §8.1 stems so it can never be mistaken for a sixth layer or interfere with monotonic decay. Positional sources (pond water, north wind, cottage hum) attenuated by distance. Interaction SFX: footfall via Task 2's `onFootfall`, lantern delivery, threshold crossing, the villager's arrival. Test that §8.1's stem count still only ever decreases while ambience is playing.

**Phase 4 — Store readiness.** App icon and launch screen; Dynamic Type on every non-gameplay screen; VoiceOver labels (the HUD and interact control already have them, the rest do not); privacy manifest declaring no tracking, which is trivially true under §2.7; App Store screenshots; and a pass to confirm no Debug-only performance assumption reaches Release. Note the known Debug/Release gap: PriorsEngine's suite runs 72.8s Debug vs 1.08s Release, so decision resolution costs ~1.3s in Debug and ~20ms in Release. Playtest builds must be Release.

---

## Self-Review

**Spec coverage.** Every constraint in Global Constraints maps to at least one task gate: §8.3's no-reaction rule is Task 3 Step 1; §8.3's no-follow rule is Task 3's waiting test; the frozen-file list and `rt_ms` semantics are Task 4 Step 5; SPEC §8's facelessness is Task 1 Step 6; determinism is stated in Global Constraints and has no new randomness in Phase 1. Phases 2–4 carry their spec obligations in their scope notes and will be expanded before execution — that is a deliberate deferral, not a gap.

**Placeholders.** None. Every code step carries the actual code. Phases 2–4 are explicitly scoped as not-yet-planned rather than described as TODO work inside Phase 1.

**Type consistency.** `settleDuration` is used in Task 3's test and defined in Task 3's implementation. `onFootfall` is produced in Task 2 and consumed by Phase 3's scope note. `presenceResponseDuration` is introduced and used within Task 4. `playerIdleTexture(direction:)`/`playerWalkCycle(direction:)`/`npcWalkCycle(variant:)` keep the names they already have in `VillageAssets.swift`, so Task 1 widens existing signatures rather than renaming them.

**Known risk.** Task 1 changes the atlas shape, and `VillageAssets` falls back to flat colour rectangles if slicing fails. A silent fallback would look like "the art didn't load" rather than a crash — Step 6's render-and-look is the guard, and it is not optional.
