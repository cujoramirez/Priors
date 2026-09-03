# Village Art & Thresholds — Program and Phase 1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement Phase 1 task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a decision look like the thing its own words describe, using art the repository already owns, and open the door to the map overhaul by giving the village a real prop vocabulary instead of 24 tile types and coloured rectangles.

**Architecture:** A second atlas, built by the existing `scripts/build_assets.py` pipeline from the DCSS CC0 pack, supplies thresholds and landmarks. `DecisionFormNode` stops drawing `SKShapeNode` primitives and composes sprites instead. `DecisionFormStyle`'s band channels survive unchanged — they now drive sprite selection and overlay alpha rather than rectangle geometry, so the seven-band distinctness requirement stays tested where it already is.

**Tech Stack:** Python 3 + Pillow (`scripts/build_assets.py`), Xcode asset catalogs, SpriteKit (`SKSpriteNode`, `SKTexture`, `SKShapeNode` for overlays only), Swift Testing.

**Spec:** `SPEC.md` v1.3 (contract) and `docs/superpowers/specs/2026-09-03-role-quest-and-decisions-design.md` (the design this serves). Read both before Task 1.

**Supersedes:** `docs/superpowers/plans/2026-09-03-decisions-that-read-as-decisions.md`, stopped after Task 3 by owner direction — procedural rectangles were the wrong answer to "the decisions don't read as decisions". What landed from it and stays: the errand-reachability invariant (Task 1), `DecisionFormStyle` (Task 2), and `DecisionFormNode`'s structure, containment test and zPosition test (Task 3). Its Tasks 4-7 are re-planned as Phase 1 Task 5 and Phase 3 below.

---

## The art-direction ruling (owner-approved, 2026-09-03)

Seven CC0 packs are vendored in `Priors/Assets-source/`. Only two were ever used. The ruling, made against rendered comparisons rather than store descriptions:

**Kenney Tiny Town stays the base** for ground, paths, walls, roofs, doors-as-architecture and characters. It survives the dusk filter because its source colours are bright, which matters: this project has already shipped a bug where the village went mathematically black before the vignette applied.

**DCSS supplies thresholds, landmarks and props only.** Stone arches, doorways, columns, statues, fountains, altars. It is where the vocabulary is — 28 gateway tiles alone.

**Why this mix will not read as an asset flip:** Kenney's source is 16px drawn at 32pt — 2pt per source pixel. DCSS's source is 32px drawn at **64pt** — also 2pt per source pixel. The apparent pixel size is identical, which is the property that makes mixed packs look wrong when it differs. **Every DCSS sprite is drawn at exactly 2×, 64×64 points.** A DCSS sprite drawn at 32pt would be double-density against its neighbours and would give the mix away instantly.

**The class-separation rule, which is what keeps it coherent:** DCSS never supplies ground, wall, roof, or character. Those are Kenney's. DCSS is the things you stop at. If a future task needs a DCSS wall, that is a signal the ruling is being eroded — raise it, do not do it.

**Rejected after rendering them:**
- `dc-dngn/vaults/grate.png` — flat pale grid, no depth, reads as a UI overlay lying on the grass.
- `dc-dngn/shops/dngn_enter_shop.png` and `dngn_abandoned_shop.png` — the word **SHOP** is baked into the sprite. English text in the world names the mechanic and is forbidden outright.
- `oga-classic-rpg-tileset` — `ASSETS.md` calls it a "Village & Overworld Tileset". It is a **character sheet with faces**, 40 tiles total. Faces violate SPEC §8.
- `oga-town-tiles` — five tiles.
- `kenney-roguelike-modern-city` — 1036 tiles of awnings, plate glass and modern shopfronts. Wrong century.

## Global Constraints

Copied verbatim. Every task's requirements implicitly include this section.

