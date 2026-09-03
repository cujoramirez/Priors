# The Village — a layout you can navigate

Design document, 2026-09-03. Written against `SPEC.md` v1.3.
Not contract. `SPEC.md` wins every conflict.

**Status:** district structure approved by the owner. Tile-level layout to be
rendered and approved before any of it is built.

---

## 0. The complaint, and what actually causes it

The owner: *"it's plain as fuck like a 32x32 box. we need a proper layout so the
user can navigate the tasks, quests, etc."*

Four verified causes, not one.

**1. The map is mirrored.** `VillageMapBuilder.buildCottages` places seven
cottages at `(22,44)` and `(52,44)`, `(18,32)` and `(56,32)`, `(22,20)` and
`(48,20)`, plus the hall at `(37,36)`. Both halves of the village are the same
village. That is the single biggest reason nowhere is anywhere: there is no
view that tells you which side of the map you are on.

**2. The path network is a plus sign.** Every path tile is the same tile, laid
in one horizontal band and one vertical band. There is no main road, no lane,
no track — so the roads carry no information about where they go.

**3. The ground varies by tint, not by texture.** `build_assets.py`'s own
comment records why: *"Tiny Town ships exactly one grass tile and two flower
variants, so the ground was ~91% a single flat green."* The fix applied was to
synthesise three tinted greens and place them by value noise in
courtyard-sized patches. Tinting a flat tile three ways yields large flat
blocks of slightly different green — which is precisely what "plain as a 32x32
box" describes. **Ground interest comes from things standing on the ground,
not from shading it.**

**4. The places the game talks about do not exist.** `buildDecisionLocations`
names thirty spots — `r_orchard_corner`, `r_pond_pier`, `r_west_bridge`,
`r_south_mill_gate`, `r_smithy_forge`, `r_weaver_porch`, `r_woodcutter_shed`,
`r_pasture_stile`. There is no orchard, pier, bridge, mill, smithy, weaver or
pasture. `COPY.md`'s report lines name landmarks the village does not contain.

## 1. Why this is a measurement problem, not decoration

`SPEC.md` §8 requires at least 30% of walkable area to contain nothing, and
calls pointless exploration *"the best data in the run"*. That only holds if
the emptiness is legible as a **choice**. Undifferentiated meadow produces
wandering, not exploration: a player who drifts across a featureless field has
not decided anything, and `approach_frac` and revisit counts are noisier for
it. Districts are what turn drift into a decision not to go somewhere.

The same argument covers navigation. Under SPEC v1.3 §8.4 markers are now
permitted, but a map whose shape tells you where you are needs fewer of them,
and every marker is a thing on screen that is not the world.

## 2. The districts

Approved structure. Asymmetric by construction — no district is the mirror of
another, and no two share a silhouette.

| District | Where | What it is | Hosts |
|---|---|---|---|
| **The Square** | centre, around the well | Paved, the hall on one side, the well at its heart. Where the player starts and returns to refill. | `r_well_square`, `r_fountain_side`, `r_town_hall_steps` |
| **The Lanes** | north of the Square | The cottages, close together on narrow lanes. The delivery round lives here. | `r_north_lane`, `r_north_hedge_gap`, `r_elder_door`, `r_weaver_porch` |
| **The Orchard** | west | Rows of trees, low fences, a gate. Quiet and regular. | `r_orchard_corner`, `r_deep_west_path`, `r_west_bridge` |
| **The Mill** | south | A mill by a stream running to the pond. The tallest silhouette in the village. | `r_south_mill_gate`, `r_crossroads_south` |
| **The Pond End** | south-east | Existing water, plus a pier, reeds, willows. | `r_pond_pier`, `r_southeast_lakeside`, `r_east_crossing` |
| **The Workyard** | east | Smithy, crates, stacked timber, fences. Cluttered where the Orchard is regular. | `r_smithy_forge`, `r_lantern_rack`, `r_peddler_stand` |
| **The Commons** | west and north-east | **Empty on purpose.** Open grass, a treeline, nothing to do. | nothing |

The Commons is not left-over space; it is the 30% SPEC §8 demands, shaped so a
player can see it is empty and choose it anyway. Log what they do there.

## 3. Roads that carry information

Three tiers, visually distinct:

- **The high road** — one continuous east-west route through the Square, the
  widest paving. It is the spine; from anywhere on it you can find the Square.
- **Lanes** — narrower, branching off the high road into the Lanes district and
  the Workyard. They lead to doors.
- **Tracks** — worn dirt, no edging, into the Orchard and the Commons. They
  lead away from the errand, which is the point.

A player should be able to tell, from the road under their feet, whether they
are heading toward the task or away from it — **without that ever being said,
and without either direction being rewarded** (§2.9).

## 4. Cottages

Seven, clustered in the Lanes rather than scattered to the corners, with
varied footprints and orientations. Clustering matters for the errand: "the
dark houses" becomes a destination you can hold in your head, and the
delivery round becomes a route rather than a scavenger hunt.

The reachability invariant is unchanged and must be re-run after any placement
change: **every door reachable from the well by a route entering no decision
zone** (`ErrandReachabilityTests`).

## 5. Thresholds, built from the village

This supersedes the DCSS threshold work. The owner's verdict on it: *"it's so
out of place dawg."* It was: DCSS is dungeon-interior art, dark and heavy, and
a free-standing arch in a meadow has no wall to belong to.

`SPEC.md` §4 already names the skins — *"unlit path, cellar door, gap in
hedge"* for `PATH`, *"long way round, closed gate"* for `DETOUR`. Build those,
from Tiny Town's own fences, posts, gates, hedges and props:

- **`PATH` — a gap in a hedge.** Hedge either side, a gap between. The band
  drives how dark the gap is. Because the gap is genuinely open, the darkness
  channel is fully visible — which fixes the defect the last review found,
  where three of seven bands collapsed behind an opaque arch.
- **`DETOUR` — a gate in a fence.** Fence line, posts, a gate. The band drives
  open → shut, plus growth and rust.
- **`TRADE` — a pitch on the road.** Barrels, a crate, a signpost. The band
  drives how the goods are laid out and how much sits in shadow.

**Two rules change from the previous design, both of them mine and both wrong:**

1. **Art may extend beyond the 36pt zone.** The zone is where measurement
   starts, not a frame the art must fit inside. The old rule is why the arch
   was 50pt against a 192pt cottage and looked like a prop. What must hold:
   the commit sill stays visible, and the art is centred on the zone so every
   approach angle is equivalent (§8.3).
2. **The 2× pixel-density rule is retired as a cross-pack reconciliation.**
   With thresholds built from Tiny Town, there is no second pack to reconcile
   inside a decision. Kenney art is 16px drawn at 32pt everywhere, full stop.

## 6. What must not change

- `ThresholdNode.zoneRadius` 36.0 and `commitZoneRadius` 14.0 (§8.3, and the
  `rt_base` fit depends on them).
- The thirty decisions, their templates, quotas, ADO-chosen prices, and how
  each resolves (§2.9). A decision may move to a better *place*; it may not
  change what it measures.
- Seven bands per template, distinct from their neighbours (§8.2).
- Determinism: the village is byte-identical for every player. Scatter is
  seeded from tile coordinates, never `Date` or an unseeded RNG.
- No faces, no readable text in the world, no marker on any decision.
- ≥30% dead space, measured and asserted.

## 7. Open question for the owner

The DCSS landmark atlas is built, tested and committed but would now be unused.
Keep it for open-map landmarks in this layout — a fountain in the Square, an
altar at a district edge, where a 64pt sprite has room and no fence to clash
with — or bin it so the village is single-pack and there is no second style to
police?
