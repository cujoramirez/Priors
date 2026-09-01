# Priors — SCHEMA

Version 1.1. Both `priors-research/` and `PriorsEngine/` must produce and
consume exactly these shapes. Change here first, then in code.

---

## 1. DecisionRecord

One per scenario presented. 30 per session.

| Field | Type | Notes |
|---|---|---|
| `index` | Int | 0-based, order presented |
| `template` | String | `PATH` \| `DETOUR` \| `ERROR` \| `CREDIT` \| `GIVE` \| `TRADE` |
| `trait` | String | `theta_e` \| `theta_i` |
| `skin` | String | which surface variant was shown |
| `price` | Double | 0.0–1.0, chosen by ADO |
| `engaged` | Bool | true = explored / corrected / gave |
| `t_presented` | Double | seconds since session start |
| `t_decided` | Double | seconds since session start |
| `rt_ms` | Int | `t_decided − t_presented`, ms |
| `approach_frac` | Double | 0.0–1.0, furthest fraction toward the threshold before deciding |
| `backtracks` | Int | direction reversals within the scenario zone |
| `idle_ms` | Int | ms stationary inside the scenario zone |
| `eye_window` | Bool | true if within ±240s of `eye_timestamp` |
| `eye_side` | String? | `before` \| `after` \| nil |
| `posterior_mean_e` | Double | posterior mean for θ_e **before** this decision |
| `posterior_sd_e` | Double | posterior SD for θ_e **before** this decision |
| `posterior_mean_i` | Double | same for θ_i |
| `posterior_sd_i` | Double | same for θ_i |
| `predicted_engage` | Double | model's P(engage) **before** the choice |
| `is_repeat_of` | Int? | index of the decision this repeats, if any |
| `why_text` | String? | free-text answer, if prompted |

**`predicted_engage` must be stored before the choice is known.** This is
what makes the prediction ledger honest.

---

## 2. MovementSample

Sampled at 4 Hz throughout the village phase. Cheap. Log wide, interpret narrow.

| Field | Type |
|---|---|
| `t` | Double |
| `x` | Double |
| `y` | Double |
| `moving` | Bool |
| `region_id` | String |

Derived at report time:
- `revisit_counts[region_id]` — for the pointless-detail claim
- `empty_region_time` — total seconds in regions with no objective
- `path_efficiency` — actual distance ÷ shortest path, per delivery

---

## 3. SessionRecord

One per playthrough.

| Field | Type | Notes |
|---|---|---|
| `session_id` | UUID | |
| `started_at` | Date | |
| `consent_dwell_ms` | Int | **headline number** |
| `consent_read_details` | Bool | |
| `details_dwell_ms` | Int? | |
| `self_image_label` | String | `Careful` \| `Curious` \| `Generous` \| `Steady` |
| `self_predicted_theta_e` | Double | 0.0–1.0, from the slider |
| `eye_enabled` | Bool | A/B flag |
| `eye_timestamp` | Double? | seconds since session start |
| `eye_approach_ms` | Int | time spent within 3 tiles of eye location after it vanished |
| `shadow_appearances` | [Double] | timestamps |
| `shadow_correct` | [Bool] | whether each prediction matched the next choice |
| `decisions` | [DecisionRecord] | |
| `movement` | [MovementSample] | |
| `final_posterior` | PosteriorSnapshot | |
| `argument_events` | [ArgumentEvent] | |

---

## 4. PosteriorSnapshot

| Field | Type |
|---|---|
| `theta_e_mean` | Double |
| `theta_e_sd` | Double |
| `theta_e_grid` | [Double] |
| `theta_e_marginal` | [Double] |
| `theta_i_mean` | Double |
| `theta_i_sd` | Double |
| `theta_i_grid` | [Double] |
| `theta_i_marginal` | [Double] |
| `beta_mean` | Double |
| `beta_sd` | Double |

---

## 5. ArgumentEvent

| Field | Type |
|---|---|
| `claim_id` | String |
| `reason` | String — `situation` \| `misread` \| `not_me` |
| `posterior_before` | PosteriorSnapshot |
| `posterior_after` | PosteriorSnapshot |

---

## 6. Claim

Generated at report time. Never persisted with invented content.

