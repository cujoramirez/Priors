# Game Layer: Diegetic Pricing + In-World Decisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the modal that prints a bare percentage (`ScenarioDialogView`) with in-world decisions — spatial templates become thresholds the player walks across, social templates become a villager who waits — and re-fit the `rt_base` prior so `BehaviouralPosterior` reads real hesitation instead of button-click latency.

**Architecture:** `VillageMapBuilder` exposes 30 pre-built, trait-tagged locations instead of always-live trigger nodes. `VillageCoordinator` arms exactly one of them at a time with the next ADO-selected `Design`, rendered as either a `ThresholdNode` (spatial: crossing/leaving resolves it) or a `WaitingVillagerNode` (social: holding Interact while facing it resolves it). Resolution flows back through `VillageScene` → `VillageCoordinator`, which logs the `DecisionRecord` with real elapsed time as `rtMs`, updates `BehaviouralPosterior`, and arms the next slot. Band phrases replace percentages via a new `BandLadder`.

**Tech Stack:** Swift 6, SwiftUI, SpriteKit, `PriorsEngine` (Swift package), Python 3 / NumPy (`priors-research`).

**Spec:** `/Users/gading/Documents/Priors/SPEC.md` §8.2, §8.3 (v1.2) — read alongside `/Users/gading/Documents/Priors/SCHEMA.md` §1, §7 and `/Users/gading/Documents/Priors/priors-research/FINDINGS.md` (the price-banding and rt_base sections). `/Users/gading/Documents/Priors/SPEC-GAME.md` §2/§3 are historical background only — superseded by SPEC.md v1.2, do not build from them directly.

## Global Constraints

- No scenario ever prints a number (SPEC §8.2). Price reaches the player only through the seven-band ladder's authored phrase and a scalar visual intensity.
- Exactly one decision is live in the world at a time (SPEC §8.3) — ADO stays fully sequential/adaptive, never batched.
- `approach_frac`, `backtracks`, `idle_ms` (SCHEMA §1) must become genuinely observed quantities from real zone dwell, not synthetic/button-driven values.
- Do not modify `Posterior`, `BehaviouralPosterior`'s likelihood math, `ADOSelector`, or `ClaimGenerator` (SPEC.md v1.2 changelog / SPEC-GAME.md §8) — only the `rt_base` prior *center* constant changes, and only in the two named places (Python `rt_posterior.py`, Swift `BehaviouralPosterior.swift`), never `RT_BASE_PRIOR_SD` below 0.8.
- No score, points, XP, leaderboard, share button, or fail state (SPEC §2.4). No confidence/prediction display during play (SPEC §2.3).
- Villagers have no faces (SPEC §8) and must not turn to look at the player or react to the eye manipulation (SPEC §6.3, §8.3 draft §5.2 constraint) — `WaitingVillagerNode` never adds gaze/attention behavior.
- If a design change needs a schema change, the order is `SCHEMA.md` → Python → regenerate goldens (`scripts/make_golden.py`) → Swift. Never the reverse.
- Villager pathfinding (`GameplayKit`/`GKGridGraph`/`GKAgent2D`) is explicitly out of scope for this plan — `WaitingVillagerNode` uses a straight-line `SKAction.move`, matching the existing `NPCNode`/`ShadowNode` pattern.
- Re-run the full verification suite (`swift test` in `PriorsEngine`, `pytest` in `priors-research`, `xcodebuild test` for the whole `Priors` scheme) before calling any task done — do not report success without the actual command output.

---

### Task 1: Author the band ladder

**Files:**
- Create: `Priors/Priors/Priors/Village/BandLadder.swift`
- Test: `Priors/Priors/PriorsTests/BandLadderTests.swift`

**Interfaces:**
- Produces: `BandLadder.band(for price: Double, template: TemplateID) -> Int` (1-based, 1...7), `BandLadder.phrase(template: TemplateID, band: Int) -> String`, `BandLadder.visualIntensity(band: Int) -> Double` (0.0...1.0).
- Consumes: `TemplateID`, `Trait` from `PriorsEngine`; `TRAIT_GRIDS`-equivalent bounds — Swift doesn't expose the Python trait grids directly, so this file hardcodes the same bounds SPEC.md §3.1/§3.2 states: θ_e ∈ [0.05, 0.85], θ_i ∈ [0.02, 0.70].

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Priors
import PriorsEngine

@Suite("BandLadder")
struct BandLadderTests {
    @Test func sevenBandsCoverTheFullRangePerTrait() async throws {
        // theta_e templates: PATH, DETOUR, TRADE
        #expect(BandLadder.band(for: 0.05, template: .path) == 1)
        #expect(BandLadder.band(for: 0.85, template: .path) == 7)
        #expect(BandLadder.band(for: 0.45, template: .path) >= 3)
        #expect(BandLadder.band(for: 0.45, template: .path) <= 5)

        // theta_i templates: ERROR, CREDIT, GIVE
        #expect(BandLadder.band(for: 0.02, template: .error) == 1)
        #expect(BandLadder.band(for: 0.70, template: .error) == 7)
    }

    @Test func bandIsMonotonicInPrice() async throws {
        let prices = stride(from: 0.05, through: 0.85, by: 0.02).map { $0 }
        var lastBand = 0
        for p in prices {
            let b = BandLadder.band(for: p, template: .detour)
            #expect(b >= lastBand)
            lastBand = b
        }
    }

    @Test func everyTemplateHasSevenDistinctNonEmptyPhrases() async throws {
        for template: TemplateID in [.path, .detour, .error, .credit, .give, .trade] {
            let phrases = (1...7).map { BandLadder.phrase(template: template, band: $0) }
            #expect(phrases.count == Set(phrases).count, "duplicate phrase in \(template)")
            for phrase in phrases {
                #expect(!phrase.isEmpty)
                #expect(!phrase.contains("%"))
                #expect(!phrase.contains(where: { $0.isNumber }))
            }
        }
    }

    @Test func visualIntensityIsMonotonicAndNormalised() async throws {
        let values = (1...7).map { BandLadder.visualIntensity(band: $0) }
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
        for (a, b) in zip(values, values.dropFirst()) {
            #expect(b > a)
        }
    }

