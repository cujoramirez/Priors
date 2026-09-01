# Priors — GAME SPEC

Version 0.1 — **draft, not yet contract.** `SPEC.md` remains the contract and
wins every conflict. This file covers the layer `SPEC.md` deliberately left
thin: what the player actually does, sees, hears, and does *with other people*
in the village. It is to be ratified (or cut down) in the session it was written
for, then folded into `SPEC.md` §8 as v1.2.

**Ratification status (2026-09-02).** §2 (diegetic pricing) and §3 (in-world
decisions) were ratified, amended, and folded into `SPEC.md` §8.2/§8.3 v1.2 —
those two sections of this file are now historical record, superseded by the
contract. Read `SPEC.md` §8.2/§8.3 and its v1.2 changelog entry, and
`priors-research/FINDINGS.md`, for what actually shipped and why it differs
from what's drafted below (band count does not follow §2.3's rule; the
procedural-sprite proposal in §6.2 was not attempted). §5 (villagers), §6
(art), and §7 (audio) remain **unratified draft**, deferred to a later
session — do not build from them without repeating this ratification pass.

---

## 0. Why this exists

The village currently fails its own premise.

`SPEC.md` §1: *"A cheerful top-down pixel game with a mundane task. The player
roams freely for ~13 minutes. A behavioural model is fit to their choices
throughout — disclosed plainly on screen 1, then never mentioned again."*

What is actually shipped is a questionnaire. Every 25 seconds a modal stops the
world and asks a numeric question:

```
                       Unlit Path
        An unlit passage opens ahead.
        Risk of losing a lantern: 40%.
              [ Enter ]  [ Stay on path ]
```

All six templates do this (`ScenarioDialogView.swift:33–65`). The number printed
is the price ADO chose to maximise information about the player. So the mask is
not thin — there is no mask. The player is doing arithmetic thirty times, and
knows it.

Three consequences, all of which the research depends on:

1. **Perception is not being measured, arithmetic is.** SPEC §3.4 models
   `P(engage | p, θ, β)`. With `p` printed, the model measures how a player
   responds to *stated* probabilities. That is a different construct from a
   threshold on lived risk, and it is the construct the report claims to have
   measured.
2. **The behavioural channel is measuring a dialog box.** `approach_frac`,
   `backtracks` and `idle_ms` are collected in the trigger zone, but the
   decision itself happens in a modal, so response time is button-click latency.
   `BehaviouralPosterior` — the thing that took MAE θ_e from 0.0599 to 0.0217 —
   is being fed the wrong hesitation.
3. **Nothing is at stake, so nothing is revealed.** Lanterns are lost and
   delivered, and neither event changes anything. A threshold on cost cannot be
   observed where there is no cost.

SCHEMA §7.1 already flags the underlying weakness in writing: *"These are
modelled correlates, not observed ones... Revisit once real tester logs exist."*
Fixing the mask is what turns them into observed ones.

---

## 1. The design rule this file exists to enforce

> **The player should never be able to name the number they are being asked
> about, and should always be able to feel it.**

Everything below follows from that.

---

## 2. Diegetic pricing

### 2.1 The problem
Price must reach the player accurately enough for §3.4 to hold, without being a
number. Perceived price `p̂ = p + ε`. Uncontrolled, `ε` inflates apparent
noise and biases β downward — the model concludes the player is indecisive when
it is the instrument that is blurry.

### 2.2 The proposal: an authored ladder plus a visual channel

Each template gets **seven price bands** with one fixed phrase each, and a
matching visual intensity. Words carry ordinal information without arithmetic;
the visual carries magnitude.

| Band | `PATH` phrase | Visual |
|---|---|---|
| 1 | `The lane is only a little dark.` | passage 2 tiles deep, lantern steady |
| 4 | `You cannot see the far end.` | 6 tiles, flame gutters, ambient drops |
| 7 | `It is black past the gate.` | 12 tiles, flame nearly out, wind audible |

Bands are authored once, mapped to price ranges, and **fixed** — the band is
chosen by the price ADO picked, never the reverse. The mapping lives in
`SPEC-GAME.md` the way report wording lives in `COPY.md`, and is equally final.

### 2.3 What this costs, and what must be measured
This is a **measurement change, not a presentation change.** Before it ships,
`priors-research/` must answer: how much does banding cost recovery?

Suggested experiment (`experiments/perceived_price.py`): re-run the recovery
sweep with `p` replaced by `band_midpoint(p) + Normal(0, σ_perception)` for
σ ∈ {0.02, 0.05, 0.10}, and report MAE θ_e at decision 15 against the 0.0217
baseline. **If banding costs more than ~0.01 MAE, the band count goes up before
the design ships.** Seven is a starting guess, not a result.

---

