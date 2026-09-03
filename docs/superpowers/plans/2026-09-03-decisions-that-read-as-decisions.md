# Decisions That Read As Decisions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each spatial template the form its own band phrases describe, prove the errand never requires engaging a decision, and teach the crossing mechanic once, in the prologue, where nothing is measured.

**Architecture:** `ThresholdNode` keeps its geometry and its commit sill and gains a swappable *form* child — lane, gate, or pitch — chosen from the template. A new `DecisionFormStyle` maps the existing 0→1 band scalar onto each form's own visual channels, so `BandLadder` and `DecisionIntensityStyle` are untouched and the band remains chosen by price, never the reverse. One new test proves every door is reachable without entering a decision zone.

**Tech Stack:** SpriteKit (`SKShapeNode`, `SKSpriteNode`, `CGPath`, `UIGraphicsImageRenderer`), Swift Testing, Swift package `PriorsEngine` (read-only here), Xcode 26 iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-03-role-quest-and-decisions-design.md`. Read it before Task 1; this plan argues from it.

## Global Constraints

Copied verbatim from `SPEC.md` v1.3 and the design doc. Every task's requirements implicitly include this section.

- **SPEC §2.9:** *"The mask may become a game. The instrument may not become visible."* Narrative, wayfinding and task framing may vary freely; the thirty decisions, what each measures and how each resolves are invariant.
- **SPEC §2.9, first consequence:** *"Nothing may reward the engaged branch of any template."*
- **SPEC §2.9, second consequence:** *"Nothing may mark a decision."* Wayfinding may point at deliveries and the well, never at a threshold or a waiting villager.
- **SPEC §2.3:** *"The model is never visible during play. No confidence meter, no prediction display, no score."*
- **SPEC §2.4:** No named protagonist, no personality, no score, no fail state, no leaderboard, no share button. No optimal path **through the thirty measured decisions**.
- **SPEC §8.3:** No modal. Spatial decisions resolve by crossing; the villager *"never follows, never repeats itself, and never reacts to being declined."*
- **SPEC §8.3:** `rt_ms` is zone-entry → resolve.
- **SPEC §8.2:** Seven bands per template, one fixed phrase and one matching visual intensity each; *"the band is only how that price is shown, selected from the price, never the reverse."* Band **distinctness** is the load-bearing variable (`experiments/perceived_price.py`, FINDINGS.md).
- **SPEC §8:** *"Villagers have no faces."* *"Dead space is required. At least 30% of walkable area contains nothing."*
- **Design doc §5.1 — geometry is frozen:** `ThresholdNode.zoneRadius` stays 36.0 and `ThresholdNode.commitZoneRadius` stays 14.0, radially symmetric, approachable from any angle. Forms are skins over identical geometry. Changing either radius changes what `rt_ms`, `approach_frac` and `backtracks` measure and invalidates the `rt_base` fit.
- **Design doc §5.2:** *"No spatial decision may present a figure that reads as approachable."*
- **Design doc §4.1:** *"The errand is completable without engaging a single measured decision."*
- **FINDINGS.md:** `RT_BASE_PRIOR_SD = 0.8` is deliberately weak. Do not tighten it.
- **Frozen files — never modify:** `Posterior.swift`, `BehaviouralPosterior.swift` likelihood math (`choiceLogLik`/`rtLogLik`/`update`), `ADOSelector.swift`, `ClaimGenerator.swift`. Also do not modify `BandLadder.swift` — the ladders are final wording.
- **`COPY.md` is final wording.** New player-facing text is added there in its established voice (second person, present or simple past, no exclamation marks, no adjectives of character, short lines) and read from there, never written inline in Swift. Its bracket notation (`[ Start ]`) marks controls and is not label text.
- **Determinism:** the village is byte-identical for every player. Any new randomness is seeded from tile coordinates, never from `Date` or an unseeded RNG.
- **Never run the full test suite** — it disrupts the owner's simulator. Scope to `-only-testing:PriorsTests`.
- **Playtest builds must be Release.** Debug is 67× slower on the posterior grid and reads as lag.

## Where the code is

Two checkouts. **Work in the main checkout: `/Users/gading/Documents/Priors`, branch `main`**, project at `Priors/Priors/Priors.xcodeproj`, DerivedData `Priors-gvyshcxlpyqenvhadcljmrescpwj`. The worktree at `.worktrees/game-layer-in-world-decisions` is kept fast-forwarded to `main`; sync it after each push:

```bash
git push origin main
git -C .worktrees/game-layer-in-world-decisions merge --ff-only main
```

## Commands

```bash
cd /Users/gading/Documents/Priors

# Scoped app tests (~90s, build dominated)
xcodebuild test -project Priors/Priors/Priors.xcodeproj -scheme Priors \
  -destination 'platform=iOS Simulator,id=A0B56E90-D0FB-47D3-BD94-DEE1F9E0038C' \
  -only-testing:PriorsTests

# One suite
  ... -only-testing:PriorsTests/DecisionFormTests

