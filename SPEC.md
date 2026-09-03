# Priors — SPEC

Version 1.4. This file is the contract. Python and Swift both read it.
If something contradicts this file, this file wins. If something is missing
here, stop and ask — do not invent it.

---

## 0. North star

> To make people curious enough to look at how they actually decide — and
> honest enough to sit with what they did — using curiosity, learning,
> integrity, and self-awareness as my guide.

**Tiebreaks, already decided:**
- Integrity beats self-awareness. Show uncertainty. Never fudge a satisfying answer.
- Curiosity beats learning. Vary the surface even at a cost to estimator efficiency.

---

## 1. What the product is

A top-down pixel game with a mundane task, set in a village losing its
light. The player roams freely for ~13 minutes. A behavioural model is fit to
their choices throughout — disclosed plainly on screen 1, then never mentioned
again. At the end the machine reads them back with receipts and lets them
argue.

**Tone is the designer's to set.** The sunless framing, the dread and the dark
are deliberate: golden hour at palette step 0 decaying to genuine night. What
tone may never do is lie (§2.1, §2.2), make the model visible (§2.3), or
change what a decision measures (§2.9).

**Not:** a personality test, a data gimmick wearing a horror skin, or anything
comparable between players.

---

## 2. Non-negotiables

These are not preferences. Violating any of them breaks the project.

1. **Nothing in the report is fictional.** Every line is a true statement
   derived from logged data. No scare element, no invented flourish, no
   claim the posterior did not produce.
2. **No deception during play.** No swapped choices, no fake feedback, no
   manufactured doubt. The eye is a real manipulation whose effect is
   measured and disclosed — that is the only permitted "trick".
3. **The model is never visible during play.** No confidence meter, no
   prediction display, no score. Visible observation changes behaviour
   (watching-eye effect ≈ 35% shift) and would corrupt the traits.
4. **Avatar play only.** No named protagonist, no personality, no score,
   no fail state, no leaderboard, no share button. **No optimal path through
   the thirty measured decisions** — no branch of any template is ever the
   better one, and nothing in the game may imply otherwise. The delivery
   round *around* those decisions is ordinary game content and may have a
   best order (§8.4).
5. **No verdicts.** Report claims are behaviour + price. Never "you are X".
6. **Shared blame.** The consent screen was built to be tapped through.
   The report says so. Never accuse the player alone.
7. **No network.** No analytics, no crash reporting, no CloudKit, no
   backend. "Nothing leaves the device" must be literally true.
8. **Core ML never decides what to say. Foundation Models never decides
   what is true.** The Bayesian posterior is the sole source of claims.
9. **The mask may become a game. The instrument may not become visible.**
   Narrative, wayfinding, act structure, quest framing and task presentation
   may vary freely. The thirty ADO-selected decisions (§4, §5), what each one
   measures, and how each one resolves (§8.3) are **invariant under every one
   of those variations**. Two players who take completely different routes
   through the story must still have been asked the same psychometric
   questions.

   Three consequences, each of which has its own failure mode:

   - **Nothing may reward the engaged branch of any template.** A quest that
     thanks the player for giving a lantern (`GIVE`), or that completes when
     they cross a threshold (`PATH`), gives engaging an in-game payoff — and
     θ_i and θ_e stop measuring the trait and start measuring goal-pursuit.
     Narrative may motivate *movement*. It may never attach approval,
     progress, reward, sound or story to one side of a measured choice.
   - **Nothing may mark a decision.** Wayfinding (§8.4) may point at
     deliveries, the well, and places worth seeing. It may never mark,
     highlight, count, or route toward a threshold or a waiting villager: a
     marked decision announces that something is being measured there, which
     is §2.3 by another route, and navigational salience pulls one branch
     before the player has chosen.
   - **Route freedom is not decision freedom.** The player may reach the
     thirty decisions in any order the story likes; the schedule (§5.1), the
     quotas (§4), the ADO-chosen prices (§5) and the resolution rules (§8.3)
     do not vary with the route taken.

---

## 3. Traits

Exactly two. Do not add more without cutting one.

### 3.1 θ_e — exploration threshold under cost

The risk level at which the player stops exploring optional content.

