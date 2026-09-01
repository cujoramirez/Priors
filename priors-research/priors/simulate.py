"""Run synthetic agents through the full 30-decision ADO loop. SCHEMA §1, §3.

Emits `DecisionRecord` arrays exactly matching SCHEMA §1. Bulk storage is
struct-of-arrays with small integer codes for the string fields; `to_records`
materialises real SCHEMA-shaped dicts for any one agent, and the tests assert
those against the schema field by field.

Two honest limits of synthetic data, both load-bearing downstream:

**The eye has no effect here.** SPEC §6.3 makes the eye a real within-subject
manipulation, but nothing in SCHEMA §7 gives a synthetic agent a response to
being watched, and inventing one would manufacture the very finding the eye
exists to test. So `eye_window` is logged exactly as SCHEMA §1 defines it and
is, by construction, uninformative in synthetic data. Its effect is only ever
measurable on human testers.

**Posterior fields are recorded before the choice.** `posterior_*` and
`predicted_engage` are all snapshotted before the response is drawn, per
SCHEMA §1. That is what makes the prediction ledger honest.
"""

from __future__ import annotations

import os
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict, dataclass
from typing import Iterator, Sequence

import numpy as np

from priors.ado import SelectionState, select_design
from priors.agents import AgentPopulation, p_engage, sample_behaviour, sample_decision_times
from priors.posterior import Posterior
from priors.rt_posterior import BehaviouralPosterior
from priors.scenarios import (
    EYE_DECISION_INDEX_RANGE,
    EYE_WINDOW_SECONDS,
    N_DECISIONS,
    TEMPLATES,
    TRAIT_SCHEDULE,
)

TEMPLATE_CODES: tuple[str, ...] = tuple(TEMPLATES)
TRAIT_CODES: tuple[str, ...] = ("theta_e", "theta_i")
SKIN_CODES: tuple[str, ...] = tuple(
    dict.fromkeys(skin for t in TEMPLATES.values() for skin in t.skins)
)
EYE_SIDE_CODES: tuple[str | None, ...] = (None, "before", "after")


@dataclass(frozen=True)
class DecisionRecord:
    """SCHEMA §1, field for field, in declaration order."""

    index: int
    template: str
    trait: str
    skin: str
    price: float
    engaged: bool
    t_presented: float
    t_decided: float
    rt_ms: int
    approach_frac: float
    backtracks: int
    idle_ms: int
    eye_window: bool
    eye_side: str | None
    posterior_mean_e: float
    posterior_sd_e: float
    posterior_mean_i: float
    posterior_sd_i: float
    predicted_engage: float
    is_repeat_of: int | None
    why_text: str | None