## 3. Decisions happen in the world

### 3.1 Spatial templates — `PATH`, `DETOUR`, `TRADE`
No modal. The scenario is a **threshold you can walk across**: the lip of a
cellar, a gap in a hedge, a gate. It is visibly marked, it is approachable from
any angle, and:

- Crossing it = `engaged: true`.
- Turning away and leaving the zone = `engaged: false`.
- Standing at it = hesitation, measured where it actually happens.

This makes `approach_frac`, `backtracks` and `idle_ms` **observed rather than
modelled**, and makes `rt_ms` the time between entering the zone and resolving
it — a real hesitation, which is what `BehaviouralPosterior` assumes.

### 3.2 Social templates — `ERROR`, `CREDIT`, `GIVE`
A villager approaches, stops, and waits. One line appears above them, drawn from
the same authored ladder. Then:

- Hold `Interact` facing them = engage (give the lantern, correct the error).
- Walk away = decline. The seconds spent standing there before walking away are
  the hesitation, and they are the most honest number in the run.

The villager does not follow, does not repeat, does not react to being refused.
No guilt-trip, no reward — SPEC §2.2 forbids manufactured doubt and §2.4 forbids
a fail state.

### 3.3 What replaces "Interact"
The current button is a generic verb. It becomes context-sensitive and is only
enabled where something is genuinely offered, which pass 1 already wired
(`canInteract`).

---

## 4. Stakes without a score

SPEC §2.4 forbids score, points and fail states. So consequence must be
**textural, not numeric**:

- Losing a lantern makes the world darker for a while, and the walk home longer.
- Delivering one lights a window that stays lit.
- Running out means walking in near-dark until you reach the well.

Nothing is counted, nothing is lost permanently, no state is unrecoverable.
The HUD stays lantern-count-only (SPEC §8).

**Guard:** any mechanic that can strand the player, end the session early, or
produce a "you failed" reading violates §2.4 and must be cut.

---

## 5. Villagers

### 5.1 What they are for
Three jobs, in priority order:
1. Make the village feel inhabited, so the mask holds.
2. Carry the social templates (§3.2).
3. Make dusk legible — as it darkens, they go home and windows light.

### 5.2 What they must never be
- **No faces** (SPEC §8: "Faces invite role-play").
- **No names, no personalities, no dialogue trees.** SPEC §2.4 is about the
  player's avatar, but the same reasoning applies: a villager with a character
  becomes someone the player performs for.
- **No reaction that resembles watching.** SPEC §6.3's eye is a *measured*
  within-subject manipulation. Villagers that turn to look at the player create
  an uncontrolled watching-eye effect that confounds it. Villager attention must
  be scheduled and logged, or absent. **This is an experimental-validity
  constraint, not a taste one.**

### 5.3 Proposed stack — GameplayKit
GameplayKit is currently imported in `PriorsApp.swift` and `VillageScene.swift`
and **entirely unused**. The villager "AI" is `SKAction.wait(2...5s)` then a
move to a random point within 60pt of home (`CharacterNode.swift`).

| Need | API |
|---|---|
| Walk without clipping walls | `GKGridGraph` over the walkable grid the map builder already computes, `findPath(from:to:)` |
| Natural movement, mutual avoidance | `GKAgent2D` + `GKBehavior` with `GKGoal(toAvoidAgents:)`, `toAvoidObstacles:`, `toReachTargetSpeed:` |
| Daily routine | `GKStateMachine`: `Idle → Travelling → Working → GoingHome`, driven by the dusk clock |
| Organic variation | `GKNoise` for wind, cloud shadow, lantern flicker |
| Reproducible sessions | `GKMersenneTwisterRandomSource` seeded per session, **seed logged** |

**The seed matters for research, not for play.** A logged seed makes a session
replayable, which is what lets a tester's run be re-examined after the fact.
Add `rng_seed` to SCHEMA §3 before implementing.

---

## 6. Art

### 6.1 Position
The current characters are Kenney "Roguelike Characters" (CC0) with faces
stripped. They read as borrowed, and they do not match the Tiny Town tiles.

The music is already **synthesised in code** — `generateProceduralStem` builds
16-bar D Dorian stems at 84 BPM from a note table. The same approach should
produce the sprites: a small generator in `scripts/`, parameterised, versioned,
and regenerable.

### 6.2 Proposal — silhouette-first, generated
- 24×24, four directions, four frames, generated from a rig: silhouette,
  garment block, lantern, shadow.
- Faceless by construction, so SPEC §8 cannot be violated by accident.
- Few colours, high contrast, heavy dark outline; tintable by the dusk palette
  so characters darken with the world instead of floating on top of it.