# Engine (unaffected by this plan, run once at the end)
swift test --package-path PriorsEngine
```

## File Structure

| File | Responsibility |
|---|---|
| `Priors/Priors/Priors/Village/DecisionFormStyle.swift` | **Create.** The form enum, the template→form lookup, and every per-form mapping from the 0→1 band scalar to that form's visual channels. No SpriteKit nodes; pure functions, so the distinctness tests are cheap and deterministic. |
| `Priors/Priors/Priors/Village/DecisionFormNode.swift` | **Create.** Three `SKNode` builders — lane, gate, pitch — each taking an intensity and returning a node centred on the threshold's origin. Art only; knows nothing about decisions or resolution. |
| `Priors/Priors/Priors/Village/ThresholdNode.swift` | **Modify.** Keeps geometry, commit sill, phrase pill. Swaps its generic darkness pool and 12-stone ring for the form node chosen from `decision.design.template`. |
| `Priors/Priors/Priors/Village/VillageMapBuilder.swift` | **Modify only if Task 1 fails.** Decision location coordinates. |
| `Priors/Priors/Priors/Screens/PracticeCrossingScene.swift` | **Create.** A small SpriteKit scene: the player, one lane, one sill, the thumbstick. Resolves by crossing *or* by leaving, continues either way, and logs nothing. |
| `Priors/Priors/Priors/Screens/PrologueScreen.swift` | **Modify.** Adds the practice crossing after its three text pages. `pages` is `[String]`; the crossing is a separate view, not a fourth string. |
| `COPY.md` | **Modify.** Practice-crossing lines; act banner text. |
| `Priors/Priors/PriorsTests/ErrandReachabilityTests.swift` | **Create.** The §4.1 invariant. |
| `Priors/Priors/PriorsTests/DecisionFormTests.swift` | **Create.** Per-form band distinctness and form selection. |
| `Priors/Priors/PriorsTests/PracticeCrossingTests.swift` | **Create.** The prologue crossing is unmeasured and the session still has exactly 30 decisions. |

---

### Task 1: Prove the errand never requires a decision

This is first because it is the load-bearing invariant of the whole design, it is cheap, and if the current map violates it the rest of the plan is built on sand. **If this test fails, stop and report the failing doors to the owner before moving decision locations.**

**Files:**
- Create: `Priors/Priors/PriorsTests/ErrandReachabilityTests.swift`
- Modify (only if the test fails): `Priors/Priors/Priors/Village/VillageMapBuilder.swift:485-505`

**Interfaces:**
- Consumes: `VillageMapBuilder.shared.buildVillage(in:)` → `(mapData: VillageMapData, decisionLocations: [DecisionLocation], eyeNode: EyeNode)`; `VillageMapData.walkableTiles: [[Bool]]`, `.doorPositions: [CGPoint]`, `.playerSpawnPosition: CGPoint`; `DecisionLocation.position: CGPoint`, `.trait: Trait`; `ThresholdNode.zoneRadius` (36.0); `VillageMapBuilder.tileSize` (32.0).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ErrandReachabilityTests.swift
//  PriorsTests
//
//  Design doc §4.1 — "The errand is completable without engaging a single
//  measured decision." Every house must be reachable by a route that enters
//  no decision zone; a threshold is always a shortcut or an aside, never the
//  way.
//
//  If crossing were ever the only way to a house, engaging would acquire an
//  in-game payoff and theta_e would stop measuring a risk threshold and start
//  measuring how badly the player wants to finish the errand — and the report
//  would still name the trait with confidence. SPEC §2.9.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Errand reachability")
@MainActor
struct ErrandReachabilityTests {

    /// Flood fill over the walkable grid from the well, treating any tile
    /// whose centre lies inside a spatial decision's zone as impassable.
    private func reachableTiles(blockingSpatialZones: Bool) -> (Set<Int>, VillageMapData, [DecisionLocation]) {
        let root = SKNode()
        let build = VillageMapBuilder.shared.buildVillage(in: root)
        let map = build.mapData
        let tile = VillageMapBuilder.tileSize

        // Only spatial decisions are crossings. Social decisions are villagers
        // who walk to the player and are declined by walking away, so they
        // never block a route.
        let blockers: [CGPoint] = blockingSpatialZones
            ? build.decisionLocations.filter { $0.trait == .thetaE }.map(\.position)
            : []

        func blocked(row: Int, col: Int) -> Bool {
            guard map.walkableTiles[row][col] else { return true }
            let centre = CGPoint(x: CGFloat(col) * tile + tile / 2,
                                 y: CGFloat(row) * tile + tile / 2)
            return blockers.contains { hypot($0.x - centre.x, $0.y - centre.y) < ThresholdNode.zoneRadius }
        }

        let rows = map.walkableTiles.count
        let cols = map.walkableTiles[0].count
        func key(_ r: Int, _ c: Int) -> Int { r * cols + c }

        let startCol = Int(map.playerSpawnPosition.x / tile)
        let startRow = Int(map.playerSpawnPosition.y / tile)

        var seen: Set<Int> = []
        var stack = [(startRow, startCol)]
        seen.insert(key(startRow, startCol))
        while let (r, c) = stack.popLast() {
            for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nr = r + dr, nc = c + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                let k = key(nr, nc)
                guard !seen.contains(k), !blocked(row: nr, col: nc) else { continue }
                seen.insert(k)
                stack.append((nr, nc))
            }
        }
        return (seen, map, build.decisionLocations)
    }

    /// The tile a player must stand on to deliver: `doorPositions` records the
    /// ground in front of the door.
    private func doorTiles(_ map: VillageMapData) -> [(row: Int, col: Int, point: CGPoint)] {
        let tile = VillageMapBuilder.tileSize
        return map.doorPositions.map {
            (row: Int($0.y / tile), col: Int($0.x / tile), point: $0)
        }
    }

    @Test("Every house is reachable without entering a decision zone")
    func everyHouseIsReachableWithoutEnteringADecisionZone() async throws {
        let (reachable, map, _) = reachableTiles(blockingSpatialZones: true)
        let cols = map.walkableTiles[0].count

        var unreachable: [CGPoint] = []
        for door in doorTiles(map) where !reachable.contains(door.row * cols + door.col) {
            unreachable.append(door.point)
        }

        #expect(unreachable.isEmpty,
                "doors requiring a decision zone to reach: \(unreachable)")
    }

    /// Guards the guard: if the flood fill were broken, the test above would
    /// pass vacuously. With nothing blocked, every door must be reachable.
    @Test("The reachability check is not vacuous")
    func theReachabilityCheckIsNotVacuous() async throws {
        let (reachable, map, locations) = reachableTiles(blockingSpatialZones: false)
        let cols = map.walkableTiles[0].count
        for door in doorTiles(map) {
            #expect(reachable.contains(door.row * cols + door.col),
                    "door unreachable even with nothing blocked: \(door.point)")
        }
        #expect(locations.contains { $0.trait == .thetaE })
    }
}
```

- [ ] **Step 2: Run it**

Run: `xcodebuild test -project Priors/Priors/Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,id=A0B56E90-D0FB-47D3-BD94-DEE1F9E0038C' -only-testing:PriorsTests/ErrandReachabilityTests`

Expected: both pass. This test is written to pass on a correct map — it is a guard, not a red-green cycle.

- [ ] **Step 3: If `everyHouseIsReachableWithoutEnteringADecisionZone` fails, STOP**

Do not move decision locations on your own judgement. Report to the owner: which doors are cut off, and which `DecisionLocation` (by `regionName`, `VillageMapBuilder.swift:485-505`) is sitting across the route. Moving a location changes which authored flavour hosts which trait, which is a design decision.

- [ ] **Step 4: Commit**

```bash
git add Priors/Priors/PriorsTests/ErrandReachabilityTests.swift
git commit -m "Test: the errand never requires engaging a decision

Design doc 4.1. Every door must be reachable from the well by a route that
enters no spatial decision zone. If crossing were ever the only way to a
house, engaging would acquire an in-game payoff and theta_e would measure
wanting-to-finish instead of a risk threshold.

Includes a non-vacuity check: with nothing blocked, every door must be
reachable, so a broken flood fill cannot make the invariant pass silently."
```

---

### Task 2: `DecisionFormStyle` — one form per template, and its channels

Pure functions only. Node building is Task 3.

**Files:**
- Create: `Priors/Priors/Priors/Village/DecisionFormStyle.swift`
- Test: `Priors/Priors/PriorsTests/DecisionFormTests.swift`

**Interfaces:**
- Consumes: `TemplateID` (from `PriorsEngine`), `DecisionIntensityStyle.adjacentBandStep` (1.0/6.0), `BandLadder.visualIntensity(band:)`.
- Produces: `enum DecisionForm { case lane, gate, pitch }`; `DecisionFormStyle.form(for: TemplateID) -> DecisionForm`; and these `(Double) -> CGFloat` / `-> Int` channel functions used by Task 3: `laneDepth`, `laneDarkAlpha`, `laneMouthNarrowing`, `gateSagRadians`, `gateWeedCount`, `gateRustAlpha`, `pitchClothAlpha`, `pitchDiceTilt`, `pitchShadowAlpha`.

- [ ] **Step 1: Write the failing test**

