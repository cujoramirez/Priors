# The Errand — role, quest, narration, and decisions that read as decisions

Design document, 2026-09-03. Written against `SPEC.md` **v1.3**.
Not contract. `SPEC.md` wins every conflict.

**Status:** awaiting owner review. On approval this becomes an implementation
plan (`docs/superpowers/plans/`), not code.

**Source note, stated up front:** the plan of 2026-09-02 cites a
"psychological-integrity framework synthesis supplied by the project owner".
That document is not in this repository. §1 below is therefore built from what
is here — `SPEC.md`, `SPEC-GAME.md`, `priors-research/FINDINGS.md` — plus the
published literature those files name by author. Where a claim is mine rather
than sourced, it says so. If the synthesis says otherwise, it wins and this
section should be corrected rather than argued with.

---

## 0. The problem this solves

The owner's words: *"it still doesn't look like trade or any quest to me right
now"*, and, more fundamentally, *"the game doesn't feel like a game the users
can play to forget the consent that they're being recorded."*

Both are the same defect seen from two distances.

Up close: `BandLadder` gives every template its own fiction — `PATH` is a lane
going dark, `DETOUR` is a gate that will not open, `TRADE` is a peddler with
dice — and all three render as **the same black disc on the ground**.
`ThresholdNode.swift:140-142` says so outright: the generic pool is a
placeholder and per-template art was "deferred to the art session". A player
reads a sentence about a peddler while looking at a hole in the grass.

At a distance: there is no errand with a shape, no role to occupy, and no story
running underneath the thirty decisions. The player has nothing to be absorbed
by, so there is nothing to absorb them away from the consent screen.

---

## 1. What the psychology requires

Four frameworks bear on this, and each one produces a *constraint*, not a
flavour. This section exists so that later sessions can tell a design decision
from a preference.

### 1.1 Evidence-centred design (Mislevy) — why the story is free and the evidence is not

ECD separates three models: the **student model** (what is being inferred), the
**evidence model** (how observations license inference), and the **task model**
(the situations presented). In Priors:

| ECD layer | Priors |
|---|---|
| Student model | (θ_e, θ_i, β) — `SPEC.md` §3 |
| Evidence model | six templates, the choice likelihood §3.4, `rt_ms` §8.3 |
| Task model | the village, the errand, the story |

The task model is the only layer this document touches. That separation is
already contract as `SPEC.md` §2.9: *the mask may become a game, the instrument
may not become visible.* Everything below is task-model work, and the test for
any proposal in it is whether the evidence model would notice.

### 1.2 Stealth assessment (Shute) — why absorption is a measurement requirement

Assessment woven into play, invisible to the player, is what removes the
Hawthorne effect and social-desirability bias — a player who knows a moral
choice is being scored answers as the person they would like to be. This is the
argument `SPEC-GAME.md` §0 already makes, and it is why a modal is banned.

The consequence people miss: **absorption is not a nice-to-have on top of the
instrument, it is a precondition for the instrument being valid.** A bored
player monitoring themselves is a contaminated measurement. The owner's
complaint that the game is not yet absorbing is therefore a measurement bug
report, and this document treats it as one.

### 1.3 Self-determination theory (Ryan & Deci) — where satisfaction may come from

Engagement runs on competence, autonomy and relatedness. Priors may supply all
three, but only from sources that are not measured:

| Need | Permitted source | Forbidden source |
|---|---|---|
| Competence | the errand — houses lit, a route well walked | any measured decision going "well" |
| Autonomy | route freedom, the 30% dead space (§8) | — |
| Relatedness | the village as an inhabited place | a villager who approves of you |

This table is the operational form of §2.9's first consequence. It is also the
answer to "how do we make it satisfying without rewarding a branch": put every
satisfaction in the errand, and none in the choices.

### 1.4 Flow (Csikszentmihalyi) — the two conditions currently failing

Flow's preconditions include **clear proximal goals** and **immediate
unambiguous feedback**. Both were absent until yesterday: delivery was silent
proximity with no affordance, and a decision was an unexplained dark disc. §8.4
work has fixed the first. This document fixes the second.

Note the tension flow creates with §2.4's ban on a fail state: challenge must
come from *legibility of consequence*, never from difficulty. Nothing here adds
difficulty.

### 1.5 Narrative transportation (Green & Brock) — the actual mechanism for "forget"