**Honest caveat:** procedural pixel art is easy to make consistent and hard to
make charming. The music worked because a note table is a complete description
of a melody; a sprite rig is not a complete description of a character. Budget a
timebox, and if the generated sprites lose to the Kenney ones on a side-by-side,
keep Kenney and spend the time on animation instead. **Judge on a rendered
comparison, not on principle.**

### 6.3 Animation backlog
Walk (4 dir × 4 frames), idle breathing, turn-in-place, carry pose, hand-over
gesture, the hesitation pose (the one that matters — a player standing at a
threshold should *look* like someone deciding).

### 6.4 Lighting
Replace the full-screen `CIColorMatrix` on an `SKEffectNode` — a known
per-frame cost — with an `SKShader` for dusk grading, and give the lantern an
`SKLightNode` so it actually casts light and shadow. The lantern becomes a
mechanic you can see, which is what makes losing one matter (§4).

---

## 7. Audio

Current: five procedural stems, D Dorian, 84 BPM, 16-bar loop, removed one at a
time as posterior SD falls (SPEC §8.1).

Requested direction: **Obsession (2026) — "Love is in the Air" pt 1 and pt 2.**

**This cannot be specified from the reference by the author of this file.** I
cannot listen to audio, and I will not invent an analysis of a track I have not
heard. The next session must obtain the parameters honestly, by one of:

1. The user describing the qualities to match — tempo feel, density, whether it
   is melodic or textural, what the two parts do differently.
2. Placing the audio in `Priors/Assets-source/audio-reference/` and running an
   analysis script (`librosa`: tempo, key estimate, spectral centroid, RMS
   envelope, onset density, stereo width) to derive concrete numbers.

**Do not skip this step and guess.** The current 84 BPM D Dorian folk loop was
authored to a written brief (`NOTES-audio.md`); replacing it needs an equally
explicit one.

Structural note: if the reference is textural rather than melodic, the
layer-removal schedule in SPEC §8.1 may need to become a filter/density schedule
instead. That is a SPEC change and must go through `SPEC.md`, not this file.

---

## 8. Constraints the overhaul may not touch

These are not preferences.

| Constraint | Source |
|---|---|
| No network of any kind | SPEC §2.7 |
| No score, points, XP, leaderboard, share, fail state | SPEC §2.4 |
| Model invisible during play — no confidence, no prediction, no score | SPEC §2.3 |
| Villagers have no faces | SPEC §8 |
| Nothing in the report is fictional | SPEC §2.1 |
| Core ML never decides what to say; Foundation Models never decides what is true | SPEC §2.8 |
| 30 decisions, template quotas, ADO price selection | SPEC §4, §5.1 |
| `COPY.md` wording is final | COPY.md |

**`PriorsEngine` is verified against the Python reference to 1e-9 across 78
tests.** The overhaul must not change `Posterior`, `BehaviouralPosterior`,
`ADOSelector` or `ClaimGenerator`. If a design change requires a schema change,
the order is: `SCHEMA.md` first, then Python, then regenerate goldens
(`scripts/make_golden.py`), then Swift.

---

## 9. Measurement risk register

Every change in this file has a measurement consequence. This table is the main
reason the file exists.

| Change | Effect on the model | Required before shipping |
|---|---|---|
| Banded/diegetic pricing (§2) | perceived ≠ true price; β biased down, θ blurred | `experiments/perceived_price.py`; band count set by result |
| In-world thresholds (§3.1) | `approach_frac`/`backtracks`/`idle_ms` become **observed**, fixing SCHEMA §7.1 | re-fit `rt_base` prior: traversal time ≠ click latency, so the LogNormal(log 2000, 0.8) centre is wrong |
| Social encounters (§3.2) | hesitation before refusing is new, high-quality θ_i signal | check it does not correlate with villager position (a confound) |
| Villager attention (§5.2) | can confound the eye manipulation | schedule and log it, or omit it |
| Lantern consequence (§4) | loss aversion shifts θ_e | decide whether that is the construct wanted; document either way |
| Seeded RNG (§5.3) | sessions become replayable | add `rng_seed` to SCHEMA §3 |

**The single largest risk:** in-world thresholds change what `rt_ms` *is*.
`BehaviouralPosterior` infers `rt_base` per player with a deliberately weak
prior (`RT_BASE_PRIOR_SD = 0.8`) precisely so a mis-centred population does not
bias θ — FINDINGS.md records that tightening it to 0.4 shifted θ_e by ~0.12 on
no evidence. That weak prior is what makes this change survivable. **Do not
tighten it to "fix" the new timing distribution.**

---

## 10. Explicitly out of scope

- §13 validation numbers (recovery is done; self-knowledge gap and Barnum
  separation need real testers, not game work).
- The report, the argument screen, the title. They are finished and truthful.
- Anything in `priors-research/` except the two experiments named above.
