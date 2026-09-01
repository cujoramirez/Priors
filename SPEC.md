# Priors — SPEC

Version 1.2. This file is the contract. Python and Swift both read it.
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

A cheerful top-down pixel game with a mundane task. The player roams freely
for ~13 minutes. A behavioural model is fit to their choices throughout —
disclosed plainly on screen 1, then never mentioned again. At the end the
machine reads them back with receipts and lets them argue.

**Not:** a personality test, a horror game with a data gimmick, or anything
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
   no fail state, no optimal path, no leaderboard, no share button.
5. **No verdicts.** Report claims are behaviour + price. Never "you are X".
6. **Shared blame.** The consent screen was built to be tapped through.
   The report says so. Never accuse the player alone.
7. **No network.** No analytics, no crash reporting, no CloudKit, no
   backend. "Nothing leaves the device" must be literally true.
8. **Core ML never decides what to say. Foundation Models never decides
   what is true.** The Bayesian posterior is the sole source of claims.

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
- HUD: lantern count only.
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

Never change key or tempo. Only remove layers. Never add anything back.

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