Absorption in a narrative measurably reduces self-monitoring and critical
scrutiny of the situation one is in. That is the mechanism by which a player
stops attending to the consent disclosure — not trickery, and not a violation
of §2.2, because the disclosure was true, was shown, and is repeated in the
report (§2.6 shared blame). **My claim, not sourced from the repo:** this is the
strongest available lever on the owner's stated goal, and it is carried by role,
place and stakes rather than by plot.

---

## 2. Role

**The player is the one who carries fire tonight.** Not a named character; a
*function*. `SPEC.md` §2.4 forbids a named protagonist and a personality, and
this respects both: a role is a job, not a self. The prologue already
establishes that the valley lives on carried fire.

What the role provides that a blank avatar does not: a reason the errand is
yours, a reason a stranger asking for your lantern is a real cost, and a reason
the dark matters. All three are stakes, and stakes are what §4 of `SPEC-GAME.md`
calls textural rather than numeric.

What the role must never acquire: a name, a face, a backstory, a line of
dialogue, or an opinion about anything the player does.

---

## 3. Story

Three acts, and — this is the part worth keeping — **the acts are already paced
by the posterior, not by the clock.** `SPEC.md` §8.1 decays the palette and the
score on mean posterior SD, and `VillageContainerView` opens each act on a slot
boundary. The story tightens exactly as the model gets certain. Nothing needs
inventing here; it needs saying out loud and then honouring.

| Act | Opens | The world | The errand |
|---|---|---|---|
| I — The Evening Bell | slot 0, palette step 0–1 | golden hour, wide streets, the village still legible | the near houses |
| II — The Eye in the Frost | slot 10, steps 2–3 | colour draining, frost taking the windows, distances longer | the far houses |
| III — The Dying Flame | slot 20, steps 4–5 | near-dark; the carried lantern is the only light | the last houses, walked in the dark |

The eye (§6.3) falls in Act II and the shadow (§6.2) in Acts II–III, both
unexplained and unnamed, both already scheduled. **Act III's dark is not a
threat.** There is no fail state; the dark is a condition, not an antagonist.

---

## 4. The quest, and the one invariant that keeps it safe

**The errand:** the houses are dark. You carry fire. Light them before the dark
finishes.

Legible, countable without being scored, and — since v1.3 narrowed §2.4 — it may
have a best order. It maps onto SDT's competence, and it is the only thing in
the game permitted to reward.

### 4.1 The invariant

> **The errand is completable without engaging a single measured decision.**

Every house must be reachable by a route that enters no decision zone. A
threshold is always a *shortcut, an alternative, or an aside* — never the way.

This is the spatial form of §2.9's first consequence, and it is the single most
important sentence in this document. If crossing a threshold is ever the way to
a house, then engaging is required to finish the quest, engaging acquires a
payoff, and θ_e stops measuring a risk threshold and starts measuring how much
the player wants to finish. The trait would be gone and the report would still
confidently name it.

It is also **mechanically checkable**, and should be a test, not a promise: run
a path search over the walkable grid with every decision zone treated as
impassable, and assert that every door is still reachable from the well.

### 4.2 What the quest may and may not say

May: *the village needs light*, *four houses are still dark*, *the well is that
way*. Task state, in `SPEC.md` §8.4's terms.

May not: anything conditioned on a measured branch. No "you did well to give
your lantern away", no completion that requires a crossing, no acknowledgement
at all that a decision happened. The `GIVE` template is the sharpest case: it
costs the player a lantern that the errand wants. That tension is the
measurement. Resolving it in the player's favour would destroy it.

---

## 5. Decisions that read as decisions

### 5.1 The frozen part

**Geometry does not change.** Every spatial decision remains a 36pt zone
(`ThresholdNode.zoneRadius`) with a 14pt commit sill
(`ThresholdNode.commitZoneRadius`), radially symmetric, approachable from any
angle. `rt_ms` is zone-entry → resolve; `approach_frac` and `backtracks` are
measured against that radius; `BehaviouralPosterior`'s `rt_base` is fitted to
it, with the deliberately weak `RT_BASE_PRIOR_SD = 0.8` that FINDINGS.md warns
must not be tightened.

Everything in §5.2 is therefore a **skin over identical geometry**. If a gate is
a gate, the gate's sill is still a circle 14pt across.

### 5.2 One form per template, each saying what its own phrases say