- **SPEC §2.9:** *"The mask may become a game. The instrument may not become visible."* The thirty decisions, what each measures and how each resolves are invariant under any art change.
- **SPEC §2.9:** *"Nothing may reward the engaged branch of any template."* *"Nothing may mark a decision."*
- **SPEC §2.3:** *"The model is never visible during play."*
- **SPEC §2.4:** No named protagonist, no personality, no score, no fail state.
- **SPEC §8.2:** Seven bands, one fixed phrase and one matching visual intensity each; *"the band is only how that price is shown, selected from the price, never the reverse."* Band **distinctness** is the load-bearing variable (`experiments/perceived_price.py`, FINDINGS.md).
- **SPEC §8.3:** No modal. `rt_ms` is zone-entry → resolve. The villager *"never reacts to being declined."*
- **SPEC §8:** *"Villagers have no faces."* *"Dead space is required. At least 30% of walkable area contains nothing."*
- **No text in the world.** No sprite, sign, or overlay may carry a readable word other than the authored band phrase from `BandLadder`. This is what rejects the DCSS shop tiles.
- **Design doc §5.1 — geometry is frozen:** `ThresholdNode.zoneRadius` 36.0, `commitZoneRadius` 14.0. Forms are skins. Changing either changes what `rt_ms`, `approach_frac` and `backtracks` measure and invalidates the `rt_base` fit.
- **Design doc §5.2:** *"No spatial decision may present a figure that reads as approachable."*
- **Art containment:** nothing in a form may draw at `zPosition` 5.0 or above, and every corner of every child must lie within `zoneRadius` of the origin. Both are already tested in `DecisionFormTests`; keep those tests passing.
- **Determinism:** the village must be byte-identical for every player. Any new randomness is seeded from tile coordinates, never `Date` or an unseeded RNG.
- **Frozen files — never modify:** `Posterior.swift`, `BehaviouralPosterior.swift` likelihood math, `ADOSelector.swift`, `ClaimGenerator.swift`, `BandLadder.swift`.
- **Licences:** every asset ships with its source pack's licence file, and `ASSETS.md` records pack, licence and what was taken. All packs used here are CC0 1.0. **itch.io packs surveyed in `ASSETS.md` (Pipoya, Sprout Lands, Super Retro World) may not be vendored** — their licences forbid redistributing the asset itself, and this repository is public.
- **Never run the full test suite** — it disrupts the owner's simulator. Scope to `-only-testing:PriorsTests/<Suite>`.
- **Playtest builds must be Release.** Debug is 67× slower on the posterior grid and reads as lag.

## Where the code is

Work in the worktree: `/Users/gading/Documents/Priors/.worktrees/game-layer-in-world-decisions`, branch `game-feel-and-persona-strip`. Merge to `main` at the finish — that is where the owner's playtest build comes from.

```bash
xcodebuild test -project Priors/Priors/Priors.xcodeproj -scheme Priors \
  -destination 'platform=iOS Simulator,id=A0B56E90-D0FB-47D3-BD94-DEE1F9E0038C' \
  -only-testing:PriorsTests/DecisionFormTests
python3 scripts/build_assets.py
```

## File Structure

| File | Responsibility |
|---|---|
| `ASSETS.md` | **Modify.** Correct the two packs it misdescribes; record the art-direction ruling and what was taken from DCSS. |
| `scripts/build_assets.py` | **Modify.** Emit a third imageset, `Landmarks`, composited from named DCSS files into a fixed grid. |
| `Priors/Priors/Priors/Assets.xcassets/Landmarks.imageset/` | **Create** (by the script, committed). |
| `Priors/Priors/Priors/Village/VillageAssets.swift` | **Modify.** Add `LandmarkType` and a `landmark(_:)` texture accessor beside the existing `TileType` / `texture(for:)`. |
| `Priors/Priors/Priors/Village/DecisionFormNode.swift` | **Modify.** Compose sprites; keep the overlay shapes only where a channel needs a tintable wash. |
| `Priors/Priors/PriorsTests/LandmarkAtlasTests.swift` | **Create.** Every `LandmarkType` slices to a non-blank texture. |
| `Priors/Priors/PriorsTests/DecisionFormTests.swift` | **Modify.** Existing containment/zPosition/distinctness tests stay; add sprite-presence assertions. |

---

## Phase 1 — thresholds that read

### Task 1: Correct `ASSETS.md` and record the ruling

`ASSETS.md` is currently misleading in ways that have already cost this project time: the village-depth plan notes it misdescribes `oga-character-bases` as a 4-direction top-down walker when it is a side-view brawler sheet, and this session found two more errors of the same kind. A survey written from store pages rather than from opening the files is worse than no survey.

