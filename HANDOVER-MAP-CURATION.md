# Handover — village map curation (isolated session)

Paste this as the opening prompt of a **fresh session**. It exists because map
curation is a tight render → look → adjust loop that does badly at the end of a
long, rate-limited session, and because the previous attempt got the layout
right and the tiles wrong.

## The job

Rebuild the village of Aethelmere as a place a player can navigate: seven
districts, roads that tell you where you are, buildings assembled correctly,
and thresholds built from the village's own materials. Then wire it in.

**Read first, in order:**
1. `SPEC.md` — the contract, now **v1.4**. §8 (the village), §8.2 (diegetic
   pricing), §8.3 (in-world decisions), §8.4 (wayfinding), §2.9 (the
   invariants that are NOT revisable), and the v1.4 changelog entry.
2. `docs/superpowers/specs/2026-09-03-village-layout-design.md` — the approved
   district structure and the four verified causes of the flatness.
3. `AGENT-LOG.md` — the project's honest record.

## The standing ruling that frames everything

Owner, 2026-09-03: the spec, copy and other docs are **incomplete and
revisable** — "loose, not a tight rule, as long as we are making a functional
game, clear story line". Revise them as needed and record what you changed.

**The exception, which does not loosen:** SPEC §2.9. The thirty ADO-selected
decisions, what each measures and how each resolves are invariant. Also frozen:
`ThresholdNode.zoneRadius` 36.0 and `commitZoneRadius` 14.0 (`rt_ms` is
measured against them), the four engine files, and `BandLadder.swift`.

## What is decided, so you need not re-litigate it

- **Map size: ~52×30 tiles**, not 80×60. The arithmetic is in SPEC v1.4: a
  landscape screen is ~29×13 tiles, SPEC asks for ~4 screens = ~1,560 tiles.
  80×60 is 4,800 = 12.3 screens, and that is the main reason the village is
  empty. This change alone triples density.
- **One asset pack: Kenney Tiny Town.** DCSS is out — the owner saw it in place
  and rejected it. Do not reintroduce a second pack. If Tiny Town cannot draw
  something, compose it from Tiny Town parts or generate it in Tiny Town's
  palette the way `build_assets.py` already generates water and tonal grass.
- **Seven districts** (design doc §2): the Square, the Lanes, the Orchard, the
  Mill, the Pond End, the Workyard, the Commons. Each hosts the decision spots
  already named after it in `VillageMapBuilder.buildDecisionLocations`.
- **Thresholds come from village materials** (design doc §5): `PATH` is a gap
  in a hedge, `DETOUR` a gate in a fence, `TRADE` a pitch of barrels and crates
  on the road. SPEC §4 already names these skins. Art may extend past the 36pt
  zone; the commit sill must stay visible and the art centred on the zone.

## The mistake that made the last attempt look broken — do not repeat it

**Tiny Town is a building KIT, not a palette.** Its 132 tiles have roles, and
the previous prototype treated them all as interchangeable flat fills. The
results, verified by rendering them enlarged:

- **Tile 63 is a gable END** — one peaked roof-end with sky either side. It was
  tiled across an entire roof, producing a repeating chevron block in the
  middle of the village. The owner asked "what is that in the center?"
- **Tile 43 is grass with pale gravel blobs** — a flowerbed. It was used to
  pave the town square, which then read as a speckled rug.
- **Tiles 4/16/28/5 are perfectly good trees**, but planted sparsely on a bare
  grid they read as a graveyard, which is what happened to the Orchard.
- **108/120 are wall segments with distinct top/base roles**, used
  interchangeably.

**Your first task is therefore tile-role curation:** render the sheet with
indices (a script that does this is trivial — `TinyTown.imageset/TinyTown.png`
is a 12×12 grid of 16px tiles, indices 0..143, where 132..143 are generated
extras), look at every tile, and write down its role — wall base, wall upper,
roof ridge, roof gable, corner, path centre, path edge, prop. Commit that
table. Everything else depends on it, and it is the artefact the last attempt
lacked.

## Known defects to fix while you are in there

