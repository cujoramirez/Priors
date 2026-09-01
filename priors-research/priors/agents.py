"""Synthetic player generator. SCHEMA §7, §7.1, §7.2.

Population parameters are quoted from SCHEMA §7:

    theta_e     ~ Beta(2, 3) scaled to [0.05, 0.85]
    theta_i     ~ Beta(2, 4) scaled to [0.02, 0.70]
    beta        ~ LogNormal(log 8, 0.5), clipped [2, 30]
    rt_base_ms  ~ LogNormal(log 2000, 0.4)
    rt_near_line_mult = 1 + 2.5 · exp(−((p − θ)/0.08)²)

Note the deliberate mismatch with SPEC §3.1/§3.2: agents are drawn from Beta
densities, but the posterior's prior is uniform over the same support. That is
not an oversight. A uniform prior is the conservative choice — recovery is
measured without letting the estimator in on the population it is scoring
against. Recovery MAE would flatter us if the prior matched the generator.

Everything here is vectorised over the population. 50,000 agents is the target
(SCHEMA §7) and a per-agent Python loop at that size is not worth writing.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from priors.scenarios import BETA, THETA_E, THETA_I, TraitName

# -- SCHEMA §7 population constants -----------------------------------------

THETA_E_BETA_AB = (2.0, 3.0)
THETA_I_BETA_AB = (2.0, 4.0)
BETA_LOGNORM = (np.log(8.0), 0.5)
RT_BASE_LOGNORM = (np.log(2000.0), 0.4)

#: SCHEMA §7 — width of the near-line band, in price units.
NEAR_LINE_WIDTH = 0.08
#: SCHEMA §7 — peak RT inflation exactly at the player's line.
RT_NEAR_LINE_PEAK = 2.5

# -- SCHEMA §7.1 behavioural feature constants ------------------------------

APPROACH_BASE, APPROACH_NEAR_GAIN, APPROACH_NOISE_SD = 0.35, 0.5, 0.12
BACKTRACK_BASE, BACKTRACK_NEAR_GAIN = 0.15, 1.2
IDLE_BASE_MS, IDLE_NEAR_GAIN_MS, IDLE_LOGNORM_SD = 200.0, 2500.0, 0.5

#: Trial-level RT noise. SCHEMA §7 gives a per-agent base and a per-trial
#: near-line multiplier but no within-agent scatter, which would make RT a
#: deterministic function of (agent, price). Recorded in SCHEMA §7.1.
RT_TRIAL_NOISE_SD = 0.25

# -- SCHEMA §7.2 timing constants -------------------------------------------

SESSION_SECONDS_RANGE = (11 * 60.0, 13 * 60.0)
TRAVEL_LOGNORM_SD = 0.5
MIN_TRAVEL_SECONDS = 1.5


@dataclass(frozen=True)
class SyntheticAgent:
    """One agent's ground truth. `simulate.py` stores these beside the records."""

    theta_e: float
    theta_i: float
    beta: float
    rt_base_ms: float

    def theta_for(self, trait: TraitName) -> float:
        return self.theta_e if trait == "theta_e" else self.theta_i


@dataclass(frozen=True)
class AgentPopulation:
    """Struct-of-arrays over the whole population."""

    theta_e: np.ndarray
    theta_i: np.ndarray
    beta: np.ndarray
    rt_base_ms: np.ndarray

    def __len__(self) -> int:
        return int(self.theta_e.shape[0])

    def __getitem__(self, i: int) -> SyntheticAgent:
        return SyntheticAgent(
            theta_e=float(self.theta_e[i]),
            theta_i=float(self.theta_i[i]),
            beta=float(self.beta[i]),
            rt_base_ms=float(self.rt_base_ms[i]),
        )

    def theta_for(self, trait: TraitName) -> np.ndarray:
        return self.theta_e if trait == "theta_e" else self.theta_i

    def slice(self, start: int, stop: int) -> "AgentPopulation":
        return AgentPopulation(
            theta_e=self.theta_e[start:stop],
            theta_i=self.theta_i[start:stop],
            beta=self.beta[start:stop],
            rt_base_ms=self.rt_base_ms[start:stop],
        )


def sample_population(n: int, rng: np.random.Generator) -> AgentPopulation:
    """Draw `n` agents per SCHEMA §7."""
    theta_e = THETA_E.lo + (THETA_E.hi - THETA_E.lo) * rng.beta(*THETA_E_BETA_AB, size=n)
    theta_i = THETA_I.lo + (THETA_I.hi - THETA_I.lo) * rng.beta(*THETA_I_BETA_AB, size=n)
    beta = np.clip(rng.lognormal(*BETA_LOGNORM, size=n), BETA.lo, BETA.hi)
    rt_base = rng.lognormal(*RT_BASE_LOGNORM, size=n)
    return AgentPopulation(theta_e=theta_e, theta_i=theta_i, beta=beta, rt_base_ms=rt_base)