**Files:** Modify `ASSETS.md`.

- [ ] **Step 1: Correct the errors**

In the comparison table and the recommendations, correct these, each with a note saying it was verified by rendering the file:
- **OGA 32×32 Village & Overworld Tileset** (`oga-classic-rpg-tileset`): described as terrain/foliage/village props. It is a **character sheet with faces**, `ClassicRPG_Sheet.png` is 320×128 = 40 tiles of 32×32. Not a tileset. Faces violate SPEC §8.
- **OGA 32×32 Top-Down Town & Buildings** (`oga-town-tiles`): `town_tiles.png` is 160×48 — **five 32×32 tiles**, not a building pack.
- **OGA Faceless Character Bases** (`oga-character-bases`): already known wrong — `rpgbaseformatted.png` is a side-view brawler sheet, not a 4-direction top-down walker.

- [ ] **Step 2: Add the ruling and the licence warning**

Add a section recording the art-direction ruling from this plan's header verbatim — Kenney base, DCSS thresholds and landmarks, the 2× rule and why, the class-separation rule, and the rejected assets with reasons. Add the licence warning: the itch.io packs in the survey (Pipoya, Sprout Lands, Super Retro World) permit commercial use but forbid redistributing the asset itself, and this repository is public, so they may not be vendored.

- [ ] **Step 3: Commit**

```bash
git add ASSETS.md
git commit -m "Correct ASSETS.md, and record the art-direction ruling

Three packs were described from store pages rather than from opening the
files. oga-classic-rpg-tileset is a 40-tile character sheet WITH FACES, not a
village tileset; oga-town-tiles is five tiles; oga-character-bases is a
side-view brawler sheet. All three verified by rendering them.

Records the owner's 2026-09-03 ruling: Kenney Tiny Town is the base for
ground, walls, roofs and characters; DCSS supplies thresholds, landmarks and
props only, drawn at 2x so its 32px source matches Kenney's 16px-at-2x pixel
density. Records what was rejected and why, including two DCSS shop tiles with
the word SHOP baked into the art.

Adds the licence warning: the itch.io packs in this survey forbid
redistributing the asset itself and this repository is public, so they may not
be vendored however permissive their commercial terms are."
```

---

### Task 2: Build the landmark atlas

**Files:**
- Modify: `scripts/build_assets.py`
- Create (by the script): `Priors/Priors/Priors/Assets.xcassets/Landmarks.imageset/`
- Modify: `Priors/Priors/Priors/Village/VillageAssets.swift`
- Test: `Priors/Priors/PriorsTests/LandmarkAtlasTests.swift`

**Interfaces:**
- Consumes: DCSS files under `Priors/Assets-source/dcss-32x32-tiles/crawl-tiles Oct-5-2010/`.
- Produces: `LandmarkType` (Swift enum, `String` raw values), `VillageAssets.landmark(_ type: LandmarkType) -> SKTexture`, and `VillageAssets.landmarkPointSize` = `64.0`.

- [ ] **Step 1: Add the atlas build**