```swift
//
//  DecisionFormTests.swift
//  PriorsTests
//
//  SPEC §8.2 — seven bands, each with a visual intensity distinct from its
//  neighbours. FINDINGS.md (`experiments/perceived_price.py`) is why: band
//  COUNT is nearly free, band DISTINCTNESS is the entire cost. When the
//  generic darkness pool is replaced by three per-template forms, each form
//  has to carry seven separable steps on its own channels — otherwise the
//  price channel is quietly degraded to make the game prettier.
//

import Testing
import SpriteKit
import PriorsEngine
@testable import Priors

@Suite("Decision forms")
@MainActor
struct DecisionFormTests {

    private let intensities = (1...7).map { BandLadder.visualIntensity(band: $0) }

    /// `Design`'s memberwise initialiser is internal to `PriorsEngine`, so no
    /// test can construct one directly — the only supported source is
    /// `ADOSelector.selectDesign`. Walk a whole 30-slot session with jitter
    /// disabled and keep the first design each template produces; SPEC §4's
    /// quotas (PATH 12, DETOUR 4, TRADE 3, ERROR 4, CREDIT 3, GIVE 4)
    /// guarantee every template appears.
    static func designsByTemplate() -> [TemplateID: Design] {
        var state = SelectionState()
        let posterior = Posterior()
        var found: [TemplateID: Design] = [:]
        for slot in 0..<30 {
            let design = ADOSelector.selectDesign(posterior: posterior,
                                                  slot: slot,
                                                  state: state,
                                                  jitter: { _ in 0 })
            if found[design.template] == nil { found[design.template] = design }
            state.commit(design)
        }
        return found
    }

    @Test("Each spatial template gets the form its own phrases describe")
    func eachSpatialTemplateGetsTheFormItsOwnPhrasesDescribe() async throws {
        #expect(DecisionFormStyle.form(for: .path) == .lane)
        #expect(DecisionFormStyle.form(for: .detour) == .gate)
        #expect(DecisionFormStyle.form(for: .trade) == .pitch)
    }

    @Test("The lane separates seven ways")
    func theLaneSeparatesSevenWays() async throws {
        for (a, b) in zip(intensities, intensities.dropFirst()) {
            #expect(DecisionFormStyle.laneDepth(b) - DecisionFormStyle.laneDepth(a) > 3.0)
            #expect(DecisionFormStyle.laneDarkAlpha(b) - DecisionFormStyle.laneDarkAlpha(a) > 0.10)
            #expect(DecisionFormStyle.laneMouthNarrowing(b)
                    - DecisionFormStyle.laneMouthNarrowing(a) > 0.5)
        }
        // Band 1 must still read as a lane at all; band 7 must not be a void.
        #expect(DecisionFormStyle.laneDepth(0.0) >= 10.0)
        #expect(DecisionFormStyle.laneDarkAlpha(1.0) <= 0.95)
    }

    @Test("The gate separates seven ways")
    func theGateSeparatesSevenWays() async throws {
        for (a, b) in zip(intensities, intensities.dropFirst()) {
            #expect(DecisionFormStyle.gateSagRadians(b) - DecisionFormStyle.gateSagRadians(a) > 0.02)
            #expect(DecisionFormStyle.gateRustAlpha(b) - DecisionFormStyle.gateRustAlpha(a) > 0.10)
        }
        // Weeds must actually appear across the ladder, not just at the end.
        let weeds = intensities.map { DecisionFormStyle.gateWeedCount($0) }
        #expect(weeds.first == 0)
        #expect(weeds.last! >= 6)
        #expect(Set(weeds).count >= 5)
        #expect(zip(weeds, weeds.dropFirst()).allSatisfy { $1 >= $0 })
    }

    @Test("The pitch separates seven ways")
    func thePitchSeparatesSevenWays() async throws {
        for (a, b) in zip(intensities, intensities.dropFirst()) {
            #expect(DecisionFormStyle.pitchClothAlpha(b) - DecisionFormStyle.pitchClothAlpha(a) > 0.05)
            #expect(DecisionFormStyle.pitchDiceTilt(b) - DecisionFormStyle.pitchDiceTilt(a) > 0.04)
            #expect(DecisionFormStyle.pitchShadowAlpha(b) - DecisionFormStyle.pitchShadowAlpha(a) > 0.08)
        }
    }

    /// The band comes from the price, never the reverse (SPEC §8.2).
    @Test("No form function can influence which band is chosen")
    func noFormFunctionCanInfluenceWhichBandIsChosen() async throws {
        for band in 1...7 {
            let i = BandLadder.visualIntensity(band: band)
            #expect(i == Double(band - 1) / 6.0)
        }
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `... -only-testing:PriorsTests/DecisionFormTests`
Expected: compile failure — `cannot find 'DecisionFormStyle' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
//
//  DecisionFormStyle.swift
//  Priors
//
//  SPEC §8.2 — "one fixed phrase and one matching visual intensity per band."
//  `DecisionIntensityStyle` maps the band scalar onto ONE generic darkness
//  pool, used identically by all six templates. That is why a sentence about
//  a peddler was rendered as a hole in the grass, and why the intensity
//  channel was "how black is the pit".
//
//  Each spatial template now gets the form its own authored phrases describe
//  (`BandLadder`): PATH is a lane the light fails in, DETOUR is a gate that
//  will not open, TRADE is a peddler's pitch. This file is the mapping from
//  the same 0->1 band scalar onto each form's own channels.
//
//  Pure functions, no SpriteKit nodes: the distinctness requirement is a
//  property of the numbers, and it is tested as one (`DecisionFormTests`).
//
//  `BandLadder` and `DecisionIntensityStyle` are untouched. The band is still
//  chosen by the price ADO picked, never by anything here.
//

import CoreGraphics
import PriorsEngine

public enum DecisionForm {
    /// PATH — an opening between walls, with the dark receding away from you.
    case lane
    /// DETOUR — a gate across the way, seized to a degree.
    case gate
    /// TRADE — the peddler's cloth, set out on the ground.
    case pitch
}

public enum DecisionFormStyle {

    /// Social templates never reach here: they are villagers who wait
    /// (`WaitingVillagerNode`), not crossings. The three spatial templates map
    /// one-to-one onto the three forms, so this is a lookup and not a new
    /// design axis — the same argument `LiveDecision.isSpatial` makes.
    public static func form(for template: TemplateID) -> DecisionForm {
        switch template {
        case .path: return .lane
        case .detour: return .gate
        case .trade: return .pitch
        case .error, .credit, .give: return .lane
        }
    }

    private static func clamp(_ intensity: Double) -> CGFloat {
        CGFloat(min(max(intensity, 0.0), 1.0))
    }

    // MARK: - Lane (PATH)
    //
    // "The lane is only a little dark." -> "It is black past the gate."
    // The channel is how far into the opening the light still reaches.

    /// Points of darkness receding from the mouth: 12 at band 1, 48 at band 7.
    /// Adjacent bands differ by 6pt.
    public static func laneDepth(_ intensity: Double) -> CGFloat {
        12.0 + clamp(intensity) * 36.0
    }

    /// Opacity at the far end of the lane. 0.32 -> 0.92, 0.10 apart.
    public static func laneDarkAlpha(_ intensity: Double) -> CGFloat {
        0.32 + clamp(intensity) * 0.60
    }

    /// How far the walls close in at the mouth, in points per side. The dark
    /// lane also gets visually narrower, so depth and aperture co-vary.
    public static func laneMouthNarrowing(_ intensity: Double) -> CGFloat {
        clamp(intensity) * 5.0
    }

    // MARK: - Gate (DETOUR)
    //
    // "The gate looks like it will open easily." -> "has not opened in years."
    // The channel is how seized the gate is: sag, growth, rust.

    /// Hinge sag. Level at band 1, 0.22 rad (~13 degrees) at band 7.
    public static func gateSagRadians(_ intensity: Double) -> CGFloat {
        clamp(intensity) * 0.22
    }

    /// Weeds climbing the bars. None at band 1, nine at band 7, monotonic.
    public static func gateWeedCount(_ intensity: Double) -> Int {
        Int((clamp(intensity) * 9.0).rounded())
    }

    /// Rust bloom over the ironwork. 0.10 -> 0.85, 0.125 apart.
    public static func gateRustAlpha(_ intensity: Double) -> CGFloat {
        0.10 + clamp(intensity) * 0.75
    }

    // MARK: - Pitch (TRADE)
    //
    // "The peddler's dice look fair." -> "certain of something you are not."
    // The channel is how the pitch is set out: cloth, dice, and how much of
    // it sits in shadow.