- **The water is the wrong blue.** `build_assets.py` synthesises it at RGB
  (3,155,220) — a saturated cyan in a palette of muted greens and oranges. It
  is the most out-of-place thing on screen after the DCSS arches. Retint it in
  Tiny Town's palette.
- **The ground varies by tint, not texture.** Three synthesised greens laid in
  courtyard-sized patches. Their averages are (118,178,94), (139,209,111),
  (136,190,93) — one green ±15%. Ground interest must come from things standing
  on the ground; do not try to fix it with more tints.
- **The map is mirrored.** Cottages sit at (22,44)/(52,44), (18,32)/(56,32),
  (22,20)/(48,20). Nothing in the rebuild should mirror.
- **The player spawns on a solid tile** — `playerSpawnPosition` (1280,960)
  resolves to tile (30,40), which is the well's cell, marked `grid = 2`.
  Pre-existing, no visible symptom, fix it while the map is open.

## Invariants to re-run after any map change — these are gates, not chores

- `ErrandReachabilityTests` — **every door reachable from the well by a route
  entering no decision zone.** Design doc §4.1: if crossing is ever the only
  way to a house, engaging acquires an in-game payoff and θ_e stops measuring a
  risk threshold. The test includes a non-vacuity check; keep it.
- **≥30% dead space** (SPEC §8). The 52×30 prototype measured 65%, so there is
  room to add content, not a shortage.
- All thirty decision spots must still exist, keep their `regionName` and
  `trait`, and sit in the district named after them. 19 θ_e and 11 θ_i.
- `-only-testing:PriorsTests` — 103 tests at handover time. Never the full
  scheme suite; it disrupts the owner's simulator.

## Method that has been working — keep it

- **Render it and look at it.** Every defect this project found that tests
  missed was found this way: a lane whose corners sat outside the zone while an
  axis-aligned assertion passed; gate bars that would have turned brown under
  the dusk filter; three nodes whose visible state lived in an `SKAction` that
  never ran in tests; a landmark sprite that was a carved face; two dice that
  composited into a face; and three of seven price bands rendering identically.
- **Prototype in Python before Swift.** The layout above was iterated in Python
  against the real tilesheet in minutes. Doing it in `VillageMapBuilder` would
  have cost hours per iteration.
- **Test the invariant, not the arithmetic.** And beware tests that cannot
  fail: three were found on this branch — one asserted a frozen file's own
  formula back at itself, one asserted two textures were different objects
  rather than which texture, one asserted a literal against a literal in a
  constant with no callers.

## State of the branch

Branch `game-feel-and-persona-strip` (worktree
`.worktrees/game-layer-in-world-decisions`), **not merged to `main`**. It
carries work worth keeping — the reachability invariant, the corrected
`ASSETS.md`, the map fix that moved three decision spots off cottage doorsteps,
`DecisionFormStyle`'s band channels — and work to be removed: the DCSS landmark
atlas (`LandmarkType`, `loadLandmarks`, `LandmarkAtlasTests`, the
`Landmarks.imageset`, the `LANDMARKS` block in `build_assets.py`) and the DCSS
threshold forms. Removing them is part of this job; git history keeps them if
the decision is ever revisited.

`stash@{0}` on that branch holds an abandoned partial fix wave for the DCSS
arches. It is superseded — drop it.

## Two things flagged for the owner, not yet decided

- **The door's sag reads as a tilt.** Any door sprite that bakes in its own
  frame will rotate its jambs with it. If a gate needs to sag, the sag must be
  carried on a separate element.
- **`rt_ms` changes meaning when the map shrinks.** Walking distance between
  decisions is the raw material of the response-time channel, and halving the
  map changes that distribution. This compounds the already-named blocker
  before any real-tester data collection: `BehaviouralPosterior` needs a
  per-family `rt_base` (see `AGENT-LOG.md`). Do not tighten `RT_BASE_PRIOR_SD`
  to compensate — FINDINGS.md records that tightening it to 0.4 shifted θ_e by
  ~0.12 on no evidence.