**`PATH` — a lane the light fails in.** Hedge or wall either side, an opening
you step into, dark receding away from you. The band rides on **how far in you
can see**: at band 1 the far side shows through; at band 7 the light dies a step
past the opening. This is what the seven authored phrases already describe, from
*"The lane is only a little dark"* to *"It is black past the gate."*

**`DETOUR` — a gate.** A real gate across the opening. The band rides on **how
seized it is**: hinges clean and swinging at band 1; sagging, weed-grown,
rust-welded into its frame at band 7. Again, exactly the ladder that exists.

**`TRADE` — a pitch, not a person.** The peddler's cloth on the ground is the
crossing; stepping onto it is taking the gamble. The band rides on the dice and
the setting-out: openly and fairly laid at band 1, weighted and half in shadow
at band 7.

The peddler stands **behind** the cloth, outside the zone, hooded and turned to
the dice. This is not decoration, it is a rule:

> **No spatial decision may present a figure that reads as approachable.**

`TRADE` resolves by crossing. A figure that reads like a waiting villager
invites the player to press Interact, which does nothing there — which is
precisely the owner's original complaint (*"i can't even interact with them"*)
rebuilt in a new place.

### 5.3 The price channel stays testable

`BandLadder` is untouched: ADO picks the price, the band picks the phrase.
`DecisionIntensityStyle` remains the single source of the 0→1 scalar; each form
gains its own mapping from that scalar to its own channels. The existing
`adjacentBandsSeparateOnEveryIntensityChannel` test is **extended per form**
rather than replaced, so "seven visually distinguishable steps" stays a tested
property. Per `SPEC.md` §8.2 and `experiments/perceived_price.py`, distinctness
is the load-bearing variable — not band count, and not prettiness.

### 5.4 Teaching, where teaching is free

One practice crossing in the **prologue**. It is not one of the thirty, logs
nothing, and touches no posterior. There the game states plainly that the player
may go through or go around, and that both are the same to the errand. Then it
never says so again.

This is the whole tutorial. It is safe *because* it is unmeasured: the same
sentence attached to a real `PATH` would sit on an ADO-priced decision and tilt
it. New wording goes to `COPY.md` in its established voice, not inline in Swift.

---

## 6. Narration

Three registers, and a rule that governs all of them.

1. **Act openings** — the three banners, already implemented, currently written
   inline in `VillageContainerView.bannerMessage(for:)`. They belong in
   `COPY.md`; the current text ("Shadows pool at every corner…") is close to the
   voice but has not been through it.
2. **Place lines** — ambient, on first entering a district. Belongs with the
   depth program's Phase 2, not here.
3. **Band phrases** — the price channel. Final wording, already authored, not
   narration to be edited.

> **The rule: narration may describe the world and the errand. It may never
> describe a choice the player made, or appear because of one.**

---

## 7. What this does not do

- It does not touch `Posterior.swift`, `BehaviouralPosterior.swift`'s
  likelihood math, `ADOSelector.swift` or `ClaimGenerator.swift`.
- It does not change `LiveDecision`, `VillageCoordinator`, the slot schedule,
  the quotas, or any ADO behaviour.
- It adds no dialogue, no named villagers, no NPC reaction to a choice, no
  score, no timer, no fail state.
- It does not make the village a place — that is Phase 2 of the depth program,
  and it is the right next thing after this.

---

## 8. Risk register

| Change | Risk to the instrument | Mitigation |
|---|---|---|
| Per-template forms | a form's channels may not separate seven ways as cleanly as alpha did | extend `adjacentBandsSeparateOnEveryIntensityChannel` per form; render all seven bands of all three forms and look at them before shipping |
| `TRADE` shows a figure | player tries Interact, gets nothing | figure sits outside the zone, hooded, turned away, never stops or turns; distinct staging from `WaitingVillagerNode` |
| Quest legibility | a route that requires a crossing silently rewards engaging | the §4.1 reachability test, run over the real map |
| Prologue tutorial | teaching leaks into a measured instance | practice crossing is not one of the thirty and logs nothing; assert the decision count is still exactly 30 |
| Richer forms | per-frame cost in `VillageScene.update` | static art plus `SKAction`; nothing new in the update loop |

---

## 9. Open questions for the owner

1. Where is the framework synthesis? §1 should be checked against it.
2. `TRADE`'s peddler is the one figure in a spatial decision. If you would
   rather no figure at all — dice and cloth alone — say so; the phrases survive
   it, and the Interact confusion risk goes to zero.
3. Act banners: move to `COPY.md` verbatim, or rewrite in `COPY.md` voice?