| Field | Type | Notes |
|---|---|---|
| `id` | String | stable, e.g. `explore_below_line` |
| `kind` | String | see COPY.md for the full set |
| `parameters` | [String: Double] | only values traceable to posterior or log |
| `supporting_decision_ids` | [Int] | **must be non-empty — hard assert** |
| `confidence` | Double | posterior SD at time of claim |
| `string_parameters` | [String: String] | non-numeric values COPY interpolates |

`string_parameters` was added in v1.1. v1.0 declared `parameters` as
`[String: Double]` only, but COPY R7 interpolates `{landmark}` and R9
interpolates `{error_description}` and `{error_choice}`, none of which are
numbers. Kept as a separate field rather than widening `parameters` to `Any`,
so the numeric contract stays exact.

Every value in it still comes from the log — a region id, a template's authored
skin text. Nothing in either dictionary may originate from a generative model
(SPEC §2.8).

---

## 7. Synthetic player generator (Python only)

For training and recovery evaluation.

```
SyntheticAgent {
  theta_e: Double     ~ Beta(2, 3) scaled to [0.05, 0.85]
  theta_i: Double     ~ Beta(2, 4) scaled to [0.02, 0.70]
  beta: Double        ~ LogNormal(log(8), 0.5), clipped [2, 30]
  rt_base_ms: Int     ~ LogNormal(log(2000), 0.4)
  rt_near_line_mult   = 1 + 2.5 · exp(−((p − θ)/0.08)²)
}
```

Generate 50,000 agents. Run each through the ADO loop for 30 decisions.
Store as `(DecisionRecord[], true_theta_e, true_theta_i, true_beta)`.

### 7.1 Behavioural features

`approach_frac`, `backtracks` and `idle_ms` are §8 model inputs but had no
generator in v1.0. They are drawn from the same near-line proximity that
drives RT — one latent cause. The closer the price sits to the player's line,
the longer they hesitate, the further in they walk, and the more they reverse.

```
d      = (p − θ) / 0.08
near   = exp(−d²)                     # 1.0 exactly at the line

rt_mult       = 1 + 2.5 · near        # §7, unchanged
approach_frac = clip(0.35 + 0.5·near + Normal(0, 0.12), 0, 1)
backtracks    ~ Poisson(0.15 + 1.2 · near)
idle_ms       ~ LogNormal(log(200 + 2500 · near), 0.5)
```

One addition beyond §7: `rt_trial_noise ~ LogNormal(0, 0.25)`, multiplied into
`rt_ms`. §7 gives a per-agent base and a per-trial near-line multiplier but no
within-agent scatter, which would make RT a deterministic function of
`(agent, price)` and let the estimator read θ straight off a response time.

**These are modelled correlates, not observed ones.** The Core ML model may
therefore learn a relationship real players do not have. That is tolerable
only because Core ML never produces a claim (SPEC §2.8) — the grid posterior
is the sole source of report content. Revisit once real tester logs exist.

### 7.2 Decision timing — stated assumption

SPEC does not specify how 30 decisions are spaced across the 11–13 minute
village phase. The simulator assumes:

- Session length per agent, uniform over [11, 13] minutes.
- Inter-decision gap is travel time, LogNormal, scaled so 30 decisions plus
  their RTs fill the session.
- `eye_timestamp` = `t_presented` of a decision index drawn uniform in
  [14, 20] (SPEC §6.3).
- `eye_window` = |`t_presented` − `eye_timestamp`| ≤ 240s (§1).

**Flagged for review.** This affects `eye_window` labelling in training data
only. It does not touch trait recovery.

---

## 8. Core ML model I/O

**Input:** `[30, 9]` float array, zero-padded. Per decision:
`[price, engaged, log(rt_ms), approach_frac, backtracks, log(idle_ms+1),
  template_onehot_e, template_onehot_i, eye_window]`

**Output:** `[4]` — `[theta_e_hat, theta_i_hat, log_beta_hat, uncertainty_hat]`

Model file: `PriorsEstimator.mlpackage`. Target < 500 KB.

**Role:** fast intuition and continuous-feature handling. It never produces a
claim. If it disagrees with the grid posterior by more than 2 SD, log the
disagreement — do not surface it in v1.
