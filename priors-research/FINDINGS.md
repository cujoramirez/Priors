# Recovery finding — SPEC §13.1 go/no-go

**RESOLVED — target met. See "the response-time channel" below.**

Final: **MAE θ_e at decision 15 = 0.0217** (target < 0.06), measured on 20,000
agents through the full template/quota/curiosity/jitter machinery, reading
choice + hesitation. θ_e clears the target by decision 5; θ_i reaches 0.0389 by
decision 15; calibration stays in 0.93–1.23 across the whole curve.

The sections below are kept as the record of how that was reached, because the
route matters: the choice-only design genuinely could not get there, and the
channel that fixed it is only safe under conditions documented here.

---

**Original status (choice-only): the target as written is not reachable.**

Run `PYTHONPATH=. .venv/bin/python -m priors.evaluate --n 50000` to reproduce.
Artifacts: `out/recovery.png`, `out/recovery.json`.

## The number

| | MAE θ_e @15 | MAE θ_e @30 |
|---|---|---|
| **Current design** (19 θ_e of 30 slots) | **0.0729** | 0.0593 |
| Target (SPEC §13.1) | < 0.06 | — |

## Why it misses

Not scheduling, and not an estimator bug. It is an information ceiling.

`experiments/ceiling.py` spends **all 30 decisions** on θ_e with EIG-optimal
pricing and no template, quota, curiosity or jitter constraints — strictly
better than anything SPEC §4 permits:

| Configuration | MAE@10 | MAE@15 | MAE@20 | MAE@30 |
|---|---|---|---|---|
| Ceiling, β estimated jointly | 0.0741 | **0.0652** | 0.0592 | 0.0503 |
| Ceiling, decisive half (β ≥ 8) | 0.0576 | **0.0492** | 0.0435 | 0.0356 |
| Ceiling, β known (oracle — unobtainable) | 0.0656 | **0.0554** | 0.0483 | 0.0399 |

Even the unreachable oracle barely clears 0.06 at decision 15. The gap from
0.0729 to 0.0652 is what scheduling costs and could be partly recovered. The
gap from 0.0652 to 0.06 cannot be recovered by any design change.

## Where the error lives

MAE@15 by true β (decisiveness):

| β range | share | MAE@15 | MAE@30 |
|---|---|---|---|
| 2.0 – 5.2 | 20% | 0.1044 | 0.0885 |
| 5.2 – 7.0 | 20% | 0.0818 | 0.0691 |
| 7.0 – 9.1 | 20% | 0.0709 | 0.0574 |
| 9.1 – 12.2 | 20% | 0.0604 | 0.0472 |
| 12.2 – 30.0 | 20% | **0.0468** | 0.0341 |

The top quintile already passes at decision 15. Median error across the whole
population is 0.0574 — under target. The mean is dragged by a long tail
(90th percentile 0.1563).

The binding constraint is SCHEMA §7's `beta ~ LogNormal(log 8, 0.5)`, which
puts ~20% of agents below β ≈ 5.2. At that β a player's choices are close to
random with respect to price. **There is no threshold to recover, because the
agent does not behave as though it has one.** No amount of questioning fixes
that; it is a property of the population, not of the instrument.

## What is working

- **Calibration is honest.** Posterior SD exceeds actual RMSE in every β bin
  (ratio 1.30–1.84). The model is conservative everywhere and never claims
  precision it lacks — which is what SPEC §0 asks for.
- **Bias is small** and is ordinary shrinkage toward the prior: +0.011 at
  decision 15, +0.005 at decision 30.
- **θ_i behaves the same way**, one step behind on evidence count: 0.0817 @15,
  0.0648 @30, from only 11 slots.
- ADO agrees with ADOpy on the chosen design at every step (`test_adopy_validation.py`).

## The decision this forces

The handover says: if MAE θ_e is not under 0.06 by decision 15, stop and
rethink rather than proceeding to the app. Options, with measured costs:

1. **Report conditional on identifiability.** Keep the design. Quote recovery
   for players the instrument can measure and say plainly, for the rest, that
   no line was found. β ≥ 8 gives MAE@15 = 0.0492. SPEC §3.3 already carries
   the language ("you deliberate near your line"). No game changes.