@dataclass
class SimulationResult:
    """Struct-of-arrays over `(n_agents, 30)`, plus per-agent ground truth."""

    template: np.ndarray
    trait: np.ndarray
    skin: np.ndarray
    price: np.ndarray
    engaged: np.ndarray
    t_presented: np.ndarray
    t_decided: np.ndarray
    rt_ms: np.ndarray
    approach_frac: np.ndarray
    backtracks: np.ndarray
    idle_ms: np.ndarray
    eye_window: np.ndarray
    eye_side: np.ndarray
    posterior_mean_e: np.ndarray
    posterior_sd_e: np.ndarray
    posterior_mean_i: np.ndarray
    posterior_sd_i: np.ndarray
    predicted_engage: np.ndarray
    is_repeat_of: np.ndarray
    # Posterior AFTER each decision — what `evaluate.py` scores recovery on.
    mean_e_after: np.ndarray
    sd_e_after: np.ndarray
    mean_i_after: np.ndarray
    sd_i_after: np.ndarray
    # Ground truth and session-level fields (SCHEMA §3).
    true_theta_e: np.ndarray
    true_theta_i: np.ndarray
    true_beta: np.ndarray
    true_rt_base_ms: np.ndarray
    eye_enabled: np.ndarray
    eye_timestamp: np.ndarray
    eye_decision_index: np.ndarray

    @property
    def n_agents(self) -> int:
        return int(self.price.shape[0])

    def to_records(self, i: int) -> list[DecisionRecord]:
        """Materialise agent `i`'s decisions as SCHEMA §1 objects."""
        out = []
        for k in range(N_DECISIONS):
            rep = int(self.is_repeat_of[i, k])
            out.append(
                DecisionRecord(
                    index=k,
                    template=TEMPLATE_CODES[int(self.template[i, k])],
                    trait=TRAIT_CODES[int(self.trait[i, k])],
                    skin=SKIN_CODES[int(self.skin[i, k])],
                    price=float(self.price[i, k]),
                    engaged=bool(self.engaged[i, k]),
                    t_presented=float(self.t_presented[i, k]),
                    t_decided=float(self.t_decided[i, k]),
                    rt_ms=int(self.rt_ms[i, k]),
                    approach_frac=float(self.approach_frac[i, k]),
                    backtracks=int(self.backtracks[i, k]),
                    idle_ms=int(self.idle_ms[i, k]),
                    eye_window=bool(self.eye_window[i, k]),
                    eye_side=EYE_SIDE_CODES[int(self.eye_side[i, k])],
                    posterior_mean_e=float(self.posterior_mean_e[i, k]),
                    posterior_sd_e=float(self.posterior_sd_e[i, k]),
                    posterior_mean_i=float(self.posterior_mean_i[i, k]),
                    posterior_sd_i=float(self.posterior_sd_i[i, k]),
                    predicted_engage=float(self.predicted_engage[i, k]),
                    is_repeat_of=None if rep < 0 else rep,
                    why_text=None,
                )
            )
        return out

    def save(self, path: str) -> None:
        np.savez_compressed(path, **{k: v for k, v in self.__dict__.items()})

    @classmethod
    def load(cls, path: str) -> "SimulationResult":
        with np.load(path, allow_pickle=False) as z:
            return cls(**{k: z[k] for k in z.files})


def _summarise(post):
    """Both traits' mean/sd in one pass where the posterior supports it."""
    fn = getattr(post, "summarise", None)
    if fn is not None:
        return fn()
    return post.mean_sd("theta_e"), post.mean_sd("theta_i")


def _simulate_chunk(args) -> dict[str, np.ndarray]:
    pop, offset, master_seed, use_rt = args
    n, d = len(pop), N_DECISIONS

    out = {
        "template": np.zeros((n, d), np.int8),
        "trait": np.zeros((n, d), np.int8),
        "skin": np.zeros((n, d), np.int8),
        "price": np.zeros((n, d), np.float64),
        "engaged": np.zeros((n, d), bool),
        "rt_ms": np.zeros((n, d), np.float32),
        "approach_frac": np.zeros((n, d), np.float32),
        "backtracks": np.zeros((n, d), np.int16),
        "idle_ms": np.zeros((n, d), np.float32),
        "posterior_mean_e": np.zeros((n, d), np.float32),
        "posterior_sd_e": np.zeros((n, d), np.float32),
        "posterior_mean_i": np.zeros((n, d), np.float32),
        "posterior_sd_i": np.zeros((n, d), np.float32),
        "predicted_engage": np.zeros((n, d), np.float32),
        "is_repeat_of": np.full((n, d), -1, np.int16),
        "mean_e_after": np.zeros((n, d), np.float32),
        "sd_e_after": np.zeros((n, d), np.float32),
        "mean_i_after": np.zeros((n, d), np.float32),
        "sd_i_after": np.zeros((n, d), np.float32),
    }

    for i in range(n):
        agent = pop[i]
        rng = np.random.default_rng([master_seed, offset + i])
        post = BehaviouralPosterior() if use_rt else Posterior()
        state = SelectionState()

        for slot in range(d):
            design = select_design(post, slot, state, rng)
            trait = design.trait

            # SCHEMA §1 — everything below is snapshotted BEFORE the response.
            (me, se), (mi, si) = _summarise(post)
            out["posterior_mean_e"][i, slot] = me
            out["posterior_sd_e"][i, slot] = se
            out["posterior_mean_i"][i, slot] = mi
            out["posterior_sd_i"][i, slot] = si
            out["predicted_engage"][i, slot] = post.predicted_engage(design.price, trait)

            theta = agent.theta_for(trait)
            engaged = bool(rng.random() < p_engage(design.price, theta, agent.beta))

            beh = sample_behaviour(
                np.array([design.price]), np.array([theta]),
                np.array([agent.rt_base_ms]), rng,
            )

            out["template"][i, slot] = TEMPLATE_CODES.index(design.template)
            out["trait"][i, slot] = TRAIT_CODES.index(trait)
            out["skin"][i, slot] = SKIN_CODES.index(design.skin)
            out["price"][i, slot] = design.price
            out["engaged"][i, slot] = engaged
            out["rt_ms"][i, slot] = beh.rt_ms[0]
            out["approach_frac"][i, slot] = beh.approach_frac[0]
            out["backtracks"][i, slot] = beh.backtracks[0]
            out["idle_ms"][i, slot] = beh.idle_ms[0]
            if design.is_repeat_of is not None:
                out["is_repeat_of"][i, slot] = design.is_repeat_of

            state.commit(design)
            if use_rt:
                post.update(design.price, trait, engaged, rt_ms=float(beh.rt_ms[0]))
            else:
                post.update(design.price, trait, engaged)

            (me, se), (mi, si) = _summarise(post)
            out["mean_e_after"][i, slot] = me
            out["sd_e_after"][i, slot] = se
            out["mean_i_after"][i, slot] = mi
            out["sd_i_after"][i, slot] = si

    return out