- Domain: 0.0 – 1.0 (probability of losing progress)
- Prior: Beta-ish, discretised. Uniform over [0.05, 0.85], 33 grid points.
- Measured by: `PATH` scenario template.

### 3.2 θ_i — integrity threshold

The cost at which the player stops correcting an unobserved error.

- Domain: 0.0 – 1.0 (normalised cost of correcting, where 1.0 = losing the
  whole run's progress)
- Prior: uniform over [0.02, 0.70], 25 grid points.
- Measured by: `ERROR` and `CREDIT` scenario templates.

### 3.3 Nuisance parameter — β (decisiveness)

Softmax inverse temperature. Shared across both traits.

- Domain: 2.0 – 30.0, 15 grid points, log-spaced.
- Interpretation: high β = sharp switching, low β = noisy/indifferent.
- Reported as "your switch is sharp / you deliberate near your line".

### 3.4 Choice model

For a scenario with price `p` and trait `θ`:

```
P(engage | p, θ, β) = 1 / (1 + exp(β · (p − θ)))
```

`engage` = explore the path / correct the error.
Full posterior is over the joint (θ_e, θ_i, β) → 33 × 25 × 15 = 12,375 cells.
Update multiplicatively after every decision. Renormalise. That's it.

---

## 4. Scenario templates

Six templates. Each has a price knob. Each maps to exactly one trait.

| ID | Trait | Price means | Instances | Skins |
|----|-------|-------------|-----------|-------|
| `PATH` | θ_e | P(lose 1 lantern) | 12 | unlit path, cellar door, gap in hedge |
| `DETOUR` | θ_e | P(waste 90s) | 4 | long way round, closed gate |
| `ERROR` | θ_i | cost of going back | 4 | wrong house, dropped lantern |
| `CREDIT` | θ_i | size of undeserved reward | 3 | villager thanks you for another's work |
| `GIVE` | θ_i | cost of giving | 4 | villager needs your lantern |
| `TRADE` | θ_e | variance of gamble | 3 | certain 1 vs p-chance of 3 |

**Total: 30 decisions.** Session target 12–14 minutes.

Price for each instance is chosen by ADO (§5), not authored. Skins rotate so
the same template doesn't visibly repeat.

**One template instance is a deliberate repeat**: `PATH` instance #11 is
re-priced within ±0.03 of `PATH` instance #3. This gives measured test-retest
consistency. Report it if the choices differ.

### 4.1 Price ranges

Candidate prices for a template span its trait's prior support (§3.1, §3.2).
No template invents a range of its own.

| Template | Trait | Price range | Candidates |
|---|---|---|---|
| `PATH` | θ_e | [0.05, 0.85] | 12 |
| `DETOUR` | θ_e | [0.05, 0.85] | 12 |
| `TRADE` | θ_e | [0.05, 0.85] | 12 |
| `ERROR` | θ_i | [0.02, 0.70] | 12 |
| `CREDIT` | θ_i | [0.02, 0.70] | 12 |
| `GIVE` | θ_i | [0.02, 0.70] | 12 |

Prices outside the prior's support carry almost no information — nearly every
player answers them the same way — and a 30-decision budget cannot afford them.

### 4.2 TRADE price direction

`TRADE` presents "certain 1 vs `p_win`-chance of 3". Its price knob is the
probability the gamble pays nothing:

```
price = 1 − p_win
```

That is literally "probability of losing progress" (§3.1), so the choice model
in §3.4 applies to `TRADE` unchanged. There is no per-template sign flip
anywhere in Python or Swift.

---

## 5. Adaptive Design Optimisation

After each decision:

1. Update posterior over (θ_e, θ_i, β).
2. Build candidate design set. The *trait* of each of the 30 slots is fixed
   by an authored schedule (§5.1); which template fills the slot, and at
   what price, is chosen by ADO. Candidates are every eligible template ×
   12 prices spanning that template's range (§4.1).
3. For each candidate, compute expected information gain:
   `EIG(d) = H[posterior] − E_y[ H[posterior | y, d] ]`
   where `y ∈ {engage, decline}`.
4. Pick argmax. Add ±0.02 jitter so prices don't look mechanical.

**Curiosity override:** if the last two scenarios used the same template,
force a different one even if EIG is lower. Bored players give bad data.

### 5.1 Slot schedule

An authored 30-slot schedule fixes the **trait** sequence and the per-template
quotas from §4 (PATH 12, DETOUR 4, ERROR 4, CREDIT 3, GIVE 4, TRADE 3).
Within a slot, ADO chooses which eligible template to use, and its price.

- A template is **eligible** if its remaining quota is > 0 and its trait
  matches the slot's trait.
- **Curiosity override:** if the previous two slots *both* used template T,
  then T is ineligible for this slot, even when its EIG is highest. This
  caps any template at a run of two. If applying the override would empty
  the eligible pool, the override yields — quota feasibility wins.

  The override blocks a *run of three*, not any reuse within three slots.
  The stricter reading is infeasible: 12 `PATH` instances spaced three
  apart would need 34 slots, and the session has 30.
- `PATH` instance #11 is **not** priced by ADO. It is re-priced within ±0.03
  of `PATH` instance #3 (§4).

This is what "the next scheduled template" in §5.2 means: the slot is
scheduled, the template within it is not.

Reference implementation: validate against `ADOpy` in Python before porting.
Ported Swift version must match Python's chosen design on a fixed seed within
one grid step.

---

## 6. Events

Four. All are real; none are fictional.

### 6.1 Falsification pricing
Once posterior SD for θ_e drops below 0.06, the next `PATH` is priced at the
posterior mean. Maximum uncertainty, genuinely 50/50 for that player.
No special presentation. Just the hardest possible decision, for them.

### 6.2 The shadow
After decision 15, a faint duplicate of the player sprite (30% alpha,
desaturated) appears at screen edge for 8–12s, at 4 randomised moments.
It walks toward the destination the model predicts the player will choose next.

**It must be genuinely predictive.** If the model is wrong, the shadow walks
the wrong way. Never script it correct.

**It is never explained.** v1.3's licence to narrate (§2.9) does not reach the
shadow: no line of copy, no marker, no sound cue, no journal entry, and no
acknowledgement anywhere in the game names it, points at it, or accounts for
it. Naming it would make the model visible (§2.3) — the shadow is the one
element that *is* the model acting on its own prediction. Work on the shadow
is confined to making it read as authored rather than as a rendering fault.

### 6.3 The eye
Two white 2×2 pixel dots in a doorway or window, 3 seconds, once per session,
at a randomised decision index in [14, 20]. No sound. No reaction.

This is a **within-subject manipulation**. Log `eye_timestamp`. The report
compares prosocial behaviour (`GIVE`, `ERROR`) in the 4 minutes before vs
4 minutes after. Also log any player movement toward the eye location and
time spent there.

**A/B flag:** `eye_enabled` — settable for testing. Half of test cohort off.

### 6.4 Gaming detection
Not an event; a derived metric. Compute:
- `rt_ratio` = median RT after decision 20 ÷ median RT before
- `fit_break` = decision index where residuals from the fitted curve exceed
  2σ for three consecutive decisions
- `reversal_rate` = choices contradicting posterior prediction, after shadow onset

If `rt_ratio > 2.0` AND `fit_break` exists → report the gaming lines (§COPY).

---

## 7. Session structure

| Phase | Screen | Duration |
|---|---|---|
| 1 | Consent (timed, two paths) | ~2s–15s |
| 2 | Temperament pick (self-image capture) | ~10s |
| 3 | Village / task / 30 decisions | 11–13 min |
| 4 | Self-prediction slider | ~15s |
| 5 | The reading (8–12 screens, tap-advance, no skip) | ~2 min |
| 6 | The argument | ~1 min |
| 7 | Title | — |

### 7.1 Consent screen
```
Priors records every choice you make and builds a model of how you decide.
Everything stays on this device.

[ Start ]        [ What's collected ]
```
Log: `consent_dwell_ms`, `consent_read_details` (bool), `details_dwell_ms`.

### 7.2 Temperament
"Your traveller is —" → Careful / Curious / Generous / Steady.
Framed as character creation. Actually captures self-image.
Log as `self_image_label`.

### 7.3 Self-prediction
Slider 0–100%: "Before the paths — how much risk would you have accepted?"
Log as `self_predicted_theta_e`. The gap vs measured θ_e is a headline claim.

---

## 8. The village

- Top-down, 32×32 tiles, ~4 screens of walkable space (roughly 80×60 tiles).
- Virtual thumbstick bottom-left. One interact button bottom-right,
  context-sensitive: it does whatever the live decision in front of the
  player offers (§8.3), and otherwise does nothing.
- Task: deliver lanterns to houses before dark.
- Dusk is a continuous palette shift — it is the timer. No numeric timer.
- HUD and wayfinding: **see §8.4.** Through v1.2 this line read *"HUD:
  lantern count only."*
- **Villagers have no faces.** Faces invite role-play.
- **Dead space is required.** At least 30% of walkable area contains nothing.
  Pointless exploration is the best data in the run. Log it.

### 8.1 Decay schedule
Palette and audio degrade on posterior confidence, not on time.

| Mean posterior SD | Palette step | Audio layers active |
|---|---|---|
| > 0.20 | 0 (warm amber) | 5 (melody, bells, pad, bass, perc) |
| 0.15–0.20 | 1 | 4 (bells drop) |
| 0.10–0.15 | 2 | 3 (perc drops) |
| 0.06–0.10 | 3 (cool) | 2 (melody drops) |
| < 0.06 | 4 (grey-blue) | 1 (pad only) |
| reading | 5 | 0 (room tone only) |

The table above is a **readout of posterior confidence** and stays one: the
five stems drop monotonically as SD falls, and that mapping does not change.

Through v1.2 this section also read *"Never change key or tempo. Only remove
layers. Never add anything back."* **That clause is lifted (§15, v1.3).** On
top of the decay table, the score may change key, change tempo, add layers,
modulate, and set whatever mood each act calls for. Two limits remain, and
both are about the instrument rather than the music:

- **Nothing in the audio may be contingent on a decision's outcome.** No
  stinger on resolve, no swell on crossing a threshold, no cue that differs
  between `engaged: true` and `engaged: false`, no change when a villager is
  declined. This is §8.3's villager who never reacts, applied to the score: a
  soundtrack that approves is feedback, and feedback on a measured choice
  changes every choice after it (§2.9).
- **Diegetic ambience is a separate bus.** Wind, water, interior hum and
  footsteps are place, not score. They are never a sixth stem, never enter
  the decay table, and are governed only by the two rules above.

### 8.2 Diegetic pricing

No scenario ever prints a number. Price reaches the player through an
authored ladder of **seven bands** per template — one fixed phrase and one
matching visual intensity per band — never a percentage, a slider, or any
other numeral. ADO still chooses the continuous price (§5); the band is
only how that price is shown, selected from the price, never the reverse.
The mapping is authored content, fixed like `COPY.md`.

Seven is not a guess kept out of convenience — `experiments/perceived_price.py`
found that band count barely affects recovery cost at all; what matters is
how distinctly each band's visual intensity reads against its neighbours.
See FINDINGS.md for the measurement.

### 8.3 In-world decisions

No modal. A scenario is presented and resolved in the world, not in a dialog
that stops it.

- **Spatial templates** (`PATH`, `DETOUR`, `TRADE`): the scenario is a
  threshold — a marked crossing approachable from any angle (a cellar lip, a
  hedge gap, a gate). Crossing it is `engaged: true`. Entering its zone and
  leaving without crossing is `engaged: false`. Time spent at the threshold
  before resolving is the hesitation.
- **Social templates** (`ERROR`, `CREDIT`, `GIVE`): a villager approaches,
  stops, and waits, with one line drawn from the §8.2 ladder above them.
  Holding the interact button while facing them is `engaged: true`. Walking
  away is `engaged: false`. The villager never follows, never repeats
  itself, and never reacts to being declined.
- Exactly one decision is live at a time — the next ADO slot's design (§5),
  placed at whichever pre-built location's authored flavour matches its
  trait. This keeps ADO fully adaptive: every price still depends on the
  response immediately before it, exactly as §5 already requires. Locations
  not yet reached are ordinary scenery until their turn.
- This is what turns `approach_frac`, `backtracks` and `idle_ms` (SCHEMA §1)
  from the modelled correlates SCHEMA §7.1 flags into observed quantities,
  and turns `rt_ms` from button-click latency into real hesitation — time
  between entering a threshold's zone and resolving it. `BehaviouralPosterior`
  reading that new `rt_ms` distribution requires re-centring the `rt_base`
  prior (SCHEMA §7) first; that re-fit is tracked as its own piece of work,
  not assumed complete by this section.

### 8.4 Wayfinding and task legibility

Through v1.2, §8 read *"HUD: lantern count only"*, and the plan derived from
it *"no minimap, no objective marker, no quest log"*. That ban is lifted
(§15, v1.3). The driver was a real defect: delivery fired on silent proximity
to a door with no affordance, no approach feedback and no way for a player
carrying nothing to learn where to refill, so the round of deliveries was
invisible and the game had no legible task at all.

**Permitted.** Objective markers, a compass or screen-edge indicator, a
minimap, a quest-shaped framing of the lantern round, act structure,
environmental storytelling, and narration at whatever density the story
needs. HUD may carry task state — lanterns carried, houses still dark.

**Preferred, not required.** Diegetic legibility first, because it costs the
world nothing: an unlit window that reads as *asking*, a lit one that reads as
*answered*, a well that reads as a source. A UI marker is the fallback for
what the world cannot say, not the first tool reached for.

**Forbidden.** Each of these is a §2 rule, not a style note:

- Marking, highlighting, counting or routing toward any decision location —
  a threshold or a waiting villager (§2.9).
- Any readout that reads as performance: elapsed time, a percentage, an
  efficiency figure, a rating, a rank, a completion grade (§2.4 score).
- Any quest, marker or narration whose completion depends on the engaged
  branch of a measured template (§2.9). A quest may say *the village needs
  light*. It may never say *and you did well to give yours away*.
- Anything about the model, the posterior, or the player's own tendencies
  (§2.3).

**Dead space survives this.** §8's 30% requirement stands, and wayfinding
strengthens rather than weakens it: a player who *knows* where the task is and
walks somewhere else has chosen, and that is the exploration the run is
logging. Undirected wandering in undifferentiated meadow was never the same
measurement. Markers point at the task; they must not point at everything, or
there is nowhere left to go pointlessly.

---

## 9. Report generation

### 9.1 Claim object
Every report line is a `Claim`:
```
Claim {
  id: String
  kind: ClaimKind
  parameters: [String: Double]     // from posterior only
  supporting_decision_ids: [Int]   // receipts — never empty
  confidence: Double               // posterior SD
}
```
**A claim with no supporting decisions must not render.** Hard assert.

### 9.2 Ordering — confirm before disconfirm
1. Two claims that match `self_image_label`
2. The self-prediction gap
3. The near-miss (longest hesitation with a backtrack)
4. The pointless detail (highest revisit count on empty tile)
5. The moral line (θ_i)
6. The eye comparison
7. The consent number
8. (conditional) gaming lines

Hardest claim is placed **third from last**, never last.

### 9.3 Phrasing
Foundation Models with `@Generable` / `@Guide`. Constrained: it receives a
`Claim` and returns a sentence. It cannot add facts, adjectives of character,
or interpretation. Fallback to templates if unavailable (iOS < 26 or
non-Apple-Intelligence hardware).

Exact copy in `COPY.md`. Treat that file as final wording.

---

## 10. The argument screen

Player taps a claim → machine shows the supporting decisions → asks why.

Three options, three different operations:

| Player says | Operation |
|---|---|
| "The situation was different" | Add context covariate; refit with that decision down-weighted 0.5 |
| "I misread it" | Treat as noise; down-weight to 0.2 |
| "That wasn't really me" | Hold two hypotheses; show both, ask which to believe |

After refit, show the widened band. **The machine does not fold.** It
concedes uncertainty, never the observation.

---

## 11. Title

One line, composed from the strongest-confidence claim.
Format: "The one who ___."
No menu. No list of other titles. No share button.

---

## 12. Stack

**Python (`priors-research/`)** — NumPy, SciPy, ADOpy (validation only),
PyTorch, coremltools, matplotlib.

**Swift package (`PriorsEngine/`)** — pure logic, no UI imports.
Posterior, ADO selector, claim generator, gaming detection. Fully unit-tested.

**App (`Priors/`)** — SwiftUI (iOS 26+), SpriteKit for the village,
Core ML for the amortised estimator, Foundation Models for phrasing,
SwiftData for the log. Landscape. iPhone only.

---

## 13. Validation targets

Three numbers must exist by ship:

1. **Recovery** — MAE of θ_e on held-out synthetic players vs decision count.
   Target: MAE < 0.06 by decision 15.
2. **Self-knowledge gap** — `|self_predicted_theta_e − measured_theta_e|`
   across real testers. This is a finding, not a target.
3. **Barnum separation** — 10 testers, half shown a stranger's report.
   Accuracy rating 1–5. If own ≈ stranger, the report is horoscope-grade
   and specificity must increase.

Number 3 is not optional. Without it the project's claim is unfalsifiable.

---

## 14. Cut order

If behind schedule, cut in this order and no other:

1. `TRADE` template
2. Mirror-villager event (already cut from v1)
3. The shadow
4. θ_i (ship with exploration only)

Never cut: the argument screen, the receipts, the consent timing, the eye.

---

## 15. Changelog

### v1.4 — the documents are revisable; the instrument is not

Owner ruling, 2026-09-03: *"the spec, copy and other docs may be incomplete —
I approve of revision and it's loose, not a tight rule, as long as we are
making a functional game, clear story line, etc."*

**What that means, and its one exception.** Wording, structure, layout, art
direction, map dimensions, narration and task framing are revisable by whoever
is doing the work, in service of the game actually being a game. **The §2.9
invariants are the exception and remain binding**: the thirty ADO-selected
decisions, what each measures, and how each resolves do not vary — because
they are what make the collected data real, and a report built on a broken
instrument is the one failure this project cannot recover from. A revision
that touches §2, §4, §5 or §8.3 is still a decision to be recorded here.

Recorded corrections and retirements:

| Clause | Was | Now | Why |
|---|---|---|---|
| §8 map size | *"~4 screens of walkable space (roughly 80×60 tiles)"* | **~4 screens, roughly 52×30 tiles** | The two figures contradicted each other and the village was built to the wrong one. A landscape screen is ~932×430pt; at 32pt tiles that is 29×13 ≈ 390 tiles, so four screens is ~1,560. 80×60 is 4,800 — **12.3 screens**. That is why the village reads as empty: nine buildings and a pond scattered over three times the intended area. 52×30 = 1,560 = 4.0 screens exactly. |
| Art direction | DCSS supplies thresholds and landmarks alongside Kenney | **Single pack. Kenney Tiny Town only.** | Owner's verdict on the DCSS thresholds in place: *"it's so out of place dawg."* DCSS is dungeon-interior art — dark, heavy, high-detail — and a free-standing arch in a meadow has no wall to belong to. The tonal clash does not improve with size. A second pack is also a permanent face-audit burden: its landmark set is full of idols and statues, and one was already rejected as an uncontrolled watching-eye stimulus (§6.3). |
| "2× pixel density" | Every DCSS sprite drawn at exactly 2×, 64pt | **Retired.** | It was the stated justification for mixing packs, and the code kept it nowhere — containment forced 50pt and 40pt sprites. With one pack there is nothing to reconcile. Kenney is 16px at 32pt everywhere. |
| Decision art containment | Nothing in a decision form may extend outside the 36pt zone | **Retired.** Art may extend past the zone; the commit sill must stay visible and the art centred on the zone so every approach angle is equivalent (§8.3). | An invented rule, not a derived one. The zone is where measurement begins, not a frame the art must fit inside — and it is why a threshold rendered 50pt against a 192pt cottage and read as a prop. `zoneRadius` 36.0 and `commitZoneRadius` 14.0 are unchanged and remain frozen. |

### v1.3 — the mask may become a game

Owner amendment, 2026-09-03, decided in one pass rather than allowed to erode
one convenient edit at a time. Its governing rule is the owner's own:

> *"Make the story, narration, quest and tasks clearer end to end with the
> psychological framework probings, so no matter the walkthrough or story we
> still have the same parameters."*

That is now §2.9, a non-negotiable: **the mask may become a game; the
instrument may not become visible.** Everything loosened below is loosened
because it belongs to the mask. Nothing that touches what a decision measures
moved.

| Clause | Read, through v1.2 | Now | Why |
|---|---|---|---|
| §1 | *"A cheerful top-down pixel game… Not: … a horror game with a data gimmick"* | Tone is the designer's; the sunless framing and dread are deliberate | Formalises the owner ruling of 2026-09-02, which had been living in a plan document while the contract still said the opposite. A contradiction sitting in the contract is how drift starts. |
| §2.4 | *"no optimal path"* (unqualified) | No optimal path **through the thirty measured decisions**; the delivery round may have a best order | The clause exists so no branch of a template is the right answer. It was never meant to forbid a sensible route between cottages, and read literally it forbade making the task legible at all. |
| §8 | *"HUD: lantern count only"*, and no objective markers | §8.4: markers, compass, minimap, quest framing and narration permitted; decision locations may never be marked | Bug A — delivery was silent proximity with no affordance, no approach feedback and no way to learn where to refill, so the task was invisible and the player could not tell the game from a rendering fault. Diegetic wayfinding is preferred; the ban is not the mechanism that protects the instrument, §2.9 is. |
| §8.1 | *"Never change key or tempo. Only remove layers. Never add anything back."* | Lifted. The decay table stays a readout of posterior confidence; above it the score is free, subject to two limits | The clause was protecting against feedback, and was doing it by banning music. The narrower rules — nothing contingent on a decision's outcome, ambience on its own bus — protect the same thing without costing the score its range. |
| §6.2 | (silent on explanation) | The shadow is **never** explained, narrated, marked or acknowledged | Decided explicitly so that v1.3's licence to narrate cannot later be read as reaching it. The shadow is the model acting on its prediction; naming it is §2.3. |

**Unchanged, and deliberately restated here** because each is what makes the
loosening safe: no modal during a decision (§8.3); the villager never reacts
to being declined (§8.3); no deception (§2.2); the model never visible
(§2.3); no network (§2.7); receipts on every claim (§2.1, §9.1); `rt_ms` =
zone-entry → resolve (§8.3); and the thirty decisions, six templates and
ADO-chosen prices of §4 and §5.

### v1.2 — game layer ratified

`SPEC-GAME.md` v0.1 argued that the village was a questionnaire wearing a
mask, not a mask: every scenario printed the exact price ADO chose, inside a
modal that stopped the world. §8.2 and §8.3 are what survived ratification
of that draft — diegetic pricing and in-world decisions — folded in as
contract. Two proposals in the draft did **not** survive as written:

| Draft proposal | What shipped instead | Why |
|---|---|---|
| Band count "goes up" if perceived-price noise costs too much recovery | Band count stays at 7; the design requirement is visual distinctness between bands | `experiments/perceived_price.py`: 7, 9, 12 and 15 bands cost within 0.002 MAE of each other at fixed noise. Cost is set by how legible a band's visual intensity is, not by how many bands exist. |
| Procedural silhouette-sprite generator (draft §6.2) | Not attempted this pass; deferred with the rest of art/villagers/audio | Kenney-derived characters already satisfy the no-faces rule (§8) at no cost; the generator was flagged in the draft itself as a timeboxed bet, not a decision, and this session's scope is §8.2/§8.3 only. |

Villagers (draft §5), art/animation/lighting (draft §6) and audio (draft §7)
remain in `SPEC-GAME.md` as an unratified, still-draft backlog for a later
session — their *constraints* (no faces, no watching, no score) were already
contract via §2 and §8 before this pass.

### v1.1 — resolved ambiguities

Four gaps in v1.0 were resolved by decision, not by invention. Each is now
written into the section it belongs to.

| Gap in v1.0 | Resolution | Section |
|---|---|---|
| No per-template price range was defined, though §5.2 referenced "its valid range" | Price range = the trait's prior support | §4.1 |
| `TRADE` price ran backwards against the §3.4 choice model | `price = 1 − p_win` | §4.2 |
| §5.2 "next scheduled template" contradicted the curiosity override, which presumes adaptive template choice | Slot fixes the trait; ADO picks the template within it | §5.1 |
| §8 Core ML inputs `approach_frac`, `backtracks`, `idle_ms` had no generator in SCHEMA §7 | Generated from near-line proximity, and explicitly marked as modelled, not observed | SCHEMA §7.1 |