Read `scripts/build_assets.py` first and follow its existing structure — it already has `imageset(name, img)` for emitting into the catalog, and `main()` composites the character atlas as a grid. Add an equivalent for landmarks. The atlas is a single row-major grid of 32×32 cells, 4 columns wide, in exactly this order (the order **is** the Swift enum's index order — if you change it, change both):

```python
# DCSS CC0, drawn at 2x (64pt) so its 32px source matches Kenney's
# 16px-at-2x: 2 points per source pixel either way. See ASSETS.md.
DCSS = ROOT / "Priors/Assets-source/dcss-32x32-tiles/crawl-tiles Oct-5-2010"
LANDMARKS = [
    ("archOpen",     "dc-dngn/gateways/dngn_stone_arch.png"),
    ("archDark",     "dc-dngn/gateways/dngn_entrance.png"),
    ("doorOpen",     "dc-dngn/dngn_open_door.png"),
    ("doorClosed",   "dc-dngn/dngn_closed_door.png"),
    ("column",       "dc-dngn/crumbled_column.png"),
    ("statue",       "dc-dngn/dngn_granite_statue.png"),
    ("fountain",     "dc-dngn/dngn_dry_fountain.png"),
    ("goods",        "dc-dngn/shops/shop_general.png"),
]

def landmark_atlas() -> Image.Image:
    cols = 4
    rows = (len(LANDMARKS) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * 32, rows * 32), (0, 0, 0, 0))
    for i, (name, rel) in enumerate(LANDMARKS):
        path = DCSS / rel
        if not path.exists():
            raise SystemExit(f"landmark source missing: {path}")
        img = Image.open(path).convert("RGBA")
        if img.size != (32, 32):
            raise SystemExit(f"landmark {name} is {img.size}, expected 32x32")
        atlas.alpha_composite(img, ((i % cols) * 32, (i // cols) * 32))
    return atlas
```

Call it from `main()` alongside the existing emissions: `imageset("Landmarks", landmark_atlas())`. Note the two `SystemExit` guards — a silently missing or wrong-sized source is exactly how this pipeline produces art that looks like a rendering fault.

- [ ] **Step 2: Run the build and LOOK at the atlas**

```bash
python3 scripts/build_assets.py
```

Then open `Priors/Priors/Priors/Assets.xcassets/Landmarks.imageset/Landmarks.png` and check it: eight sprites, none blank, none clipped, each on its own 32×32 cell with transparent background. **This step is not optional.** `VillageAssets` falls back to flat colour rectangles when slicing fails, so a broken atlas does not crash — it produces art that looks like missing art, which is the exact failure this whole plan exists to fix.

- [ ] **Step 3: Write the failing test**

```swift
//
//  LandmarkAtlasTests.swift
//  PriorsTests
//
//  `VillageAssets` falls back to flat colour rectangles when a slice fails, so
//  a broken atlas does not crash — it silently ships art that looks like
//  missing art. This project once shipped a well sprite as the player
//  character because nobody opened the atlas. These assert that every
//  landmark slices to something with actual pixels in it.
//

import Testing
import SpriteKit
import UIKit
@testable import Priors

@Suite("Landmark atlas")
@MainActor
struct LandmarkAtlasTests {

    @Test("Every landmark slices to a non-blank texture")
    func everyLandmarkSlicesToANonBlankTexture() async throws {
        for type in LandmarkType.allCases {
            let texture = VillageAssets.shared.landmark(type)
            #expect(texture.size().width == 32, "\(type) is \(texture.size())")
            #expect(texture.size().height == 32, "\(type) is \(texture.size())")

            // Non-blank: at least a tenth of the pixels must be opaque.
            let image = UIImage(cgImage: texture.cgImage())
            let data = try #require(image.cgImage?.dataProvider?.data as Data?)
            var opaque = 0
            for i in stride(from: 3, to: data.count, by: 4) where data[i] > 8 { opaque += 1 }
            let total = data.count / 4
            #expect(opaque * 10 > total, "\(type) is \(opaque)/\(total) opaque — blank or nearly so")
        }
    }

    /// The 2x rule (ASSETS.md): DCSS's 32px source drawn at 64pt is 2 points
    /// per source pixel, matching Kenney's 16px drawn at 32pt. A DCSS sprite
    /// drawn at 32pt would be double-density against its neighbours and would
    /// give the mix away instantly.
    @Test("Landmarks are drawn at twice their source size")
    func landmarksAreDrawnAtTwiceTheirSourceSize() async throws {
        #expect(VillageAssets.landmarkPointSize == 64.0)
        #expect(VillageAssets.landmarkPointSize == VillageAssets.tileSize * 2)
    }
}
```

- [ ] **Step 4: Run it to confirm it fails**

Run the `-only-testing:PriorsTests/LandmarkAtlasTests` command.
Expected: compile failure — `cannot find 'LandmarkType' in scope`.

- [ ] **Step 5: Add `LandmarkType` and the accessor**

In `VillageAssets.swift`, beside the existing `TileType`, following its shape exactly (raw index, one `switch`, a cached dictionary):

```swift
/// DCSS CC0 landmarks and thresholds — the things you stop at. Kenney supplies
/// ground, walls, roofs and characters; this pack supplies nothing of those.
/// See ASSETS.md's art-direction ruling.
///
/// The index order matches `LANDMARKS` in `scripts/build_assets.py`. Change
/// one and you must change the other.
public enum LandmarkType: Int, CaseIterable, Sendable {
    case archOpen = 0
    case archDark
    case doorOpen
    case doorClosed
    case column
    case statue
    case fountain
    case goods
}
```

Add a `landmarkTextures: [LandmarkType: SKTexture]` cache, a `loadLandmarks()` called from `init()` beside `loadTiles()`, a `landmark(_:)` accessor mirroring `texture(for:)`, and:

```swift
/// On-screen size for a landmark. DCSS source is 32px; drawn at 64pt that is
/// 2 points per source pixel, the same density as Kenney's 16px at 32pt.
public static let landmarkPointSize: CGFloat = 64.0
```

Slice from the `Landmarks` imageset with a 32px source cell and 4 columns, exactly as `loadTiles()` slices `TinyTown`.

- [ ] **Step 6: Run the tests**

Expected: both pass. If a landmark comes back blank, the atlas is wrong — go back to Step 2 and look at the PNG rather than adjusting the threshold in the test.

- [ ] **Step 7: Commit**

```bash
git add scripts/build_assets.py Priors/Priors/Priors/Assets.xcassets/Landmarks.imageset Priors/Priors/Priors/Village/VillageAssets.swift Priors/Priors/PriorsTests/LandmarkAtlasTests.swift
git commit -m "A landmark atlas: the things you stop at

Eight DCSS CC0 sprites — two arches, two door states, column, statue,
fountain, goods — built by the same pipeline that already emits the tile and
character atlases, with hard failures on a missing or wrong-sized source
rather than the silent fallback that makes a broken atlas look like missing
art.

Drawn at 64pt: DCSS's 32px source at 2x is 2 points per source pixel, the same
density as Kenney's 16px at 32pt, which is the property that keeps a mixed
pack from reading as an asset flip."
```

---

### Task 3: `PATH` becomes an arch with the dark behind it

**Files:** Modify `Priors/Priors/Priors/Village/DecisionFormNode.swift`, `Priors/Priors/PriorsTests/DecisionFormTests.swift`.

**Interfaces:** Consumes `VillageAssets.shared.landmark(_:)`, `VillageAssets.landmarkPointSize`, `DecisionFormStyle.laneDepth/laneDarkAlpha/laneMouthNarrowing`.

The phrases run *"The lane is only a little dark"* → *"It is black past the gate."* The form is a stone arch you can see through, with darkness gathering in the opening as the band rises.

- [ ] **Step 1: Replace `makeLane`**

Keep the function name and signature. Build:
1. `archOpen` as an `SKSpriteNode` at `landmarkPointSize`, `zPosition` 4.2, centred at the origin.
2. Behind it (`zPosition` 4.0), a black `SKShapeNode` filling the arch's opening, its alpha from `laneDarkAlpha` and its height from `laneDepth`, so the dark reaches further back as the band rises.
3. At the top three bands only, swap `archOpen` for `archDark` — the sprite whose opening is already black — so the highest bands change the *sprite*, not just an alpha. Use `DecisionFormStyle.laneDarkAlpha(intensity) > 0.70` as the switch, and note in a comment that this is a presentation threshold and not a band boundary.

`laneMouthNarrowing` now narrows the dark shape rather than moving walls.

**Containment:** the sprite is 64pt across, so its corners sit at 32·√2 ≈ 45.3 from the origin — outside the 36pt zone, and the existing containment test will fail. That test is correct and must not be weakened. Scale the sprite to fit: the largest square whose corners are inside a 36pt circle has a half-side of 36/√2 ≈ 25.45, so draw it at **50pt**, not 64. Record in a comment that this is the one place the 2× rule yields to the geometry, and why — a threshold's art must not spill outside the zone, because the zone is the decision.

- [ ] **Step 2: Add sprite assertions to `DecisionFormTests`**

```swift
    @Test("The lane is an arch, and the dark deepens behind it")
    func theLaneIsAnArchAndTheDarkDeepensBehindIt() async throws {
        let low = DecisionFormNode.make(form: .lane, intensity: 0.0)
        let high = DecisionFormNode.make(form: .lane, intensity: 1.0)

        let lowSprites = low.children.compactMap { $0 as? SKSpriteNode }
        let highSprites = high.children.compactMap { $0 as? SKSpriteNode }
        #expect(lowSprites.count == 1, "the lane should be one arch sprite plus overlays")
        #expect(highSprites.count == 1)

        // The high band swaps the sprite, not only the alpha.
        #expect(lowSprites[0].texture !== highSprites[0].texture)
    }
```

- [ ] **Step 3: Run the suite; every existing test must still pass**

Run `-only-testing:PriorsTests/DecisionFormTests`. The containment test and the zPosition test are the ones to watch — they are the reason the sprite is 50pt and not 64.

- [ ] **Step 4: Commit**

```bash
git add Priors/Priors/Priors/Village/DecisionFormNode.swift Priors/Priors/PriorsTests/DecisionFormTests.swift
git commit -m "PATH is an arch with the dark gathering behind it

Was two rectangles and a wedge. The phrases run from 'only a little dark' to
'black past the gate', and now so does the art: a stone arch you can see
through, darkness deepening in the opening with the band, and a swap to the
already-black entrance sprite at the top three bands so the highest prices
change the sprite rather than only an alpha.

Drawn at 50pt rather than the 64pt the 2x rule asks for: a 64pt square's
corners sit 45pt from centre, outside the 36pt zone, and art may not spill
past the zone because the zone is the decision."
```

---

### Task 4: `DETOUR` becomes a door that will not open

**Files:** Modify `DecisionFormNode.swift`, `DecisionFormTests.swift`.

The phrases run *"The gate looks like it will open easily"* → *"The gate has not opened in years."*

- [ ] **Step 1: Replace `makeGate`**

Keep the name and signature. Build `doorOpen` at bands where `gateSagRadians(intensity)` is below its midpoint and `doorClosed` above it — the sprite carries the ladder's core meaning, open to shut. Then overlay, all inside the zone and all below `zPosition` 5.0:
- rust: a warm `SKShapeNode` wash over the door with alpha `gateRustAlpha`, blend `.alpha`;
- growth: `gateWeedCount` small green shapes along the door's base, positioned by a fixed fan from the index as they are today — no RNG;
- sag: apply `gateSagRadians` as `zRotation` on the sprite, hung so it rotates about its left edge.

Same 50pt sizing and the same reason as Task 3.

- [ ] **Step 2: Add the assertion**

```swift
    @Test("The gate shuts as the band rises")
    func theGateShutsAsTheBandRises() async throws {
        let low = DecisionFormNode.make(form: .gate, intensity: 0.0)
        let high = DecisionFormNode.make(form: .gate, intensity: 1.0)
        let lowDoor = try #require(low.children.compactMap { $0 as? SKSpriteNode }.first)
        let highDoor = try #require(high.children.compactMap { $0 as? SKSpriteNode }.first)
        #expect(lowDoor.texture !== highDoor.texture, "open at band 1, shut at band 7")
        #expect(abs(highDoor.zRotation) > abs(lowDoor.zRotation), "the high band sags further")
    }
```

- [ ] **Step 3: Run the suite, then commit**

```bash
git commit -m "DETOUR is a door, open at band 1 and shut at band 7

The sprite carries the ladder's core meaning — open to shut — with rust,
growth and hinge sag layered on top from the same channels as before. The
weeds are still placed by a fixed fan from their index, never an RNG: the
village must be byte-identical for every player."
```

---

### Task 5: `TRADE` becomes a pitch, with no approachable figure

**Files:** Modify `DecisionFormNode.swift`, `DecisionFormTests.swift`.

The phrases are about a peddler. The form is their pitch: a cloth on the ground with goods laid out. **No figure.** `TRADE` resolves by crossing, and a figure that reads like a waiting villager invites a hold on Interact that does nothing there — the owner's original complaint, rebuilt somewhere new.

- [ ] **Step 1: Replace `makePitch`**

Keep the cloth as an `SKShapeNode` (it is a tinted surface, not a prop) with alpha from `pitchClothAlpha`, and place the `goods` landmark sprite on it at 40pt. Keep the two procedural dice with `pitchDiceTilt`, and the near-half shadow with `pitchShadowAlpha`. The DCSS shop *buildings* are rejected — they carry the word SHOP in the art.

- [ ] **Step 2: Add the assertion**

```swift
    @Test("The pitch lays out goods and shows no figure")
    func thePitchLaysOutGoodsAndShowsNoFigure() async throws {
        for band in 1...7 {
            let node = DecisionFormNode.make(form: .pitch,
                                             intensity: BandLadder.visualIntensity(band: band))
            let sprites = node.children.compactMap { $0 as? SKSpriteNode }
            #expect(sprites.count == 1, "band \(band): the goods, and nothing else")
            // Design doc §5.2 — no approachable figure in a spatial decision.
            #expect(node.childNode(withName: "trade_figure") == nil)
        }
    }
```

- [ ] **Step 3: Run the suite, then commit**

```bash
git commit -m "TRADE is a pitch: a cloth, goods laid out, and no figure

TRADE resolves by crossing, so it may not present anything that reads as an
approachable villager — that invites a hold on Interact which does nothing
and is exactly the confusion this work exists to remove. DCSS's shop
buildings are rejected outright: the word SHOP is baked into the art."
```

---

### Task 6: Render all twenty-one bands and look at them

Not a formality. Every defect this programme has found that the tests missed was found by rendering: a lane whose corners sat outside the zone while an axis-aligned assertion passed, gate bars that would have turned brown under the dusk filter, three nodes whose visible state lived in an `SKAction` that never ran.

**Files:** Create then delete `Priors/Priors/PriorsTests/ZZFormDump.swift`.

- [ ] **Step 1: Dump the strips**

Write a throwaway test that, for each of `.lane`, `.gate`, `.pitch`, builds all seven bands via `DecisionFormNode.make`, lays them out in a row on a grass-coloured background with a commit-sill circle drawn at each, renders with `SKView.texture(from:crop:)`, and writes a PNG to `NSTemporaryDirectory()`. Print each path. Copy them out and open them.

- [ ] **Step 2: Judge against these questions**

- Can you tell band 1 from band 2 at a glance? Band 6 from band 7? A numeric test passing is necessary, not sufficient.
- Does band 7 still read as an arch, a door, a pitch — or has it collapsed into a dark blob? That collapse is the failure this programme exists to fix.
- Is the commit sill visible at every band, including band 7?
- Do the DCSS sprites sit against Kenney grass without reading as pasted-on? If they do read as pasted-on, say so and stop — that is the art-direction ruling failing, and it is the owner's call, not yours.

- [ ] **Step 3: Fix what you saw, re-dump, then delete the harness and commit**

Changes go in `DecisionFormStyle` (channel spans) or `DecisionFormNode` (composition). Record in the commit message what you saw and what you changed because of it.

---

## Phase 2 — the map (scoped, not yet task-level)

The village is 80×60 tiles of uniform meadow with seven cottages on it. Nowhere is anywhere, which weakens the measurement: SPEC §8 requires 30% dead space and calls pointless exploration "the best data in the run", but dead space only reads as *choosing not to go somewhere* if the somewhere is legible. With a landmark atlas in place, districts become buildable: a well square, a pond end, an orchard, a mill, a north lane. `VillageMapBuilder` already names thirty decision locations after places that do not exist yet — `r_orchard_corner`, `r_pond_pier`, `r_west_bridge`. Build the places the names promise.

Plan this when Phase 1 lands. It inherits the errand-reachability invariant from the superseded plan — every door reachable without entering a decision zone — which must be re-run after any map change.

## Phase 3 — interaction (scoped, not yet task-level)

Carried over from the superseded plan: the practice crossing in the prologue, taught once where nothing is measured, and the act banners moved into `COPY.md`. Add to it whatever Phase 1's render pass shows is still unclear about what the player is meant to do.

## Deferred, with reasons

- **Per-family `rt_base`** — the named blocker before real-tester data collection (`AGENT-LOG.md`). A `PriorsEngine` change, out of scope.
- **The player spawns on a solid tile** — `playerSpawnPosition` (1280,960) resolves to tile (30,40), which is the well's cell, marked `grid = 2`. Found during the superseded plan's Task 1 review. Pre-existing, no visible symptom, belongs with Phase 2.
- **Audio** — SPEC §8.1 as amended in v1.3 permits key and tempo changes now; diegetic ambience is a separate bus. Its own program.