    @Test func priceOutsideRangeClampsToTheEdgeBand() async throws {
        #expect(BandLadder.band(for: -0.1, template: .path) == 1)
        #expect(BandLadder.band(for: 1.5, template: .path) == 7)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/BandLadderTests 2>&1 | tail -40`
Expected: FAIL — `BandLadder` does not exist yet (build error).

- [ ] **Step 3: Write the implementation**

```swift
//
//  BandLadder.swift
//  Priors
//
//  SPEC §8.2 — the price never reaches the player as a number. Each of the
//  six templates gets seven authored phrases spanning its trait's prior
//  support (SPEC §3.1/§3.2), plus a matching scalar visual intensity.
//  Band count is fixed at 7: `experiments/perceived_price.py` found that
//  going to 9, 12 or 15 bands changes recovery cost by less than 0.002 MAE
//  at any noise level tested — the real lever is how distinctly each band's
//  visual intensity reads against its neighbours, not how many bands exist.
//  See FINDINGS.md.
//

import PriorsEngine

public enum BandLadder {
    /// SPEC §3.1/§3.2 — the trait's prior support. No template invents its
    /// own range; this mirrors SCHEMA/SPEC exactly, not `experiments/`.
    private static func range(for template: TemplateID) -> (lo: Double, hi: Double) {
        switch template {
        case .path, .detour, .trade: return (0.05, 0.85)   // theta_e
        case .error, .credit, .give: return (0.02, 0.70)   // theta_i
        }
    }

    /// 1-based band index in 1...7. Clamped at the edges rather than
    /// extrapolated — SPEC §4.1 already restricts candidate prices to the
    /// trait's support, so out-of-range input only happens from a caller bug,
    /// and clamping fails safe instead of crashing mid-session.
    public static func band(for price: Double, template: TemplateID) -> Int {
        let (lo, hi) = range(for: template)
        guard hi > lo else { return 1 }
        let t = (price - lo) / (hi - lo)
        let clamped = min(max(t, 0.0), 1.0)
        let raw = Int((clamped * 7.0).rounded(.down)) + 1
        return min(max(raw, 1), 7)
    }

    /// 0.0 at band 1, 1.0 at band 7, evenly spaced — the rendering layer
    /// (ThresholdNode / WaitingVillagerNode) maps this to darkness/fog alpha.
    public static func visualIntensity(band: Int) -> Double {
        let clamped = min(max(band, 1), 7)
        return Double(clamped - 1) / 6.0
    }

    /// Authored, fixed content — SPEC.md §8.2 treats this ladder as final
    /// wording, the way COPY.md treats the reading screens. Escalates
    /// severity across the trait's support without ever naming a number.
    public static func phrase(template: TemplateID, band: Int) -> String {
        let clamped = min(max(band, 1), 7)
        return ladders[template]![clamped - 1]
    }

    private static let ladders: [TemplateID: [String]] = [
        .path: [
            "The lane is only a little dark.",
            "Shadows pool at the edges of the path.",
            "The light doesn't reach as far as it should.",
            "You cannot see the far end.",
            "The dark presses in on both sides.",
            "The lantern is the only light left.",
            "It is black past the gate.",
        ],
        .detour: [
            "The gate looks like it will open easily.",
            "The gate is stiffer than it looks.",
            "The gate has been shut a while.",
            "The gate does not want to move.",
            "Something has swollen the wood shut.",
            "The gate has rusted into its frame.",
            "The gate has not opened in years.",
        ],
        .trade: [
            "The peddler's dice look fair.",
            "The peddler's dice look slightly worn.",
            "The peddler will not meet your eye.",
            "The peddler's smile does not move.",
            "The peddler has done this before.",
            "The peddler already has your one lantern in mind.",
            "The peddler is certain of something you are not.",
        ],
        .error: [
            "It is a short walk back.",
            "It is a walk you would rather not make twice.",
            "Going back costs you real time.",
            "Going back means retracing the whole path.",
            "Going back means losing the ground you made.",
            "Going back costs you most of what you have carried.",
            "Going back costs you the whole errand.",
        ],
        .credit: [
            "The thanks is small. Barely worth mentioning.",
            "The thanks is more than you did.",
            "The thanks is for work you can see was someone else's.",
            "The thanks is generous, and wrong.",
            "The thanks is the kind that gets repeated to others.",
            "The thanks is the kind that changes what people expect of you.",
            "The thanks is the kind that replaces someone else entirely.",
        ],
        .give: [
            "Giving costs you almost nothing.",
            "Giving costs you a little light.",
            "Giving means walking the rest of the way dimmer.",
            "Giving means the next stretch is yours to walk in the dark.",
            "Giving means going without for a long stretch.",
            "Giving means arriving with nothing left to give again.",
            "Giving means giving away the last light you have.",
        ],
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/BandLadderTests 2>&1 | tail -40`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/BandLadder.swift Priors/Priors/PriorsTests/BandLadderTests.swift
git commit -m "Add BandLadder: seven authored phrases per template, SPEC §8.2"
```

---

### Task 2: Re-fit the `rt_base` prior center in Python

**Files:**
- Modify: `priors-research/priors/agents.py:34` (`RT_BASE_LOGNORM`)
- Modify: `priors-research/priors/rt_posterior.py:56-59` (`RT_BASE_PRIOR_SD` docstring + `RT_BASE_GRID`), `priors-research/priors/rt_posterior.py:114-116` (prior computation)
- Modify: `priors-research/scripts/make_golden.py` (no code change — re-run to regenerate the fixture)
- Test: `priors-research/tests/test_agents.py`, `priors-research/tests/test_rt_posterior.py` (existing tests, re-run — do not add new hardcoded-2000 assumptions)

**Interfaces:**
- Consumes: nothing new.
- Produces: `agents.RT_BASE_LOGNORM = (log(1500.0), 0.4)`, `rt_posterior.RT_BASE_GRID` centred at 1500.0. `RT_BASE_PRIOR_SD` stays `0.8` — unchanged, do not touch.

**Why 1500ms, not 2000ms:** SPEC.md §8.3 says `rt_ms` becomes real hesitation — the time between entering a threshold's zone and resolving it — instead of button-click latency. Task 6 fixes the zone radius at 36pt (unchanged from the existing `ScenarioTriggerNode`) and the player's speed at 110pt/s (unchanged from `PlayerNode`), so a confident player crossing the zone diametrically takes `2×36/110 ≈ 655ms` of pure travel. Adding a plain perceptual/decision reaction time for reading the band phrase and deciding (typically several hundred ms to just over a second for a non-trivial judgement, not a simple reflex) puts an unhesitant baseline around **1500ms** — lower than 2000ms because walking a small zone at full speed is fast, but not as low as pure reaction time because reading and deciding isn't instant. This is a stated design assumption, not measured data (no real testers exist yet), exactly like SCHEMA §7.2's session-timing assumption — and it is safe to be approximately wrong about because `RT_BASE_PRIOR_SD` stays at 0.8, the value FINDINGS.md's `rt_base_prior.py` sweep showed keeps the channel flat (cost < 0.001 MAE) across population medians from 1200ms to 5000ms.

- [ ] **Step 1: Make the change in `agents.py`**

```python
# priors-research/priors/agents.py, replace line 34:
RT_BASE_LOGNORM = (np.log(1500.0), 0.4)
```

- [ ] **Step 2: Make the change in `rt_posterior.py`**

```python
# priors-research/priors/rt_posterior.py, replace lines 44-59 (the docstring
# comment above RT_BASE_PRIOR_SD stays conceptually the same; only the
# median changes):

#: Per-player baseline response time.
#:
#: SPEC §8.3 — this is real hesitation (time in a threshold's zone before
#: resolving), not button-click latency, once the in-world redesign ships.
#: 1500ms is a stated design assumption (zone radius 36pt at 110pt/s travel
#: speed, plus perceive-and-decide time), not measured data — see the
#: implementation plan's Task 2 for the derivation. The prior stays
#: deliberately weak regardless: `experiments/rt_base_prior.py` showed
#: `RT_BASE_PRIOR_SD = 0.8` keeps the channel flat (cost < 0.001 MAE) across
#: population medians from 1200ms to 5000ms, so being approximately wrong
#: about this number costs nothing once real tester data replaces it.
RT_BASE_PRIOR_SD = 0.8
RT_BASE_MEDIAN_MS = 1500.0
RT_BASE_GRID = np.geomspace(
    RT_BASE_MEDIAN_MS * np.exp(-2.4 * RT_BASE_PRIOR_SD),
    RT_BASE_MEDIAN_MS * np.exp(2.4 * RT_BASE_PRIOR_SD), 11
)
```

```python
# priors-research/priors/rt_posterior.py, in BehaviouralPosterior.__init__,
# replace the line:
#     -0.5 * ((np.log(self.rt_base) - np.log(2000.0)) / RT_BASE_PRIOR_SD) ** 2, 3
# with:
            -0.5 * ((np.log(self.rt_base) - np.log(RT_BASE_MEDIAN_MS)) / RT_BASE_PRIOR_SD) ** 2, 3
```

- [ ] **Step 3: Run the Python test suite**

Run: `cd /Users/gading/Documents/Priors/priors-research && .venv/bin/python -m pytest tests/ -q 2>&1 | tail -30`
Expected: all 165 tests still pass. If `test_constant_price_rt_is_uninformative_about_theta` or any RT test in `test_rt_posterior.py` fails because of the tolerance shift from the new center, read the failure: these tests assert *qualitative* safety properties (uninformativeness, calibration, peak-collapse), not the literal value 1500 vs 2000, so a failure means the assertion's numeric tolerance (e.g. `abs=0.02`) needs a small, documented widening to match the new grid spacing — not a change to the property being tested. Do not weaken a safety assertion's *direction*, only its numeric tolerance, and say why in the diff.

- [ ] **Step 4: Regenerate the golden fixture**

Run: `cd /Users/gading/Documents/Priors/priors-research && PYTHONPATH=. .venv/bin/python scripts/make_golden.py`
Expected: `wrote .../PriorsEngine/Tests/PriorsEngineTests/Fixtures/golden.json` with a `behavioural` section reflecting the new center.

- [ ] **Step 5: Commit**

```bash
cd /Users/gading/Documents/Priors
git add priors-research/priors/agents.py priors-research/priors/rt_posterior.py PriorsEngine/Tests/PriorsEngineTests/Fixtures/golden.json
git commit -m "Re-fit rt_base prior center to 1500ms for in-world hesitation (SPEC §8.3)"
```

---

### Task 3: Port the `rt_base` center to Swift

**Files:**
- Modify: `PriorsEngine/Sources/PriorsEngine/BehaviouralPosterior.swift:65-68`
- Test: `PriorsEngine/Tests/PriorsEngineTests/BehaviouralPosteriorGoldenTests.swift` (existing, re-run against the regenerated fixture from Task 2)

**Interfaces:**
- Produces: `BehaviouralPosterior.rtBaseMedianMs = 1500.0` (was `2000.0`). `rtBasePriorSD` unchanged at `0.8`.

- [ ] **Step 1: Confirm the golden test currently fails against the new fixture**

Run: `cd /Users/gading/Documents/Priors/PriorsEngine && swift test --filter BehaviouralPosteriorGoldenTests 2>&1 | tail -40`
Expected: FAIL — the fixture from Task 2 now encodes a different `rt_base` centre than the Swift constant, so the `behavioural` sequence's posterior means/SDs will mismatch.

- [ ] **Step 2: Make the change**

```swift
// PriorsEngine/Sources/PriorsEngine/BehaviouralPosterior.swift, replace
// lines 65-68:

    /// Prior width on the per-player baseline response time, in log space.
    ///
    /// SPEC §8.3 — `rt_base` is real hesitation now, not button-click
    /// latency. Weak regardless: `experiments/rt_base_prior.py` showed sd 0.8
    /// keeps the channel flat (cost < 0.001 MAE) across population medians
    /// from 1200ms to 5000ms — see the implementation plan's Task 2 for how
    /// 1500ms below was derived (it is a stated design assumption, not
    /// measured data). A test guards against tightening this casually.
    public static let rtBasePriorSD = 0.8

    /// The `rt_base` prior's centre. See Task 2 of the game-layer plan for
    /// the derivation (zone radius 36pt at 110pt/s travel speed, plus
    /// perceive-and-decide time).
    public static let rtBaseMedianMs = 1500.0
```

- [ ] **Step 3: Run the golden test to verify it passes**

Run: `cd /Users/gading/Documents/Priors/PriorsEngine && swift test --filter BehaviouralPosteriorGoldenTests 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 4: Run the full PriorsEngine suite**

Run: `cd /Users/gading/Documents/Priors/PriorsEngine && swift test 2>&1 | tail -10`
Expected: 78 tests, 0 failures (the count may grow slightly if Task 1's `BandLadderTests` live in the app target, not this package — confirm the count matches what was there before plus any package-level additions from this plan, currently none).

- [ ] **Step 5: Commit**

```bash
cd /Users/gading/Documents/Priors
git add PriorsEngine/Sources/PriorsEngine/BehaviouralPosterior.swift
git commit -m "Port rt_base prior center (1500ms) to Swift, matching regenerated goldens"
```

---

### Task 4: `LiveDecision` model, replacing `ScenarioPromptData`

**Files:**
- Create: `Priors/Priors/Priors/Village/LiveDecision.swift`
- Delete: `Priors/Priors/Priors/Village/ScenarioDialogView.swift` (both `ScenarioPromptData` and `ScenarioDialogView` — the modal and its data model are both removed; the phrase now renders inside `ThresholdNode`/`WaitingVillagerNode`, built in Tasks 6-7)
- Modify: `Priors/Priors/PriorsTests/PriorsTests.swift:238-250` (`scenarioPromptFormatting` test — rewritten against `LiveDecision`)

**Interfaces:**
- Consumes: `Design`, `TemplateID`, `Trait` from `PriorsEngine`; `BandLadder` from Task 1.
- Produces: `LiveDecision` struct with `design: Design`, `band: Int`, `phrase: String`, `visualIntensity: Double`, `isSpatial: Bool` (true for `.path`/`.detour`/`.trade`, false for `.error`/`.credit`/`.give`).

- [ ] **Step 1: Write the failing test (replacing the old one)**

```swift
// Priors/Priors/PriorsTests/PriorsTests.swift — replace the
// `scenarioPromptFormatting` test (lines 238-250) with:

    @Test func liveDecisionFormatting() async throws {
        let post = Posterior()
        let state = SelectionState()

        for slot in 0..<6 {
            let design = ADOSelector.selectDesign(posterior: post, slot: slot, state: state)
            let decision = LiveDecision(design: design)
            #expect(!decision.phrase.isEmpty)
            #expect(!decision.phrase.contains("%"))
            #expect(decision.band >= 1 && decision.band <= 7)
            #expect(decision.visualIntensity >= 0.0 && decision.visualIntensity <= 1.0)
            let expectedSpatial: Bool
            switch design.template {
            case .path, .detour, .trade: expectedSpatial = true
            case .error, .credit, .give: expectedSpatial = false
            }
            #expect(decision.isSpatial == expectedSpatial)
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/PriorsTests/liveDecisionFormatting 2>&1 | tail -40`
Expected: FAIL — `LiveDecision` does not exist.

- [ ] **Step 3: Delete `ScenarioDialogView.swift`**

```bash
git rm Priors/Priors/Priors/Village/ScenarioDialogView.swift
```

- [ ] **Step 4: Write `LiveDecision.swift`**

```swift
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/PriorsTests/liveDecisionFormatting 2>&1 | tail -40`
Expected: PASS.

**Note for the implementer:** this task leaves `VillageCoordinator.swift` and `VillageContainerView.swift` referencing the now-deleted `ScenarioPromptData`/`ScenarioDialogView` — the project will not build again until Tasks 9-11 finish rewiring them. That is expected; do not try to patch those references here. If you need an intermediate green build, stub `VillageCoordinator`'s references to the old names with `LiveDecision` equivalents inline as you go, but the full app target will not compile cleanly until Task 11 is done. `PriorsEngineTests` and `PriorsTests`-level unit tests that don't touch the view layer will still run.

- [ ] **Step 6: Commit**

```bash
git add Priors/Priors/Priors/Village/LiveDecision.swift Priors/Priors/PriorsTests/PriorsTests.swift
git commit -m "Add LiveDecision, remove ScenarioDialogView modal (SPEC §8.2/§8.3)"
```

---

### Task 5: `VillageMapBuilder` — trait-tagged decision locations

**Files:**
- Modify: `Priors/Priors/Priors/Village/VillageMapBuilder.swift:11-48` (`TriggerZoneInfo`, `ScenarioTriggerNode` stay as-is structurally but gain a `trait` field derived from the old `templateHint`), `:414-458` (`buildScenarioTriggers`, renamed and changed to not eagerly attach physics/visuals)
- Test: `Priors/Priors/PriorsTests/VillageMapBuilderTests.swift` (new)

**Interfaces:**
- Produces: `struct DecisionLocation: Sendable { let id: Int; let position: CGPoint; let regionName: String; let trait: Trait }`, `VillageMapBuilder.buildVillage(in:)` now also returns `decisionLocations: [DecisionLocation]` (replacing the `triggers: [ScenarioTriggerNode]` it used to return — no `ScenarioTriggerNode`s are built eagerly any more).
- Consumes: `Trait` from `PriorsEngine`.

**Why this shape:** the existing 30 hand-placed spots already split 19/11 between the theta_e-flavoured templates (PATH 12, DETOUR 4, TRADE 3) and the theta_i-flavoured ones (ERROR 4, CREDIT 3, GIVE 4) — exactly SPEC §5.1's slot counts. This task keeps every position and name, and narrows the per-spot label from a specific template hint (which nothing should hard-code, since SPEC §5.1 reserves template choice for ADO) down to just the trait the spot's geometry/flavour fits.

- [ ] **Step 1: Write the failing test**

```swift
// Priors/Priors/PriorsTests/VillageMapBuilderTests.swift
import Testing
import SpriteKit
@testable import Priors
import PriorsEngine

@Suite("VillageMapBuilder decision locations")
struct VillageMapBuilderTests {
    @Test func exactlyNineteenSpatialAndElevenSocialLocations() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let spatial = result.decisionLocations.filter { $0.trait == .thetaE }
        let social = result.decisionLocations.filter { $0.trait == .thetaI }
        #expect(spatial.count == 19)
        #expect(social.count == 11)
        #expect(result.decisionLocations.count == 30)
    }

    @Test func allLocationIDsAreUnique() async throws {
        let root = SKNode()
        let result = VillageMapBuilder.shared.buildVillage(in: root)
        let ids = Set(result.decisionLocations.map(\.id))
        #expect(ids.count == result.decisionLocations.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/VillageMapBuilderTests 2>&1 | tail -40`
Expected: FAIL — `decisionLocations` does not exist on the returned tuple yet.

- [ ] **Step 3: Add `DecisionLocation` and change `buildScenarioTriggers`**

```swift
// Priors/Priors/Priors/Village/VillageMapBuilder.swift — replace the
// TriggerZoneInfo/ScenarioTriggerNode block at lines 11-48 with:

import PriorsEngine

/// One of the 30 pre-built spots a decision can be armed at. Ordinary
/// scenery until VillageCoordinator arms it (SPEC §8.3) — no physics body,
/// no visual, until then.
public struct DecisionLocation: Sendable {
    public let id: Int
    public let position: CGPoint
    public let regionName: String
    /// theta_e -> a spatial threshold (PATH/DETOUR/TRADE); theta_i -> a
    /// waiting villager (ERROR/CREDIT/GIVE). SPEC §3.1/§3.2's split is
    /// exactly the trait split, so this one field is enough to route arming.
    public let trait: Trait
}

@MainActor
public class EyeNode: SKNode {
```

```swift
// Priors/Priors/Priors/Village/VillageMapBuilder.swift — replace
// buildScenarioTriggers (lines 414-458) with:

    /// 30 pre-built spots, unchanged in position/name from the original
    /// layout — only the label narrows from a specific template hint to the
    /// trait the spot's flavour fits (SPEC §5.1 reserves template choice for
    /// ADO, never a location).
    private func buildDecisionLocations() -> [DecisionLocation] {
        let configs: [(x: Int, y: Int, name: String, trait: Trait)] = [
            (25, 43, "r_cellar_nw", .thetaE), (55, 43, "r_elder_door", .thetaI),
            (20, 31, "r_weaver_porch", .thetaI), (58, 31, "r_smithy_forge", .thetaI),
            (25, 19, "r_woodcutter_shed", .thetaE), (51, 19, "r_farm_gate", .thetaE),
            (40, 35, "r_town_hall_steps", .thetaI), (40, 26, "r_crossroads_south", .thetaE),
            (32, 29, "r_west_bridge", .thetaE), (48, 29, "r_east_crossing", .thetaI),
            (28, 42, "r_north_hedge_gap", .thetaE), (52, 42, "r_north_lane", .thetaE),
            (16, 29, "r_deep_west_path", .thetaE), (64, 29, "r_deep_east_path", .thetaE),
            (40, 47, "r_north_clearing_edge", .thetaE), (40, 13, "r_south_mill_gate", .thetaE),
            (24, 25, "r_orchard_corner", .thetaI), (56, 25, "r_pond_pier", .thetaI),
            (36, 42, "r_hall_backdoor", .thetaI), (44, 42, "r_hall_cellar", .thetaE),
            (30, 20, "r_woodland_track", .thetaE), (50, 20, "r_pasture_stile", .thetaE),
            (38, 30, "r_well_square", .thetaI), (42, 30, "r_fountain_side", .thetaI),
            (18, 40, "r_northwest_meadow_trail", .thetaE), (62, 40, "r_northeast_meadow_trail", .thetaE),
            (18, 15, "r_southwest_forest_path", .thetaE), (62, 15, "r_southeast_lakeside", .thetaE),
            (35, 27, "r_peddler_stand", .thetaE), (45, 27, "r_lantern_rack", .thetaI),
        ]
        return configs.enumerated().map { index, cfg in
            DecisionLocation(
                id: index,
                position: CGPoint(x: CGFloat(cfg.x) * Self.tileSize, y: CGFloat(cfg.y) * Self.tileSize),
                regionName: cfg.name,
                trait: cfg.trait
            )
        }
    }
```

```swift
// Priors/Priors/Priors/Village/VillageMapBuilder.swift — change the
// buildVillage(in:) signature and body (was returning `triggers:
// [ScenarioTriggerNode]`; now returns `decisionLocations: [DecisionLocation]`):

    public func buildVillage(in rootNode: SKNode) -> (mapData: VillageMapData, decisionLocations: [DecisionLocation], eyeNode: EyeNode) {
        // ... unchanged steps 1-5 ...

        // 6. Decision locations (no physics/visuals until armed — SPEC §8.3)
        let decisionLocations = buildDecisionLocations()

        // 7. Build Eye Node
        // ... unchanged ...

        // ... unchanged steps 8 ...

        return (mapData, decisionLocations, eyeNode)
    }
```

Note: `ScenarioTriggerNode` the class (physics-body-carrying `SKNode` subclass) is deleted entirely here — Task 6 replaces it with `ThresholdNode`, which is armed on demand rather than built for all 30 spots up front.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsTests/VillageMapBuilderTests 2>&1 | tail -40`
Expected: PASS, both tests. (The exact 19/11 split assertion is the load-bearing regression check — if a future edit to the config table breaks the count, this test catches it immediately.)

**Note for the implementer:** `VillageScene.swift` still refers to the old `triggers: [ScenarioTriggerNode]` field and `ScenarioTriggerNode` type at this point (lines 24, 111-115 per the pre-existing file) — that will not compile until Task 9. Confirm this task's own new test target compiles and passes in isolation; the whole-scheme build stays red until Task 9.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/VillageMapBuilder.swift Priors/Priors/PriorsTests/VillageMapBuilderTests.swift
git commit -m "VillageMapBuilder: trait-tagged DecisionLocations replace eager ScenarioTriggerNodes"
```

---

### Task 6: `ThresholdNode` — the spatial live decision

**Files:**
- Create: `Priors/Priors/Priors/Village/ThresholdNode.swift`

**Interfaces:**
- Consumes: `LiveDecision` (Task 4), `PhysicsCategory` (existing, in `CharacterNode.swift`).
- Produces: `ThresholdNode(decision: LiveDecision)`, `.radius: CGFloat = 36.0`, `.commitRadius: CGFloat = 14.0`, `.setIntensity(_ intensity: Double)` (drives the darkness overlay alpha), the node's own `SKPhysicsBody` (sensor, `categoryBitMask = PhysicsCategory.trigger`).

**Geometry rationale:** `radius` (36pt) is unchanged from the old `ScenarioTriggerNode.radius`, so the existing zone-dwell tracking in `VillageScene` (Task 9) keeps working unmodified. `commitRadius` (14pt) is new — SPEC §8.3 defines crossing as `engaged: true` and leaving-without-crossing as `engaged: false`; this plan operationalises "crossing" as *having come within `commitRadius` of the threshold's centre before leaving the outer `radius`*, since the threshold is "approachable from any angle" (SPEC §3.1 draft wording, folded into §8.3) rather than a single directional line. 14pt is roughly 40% of the outer radius — close enough to the centre that a player who merely puts a toe in the zone and turns around does not count as having crossed, far enough out that a player walking through at any angle reliably passes inside it.

- [ ] **Step 1: Write `ThresholdNode.swift`**

(No isolated unit test here — this is a rendering/physics node whose behaviour is exercised end-to-end by `VillageScene`'s tests in Task 9. Writing a standalone test would require a live `SKPhysicsWorld` step loop, which the existing codebase doesn't do for `ScenarioTriggerNode` either; follow that precedent.)

```swift
//
//  ThresholdNode.swift
//  Priors
//
//  SPEC §8.3 — a spatial decision (PATH/DETOUR/TRADE) is a threshold the
//  player walks across, not a modal. Crossing (getting within `commitRadius`
//  before leaving `radius`) is engaged: true; entering and leaving without
//  ever reaching `commitRadius` is engaged: false. VillageScene tracks the
//  actual crossing/leaving transition (Task 9); this node only renders the
//  band phrase and the intensity, and carries the sensor physics body.
//

import SpriteKit

@MainActor
public final class ThresholdNode: SKNode {
    public let decision: LiveDecision
    public let radius: CGFloat = 36.0
    public let commitRadius: CGFloat = 14.0

    private let darknessOverlay: SKShapeNode
    private let phraseLabel: SKLabelNode

    public init(decision: LiveDecision) {
        self.decision = decision

        darknessOverlay = SKShapeNode(circleOfRadius: 36.0)
        darknessOverlay.fillColor = .black
        darknessOverlay.strokeColor = .clear
        darknessOverlay.zPosition = 4
        darknessOverlay.blendMode = .alpha

        phraseLabel = SKLabelNode(fontNamed: "Menlo")
        phraseLabel.fontSize = 12
        phraseLabel.fontColor = SKColor(white: 0.9, alpha: 0.9)
        phraseLabel.position = CGPoint(x: 0, y: 44)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        super.init()
        self.name = "threshold_live"
        self.zPosition = 3

        addChild(darknessOverlay)
        addChild(phraseLabel)
        setIntensity(decision.visualIntensity)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.trigger
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        self.physicsBody = body
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 0.0 (barely dimmed) to 1.0 (near-black) — SPEC §8.2's "matching visual
    /// intensity" per band, generic across templates for this pass. Bespoke
    /// per-template art (flame-gutter, wind-audible, etc.) is deferred to the
    /// art session (SPEC-GAME.md draft §6, not ratified into contract).
    public func setIntensity(_ intensity: Double) {
        let clamped = min(max(intensity, 0.0), 1.0)
        darknessOverlay.alpha = CGFloat(0.08 + clamped * 0.55)
    }
}
```

- [ ] **Step 2: Confirm the file compiles in isolation**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60`
Expected: this specific file compiles without errors (the overall build may still fail on other files not yet updated — Tasks 9-11 finish the rewiring. If the build error output at this point is specifically about `ThresholdNode.swift`, fix it before proceeding; if it is about `VillageScene.swift`/`VillageCoordinator.swift` referencing the old, now-removed `ScenarioTriggerNode` type, that's expected and resolved in Task 9).

- [ ] **Step 3: Commit**

```bash
git add Priors/Priors/Priors/Village/ThresholdNode.swift
git commit -m "Add ThresholdNode: spatial in-world decision rendering (SPEC §8.3)"
```

---

### Task 7: `WaitingVillagerNode` — the social live decision

**Files:**
- Create: `Priors/Priors/Priors/Village/WaitingVillagerNode.swift`

**Interfaces:**
- Consumes: `LiveDecision`, `VillageAssets` (existing, for villager textures/variants — same API `NPCNode` already uses: `VillageAssets.shared.npcIdleTexture(variant:)`, `.villagerVariantCount`).
- Produces: `WaitingVillagerNode(decision: LiveDecision, id: String)`, `.approachRadius: CGFloat = 40.0` (how close the player must be, facing the villager, for Interact to register), `.walkIn(to: CGPoint, from: CGPoint)` (scripted approach, mirrors `ShadowNode.walkToward`), `.isPlayerFacingAndClose(playerPosition: CGPoint, playerDirection: Direction) -> Bool`.

**Why no gaze/attention:** SPEC.md §8.3 (folded from draft §5.2) forbids villager attention that resembles watching, because it confounds the eye manipulation (SPEC §6.3). This node faces a fixed direction once it stops (toward wherever it walked in from, i.e. away from open space, not toward the player) and never turns to track the player — deliberately, so it cannot be mistaken for an attention cue.

- [ ] **Step 1: Write `WaitingVillagerNode.swift`**

```swift
//
//  WaitingVillagerNode.swift
//  Priors
//
//  SPEC §8.3 — a social decision (ERROR/CREDIT/GIVE) is a villager who
//  approaches, stops, and waits with the band phrase above them, not a
//  modal. Holding Interact while facing them resolves engaged: true;
//  walking away resolves engaged: false (VillageScene tracks this, Task 9).
//
//  Never turns to track the player — SPEC §8.3 forbids villager attention
//  that resembles watching, since it would confound the eye manipulation
//  (SPEC §6.3). This node picks its facing once, when it stops, and holds it.
//
//  Uses a straight-line SKAction.move for the walk-in, matching the existing
//  NPCNode/ShadowNode pattern. GameplayKit pathfinding is out of scope for
//  this plan (SPEC-GAME.md draft §5, not ratified into contract this pass).
//

import SpriteKit

@MainActor
public final class WaitingVillagerNode: SKNode {
    public let decision: LiveDecision
    public let villagerID: String
    public let approachRadius: CGFloat = 40.0

    private let sprite: SKSpriteNode
    private let phraseLabel: SKLabelNode
    private let variant: Int
    public private(set) var hasArrived: Bool = false

    public init(decision: LiveDecision, id: String) {
        self.decision = decision
        self.villagerID = id
        self.variant = abs(id.hashValue) % VillageAssets.shared.villagerVariantCount

        sprite = SKSpriteNode(texture: VillageAssets.shared.npcIdleTexture(variant: variant),
                               size: CGSize(width: 32, height: 32))
        sprite.zPosition = 9

        phraseLabel = SKLabelNode(fontNamed: "Menlo")
        phraseLabel.fontSize = 12
        phraseLabel.fontColor = SKColor(white: 0.9, alpha: 0.9)
        phraseLabel.position = CGPoint(x: 0, y: 30)
        phraseLabel.numberOfLines = 2
        phraseLabel.preferredMaxLayoutWidth = 160
        phraseLabel.horizontalAlignmentMode = .center
        phraseLabel.alpha = 0.0
        phraseLabel.text = decision.phrase
        phraseLabel.zPosition = 20

        super.init()
        self.name = "waiting_villager_\(id)"
        addChild(sprite)
        addChild(phraseLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Walks in a straight line from `from` to `to`, then shows the phrase
    /// and holds position. Speed matches NPCNode's wander speed (35pt/s) so
    /// arrival doesn't read as urgent or alarming.
    public func walkIn(to destination: CGPoint, from origin: CGPoint) {
        position = origin
        let dx = destination.x - origin.x, dy = destination.y - origin.y
        let dir = Direction.from(vector: CGVector(dx: dx, dy: dy))
        sprite.xScale = dir == .left ? -1 : 1
        let walkFrames = VillageAssets.shared.npcWalkCycle(variant: variant)
        let animate = SKAction.repeatForever(SKAction.animate(with: walkFrames, timePerFrame: 0.15))
        let distance = hypot(dx, dy)
        let move = SKAction.move(to: destination, duration: TimeInterval(distance / 35.0))
        sprite.run(animate, withKey: "villager_walk")

        run(SKAction.sequence([
            move,
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.sprite.removeAction(forKey: "villager_walk")
                self.sprite.texture = VillageAssets.shared.npcIdleTexture(variant: self.variant)
                self.hasArrived = true
                self.phraseLabel.run(.fadeAlpha(to: 1.0, duration: 0.4))
            },
        ]))
    }

    /// SPEC §8.3's "holding Interact while facing them" — approximated as
    /// "close enough, and has finished arriving." Facing is not checked
    /// against the player's exact heading (the existing Direction enum is
    /// 4-way and would make this needlessly finicky); proximity while the
    /// interact button is enabled (VillageScene only enables it near a live
    /// decision, Task 9) is the actual gate.
    public func isPlayerClose(playerPosition: CGPoint) -> Bool {
        hasArrived && hypot(playerPosition.x - position.x, playerPosition.y - position.y) <= approachRadius
    }
}
```

- [ ] **Step 2: Confirm the file compiles in isolation**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60`
Expected: no new errors attributable to `WaitingVillagerNode.swift` (other files still red until Task 9-11, as in Task 6).

- [ ] **Step 3: Commit**

```bash
git add Priors/Priors/Priors/Village/WaitingVillagerNode.swift
git commit -m "Add WaitingVillagerNode: social in-world decision rendering (SPEC §8.3)"
```

---

### Task 8: Press-and-hold Interact button

**Files:**
- Modify: `Priors/Priors/Priors/Village/VirtualControls.swift:16-18, 124-149`

**Interfaces:**
- Produces: `VirtualControlsView.onInteractPressChanged: ((Bool) -> Void)?` replaces `onInteract: (() -> Void)?`. Called with `true` when the button is pressed down, `false` when released — the caller (Task 11) measures hold duration itself.

**Why:** SPEC §8.3's social mechanic is "holding Interact while facing them," not a tap. A single `Button(action:)` only fires on release-inside; this plan needs press-start and press-end as two distinct events, tracked with a `DragGesture(minimumDistance: 0)` the same way the thumbstick already tracks continuous press state.

- [ ] **Step 1: Make the change**

```swift
// Priors/Priors/Priors/Village/VirtualControls.swift — replace lines 16-18:

    public var canInteract: Bool
    public var onVectorChange: ((CGVector) -> Void)?
    /// Fires `true` on press-down, `false` on release — SPEC §8.3's social
    /// mechanic needs hold duration, which a single tap action can't express.
    public var onInteractPressChanged: ((Bool) -> Void)?
```

```swift
// Priors/Priors/Priors/Village/VirtualControls.swift — replace the `init`
// parameter (line ~31) and the whole `interactButton` computed property
// (lines 124-149):

    public init(
        lanternCount: Int = 0,
        canInteract: Bool = false,
        onVectorChange: ((CGVector) -> Void)? = nil,
        onInteractPressChanged: ((Bool) -> Void)? = nil
    ) {
        self.lanternCount = lanternCount
        self.canInteract = canInteract
        self.onVectorChange = onVectorChange
        self.onInteractPressChanged = onInteractPressChanged
    }
```

```swift
    /// Dimmed and inert away from a live decision; solid and gently pulsing
    /// once one is armed. Press-and-hold, not tap — SPEC §8.3's social
    /// mechanic resolves on hold duration, tracked by the caller.
    private var interactButton: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(canInteract ? 0.85 : 0.2), lineWidth: 2)
                .background(Circle().fill(Color.black.opacity(canInteract ? 0.5 : 0.25)))
                .frame(width: 68, height: 68)
                .scaleEffect(canInteract && pulse ? 1.06 : 1.0)

            Text("Interact")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(canInteract ? 1.0 : 0.3))
        }
        .contentShape(Circle())
        .opacity(canInteract ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.25), value: canInteract)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard canInteract, !isPressed else { return }
                    isPressed = true
                    onInteractPressChanged?(true)
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onInteractPressChanged?(false)
                }
        )
        .onChange(of: canInteract) { _, live in
            pulse = false
            if isPressed { isPressed = false; onInteractPressChanged?(false) }
            guard live else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
```

```swift
// Priors/Priors/Priors/Village/VirtualControls.swift — add a new @State
// near the existing ones (line ~22):

    @State private var isPressed: Bool = false
```

- [ ] **Step 2: Confirm the file compiles in isolation**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -60`
Expected: no new errors attributable to `VirtualControls.swift` itself. `VillageContainerView.swift` will now fail to build because it still passes `onInteract:` — expected, fixed in Task 11.

- [ ] **Step 3: Commit**

```bash
git add Priors/Priors/Priors/Village/VirtualControls.swift
git commit -m "VirtualControls: interact button becomes press-and-hold, not tap"
```

---

### Task 9: `VillageScene` — arming and auto-resolution

**Files:**
- Modify: `Priors/Priors/Priors/Village/VillageScene.swift` (multiple regions: the `triggers`/`activeTrigger` state at lines 24, 36-38; `setupWorld()`'s trigger-building call at line 111-115; `updateTriggerProximity` at lines 314-361; `currentScenarioMetrics()` at lines 383-390)

**Interfaces:**
- Consumes: `DecisionLocation`, `ThresholdNode`, `WaitingVillagerNode`, `LiveDecision` from Tasks 4-7.
- Produces: `VillageScene.armDecision(_ decision: LiveDecision, at location: DecisionLocation)`, `VillageScene.setInteractPressed(_ pressed: Bool)`, `VillageScene.onLiveDecisionResolved: ((engaged: Bool, metrics: (approachFrac: Double, backtracks: Int, idleMs: Int)) -> Void)?`, `VillageScene.decisionLocations: [DecisionLocation]` (exposed read-only for `VillageCoordinator` to pick from), `VillageScene.canInteractNow: Bool` (drives the button's `canInteract` — true only near a live social decision, ready to hold).

**Mechanics:**
- Spatial: reuses the existing zone-dwell tracking (`zoneMinDistance`, `zoneIdleDuration`, `zoneBacktrackCount`) against the armed `ThresholdNode`'s `radius`/`commitRadius`. Resolution fires automatically the instant the player's distance from the node's centre exceeds `radius` again, having been inside it — `engaged = (zoneMinDistance <= node.commitRadius)`.
- Social: `HOLD_DURATION = 0.6` — the player must hold Interact continuously for 0.6s while within the villager's `approachRadius`. Resolution fires `engaged: true` the instant held time reaches 0.6s, or `engaged: false` if the player leaves `approachRadius` (a wider "decline" radius, `approachRadius * 2 = 80pt`, so walking away — not just stepping half a pace back — is what counts as declining) before holding long enough.

- [ ] **Step 1: Replace the trigger state and `setupWorld` wiring**

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — replace lines 20-38
// (Entities block through the trigger-proximity properties):

    // Entities
    public private(set) var playerNode: PlayerNode!
    public private(set) var npcs: [NPCNode] = []
    public private(set) var eyeNode: EyeNode!
    public private(set) var mapData: VillageMapData!
    public private(set) var decisionLocations: [DecisionLocation] = []

    // Camera & Lighting
    public private(set) var sceneCamera: SKCameraNode!
    public private(set) var lightingOverlay: SKSpriteNode!

    // Controls and Movement
    private var inputVector: CGVector = .zero
    public var movementSampler: MovementSampler?
    private var lastSampleTime: TimeInterval = 0.0

    // MARK: - Live decision (SPEC §8.3)
    //
    // Exactly one decision is ever live at a time. `armDecision` places
    // either a ThresholdNode (spatial) or a WaitingVillagerNode (social);
    // resolution is detected here, in `update(_:)`, and reported through
    // `onLiveDecisionResolved` rather than any button callback for spatial
    // decisions — the world resolves itself.
    private var armedThreshold: ThresholdNode?
    private var armedVillager: WaitingVillagerNode?
    public var onLiveDecisionResolved: (((engaged: Bool, metrics: (approachFrac: Double, backtracks: Int, idleMs: Int)) -> Void))?

    private var isInsideArmedZone: Bool = false
    private var isInteractHeld: Bool = false
    private var interactHoldStartTime: TimeInterval?
    private static let socialHoldDuration: TimeInterval = 0.6
```

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — in setupWorld(), replace
// the block:
//     self.triggers = buildResult.triggers
// with:
        self.decisionLocations = buildResult.decisionLocations
```

- [ ] **Step 2: Replace `updateTriggerProximity` with zone-dwell tracking against the armed node, plus interact-hold tracking**

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — replace the whole
// `updateTriggerProximity(currentTime:)` method (lines 314-361) with:

    /// True only when a social decision is armed and the player is close
    /// enough to start holding Interact — drives VirtualControlsView's
    /// `canInteract`.
    public var canInteractNow: Bool {
        guard let villager = armedVillager, let player = playerNode else { return false }
        return villager.isPlayerClose(playerPosition: player.position)
    }

    public func setInteractPressed(_ pressed: Bool) {
        isInteractHeld = pressed
        interactHoldStartTime = pressed ? nil : interactHoldStartTime
    }

    private func updateArmedDecision(currentTime: TimeInterval) {
        guard let player = playerNode else { return }

        if let threshold = armedThreshold {
            let dist = hypot(player.position.x - threshold.position.x,
                              player.position.y - threshold.position.y)
            let inZone = dist <= threshold.radius

            if inZone, !isInsideArmedZone {
                isInsideArmedZone = true
                zoneEntryTime = currentTime
                zoneLastMovementTime = currentTime
                zoneIdleDuration = 0.0
                zoneMinDistance = dist
                zoneBacktrackCount = 0
                zonePreviousDirection = player.currentDirection
            } else if inZone {
                if player.isMoving {
                    zoneLastMovementTime = currentTime
                    if let prevDir = zonePreviousDirection, prevDir != player.currentDirection,
                       isOpposite(prevDir, player.currentDirection) {
                        zoneBacktrackCount += 1
                    }
                    zonePreviousDirection = player.currentDirection
                } else {
                    zoneIdleDuration += (currentTime - zoneLastMovementTime)
                    zoneLastMovementTime = currentTime
                }
                zoneMinDistance = min(zoneMinDistance, dist)
            } else if isInsideArmedZone {
                // Left the zone: resolve now. Crossing = got within
                // commitRadius before leaving; otherwise a decline.
                isInsideArmedZone = false
                let engaged = zoneMinDistance <= threshold.commitRadius
                let metrics = currentZoneMetrics(zoneRadius: threshold.radius)
                threshold.removeFromParent()
                armedThreshold = nil
                onLiveDecisionResolved?((engaged: engaged, metrics: metrics))
            }
            return
        }

        if let villager = armedVillager {
            let close = villager.isPlayerClose(playerPosition: player.position)
            let declineDistance = villager.approachRadius * 2.0
            let dist = hypot(player.position.x - villager.position.x,
                              player.position.y - villager.position.y)

            if close, isInteractHeld {
                if interactHoldStartTime == nil { interactHoldStartTime = currentTime }
                if currentTime - (interactHoldStartTime ?? currentTime) >= Self.socialHoldDuration {
                    let metrics = (approachFrac: 1.0, backtracks: 0,
                                   idleMs: Int((currentTime - zoneEntryTime) * 1000))
                    villager.removeFromParent()
                    armedVillager = nil
                    interactHoldStartTime = nil
                    onLiveDecisionResolved?((engaged: true, metrics: metrics))
                }
                return
            }
            interactHoldStartTime = nil

            if villager.hasArrived, zoneEntryTime == 0.0, dist <= declineDistance {
                zoneEntryTime = currentTime
            }
            if villager.hasArrived, dist > declineDistance, zoneEntryTime > 0.0 {
                let metrics = (approachFrac: close ? 1.0 : 0.5, backtracks: 0,
                               idleMs: Int((currentTime - zoneEntryTime) * 1000))
                villager.removeFromParent()
                armedVillager = nil
                zoneEntryTime = 0.0
                onLiveDecisionResolved?((engaged: false, metrics: metrics))
            }
        }
    }

    private func isOpposite(_ a: Direction, _ b: Direction) -> Bool {
        (a == .down && b == .up) || (a == .up && b == .down)
            || (a == .left && b == .right) || (a == .right && b == .left)
    }

    private func currentZoneMetrics(zoneRadius: CGFloat) -> (approachFrac: Double, backtracks: Int, idleMs: Int) {
        let approach = max(0.0, min(1.0, Double(1.0 - (zoneMinDistance / zoneRadius))))
        return (approachFrac: approach, backtracks: zoneBacktrackCount, idleMs: Int(zoneIdleDuration * 1000))
    }
```

- [ ] **Step 3: Replace `currentScenarioMetrics()` and wire `armDecision`, and call the new update method from `update(_:)`**

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — delete the old
// `currentScenarioMetrics()` method (lines 383-390); its job is now done by
// `currentZoneMetrics` above, called at resolution time rather than queried
// on demand.
```

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — in update(_:), replace
// the line:
//     updateTriggerProximity(currentTime: currentTime)
// with:
        updateArmedDecision(currentTime: currentTime)
```

```swift
// Priors/Priors/Priors/Village/VillageScene.swift — add near
// spawnShadow/triggerEye (MARK: In-Village Events):

    /// SPEC §8.3 — arms exactly one decision at a time. Removes whatever was
    /// previously armed first (should never happen in practice, since
    /// VillageCoordinator only arms the next slot after the current one
    /// resolves, but this keeps the invariant true even under a
    /// double-call).
    public func armDecision(_ decision: LiveDecision, at location: DecisionLocation) {
        armedThreshold?.removeFromParent()
        armedThreshold = nil
        armedVillager?.removeFromParent()
        armedVillager = nil
        isInsideArmedZone = false
        interactHoldStartTime = nil
        zoneEntryTime = 0.0

        if decision.isSpatial {
            let node = ThresholdNode(decision: decision)
            node.position = location.position
            worldNode.addChild(node)
            armedThreshold = node
        } else {
            let node = WaitingVillagerNode(decision: decision, id: "social_\(location.id)")
            let approachOffset = CGPoint(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: -60...60))
            worldNode.addChild(node)
            node.walkIn(to: location.position,
                        from: CGPoint(x: location.position.x + approachOffset.x,
                                       y: location.position.y + approachOffset.y))
            armedVillager = node
        }
    }
```

- [ ] **Step 4: Confirm the file compiles in isolation**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -80`
Expected: `VillageScene.swift` itself compiles. `VillageCoordinator.swift` and `VillageContainerView.swift` still reference the old API (`activeTrigger`, `onActiveTriggerChanged`, `currentScenarioMetrics()`) — expected, fixed in Tasks 10-11.

- [ ] **Step 5: Commit**

```bash
git add Priors/Priors/Priors/Village/VillageScene.swift
git commit -m "VillageScene: arm/resolve exactly one live decision at a time (SPEC §8.3)"
```

---

### Task 10: `VillageCoordinator` — arm/resolve loop

**Files:**
- Modify: `Priors/Priors/Priors/Village/VillageCoordinator.swift` (the `activePrompt`/`isPresentingScenario` state at lines 26-27; `presentCurrentScenario` at lines 69-96; `handleChoice` at lines 98-177)
- Modify: `Priors/Priors/Priors/Village/VillageContainerView.swift` (removes the `ScenarioDialogView` presentation and the tap-based `onInteract`, wires press/hold and arming — this file is touched here rather than a separate task because it cannot compile independently of `VillageCoordinator`'s new API)

**Interfaces:**
- Produces: `VillageCoordinator.armNextDecision(scene:)` (replaces `presentCurrentScenario`), `VillageCoordinator.resolveLiveDecision(engaged:metrics:movementSampler:scene:)` (replaces `handleChoice`). Still uses choice-only `Posterior` in this task — the switch to `BehaviouralPosterior` is Task 12, after this task proves the mechanics work end-to-end with real `rt_ms`.

- [ ] **Step 1: Replace the presentation state and `presentCurrentScenario`**

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — replace lines
// 26-27:

    public var lanternCount: Int = 3
    public var liveDecision: LiveDecision?
```

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — replace
// presentCurrentScenario (lines 69-96) with:

    /// SPEC §8.3 — arms the next ADO slot's design at whichever pre-built
    /// location's trait matches, nearest to the player. Exactly one decision
    /// is live at a time: this keeps ADO fully adaptive, since the design for
    /// slot N+1 is only computed after slot N's response is known.
    @MainActor
    public func armNextDecision(scene: VillageScene) {
        guard currentSlot < Scenarios.decisionCount else { return }
        guard liveDecision == nil else { return }

        let design = ADOSelector.selectDesign(
            posterior: posterior,
            slot: currentSlot,
            state: selectionState
        )
        let decision = LiveDecision(design: design)
        let wantedTrait = decision.isSpatial ? Trait.thetaE : Trait.thetaI
        let candidates = scene.decisionLocations.filter {
            $0.trait == wantedTrait && !usedLocationIDs.contains($0.id)
        }
        guard let player = scene.playerNode else { return }
        guard let nearest = candidates.min(by: { a, b in
            let da = hypot(a.position.x - player.position.x, a.position.y - player.position.y)
            let db = hypot(b.position.x - player.position.x, b.position.y - player.position.y)
            return da < db
        }) else {
            assertionFailure("slot \(currentSlot): no unused \(wantedTrait) location left")
            return
        }
        usedLocationIDs.insert(nearest.id)

        let now = ContinuousClock.now
        scenarioPresentationInstant = now
        scenarioPresentationSeconds = monotonicSecondsSinceStart(at: now)

        liveDecision = decision
        scene.armDecision(decision, at: nearest)

        if shadowSlots.contains(currentSlot) {
            triggerShadowPrediction(nextDesign: design, in: scene)
        }
        if currentSlot == eyeDecisionIndex && eyeTimestamp == nil {
            triggerEyeEvent(in: scene)
        }
    }
```

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — add near the
// other stored properties (next to `shadowSlots`):

    private var usedLocationIDs: Set<Int> = []
```

- [ ] **Step 2: Replace `handleChoice` with `resolveLiveDecision`**

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — replace
// handleChoice (lines 98-177) with:

    @MainActor
    public func resolveLiveDecision(
        engaged: Bool,
        metrics: (approachFrac: Double, backtracks: Int, idleMs: Int),
        movementSampler: MovementSampler,
        scene: VillageScene
    ) {
        guard let decision = liveDecision else { return }
        let design = decision.design

        let now = ContinuousClock.now
        let presentationTime = scenarioPresentationInstant ?? now
        let duration = now - presentationTime
        let rtMs = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        let tDecided = monotonicSecondsSinceStart(at: now)

        let (meanE, sdE) = posterior.meanSD(.thetaE)
        let (meanI, sdI) = posterior.meanSD(.thetaI)
        let predictedEngage = posterior.predictedEngage(price: design.price, trait: design.trait)

        let (inEyeWindow, eyeSide) = EventTriggers.eyeWindow(
            tPresented: scenarioPresentationSeconds,
            eyeTimestamp: eyeTimestamp
        )

        let record = DecisionRecord(
            index: currentSlot,
            template: design.template,
            trait: design.trait,
            skin: design.skin,
            price: design.price,
            engaged: engaged,
            tPresented: scenarioPresentationSeconds,
            tDecided: tDecided,
            rtMs: rtMs,
            approachFrac: metrics.approachFrac,
            backtracks: metrics.backtracks,
            idleMs: metrics.idleMs,
            eyeWindow: inEyeWindow,
            eyeSide: eyeSide,
            posteriorMeanE: meanE,
            posteriorSDE: sdE,
            posteriorMeanI: meanI,
            posteriorSDI: sdI,
            predictedEngage: predictedEngage,
            isRepeatOf: design.isRepeatOf
        )

        decisions.append(record)

        posterior.update(price: design.price, trait: design.trait, engaged: engaged)
        selectionState.commit(design)

        updateLanternCount(for: design.template, engaged: engaged, price: design.price)

        let newSdE = posterior.meanSD(.thetaE).sd
        scene.updateDusk(forMeanPosteriorSD: newSdE)
        AudioManager.shared.updateDecay(meanPosteriorSD: newSdE)

        liveDecision = nil
        currentSlot += 1

        if currentSlot >= Scenarios.decisionCount {
            finishSession(movementSampler: movementSampler, scene: scene)
        } else {
            armNextDecision(scene: scene)
        }
    }
```

- [ ] **Step 3: Rewire `VillageContainerView.swift`**

```swift
// Priors/Priors/Priors/Village/VillageContainerView.swift — replace the
// whole body's VirtualControlsView + ScenarioDialogView block (lines 43-72)
// with:

            VirtualControlsView(
                lanternCount: coordinator.lanternCount,
                canInteract: villageScene.canInteractNow,
                onVectorChange: { vector in
                    villageScene.setInputVector(vector)
                },
                onInteractPressChanged: { pressed in
                    villageScene.setInteractPressed(pressed)
                }
            )
```

```swift
// Priors/Priors/Priors/Village/VillageContainerView.swift — replace the
// `.onAppear` block's trigger/lantern wiring (lines 74-91) with:

        .onAppear {
            movementSampler.start()
            AudioManager.shared.startVillageAudio()
            coordinator.onSessionComplete = { @MainActor record in
                onComplete(record)
            }
            villageScene.onLiveDecisionResolved = { result in
                coordinator.resolveLiveDecision(
                    engaged: result.engaged,
                    metrics: result.metrics,
                    movementSampler: movementSampler,
                    scene: villageScene
                )
            }
            villageScene.onLanternDelivered = { remaining in
                coordinator.lanternCount = remaining
            }
            villageScene.onLanternsRefilled = { remaining in
                coordinator.lanternCount = remaining
            }
            coordinator.armNextDecision(scene: villageScene)
        }
```

Note: `canInteract` needs to update live as the player moves, but SwiftUI's `@State private var villageScene` doesn't automatically re-render on the scene's internal mutation of `canInteractNow`. Poll it the same way `onActiveTriggerChanged` used to push updates — add a small `@State private var canInteract: Bool = false` and a per-frame check. The simplest fix consistent with the existing codebase's patterns:

```swift
// Priors/Priors/Priors/Village/VillageContainerView.swift — add a
// @State property near `canInteract` (remove the old `canInteract` state
// that mirrored `activeTrigger`, replace with a timer-polled version):

    @State private var canInteract: Bool = false
    @State private var pollTimer: Timer?
```

```swift
// and change the VirtualControlsView call's canInteract argument from
// `villageScene.canInteractNow` to the polled `canInteract` state, and add
// to `.onAppear`:

            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in canInteract = villageScene.canInteractNow }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
```

- [ ] **Step 4: Build and fix remaining references**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -100`
Expected: build succeeds. If there are remaining compile errors referencing `activePrompt`, `isPresentingScenario`, `activeTrigger`, `onActiveTriggerChanged`, `currentScenarioMetrics`, or `ScenarioPromptData` anywhere (e.g. `VillageCoordinator`'s own leftover reference at the old `activePrompt` declaration, or any other file this plan's grep didn't catch), remove/replace them following the same pattern as above — those are the exact names this task's rewiring is meant to retire.

- [ ] **Step 5: Run the full app test suite**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -100`
Expected: all unit tests pass. UI tests that specifically exercised the old modal (`scenario_engage_button`/`scenario_decline_button` — confirmed in this plan's research that no UI test currently references those identifiers, so none should need rewriting; if one does turn up, update it to drive the new press-and-hold/threshold-crossing flow instead of tapping a button).

- [ ] **Step 6: Commit**

```bash
git add Priors/Priors/Priors/Village/VillageCoordinator.swift Priors/Priors/Priors/Village/VillageContainerView.swift
git commit -m "VillageCoordinator/VillageContainerView: arm/resolve loop replaces modal (SPEC §8.3)"
```

---

### Task 11: Render and look at it before wiring further

**Files:** none modified — verification only, per the standing project lesson ("render every asset and look at it before wiring it in").

- [ ] **Step 1: Launch the village phase directly and capture a screenshot**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PriorsUITests/VillageAppearanceTests 2>&1 | tail -40`

- [ ] **Step 2: Extract the attachment**

Run: `xcrun xcresulttool export attachments --path <path-to-latest .xcresult from the test output above> --output-path /tmp/village-screenshot`

- [ ] **Step 3: Read the extracted image**

Use the Read tool on the extracted PNG. Confirm, by looking:
- A `ThresholdNode` or `WaitingVillagerNode` is visible and armed near the player's spawn point (the test may need a brief `-startPhase village` wait for `armNextDecision` to fire on appear).
- The darkness overlay / phrase label render legibly, not as a black square or missing texture (the "well" and "walking wells" lessons in AGENT-LOG.md are exactly this failure mode).
- No leftover modal or percentage text appears anywhere on screen.

If anything looks wrong, fix it before proceeding — do not report Task 10 as visually correct on the basis of it compiling and the unit tests passing alone.

- [ ] **Step 4: No commit** (verification only; if fixes were needed, they belong to whichever earlier task's file they touch — commit there, not here.)

---

### Task 12: Switch `VillageCoordinator` to `BehaviouralPosterior`

**Files:**
- Modify: `Priors/Priors/Priors/Village/VillageCoordinator.swift:22` (`posterior` type) and the two call sites that call `.update(price:trait:engaged:)` (now Task 10's `resolveLiveDecision`) and `.meanSD` / `.predictedEngage` (already trait-generic method names shared by both types per `ChoicePosterior`, per `BehaviouralPosterior.swift`'s `protocol ChoicePosterior` conformance — confirm the exact shared protocol surface before assuming no other call sites need changes)

**Interfaces:**
- Produces: `VillageCoordinator.posterior: BehaviouralPosterior` (was `Posterior`). `resolveLiveDecision` now passes `rtMs: Double(rtMs)` into `.update(...)`.

**Why last:** SPEC.md §8.3 and the plan's Global Constraints are explicit that this switch only makes sense once `rt_ms` is real hesitation, which Tasks 6-10 just made true. Doing this earlier would have fed `BehaviouralPosterior` the old click-latency numbers, which is exactly the "feeding it the wrong hesitation" failure the whole session started from.

**Confirmed, not speculative:** `ADOSelector.selectDesign(posterior: some ChoicePosterior, slot:, state:, jitter:)` (`ADOSelector.swift:166-171`) is already generic over `ChoicePosterior`, and `BehaviouralPosterior: Sendable, ChoicePosterior` already conforms (`BehaviouralPosterior.swift:47`, satisfying the protocol's `thetaE`/`thetaI`/`beta`/`traitBetaMarginal`/`meanSD` requirements at `ADOSelector.swift:36-48`). No signature changes are needed anywhere in `ADOSelector.swift` — only `VillageCoordinator`'s stored property type changes.

- [ ] **Step 1: Make the type change**

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — replace line 22:

    public var posterior = BehaviouralPosterior()
```

- [ ] **Step 2: Feed real `rtMs` into the update call**

```swift
// Priors/Priors/Priors/Village/VillageCoordinator.swift — in
// resolveLiveDecision (Task 10), replace:
//     posterior.update(price: design.price, trait: design.trait, engaged: engaged)
// with:
        posterior.update(price: design.price, trait: design.trait, engaged: engaged, rtMs: Double(rtMs))
```

- [ ] **Step 3: Build and run the full app test suite**

Run: `cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -100`
Expected: all tests pass. If any test constructed `VillageCoordinator` and asserted specifically on `Posterior`-typed behaviour (check `PriorsTests.swift`'s coordinator-flow test, the one asserting `record.finalPosterior.thetaEMean > 0` around line 230), confirm it still passes — `BehaviouralPosterior.snapshot()` produces the same `PosteriorSnapshot` shape, so this should need no test changes, but verify rather than assume.

- [ ] **Step 4: Commit**

```bash
git add Priors/Priors/Priors/Village/VillageCoordinator.swift
git commit -m "VillageCoordinator: read BehaviouralPosterior now that rt_ms is real hesitation"
```

---

### Task 13: Full verification and AGENT-LOG entry

**Files:**
- Modify: `AGENT-LOG.md` (append — do not rewrite prior entries)

- [ ] **Step 1: Run every suite named in the session's verification gate**

```bash
cd /Users/gading/Documents/Priors/PriorsEngine && swift test 2>&1 | tail -10
cd /Users/gading/Documents/Priors/priors-research && .venv/bin/python -m pytest tests/ -q 2>&1 | tail -10
cd /Users/gading/Documents/Priors/Priors/Priors && xcodebuild -project Priors.xcodeproj -scheme Priors -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```
Expected: all three green, with the actual test counts recorded (they will have grown from 78/165/33+9 by however many this plan's tasks added — `BandLadderTests`, `VillageMapBuilderTests`, and the rewritten `liveDecisionFormatting`/coordinator tests).

- [ ] **Step 2: Screenshot the village once more, end to end**

Repeat Task 11's screenshot capture. Confirm visually that a full arm→resolve→re-arm cycle is at least plausible from a single frame (a live decision is visibly present, its phrase is legible, the darkness/label render correctly at more than one band — try forcing a high-band price by walking through several decisions and observing the darkness overlay actually varies).

- [ ] **Step 3: Append the AGENT-LOG.md entry**

Follow the existing entries' structure (Status / Files touched / What was verified / narrative / Assumptions made / Open questions). Report the true state — if any task's step above required deviating from this plan's exact code (a signature that didn't match, a test tolerance that needed widening), say so plainly, the way prior entries in this file already do (the "well" correction, the five-defects correction). Do not claim done anything this plan's own verification steps didn't actually confirm.

- [ ] **Step 4: Commit**

```bash
git add AGENT-LOG.md
git commit -m "Session record: in-world decisions + rt_base refit implemented and verified"
```

---

## Self-review notes (from the plan author, not a task)

- **Spec coverage:** §8.2 (Task 1, 4), §8.3 spatial (Tasks 5, 6, 9), §8.3 social (Tasks 5, 7, 8, 9), §8.3's `rt_base` re-fit clause (Tasks 2, 3, 12) are each covered. Villagers'/art's/audio's constraints (no faces, no watching, no score) are respected by construction (Task 7's no-gaze note, no new score/HUD element anywhere in this plan) rather than by a dedicated task, since this plan does not touch those subsystems.
- **Deliberately out of scope, confirmed against the Global Constraints:** GameplayKit pathfinding/avoidance/state machines, procedural sprites, audio. None of this plan's tasks introduce them.
- **Known follow-up, not a defect:** template-to-location visual correspondence (a PATH decision arming at a spot originally laid out for DETOUR) is possible under Task 5's trait-only matching and is explicitly accepted, not fixed, in this pass — flagged in Task 5's own description.