def simulate(
    pop: AgentPopulation,
    seed: int = 20260901,
    workers: int | None = None,
    chunk_size: int = 500,
    use_rt: bool = False,
) -> SimulationResult:
    """Run the whole population. Results do not depend on `workers`:
    each agent draws from `default_rng([seed, global_index])`.

    `use_rt` swaps the choice-only posterior for the behavioural one, which
    also reads hesitation (see `rt_posterior`). The logged records are
    identical either way — only the inference changes.
    """
    n = len(pop)
    bounds = [(s, min(s + chunk_size, n)) for s in range(0, n, chunk_size)]
    tasks = [(pop.slice(a, b), a, seed, use_rt) for a, b in bounds]

    workers = workers if workers is not None else min(os.cpu_count() or 1, len(tasks))
    if workers <= 1:
        chunks = [_simulate_chunk(t) for t in tasks]
    else:
        with ProcessPoolExecutor(max_workers=workers) as ex:
            chunks = list(ex.map(_simulate_chunk, tasks))

    merged = {k: np.concatenate([c[k] for c in chunks], axis=0) for k in chunks[0]}

    # Timing and the eye are derived once the response times are known (SCHEMA §7.2).
    rng = np.random.default_rng([seed, 0xE7E])
    t_presented, t_decided, _ = sample_decision_times(merged["rt_ms"].astype(np.float64), rng)

    lo, hi = EYE_DECISION_INDEX_RANGE
    eye_idx = rng.integers(lo, hi + 1, size=n)
    eye_enabled = np.arange(n) % 2 == 0  # SPEC §6.3 A/B: half the cohort off
    eye_ts = t_presented[np.arange(n), eye_idx]
    eye_ts = np.where(eye_enabled, eye_ts, np.nan)

    delta = t_presented - eye_ts[:, None]
    eye_window = eye_enabled[:, None] & (np.abs(delta) <= EYE_WINDOW_SECONDS)
    eye_side = np.where(~eye_window, 0, np.where(delta < 0, 1, 2)).astype(np.int8)

    return SimulationResult(
        t_presented=t_presented.astype(np.float32),
        t_decided=t_decided.astype(np.float32),
        eye_window=eye_window,
        eye_side=eye_side,
        true_theta_e=pop.theta_e,
        true_theta_i=pop.theta_i,
        true_beta=pop.beta,
        true_rt_base_ms=pop.rt_base_ms,
        eye_enabled=eye_enabled,
        eye_timestamp=eye_ts,
        eye_decision_index=eye_idx.astype(np.int16),
        **merged,
    )