# -- choice ------------------------------------------------------------------


def p_engage(price, theta, beta):
    """SPEC §3.4. Broadcasts. Written as a sigmoid to avoid overflow at β=30."""
    return 1.0 / (1.0 + np.exp(np.clip(beta * (price - theta), -700.0, 700.0)))


def respond(price, theta, beta, rng: np.random.Generator) -> np.ndarray:
    """Sample engage/decline from the SPEC §3.4 choice model."""
    p = p_engage(price, theta, beta)
    return rng.random(size=np.shape(p)) < p


# -- behaviour ---------------------------------------------------------------


def near_line(price, theta) -> np.ndarray:
    """SCHEMA §7/§7.1 — 1.0 exactly at the player's line, falling off over 0.08."""
    d = (np.asarray(price, dtype=np.float64) - np.asarray(theta, dtype=np.float64))
    return np.exp(-((d / NEAR_LINE_WIDTH) ** 2))


def rt_near_line_mult(price, theta) -> np.ndarray:
    """SCHEMA §7 — `1 + 2.5 · exp(−((p − θ)/0.08)²)`."""
    return 1.0 + RT_NEAR_LINE_PEAK * near_line(price, theta)


@dataclass(frozen=True)
class BehaviourSample:
    """The four logged behaviours for one decision. SCHEMA §1."""

    rt_ms: np.ndarray
    approach_frac: np.ndarray
    backtracks: np.ndarray
    idle_ms: np.ndarray


def sample_behaviour(
    price,
    theta,
    rt_base_ms,
    rng: np.random.Generator,
    rt_trial_noise_sd: float = RT_TRIAL_NOISE_SD,
) -> BehaviourSample:
    """Draw RT and the three behavioural features. SCHEMA §7, §7.1.

    All four share one latent cause: proximity of the price to the player's
    line. Hesitation, approach and backtracking peak together, exactly where
    RT does.
    """
    near = near_line(price, theta)
    shape = np.shape(near)

    noise = rng.lognormal(0.0, rt_trial_noise_sd, size=shape) if rt_trial_noise_sd > 0 else 1.0
    rt_ms = np.maximum(np.asarray(rt_base_ms) * (1.0 + RT_NEAR_LINE_PEAK * near) * noise, 1.0)

    approach = APPROACH_BASE + APPROACH_NEAR_GAIN * near
    approach = np.clip(approach + rng.normal(0.0, APPROACH_NOISE_SD, size=shape), 0.0, 1.0)

    backtracks = rng.poisson(BACKTRACK_BASE + BACKTRACK_NEAR_GAIN * near, size=shape)

    idle_ms = rng.lognormal(
        np.log(IDLE_BASE_MS + IDLE_NEAR_GAIN_MS * near), IDLE_LOGNORM_SD, size=shape
    )

    return BehaviourSample(
        rt_ms=rt_ms,
        approach_frac=approach,
        backtracks=backtracks.astype(np.int64),
        idle_ms=idle_ms,
    )


# -- timing ------------------------------------------------------------------


def sample_decision_times(
    rt_ms: np.ndarray, rng: np.random.Generator
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Lay `n_decisions` decisions out across an 11–13 minute session.

    SCHEMA §7.2, a stated assumption rather than a SPEC quote. Travel gaps are
    LogNormal, rescaled so the decisions plus their response times fill the
    session. Returns `(t_presented, t_decided, session_seconds)`, seconds since
    session start, each shaped like `rt_ms`.
    """
    rt_ms = np.atleast_2d(rt_ms)
    n_agents, n_dec = rt_ms.shape
    rt_s = rt_ms / 1000.0

    session = rng.uniform(*SESSION_SECONDS_RANGE, size=(n_agents, 1))
    gaps = rng.lognormal(0.0, TRAVEL_LOGNORM_SD, size=(n_agents, n_dec))

    budget = np.maximum(session - rt_s.sum(axis=1, keepdims=True), n_dec * MIN_TRAVEL_SECONDS)
    gaps = MIN_TRAVEL_SECONDS + (gaps / gaps.sum(axis=1, keepdims=True)) * (
        budget - n_dec * MIN_TRAVEL_SECONDS
    )

    # Decision k is presented after k travel gaps and k completed responses.
    t_presented = np.cumsum(gaps, axis=1) + np.concatenate(
        [np.zeros((n_agents, 1)), np.cumsum(rt_s, axis=1)[:, :-1]], axis=1
    )
    return t_presented, t_presented + rt_s, session[:, 0]