    /// The cloth darkens from a plain mat to something deliberately dim.
    /// 0.30 -> 0.80, 0.083 apart.
    public static func pitchClothAlpha(_ intensity: Double) -> CGFloat {
        0.30 + clamp(intensity) * 0.50
    }

    /// The dice sit increasingly askew — weighted, not thrown. Up to 0.42 rad.
    public static func pitchDiceTilt(_ intensity: Double) -> CGFloat {
        clamp(intensity) * 0.42
    }

    /// Shadow pooling over the near half of the pitch. 0.12 -> 0.80.
    public static func pitchShadowAlpha(_ intensity: Double) -> CGFloat {
        0.12 + clamp(intensity) * 0.68
    }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `... -only-testing:PriorsTests/DecisionFormTests`
Expected: all five pass. If a distinctness assertion fails, widen that channel's span in `DecisionFormStyle` — never loosen the assertion.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/DecisionFormStyle.swift Priors/Priors/PriorsTests/DecisionFormTests.swift
git commit -m "One form per spatial template, with its own seven-step channels

BandLadder already gives each template its own fiction and all three rendered
as the same darkness pool. This maps the same band scalar onto lane, gate and
pitch channels instead. Pure functions, so seven-way distinctness stays a
tested property of the numbers — SPEC 8.2, where distinctness rather than band
count is the whole cost.

BandLadder and DecisionIntensityStyle untouched; the band is still chosen by
the price ADO picked."
```

---

### Task 3: `DecisionFormNode` — build the three forms

Art only. No knowledge of decisions, resolution, or the coordinator.

**Files:**
- Create: `Priors/Priors/Priors/Village/DecisionFormNode.swift`
- Test: `Priors/Priors/PriorsTests/DecisionFormTests.swift` (append)

**Interfaces:**
- Consumes: `DecisionForm`, every channel function from Task 2, `ThresholdNode.zoneRadius` (36.0).
- Produces: `DecisionFormNode.make(form: DecisionForm, intensity: Double) -> SKNode`. The returned node is centred on the threshold origin, has `zPosition` 4, and contains no node above `zPosition` 5 so the commit sill and phrase pill still read on top.

- [ ] **Step 1: Write the failing test (append to `DecisionFormTests.swift`, inside the suite)**

```swift
    @Test("Every form builds a node that stays under the sill and the pill")
    func everyFormBuildsANodeThatStaysUnderTheSillAndThePill() async throws {
        for form in [DecisionForm.lane, .gate, .pitch] {
            for band in 1...7 {
                let node = DecisionFormNode.make(form: form,
                                                 intensity: BandLadder.visualIntensity(band: band))
                #expect(!node.children.isEmpty, "\(form) band \(band) built nothing")
                let maxZ = node.children.map(\.zPosition).max() ?? 0
                #expect(maxZ < 5.0, "\(form) band \(band) draws over the commit sill")
                // Nothing may spill outside the zone: the zone is the decision.
                let bounds = node.calculateAccumulatedFrame()
                #expect(bounds.width <= ThresholdNode.zoneRadius * 2 + 1)
                #expect(bounds.height <= ThresholdNode.zoneRadius * 2 + 1)
            }
        }
    }