2. **Move the target to decision 30.** Currently 0.0593 — passes as written.
   Costs nothing but weakens the mid-session decay schedule in SPEC §8.1.
3. **Front-load θ_e.** Recovers at most 0.0729 → ~0.065 @15. Still fails, and
   costs θ_i, which supplies the moral line (COPY R9).
4. **Cut θ_i entirely** (SPEC §14 cut #4). Buys the full ceiling, 0.0652 @15.
   Still fails, and loses a headline claim.
5. **Revisit the β prior.** If real players are more decisive than
   LogNormal(log 8, 0.5), the target becomes reachable. That is an empirical
   question, answerable only with real testers — assuming it would be fudging.

Options 3 and 4 do not reach the target and cost real content. Options 1 and 2
are honest restatements of what the instrument can do.

---

# Follow-up: the response-time channel

The ceiling above is a ceiling for **choice-based** inference only. The
posterior currently discards `rt_ms`, `approach_frac`, `backtracks` and
`idle_ms`, yet SCHEMA §7/§7.1 make all four peak at the player's line.

Choice tells you the **direction** of θ relative to the price. Hesitation
tells you the **distance**. They are complementary, and the second is free —
it is already logged.

## What it is worth (`experiments/rt_channel.py`)

| | MAE@10 | MAE@15 | MAE@30 |
|---|---|---|---|
| choice only (the ceiling) | 0.0738 | 0.0649 | 0.0507 |
| choice + RT | 0.0247 | **0.0208** | 0.0177 |

95.3% of agents land under 0.06 at decision 15. Even the indecisive
β ∈ [2, 5.2] group reaches 0.0265 — the players choice-only inference cannot
measure at all.

## Why the naive version is unusable (`experiments/rt_robustness.py`)

That result has the estimator inverting exactly the generator that made the
data. Real hesitation will not obey SCHEMA §7. With the RT parameters **fixed**
at their SCHEMA values while the world differs:

| Generator | MAE@15 | calibration |
|---|---|---|
| matches SCHEMA §7 | 0.0211 | 0.86 |
| weaker hesitation (peak 1.0) | 0.0489 | 0.43 |
| **no near-line effect (peak 0)** | **0.1391** | **0.26** |
| very noisy RT (σ 0.8) | 0.0908 | 0.19 |

Calibration is posterior SD ÷ RMSE; below 1.0 is overconfident. Every cell is
overconfident, and the worst case is *worse than ignoring RT entirely* while
claiming ~4× more precision than it has. That is a machine confidently
asserting a line the player does not have — the exact failure SPEC §0 and
non-negotiable §2.1 forbid.

**Fixed RT parameters must not ship.**

## The safe version (`experiments/rt_learned.py`)

Stop asserting the RT law; infer it. `peak`, `sigma` and `rt_base` become
nuisance dimensions. If a player's hesitation carries no signal, the posterior
over `peak` collapses toward 0 and RT stops contributing on its own —
misspecification becomes uncertainty instead of bias.

| Generator | MAE@15 | calibration | inferred peak |
|---|---|---|---|
| matches SCHEMA §7 (true peak 2.5) | **0.0180** | 1.26 | 2.37 |
| weaker hesitation (true peak 1.0) | 0.0290 | 1.20 | 1.23 |
| much weaker (true peak 0.5) | 0.0446 | 1.07 | 0.73 |
| no near-line effect (true peak 0) | 0.0712 | 0.96 | 0.34 |
| narrower band (width 0.05) | 0.0269 | 1.06 | 1.88 |
| wider band (width 0.12) | 0.0197 | 1.16 | 2.62 |
| noisier RT (σ 0.5) | 0.0311 | 1.20 | 2.07 |
| very noisy RT (σ 0.8) | 0.0419 | 1.10 | 1.93 |
| weak + noisy + wide | 0.0462 | 1.03 | 1.50 |

Honest in every condition, better than choice-only in eight of nine, and the
inferred `peak` tracks the truth. The one worse case costs 0.007 MAE and says
so in its own SD.

**This also makes the report more specific, not less.** The machine can say
what it measured — "you went in, and you thought about it for eight seconds" —
because it now has evidence for the hesitation, not just the choice. Nothing
is invented; a channel that was always in the log is finally being read.

## Cost

The posterior grows from (θ_e, θ_i, β) to (θ_e, θ_i, β, rt_base, peak, σ).
That is a real cost for `PriorsEngine` and needs a sizing decision before the
Swift port is written.

## The prior that nearly bit us (`experiments/rt_base_prior.py`)

A test failure surfaced a dependency the robustness sweep had missed. At a
single repeated price, a uniformly slow response can be explained two ways:
a large `rt_base`, or the price sitting near the player's line. With SCHEMA
§7's LogNormal(log 2000, **0.4**) prior on `rt_base`, rt = 6000 ms is 2.75
prior SDs out, so the posterior prefers "near the line" and shifted θ_e by
~0.12 on no real evidence.

That is the same failure mode as fixed RT parameters, one level down: an
assumption about the population doing work that the data should be doing.
Sweeping the true population median against the prior width:

| True population median | prior sd 0.4 | prior sd 0.8 |
|---|---|---|
| 2000 ms (matches SCHEMA §7) | 0.0181 / cal 1.28 | 0.0182 / cal 1.28 |
| 3200 ms (1.6× slower) | 0.0187 / cal 1.24 | 0.0180 / cal 1.32 |
| 5000 ms (2.5× slower) | 0.0221 / cal 1.03 | **0.0183 / cal 1.32** |
| 1200 ms (faster) | 0.0187 / cal 1.26 | 0.0176 / cal 1.33 |

The weak prior is flat across every population at no cost when SCHEMA §7 is
right. `RT_BASE_PRIOR_SD = 0.8` is now the default, and a test guards against
tightening it casually. It also removed the constant-price artefact: with the
weak prior, a flat RT elevation moves θ_e by < 0.02, as it should.

**Rule this establishes.** Every RT-law parameter is inferred, and every prior
over one is weak. `rt_base`, `peak` and `sigma` are nuisance dimensions that
exist to be marginalised away. The moment one is pinned to an assumed value,
the estimator starts asserting things the data did not say — which for this
project is not a tuning error but a violation of the premise.

---

# The amortised estimator learned the wrong thing

`train.py` first reported MAE θ_e = **0.0103** against the grid posterior's
0.0599 — six times better than Bayes-optimal inference on the same choices.
A network cannot beat the posterior on the evidence the posterior uses, so it
was using something else.

Scrambling each input channel against price (marginal preserved, correspondence
destroyed) located it:

| Perturbation | MAE θ_e |
|---|---|
| intact | 0.0103 |
| scramble `log(rt_ms)` | 0.0171 |
| scramble `approach_frac` | 0.0159 |
| scramble `backtracks` | 0.0110 |
| scramble `log(idle_ms)` | 0.0646 |
| scramble **all four** behavioural channels | **0.1092** |
| zero all four (choice + template only) | **0.1392** |
| *grid posterior, choice only* | *0.0599* |

The entire advantage was the near-line structure in the behavioural features,
and the network never learned the choice channel at all — stripped of
behaviour it scored **worse than the posterior it approximates**. It had found
SCHEMA §7.1's generator formula and stopped there.

That formula is our own assumption. SCHEMA §7.1 says so in as many words:
modelled correlates, not observed ones. A model whose accuracy rests on it is
measuring the simulator.

## Fix: make it earn the choice channel

`train.py` now augments each batch — behavioural channels dropped (p=0.30 per
channel) or scrambled (p=0.25 per sample). Scrambling matters as much as
dropping: it teaches the network that an *uninformative* channel is
uninformative, rather than that a *missing* one is.

| | unaugmented | augmented |
|---|---|---|
| intact | 0.0103 | 0.0138 |
| scrambled behaviour | 0.1092 | **0.0703** |
| behaviour removed | 0.1392 | **0.0587** |
| calibration θ_e | 0.80 | **0.94** |

It now falls back to the grid posterior's own accuracy (0.0587 vs 0.0599)
instead of collapsing, and is close to honest about its uncertainty. Cost:
0.0035 MAE when hesitation is perfectly informative. Worth it.

`val_mae_theta_e_no_behaviour` is now reported on every training run so a
brittle model cannot look good again.

## Export

`PriorsEstimator.mlpackage`, 40.4 KB against the 500 KB budget, matching
PyTorch to 5.9e-3 (float16 compute). 13,316 parameters.

---

# Banding the price doesn't cost what band count would suggest

SPEC-GAME.md's diegetic-pricing proposal replaces the printed percentage with
one of seven authored phrases plus a visual intensity, chosen from the price
ADO already selected. The document flagged this correctly as a measurement
change, not a presentation one — asked "how much does banding cost?", and
prescribed a fix if the answer was too much: "the band count goes up before
the design ships."

## What was measured (`experiments/perceived_price.py`)

Full ADO + `BehaviouralPosterior` pipeline (templates, quotas, curiosity,
jitter) — the same machinery behind the 0.0217 baseline above — with the
response-generating price replaced by `p_hat = band_midpoint(p) + Normal(0,
sigma)` for choice and all three behavioural channels. Inference still
conditions on the true authored price, per SCHEMA §1: the researcher knows
what was designed, the player only ever felt the band.

| Condition | MAE θ_e @15 | calibration | cost vs. no banding (0.0228) |
|---|---|---|---|
| No banding (sanity check) | 0.0228 | 0.96 | — |
| 7 bands, σ=0.02 | 0.0307 | 1.01 | +0.0079 |
| 7 bands, σ=0.05 | 0.0404 | 0.99 | +0.0176 |
| 9 bands, σ=0.05 | 0.0380 | 1.06 | +0.0152 |
| 12 bands, σ=0.05 | 0.0385 | 1.05 | +0.0157 |
| 15 bands, σ=0.05 | 0.0365 | 1.04 | +0.0137 |
| 7 bands, σ=0.10 | 0.0609 | 0.97 | +0.0381 |
| 9 bands, σ=0.10 | 0.0602 | 0.97 | +0.0374 |
| 12 bands, σ=0.10 | 0.0597 | 0.96 | +0.0369 |
| 15 bands, σ=0.10 | 0.0605 | 0.91 | +0.0377 |

Sanity check reproduces the 0.0217 baseline within simulation noise (1,500
agents vs. the baseline's 20,000).

## The band count does almost nothing

At fixed σ, going from 7 to 15 bands moves MAE by less than 0.002 — noise,
not signal. SPEC-GAME.md's prescribed remedy for excess cost ("the band
count goes up") **does not work**: quadrupling the number of bands at σ=0.05
or σ=0.10 leaves the cost essentially where it started. The near-line
structure that the choice and RT channels both key off of (SCHEMA §7, §7.1)
is centred on whatever price the player *perceives*; adding bands narrows
the quantisation step but does nothing about the Normal(0, σ) sitting on top
of it, and that noise term is what actually costs the recovery.

**The real lever is σ** — how tightly a band's visual intensity lets a player
feel its rough magnitude, not how many bands exist. This reframes what
"shipping §8.2 well" means: invest in making each band visually
unmistakable from its neighbours, not in subdividing the price range further.

## Whether it still ships

Even the worst case tested (σ=0.10, the loosest perceptual read) lands at
0.0597–0.0609 — split almost exactly on the SPEC §13.1 hard target (MAE < 0.06
by decision 15), not a clear failure. The softer "~0.01 MAE" budget
SPEC-GAME.md proposed as an early-warning trigger is blown at σ ≥ 0.05, but
that budget was itself a guess, not a derived number — the hard target from
SPEC.md is what actually gates shipping, and it holds. Seven bands ships;
the precision cost is real (roughly 1.6–2.7× the unbanded MAE depending on
σ) and the report's confidence language should reflect it, but it is not a
go/no-go risk the way the original choice-only ceiling was.

## The pattern across all three findings

The same failure appeared three times, each time as an assumption doing work
the data should do:

1. RT parameters fixed at SCHEMA §7 values → confidently wrong when players differ.
2. `rt_base` prior too tight → a slow player misread as standing on their line.
3. Amortised network trained without augmentation → learned the generator, not the task.

Each was invisible in the headline accuracy number and only appeared when
something was deliberately broken. SPEC §2.8 — *Core ML never decides what to
say; the Bayesian posterior is the sole source of claims* — is the structural
reason none of these could have reached a player as a false claim. It is worth
keeping for exactly that reason.
