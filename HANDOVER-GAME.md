# Handover — game overhaul session

Paste the block below as the opening prompt of a session dedicated to the game
layer. Nothing else should be attempted in that session.

---

You are working on **Priors**, an iOS behavioural-modelling game.
Working directory: `/Users/gading/Documents/Priors`

Read in this order before touching anything: `SPEC.md` (the contract),
`SPEC-GAME.md` (this session's brief — a draft, not yet contract), `SCHEMA.md`,
`COPY.md`, and `priors-research/FINDINGS.md`. `AGENT-LOG.md` is the running
record; append to it as you go.

**This session is only about the game layer.** The Bayesian engine, the report,
the argument screen and the title are finished and verified — do not touch them.

## Verified state

| Repo | Status |
|---|---|
| `priors-research/` (Python) | 165 tests passing |
| `PriorsEngine/` (Swift) | 78 tests passing, matches Python to 1e-9 |
| `Priors/` (iOS app) | 33 unit + 9 UI tests passing, builds clean |

Verify before you start, and do not report anything done without re-running these:

```sh
cd PriorsEngine && swift test && cd ..
cd priors-research && .venv/bin/python -m pytest tests/ -q && cd ..
xcodebuild -project Priors/Priors/Priors.xcodeproj -scheme Priors \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## The problem you are solving

The village is not a mask. It is a questionnaire with a walking simulator
attached. All six scenario templates print the price ADO chose as a bare
percentage — `"Risk of losing a lantern: 40%."` — inside a modal that stops the
world (`ScenarioDialogView.swift:33–65`). The player does arithmetic thirty
times and knows exactly what is being measured.

`SPEC-GAME.md` §0 sets out the three consequences and §1 gives the rule that
everything follows from:

> The player should never be able to name the number they are being asked
> about, and should always be able to feel it.

## What to do, in order

1. **Ratify or cut `SPEC-GAME.md`.** It is v0.1 draft. Argue with it before
   building from it — particularly the seven-band ladder (§2.2), which is a
   guess, and the procedural-sprite proposal (§6.2), which may lose to the
   Kenney art it replaces. Then fold the surviving parts into `SPEC.md` §8 as
   v1.2. **Do not build from a draft.**

2. **Run `experiments/perceived_price.py` before implementing §2.** Banding the
   price is a measurement change. Re-run recovery with `p` replaced by
   `band_midpoint(p) + Normal(0, σ)` for σ ∈ {0.02, 0.05, 0.10} and compare
   MAE θ_e at decision 15 to the 0.0217 baseline. The band count is set by that
   result, not by taste.

3. **Replace modals with in-world decisions** (§3). Spatial templates become
   thresholds you walk across; social templates become a villager who waits.
   This is the highest-value change: it turns `approach_frac`, `backtracks` and
   `idle_ms` from *modelled correlates* into *observed* ones, which SCHEMA §7.1
   flags in writing as the thing to revisit.

4. **Re-fit the `rt_base` prior** (§9). In-world thresholds change what `rt_ms`
   is — traversal-and-hesitation time, not button-click latency — so
   `BehaviouralPosterior`'s LogNormal centre of 2000 ms is wrong for the new
   distribution. Re-centre it in Python, regenerate goldens
   (`PYTHONPATH=. .venv/bin/python scripts/make_golden.py`), then port.
   **Do not tighten `RT_BASE_PRIOR_SD` below 0.8.** FINDINGS.md records that
   0.4 shifted θ_e by ~0.12 on no evidence; the weak prior is what makes this
   change survivable at all.

5. **Villagers** (§5). GameplayKit is imported in two files and completely
   unused; the current AI is `wait(2–5s)` then move to a random point within
   60pt of home. Use `GKGridGraph` for pathfinding over the walkable grid the
   map builder already computes, `GKAgent2D` + `GKBehavior` for movement and
   mutual avoidance, and `GKStateMachine` for a dusk-driven routine.
   Seed `GKMersenneTwisterRandomSource` per session and add `rng_seed` to
   SCHEMA §3 — replayable sessions matter for research.

6. **Art and animation** (§6). Timebox the procedural sprite generator and judge
   it on a rendered side-by-side against the current Kenney art. If it loses,
   keep Kenney and spend the time on animation instead — especially the
   hesitation pose, since a player standing at a threshold should look like
   someone deciding. Also swap the full-screen `CIColorMatrix` for an
   `SKShader`, and give the lantern an `SKLightNode`.

7. **Audio** (§7). The requested reference is *Obsession (2026) — "Love is in
   the Air" pt 1 and pt 2*. **Do not guess at it.** Either ask the user to
   describe the qualities to match, or put the files in
   `Priors/Assets-source/audio-reference/` and derive tempo, key, spectral
   centroid, RMS envelope and onset density with `librosa`. The current
   84 BPM D Dorian loop was written to an explicit brief in `NOTES-audio.md`;
   its replacement needs one too.

## Constraints you may not break

No network of any kind (§2.7). No score, points, XP, leaderboard, share button
or fail state (§2.4). The model stays invisible during play (§2.3). Villagers
have no faces (§8). Nothing in the report is fictional (§2.1). `COPY.md` wording
is final. The 30-decision budget and template quotas are research constraints,
not design choices (§4, §5.1).

`PriorsEngine` matches the Python reference to 1e-9. If a design change needs a
schema change, the order is `SCHEMA.md` → Python → regenerate goldens → Swift.
Never the reverse.

**One constraint that is easy to miss:** SPEC §6.3's eye is a *measured*
within-subject manipulation. Villagers that turn to look at the player create an
uncontrolled watching-eye effect that confounds it. Villager attention must be
scheduled and logged, or absent. This is experimental validity, not taste.

## How to work

Verify before asserting. Two lessons from previous sessions, both real:

- An earlier session shipped Kenney Tiny Town **tile 104 as the player
  character**. It is a *well* — shingled roof, wooden posts, blue water. It sits
  between a ladder, a bomb, a barrel and a bucket. Nobody rendered it and looked
  at it. **Render every asset and look at it before wiring it in.**
- A previous handover listed five defects; two did not exist. Check the code,
  not the summary.

Screenshots are cheap: `-startPhase village` opens the village directly, and
`VillageAppearanceTests` captures a screenshot into the xcresult, which
`xcrun xcresulttool export attachments` will extract. Use it.