    /// The gate grows weeds as the band rises; the lane does not. A form that
    /// ignored its intensity would build identical nodes and pass everything
    /// else in this suite.
    @Test("Each form actually changes with the band")
    func eachFormActuallyChangesWithTheBand() async throws {
        for form in [DecisionForm.lane, .gate, .pitch] {
            let low = DecisionFormNode.make(form: form, intensity: 0.0)
            let high = DecisionFormNode.make(form: form, intensity: 1.0)
            let lowCount = low.calculateAccumulatedFrame()
            let highCount = high.calculateAccumulatedFrame()
            let changed = low.children.count != high.children.count
                || abs(lowCount.width - highCount.width) > 0.5
                || abs(lowCount.height - highCount.height) > 0.5
            #expect(changed, "\(form) renders identically at band 1 and band 7")
        }
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `... -only-testing:PriorsTests/DecisionFormTests`
Expected: compile failure — `cannot find 'DecisionFormNode' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
//
//  DecisionFormNode.swift
//  Priors
//
//  The art for SPEC §8.3's spatial decisions, one form per template. Built
//  from `DecisionFormStyle`'s channels, which is where the seven-band
//  distinctness requirement lives and is tested.
//
//  Everything here is centred on the threshold's origin and stays inside
//  `ThresholdNode.zoneRadius`: the zone IS the decision, and art spilling
//  past it would make the crossing's edge ambiguous. Nothing draws at
//  zPosition 5 or above, which is where the commit sill and the phrase pill
//  live — the player must always be able to see where crossing happens.
//
//  Determinism (plan Global Constraints): every position here is computed
//  from the intensity and an index, never from an RNG.
//

import SpriteKit
import UIKit

public enum DecisionFormNode {

    public static func make(form: DecisionForm, intensity: Double) -> SKNode {
        switch form {
        case .lane: return makeLane(intensity: intensity)
        case .gate: return makeGate(intensity: intensity)
        case .pitch: return makePitch(intensity: intensity)
        }
    }

    // MARK: - Lane

    /// Two walls with an opening between them and the dark receding away.
    /// Read from the player's approach (from below): the mouth is at the near
    /// edge of the zone and the dark runs away from them.
    private static func makeLane(intensity: Double) -> SKNode {
        let root = SKNode()
        let r = ThresholdNode.zoneRadius
        let depth = DecisionFormStyle.laneDepth(intensity)
        let narrowing = DecisionFormStyle.laneMouthNarrowing(intensity)
        let halfMouth = max(10.0, 16.0 - narrowing)

        // The two walls. Stone, near-white at source: the dusk filter scales
        // green by 0.70 and blue by 0.52 at step 0, so a mid-grey lands as
        // dark brown and stops reading as stone (same reason as
        // ThresholdNode's marker stones).
        for side in [-1.0, 1.0] as [CGFloat] {
            let wall = SKShapeNode(rectOf: CGSize(width: 9, height: r * 1.6), cornerRadius: 2)
            wall.position = CGPoint(x: side * (halfMouth + 5), y: 0)
            wall.fillColor = SKColor(red: 0.90, green: 0.88, blue: 0.83, alpha: 0.95)
            wall.strokeColor = SKColor(red: 0.18, green: 0.15, blue: 0.14, alpha: 0.85)
            wall.lineWidth = 1.0
            wall.isAntialiased = true
            wall.zPosition = 4.2
            root.addChild(wall)
        }

        // The dark between them: a tapering wedge running away from the
        // player, capped to the zone so it never spills outside the decision.
        let far = min(depth, r)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfMouth, y: -r * 0.5))
        path.addLine(to: CGPoint(x: halfMouth, y: -r * 0.5))
        path.addLine(to: CGPoint(x: halfMouth * 0.55, y: far))
        path.addLine(to: CGPoint(x: -halfMouth * 0.55, y: far))
        path.closeSubpath()

        let dark = SKShapeNode(path: path)
        dark.fillColor = SKColor(white: 0.0, alpha: DecisionFormStyle.laneDarkAlpha(intensity))
        dark.strokeColor = .clear
        dark.isAntialiased = true
        dark.zPosition = 4.0
        root.addChild(dark)

        return root
    }

    // MARK: - Gate

    /// A gate across the way: two posts, three bars, sagging and rusting and
    /// growing over as the band rises.
    private static func makeGate(intensity: Double) -> SKNode {
        let root = SKNode()
        let halfWidth: CGFloat = 22
        let sag = DecisionFormStyle.gateSagRadians(intensity)
        let rust = DecisionFormStyle.gateRustAlpha(intensity)

        for side in [-1.0, 1.0] as [CGFloat] {
            let post = SKShapeNode(rectOf: CGSize(width: 5, height: 26), cornerRadius: 1.5)
            post.position = CGPoint(x: side * halfWidth, y: 0)
            post.fillColor = SKColor(red: 0.42, green: 0.33, blue: 0.24, alpha: 1.0)
            post.strokeColor = SKColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 0.9)
            post.lineWidth = 1.0
            post.zPosition = 4.3
            root.addChild(post)
        }

        // The leaf, hung from the left post so sag rotates about it.
        let leaf = SKNode()
        leaf.position = CGPoint(x: -halfWidth, y: 0)
        leaf.zRotation = -sag
        leaf.zPosition = 4.2
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: halfWidth * 2 - 4, height: 3), cornerRadius: 1)
            bar.position = CGPoint(x: halfWidth - 2, y: CGFloat(i - 1) * 8)
            bar.fillColor = SKColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 1.0)
            bar.strokeColor = SKColor(red: 0.14, green: 0.12, blue: 0.11, alpha: 0.9)
            bar.lineWidth = 0.8
            leaf.addChild(bar)

            let bloom = SKShapeNode(rectOf: CGSize(width: halfWidth * 2 - 4, height: 3), cornerRadius: 1)
            bloom.position = bar.position
            bloom.fillColor = SKColor(red: 0.55, green: 0.26, blue: 0.10, alpha: rust)
            bloom.strokeColor = .clear
            leaf.addChild(bloom)
        }
        root.addChild(leaf)

        // Growth climbing the bars. Positions are a fixed fan, not random.
        let weeds = DecisionFormStyle.gateWeedCount(intensity)
        for i in 0..<weeds {
            let t = CGFloat(i) / CGFloat(max(weeds - 1, 1))
            let weed = SKShapeNode(rectOf: CGSize(width: 2, height: 7 + t * 5), cornerRadius: 1)
            weed.position = CGPoint(x: -halfWidth + 4 + t * (halfWidth * 2 - 8), y: -8)
            weed.zRotation = (t - 0.5) * 0.5
            weed.fillColor = SKColor(red: 0.30, green: 0.42, blue: 0.20, alpha: 0.95)
            weed.strokeColor = .clear
            weed.zPosition = 4.4
            root.addChild(weed)
        }

        return root
    }

    // MARK: - Pitch

    /// The peddler's cloth on the ground with the dice on it. The peddler
    /// themself is NOT built here: design doc §5.2 — "no spatial decision may
    /// present a figure that reads as approachable" — and the figure is placed
    /// outside the zone by `ThresholdNode`.
    private static func makePitch(intensity: Double) -> SKNode {
        let root = SKNode()

        let cloth = SKShapeNode(rectOf: CGSize(width: 44, height: 30), cornerRadius: 3)
        cloth.fillColor = SKColor(red: 0.36, green: 0.16, blue: 0.20,
                                  alpha: DecisionFormStyle.pitchClothAlpha(intensity))
        cloth.strokeColor = SKColor(red: 0.68, green: 0.58, blue: 0.36, alpha: 0.75)
        cloth.lineWidth = 1.2
        cloth.isAntialiased = true
        cloth.zPosition = 4.0
        root.addChild(cloth)

        let tilt = DecisionFormStyle.pitchDiceTilt(intensity)
        for (i, dx) in [CGFloat(-9), 9].enumerated() {
            let die = SKShapeNode(rectOf: CGSize(width: 9, height: 9), cornerRadius: 1.5)
            die.position = CGPoint(x: dx, y: 2)
            die.zRotation = tilt * (i == 0 ? 1 : -1)
            die.fillColor = SKColor(red: 0.93, green: 0.90, blue: 0.83, alpha: 0.98)
            die.strokeColor = SKColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 0.9)
            die.lineWidth = 0.9
            die.zPosition = 4.3
            root.addChild(die)

            let pip = SKShapeNode(circleOfRadius: 1.3)
            pip.position = die.position
            pip.fillColor = SKColor(white: 0.12, alpha: 0.95)
            pip.strokeColor = .clear
            pip.zPosition = 4.4
            root.addChild(pip)
        }

        // Shadow over the near half — the part of the pitch you cannot read.
        let shadow = SKShapeNode(rectOf: CGSize(width: 44, height: 15), cornerRadius: 3)
        shadow.position = CGPoint(x: 0, y: -7.5)
        shadow.fillColor = SKColor(white: 0.0, alpha: DecisionFormStyle.pitchShadowAlpha(intensity))
        shadow.strokeColor = .clear
        shadow.zPosition = 4.5
        root.addChild(shadow)

        return root
    }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `... -only-testing:PriorsTests/DecisionFormTests`
Expected: all seven pass.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/DecisionFormNode.swift Priors/Priors/PriorsTests/DecisionFormTests.swift
git commit -m "Build the lane, the gate and the pitch

Art only, driven entirely by DecisionFormStyle's channels. Everything stays
inside the zone radius, because the zone is the decision and art spilling past
it would make the crossing's edge ambiguous, and nothing draws at zPosition 5
or above so the commit sill and phrase pill stay readable on top.

The peddler figure is deliberately not built here — a spatial decision may not
present an approachable figure (design doc 5.2)."
```

---

### Task 4: Put the forms into `ThresholdNode`, and the peddler outside the zone

**Files:**
- Modify: `Priors/Priors/Priors/Village/ThresholdNode.swift` (the `darknessOverlay` and `markerRing` properties, the initialiser, and `setIntensity`)
- Test: `Priors/Priors/PriorsTests/DecisionFormTests.swift` (append)

**Interfaces:**
- Consumes: `DecisionFormNode.make(form:intensity:)`, `DecisionFormStyle.form(for:)`, `LiveDecision.design.template`, `LiveDecision.visualIntensity`.
- Produces: `ThresholdNode.formNode: SKNode` (internal, for tests). `zoneRadius`, `commitZoneRadius`, `radius`, `commitRadius`, `setIntensity(_:)` and the phrase pill keep their current names and behaviour.

- [ ] **Step 1: Write the failing test (append to `DecisionFormTests.swift`)**

```swift
    /// The geometry is frozen (design doc §5.1). A form is a skin; if any of
    /// this moves, `rt_ms`, `approach_frac` and `backtracks` change meaning
    /// and `BehaviouralPosterior`'s `rt_base` fit is invalidated.
    @Test("A form never changes the geometry it is drawn on")
    func aFormNeverChangesTheGeometryItIsDrawnOn() async throws {
        #expect(ThresholdNode.zoneRadius == 36.0)
        #expect(ThresholdNode.commitZoneRadius == 14.0)

        let designs = Self.designsByTemplate()
        for template in [TemplateID.path, .detour, .trade] {
            let design = try #require(designs[template])
            let node = ThresholdNode(decision: LiveDecision(design: design))
            #expect(node.radius == 36.0)
            #expect(node.commitRadius == 14.0)
        }
    }

    @Test("Each template renders as its own form")
    func eachTemplateRendersAsItsOwnForm() async throws {
        let designs = Self.designsByTemplate()
        let cases: [(TemplateID, DecisionForm)] = [(.path, .lane), (.detour, .gate), (.trade, .pitch)]
        for (template, expected) in cases {
            let design = try #require(designs[template])
            let node = ThresholdNode(decision: LiveDecision(design: design))
            #expect(node.form == expected)
            #expect(!node.formNode.children.isEmpty)
        }
    }

    /// Design doc §5.2. TRADE resolves by CROSSING, so a figure that reads as
    /// an approachable villager would invite a hold on Interact that does
    /// nothing — the owner's original "i can't even interact with them",
    /// rebuilt somewhere new.
    @Test("The peddler stands outside the zone")
    func thePeddlerStandsOutsideTheZone() async throws {
        let design = try #require(Self.designsByTemplate()[.trade])
        let node = ThresholdNode(decision: LiveDecision(design: design))
        let figure = try #require(node.childNode(withName: "trade_figure"))
        let distance = hypot(figure.position.x, figure.position.y)
        #expect(distance > ThresholdNode.zoneRadius)
    }

    @Test("Only TRADE has a figure at all")
    func onlyTradeHasAFigureAtAll() async throws {
        let designs = Self.designsByTemplate()
        for template in [TemplateID.path, .detour] {
            let design = try #require(designs[template])
            let node = ThresholdNode(decision: LiveDecision(design: design))
            #expect(node.childNode(withName: "trade_figure") == nil)
        }
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `... -only-testing:PriorsTests/DecisionFormTests`
Expected: compile failure — `value of type 'ThresholdNode' has no member 'form'`.

- [ ] **Step 3: Modify `ThresholdNode`**

Replace the `darknessOverlay` and `markerRing` stored properties with:

```swift
    /// The form this decision takes, from its template (`DecisionFormStyle`).
    public let form: DecisionForm
    /// The form's art. Rebuilt by `setIntensity`, because a form's geometry —
    /// how deep the lane runs, how far the gate sags — is a function of the
    /// band and cannot be restyled in place the way a single pool's alpha
    /// could.
    private(set) var formNode: SKNode
    /// TRADE only: the peddler, standing beyond the zone (design doc §5.2).
    private var tradeFigure: SKSpriteNode?
```

Delete the `markerRing` construction loop (`ThresholdNode.swift:90-107`) and the `darknessOverlay` construction. Keep `commitSill` exactly as it is — it is the affordance the prologue teaches, and it must be identical across all three forms.

In `init`, before `super.init()`:

```swift
        self.form = DecisionFormStyle.form(for: decision.design.template)
        self.formNode = DecisionFormNode.make(form: form, intensity: decision.visualIntensity)
```

After `super.init()`, replace `addChild(markerRing)` / `addChild(darknessOverlay)` with:

```swift
        addChild(formNode)
        if form == .pitch {
            // Hooded, turned to the dice, well outside the zone: present
            // enough for the phrases to mean something, never approachable.
            let figure = SKSpriteNode(texture: VillageAssets.shared.npcIdleTexture(variant: 0),
                                      size: CGSize(width: 32, height: 32))
            figure.name = "trade_figure"
            figure.position = CGPoint(x: 0, y: Self.zoneRadius + 22)
            figure.zPosition = 4.6
            figure.color = .black
            figure.colorBlendFactor = 0.45
            addChild(figure)
            tradeFigure = figure
        }
```

Replace the body of `setIntensity` with:

```swift
    /// SPEC §8.2's "matching visual intensity", now per form: the lane's dark
    /// runs deeper, the gate sags and rusts further, the pitch dims and its
    /// dice sit further askew. Channels and their seven-way separation live in
    /// `DecisionFormStyle` and are tested there.
    ///
    /// The node is rebuilt rather than restyled: a form's geometry is a
    /// function of the band, so there is nothing to tween.
    public func setIntensity(_ intensity: Double) {
        let clamped = min(max(intensity, 0.0), 1.0)
        formNode.removeFromParent()
        formNode = DecisionFormNode.make(form: form, intensity: clamped)
        addChild(formNode)
    }
```

- [ ] **Step 4: Run the whole suite**

Run: `... -only-testing:PriorsTests`
Expected: all pass. `LiveDecisionResolutionTests` must be untouched and green — it pins resolution, which this task must not have changed. If it fails, the geometry moved; revert and re-read design doc §5.1.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/ThresholdNode.swift Priors/Priors/PriorsTests/DecisionFormTests.swift
git commit -m "A threshold now looks like what its phrase says

ThresholdNode swaps the generic darkness pool and twelve-stone ring for the
form its template calls for. The commit sill is kept identical across all
three: it is the affordance the prologue teaches, and the player is entitled
to see where crossing happens whatever the fiction is.

TRADE's peddler stands beyond the zone, hooded and turned away. TRADE resolves
by crossing, so a figure that read as an approachable villager would invite a
hold on Interact that does nothing.

Geometry unchanged: 36pt zone, 14pt sill, pinned by test."
```

---

### Task 5: Render all twenty-one bands and look at them

Not optional, and not a formality. This project shipped a well sprite as the player character because nobody opened the atlas, and this session alone found five defects that every test passed through — three of them nodes whose *state* lived in an `SKAction`, so they were invisible whenever the scene had not run.

**Files:**
- Create (temporary, deleted in Step 5): `Priors/Priors/PriorsTests/ZZFormDump.swift`

**Interfaces:**
- Consumes: `ThresholdNode(decision:)`, `SKView.texture(from:crop:)`.
- Produces: nothing. This task ships no source.

- [ ] **Step 1: Write the dump**

```swift
import Testing
import SpriteKit
import UIKit
import PriorsEngine
@testable import Priors

@Suite("Form dump")
@MainActor
struct ZZFormDump {
    @Test func dumpEveryBandOfEveryForm() async throws {
        let scene = SKScene(size: CGSize(width: 900, height: 500))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 900, height: 500))
        view.presentScene(scene)
        scene.isPaused = true
        scene.backgroundColor = SKColor(red: 0.38, green: 0.52, blue: 0.30, alpha: 1)

        // All seven bands of each form. Built from `DecisionFormNode`
        // directly: a specific band needs a specific price, and `Design`
        // cannot be constructed outside PriorsEngine.
        for form in [DecisionForm.lane, .gate, .pitch] {
            let row = SKNode()
            scene.addChild(row)
            for band in 1...7 {
                let node = DecisionFormNode.make(form: form,
                                                 intensity: BandLadder.visualIntensity(band: band))
                node.position = CGPoint(x: CGFloat(band) * 110 - 55, y: 250)
                row.addChild(node)

                // The sill, drawn here so the strip shows what the player
                // sees: it must stay visible at every band.
                let sill = SKShapeNode(circleOfRadius: ThresholdNode.commitZoneRadius)
                sill.position = node.position
                sill.fillColor = .clear
                sill.strokeColor = SKColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 0.50)
                sill.lineWidth = 1.5
                row.addChild(sill)
            }
            let tex = try #require(view.texture(from: row,
                crop: CGRect(x: 0, y: 150, width: 800, height: 200)))
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("form_\(form).png")
            try #require(UIImage(cgImage: tex.cgImage()).pngData()).write(to: url)
            print("DUMPED \(url.path)")
            row.removeFromParent()
        }

        // One real ThresholdNode per template, to confirm the phrase pill and
        // the sill still read on top of the form in the assembled node.
        var state = SelectionState()
        let posterior = Posterior()
        var seen: Set<TemplateID> = []
        for slot in 0..<30 {
            let design = ADOSelector.selectDesign(posterior: posterior, slot: slot,
                                                  state: state, jitter: { _ in 0 })
            state.commit(design)
            guard [.path, .detour, .trade].contains(design.template),
                  !seen.contains(design.template) else { continue }
            seen.insert(design.template)
            let node = ThresholdNode(decision: LiveDecision(design: design))
            node.position = CGPoint(x: 400, y: 250)
            scene.addChild(node)
            let tex = try #require(view.texture(from: scene,
                crop: CGRect(x: 250, y: 130, width: 300, height: 240)))
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("threshold_\(design.template).png")
            try #require(UIImage(cgImage: tex.cgImage()).pngData()).write(to: url)
            print("DUMPED \(url.path)")
            node.removeFromParent()
        }
    }
}
```

- [ ] **Step 2: Run it and copy the images out**

```bash
xcodebuild test -project Priors/Priors/Priors.xcodeproj -scheme Priors \
  -destination 'platform=iOS Simulator,id=A0B56E90-D0FB-47D3-BD94-DEE1F9E0038C' \
  -only-testing:PriorsTests/ZZFormDump 2>&1 | grep DUMPED
# copy the three paths printed to a scratch directory and open them
```

- [ ] **Step 3: Actually look, against these questions**

Six images: three seven-band strips (`form_*.png`) and three assembled
thresholds (`threshold_*.png`). For each of the three strips:
- Can you tell band 1 from band 2 at a glance? Band 6 from band 7? If any adjacent pair is hard to separate, widen that channel in `DecisionFormStyle` — the numeric test passing is necessary, not sufficient.
- Does band 7 still read as a lane / gate / pitch, or has it collapsed into a dark blob? The failure this whole plan exists to fix was a form that read as a hole.
- Is the commit sill visible at every band, including band 7? If the form swallows it, the player cannot see where crossing happens.

- [ ] **Step 4: Fix what you saw, and re-dump until it reads**

Changes go in `DecisionFormStyle` (channel spans) or `DecisionFormNode` (shapes). Re-run Step 2 after each change. Record in the commit message what you changed and what you saw that made you change it.

- [ ] **Step 5: Delete the dump and commit**

```bash
rm Priors/Priors/PriorsTests/ZZFormDump.swift
git add -A Priors
git commit -m "Tune the form channels against rendered bands

<what you saw, and what you changed because of it>

The dump harness is deleted: it renders no shipping code and its value was
in the looking."
```

---

### Task 6: The practice crossing, in the prologue

**Files:**
- Create: `Priors/Priors/Priors/Screens/PracticeCrossingScene.swift`
- Modify: `COPY.md` (new section)
- Modify: `Priors/Priors/Priors/Screens/PrologueScreen.swift` — three text pages in `public static let pages: [String]`, landscape two-column layout rebuilt in commit `c8e523a`. Read it before editing and follow its structure; do not restructure it.
- Test: `Priors/Priors/PriorsTests/PracticeCrossingTests.swift`

**Interfaces:**
- Consumes: `DecisionFormNode.make(form: .lane, intensity:)`, `ThresholdNode.zoneRadius`, `ThresholdNode.commitZoneRadius`, `PlayerNode`, `VirtualControlsView`.
- Produces: `PracticeCrossingScene(onResolved: @escaping () -> Void)`; `PracticeCrossingScene.hasResolved: Bool`; `PrologueCopy.practiceCrossing: String`.

**Why it is a scene and not a fourth text page:** the point is that the player
performs the verb once. A page that says "you can walk into a lane" teaches a
sentence; walking into one teaches the mechanic. It is also the only place this
can be done at all, because it is unmeasured.

- [ ] **Step 1: Add the copy**

Append to `COPY.md`, in its established voice — second person, present or simple past, no exclamation marks, no adjectives of character, short lines. The brackets mark a control and are not label text:

```markdown
## The practice crossing

Shown once, in the prologue. Not one of the thirty decisions. Nothing here is
logged and nothing reaches the posterior — which is exactly why it is allowed
to explain the mechanic at all. No line in the village ever says this again.

```
The lane ahead is dark.

You can walk into it, or go around it.
Both are the same to the errand.

[ Continue ]
```
```

- [ ] **Step 2: Write the failing test**

```swift
//
//  PracticeCrossingTests.swift
//  PriorsTests
//
//  Design doc §5.4 — the crossing mechanic is taught once, in the prologue,
//  on an instance that is not one of the thirty and logs nothing. That is
//  what makes it safe to be explicit: the same sentence attached to a real
//  PATH would sit on an ADO-priced decision and tilt it.
//

import Testing
import PriorsEngine
@testable import Priors

@Suite("Practice crossing")
@MainActor
struct PracticeCrossingTests {

    /// The session is still exactly thirty measured decisions. The practice
    /// crossing lives in the prologue and is not one of them.
    @Test("The practice crossing is not one of the thirty")
    func thePracticeCrossingIsNotOneOfTheThirty() async throws {
        #expect(Scenarios.traitSchedule.count == 30)
        let quotas = Scenarios.templates.values.map(\.instances).reduce(0, +)
        #expect(quotas == 30)
    }

    /// Both outcomes must end the practice identically. A tutorial where
    /// crossing continues and going around does not would teach a preference,
    /// and the first real PATH would inherit it.
    @Test("Crossing and going around end the practice the same way")
    func crossingAndGoingAroundEndThePracticeTheSameWay() async throws {
        for target in [CGPoint(x: 0, y: 90), CGPoint(x: 200, y: 0)] {
            var resolvedCount = 0
            let scene = PracticeCrossingScene(size: CGSize(width: 800, height: 450)) {
                resolvedCount += 1
            }
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
            view.presentScene(scene)
            scene.isPaused = true

            // Walk into the zone, then to the target.
            scene.playerForTesting.position = CGPoint(x: 0, y: 60)
            scene.update(1.0)
            scene.playerForTesting.position = target
            scene.update(2.0)

            #expect(scene.hasResolved)
            #expect(resolvedCount == 1)

            // And it never fires twice.
            scene.update(3.0)
            #expect(resolvedCount == 1)
        }
    }

    @Test("The prologue teaches both options evenly")
    func theProloguePagesTeachBothOptionsEvenly() async throws {
        let text = PrologueCopy.practiceCrossing
        #expect(text.contains("walk into it"))
        #expect(text.contains("go around it"))
        // Symmetry is the point: a line that named only one option would be
        // an instruction, and the first PATH would inherit it.
        #expect(text.contains("Both are the same to the errand."))
        #expect(!text.contains("["))
    }
}
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `... -only-testing:PriorsTests/PracticeCrossingTests`
Expected: compile failure — `cannot find 'PrologueCopy' in scope`.

- [ ] **Step 4: Implement**

Add the copy constant beside the prologue's existing text (follow whatever pattern that file already uses for its pages — read it first), stripping the `[ Continue ]` bracket line, which marks a control:

```swift
enum PrologueCopy {
    /// COPY.md, "The practice crossing". Not one of the thirty decisions:
    /// nothing here is logged and nothing reaches the posterior, which is the
    /// only reason the mechanic may be explained in words at all.
    static let practiceCrossing = """
    The lane ahead is dark.

    You can walk into it, or go around it.
    Both are the same to the errand.
    """
}
```

Then build the scene. It is deliberately small: no coordinator, no posterior, no logging, no `MovementSampler`.

```swift
//
//  PracticeCrossingScene.swift
//  Priors
//
//  Design doc §5.4 — the crossing mechanic, taught once, on an instance that
//  is not one of the thirty. Nothing here is logged and nothing reaches the
//  posterior, which is the only reason the game may explain the mechanic in
//  words at all (SPEC §2.9).
//
//  Deliberately not a `VillageScene`: no decision is armed, no `rt_ms` is
//  measured, no `MovementSampler` is attached, and both outcomes continue
//  identically. Crossing and going around must be indistinguishable in
//  consequence, or the tutorial teaches a preference and the first real PATH
//  inherits it.
//

import SpriteKit

@MainActor
public final class PracticeCrossingScene: SKScene {
    public private(set) var hasResolved = false
    private let onResolved: () -> Void
    private var player: PlayerNode!
    /// Test seam: the practice scene has no coordinator to drive it, so a
    /// test moves the figure directly the way `VillageScene`'s tests do.
    var playerForTesting: PlayerNode { player }
    private var inputVector: CGVector = .zero
    private var hasEnteredZone = false
    private let crossingPoint = CGPoint(x: 0, y: 90)

    public init(size: CGSize, onResolved: @escaping () -> Void) {
        self.onResolved = onResolved
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.2)

        // Band 4 — visibly dark, unmistakably a lane, and priced by nothing.
        let lane = DecisionFormNode.make(form: .lane, intensity: 0.5)
        lane.position = crossingPoint
        addChild(lane)

        let sill = SKShapeNode(circleOfRadius: ThresholdNode.commitZoneRadius)
        sill.position = crossingPoint
        sill.fillColor = .clear
        sill.strokeColor = SKColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 0.50)
        sill.lineWidth = 1.5
        addChild(sill)

        player = PlayerNode()
        player.position = .zero
        addChild(player)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func setInputVector(_ vector: CGVector) { inputVector = vector }

    public override func update(_ currentTime: TimeInterval) {
        guard !hasResolved, let player else { return }
        player.updateMovement(vector: inputVector)

        let d = hypot(player.position.x - crossingPoint.x, player.position.y - crossingPoint.y)
        if d < ThresholdNode.zoneRadius { hasEnteredZone = true }

        // Both outcomes end the same way, on purpose.
        let crossed = d < ThresholdNode.commitZoneRadius
        let wentAround = hasEnteredZone && d > ThresholdNode.zoneRadius
        let walkedPast = player.position.y > crossingPoint.y + ThresholdNode.zoneRadius
        if crossed || wentAround || walkedPast {
            hasResolved = true
            onResolved()
        }
    }
}
```

Then present it from `PrologueScreen` after the third page, with `PrologueCopy.practiceCrossing` shown alongside it and `onResolved` advancing to the village. Follow the screen's existing landscape two-column layout — the narrative column takes the text, the rail takes the control.

- [ ] **Step 5: Run the whole suite**

Run: `... -only-testing:PriorsTests`
Expected: all pass, including the existing prologue tests.

- [ ] **Step 6: Commit**

```bash
git add COPY.md Priors/Priors/Priors Priors/Priors/PriorsTests/PracticeCrossingTests.swift
git commit -m "Teach the crossing once, in the prologue, where nothing is measured

Design doc 5.4. The practice crossing is not one of the thirty, logs nothing
and touches no posterior — which is precisely why it may say in words that you
can go through or go around, and that both are the same to the errand. The
village never says it again.

Wording lives in COPY.md; the test pins the symmetry, because a line naming
only one option would be an instruction the first PATH inherits."
```

---

### Task 7: Move the act banners into `COPY.md`

Small, and it closes a standing violation: the act text is currently written inline in Swift while `COPY.md` is supposed to be final wording.

**Files:**
- Modify: `COPY.md`
- Modify: `Priors/Priors/Priors/Village/VillageContainerView.swift:34-47`
- Test: `Priors/Priors/PriorsTests/PracticeCrossingTests.swift` (append)

**Interfaces:**
- Consumes: `VillageContainerView.bannerMessage(for:) -> String?`, unchanged in signature.
- Produces: nothing.

- [ ] **Step 1: Add the section to `COPY.md`**

```markdown
## Act banners

Shown once each, on the slot given. They describe the world and the errand,
never a choice the player made (SPEC §2.9).

### Slot 0 — Act I
```
Act I: The Evening Bell
The streets are wide, and the lanterns burn bright.
```

### Slot 10 — Act II
```
Act II: The Eye in the Frost
Shadows pool at every corner. The frost begins to take the windows.
```

### Slot 15
```
The Ancient Effigy opens its eyes. You are not alone in the cold.
```

### Slot 20 — Act III
```
Act III: The Dying Flame
The bell has gone silent. Only what you carry remains.
```
```

- [ ] **Step 2: Write the failing test (append to `PracticeCrossingTests.swift`)**

```swift
    /// SPEC §2.9's narration rule: an act banner may describe the world and
    /// the errand, never a choice the player made.
    @Test("Act banners appear only on their authored slots")
    func actBannersAppearOnlyOnTheirAuthoredSlots() async throws {
        #expect(VillageContainerView.bannerMessage(for: 0) != nil)
        #expect(VillageContainerView.bannerMessage(for: 10) != nil)
        #expect(VillageContainerView.bannerMessage(for: 15) != nil)
        #expect(VillageContainerView.bannerMessage(for: 20) != nil)
        for slot in [1, 5, 9, 11, 16, 21, 29] {
            #expect(VillageContainerView.bannerMessage(for: slot) == nil)
        }
        // No banner may contain a bracketed control marker: COPY.md's
        // brackets mark controls and are not label text. Shipping them
        // literally has been a real bug on this project.
        for slot in [0, 10, 15, 20] {
            #expect(VillageContainerView.bannerMessage(for: slot)?.contains("[") == false)
        }
    }
```

- [ ] **Step 3: Run it**

Run: `... -only-testing:PriorsTests/PracticeCrossingTests`
Expected: passes already (the current inline text satisfies it). This test exists to pin the behaviour across the move in Step 4.

- [ ] **Step 4: Move the strings**

Replace the string literals in `VillageContainerView.bannerMessage(for:)` with references to a `VillageCopy` enum holding them, carrying a comment naming `COPY.md`'s "Act banners" section as the source. Keep the function's signature and slot mapping exactly as they are.

- [ ] **Step 5: Run the whole suite and both engines**

```bash
xcodebuild test ... -only-testing:PriorsTests
swift test --package-path PriorsEngine
```
Expected: PriorsTests all pass; PriorsEngine 78/78 (unchanged by this plan, run once here to prove it).

- [ ] **Step 6: Commit and sync**

```bash
git add COPY.md Priors/Priors/Priors/Village/VillageContainerView.swift Priors/Priors/PriorsTests/PracticeCrossingTests.swift
git commit -m "Act banners move to COPY.md

They were written inline in Swift while COPY.md is supposed to be final
wording. Text unchanged; the slots and the function signature are pinned by
test across the move."
git push origin main
git -C .worktrees/game-layer-in-world-decisions merge --ff-only main
git -C .worktrees/game-layer-in-world-decisions push origin game-feel-and-persona-strip
```

---

## Done when

- All seven tasks committed, `PriorsTests` green, `PriorsEngine` 78/78.
- A Release build launched with `-startPhase village` shows a threshold that reads as a lane, a gate or a pitch, and the twenty-one rendered bands separate at a glance.
- `AGENT-LOG.md` carries an entry in the project's style: what was built, what the renders showed, what was deferred, and anything found that was not fixed.

## Spec sections with no task, and why

- **Design doc §2 (Role).** Nothing to build. "The one who carries fire" is
  already what the prologue establishes and what `SPEC.md` §2.4 permits — a
  function, not a character. §2's content is a set of prohibitions (no name, no
  face, no backstory, no opinion), and every one of them is already true. A
  task here would be a task to change nothing.
- **Design doc §3 (Story).** The three acts exist and are already paced by
  posterior SD rather than the clock. Task 7 moves their words to `COPY.md`;
  the pacing is left exactly as it is, which is the point of §3.
- **Design doc §6, register 2 (place lines).** Deferred with Phase 2 below.

## Deferred, deliberately

- The village as a *place* — districts, silhouettes, landmarks. That is Phase 2 of `docs/superpowers/plans/2026-09-02-village-depth-program.md` and is the right next thing after this.
- Diegetic ambience on its own bus (SPEC §8.1 as amended in v1.3).
- Per-family `rt_base` — the named blocker before real-tester data collection, recorded in `AGENT-LOG.md`. A `PriorsEngine` change, out of scope here.
