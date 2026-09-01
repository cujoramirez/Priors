"""Posterior with the response-time channel. Extends SPEC §3.4.

`posterior.Posterior` uses only the binary choice. It is validated against
ADOpy and stays the reference for a choice-only Swift port. This module adds
the channel that was always in the log and never read.

Choice tells you the **direction** of θ relative to the price. Hesitation tells
you the **distance**: SCHEMA §7 makes RT peak exactly at the player's line, and
that peak is symmetric in θ around p, so it localises |p − θ| without saying
which side. The two are complementary, and together they cut MAE at decision 15
from 0.065 to 0.018 (`experiments/rt_channel.py`).

**The RT law is inferred, never assumed.** `experiments/rt_robustness.py` shows
that fixing SCHEMA §7's parameters and being wrong about a real player is
catastrophic: when the true near-line effect is absent, MAE goes to 0.139 with
calibration 0.26 — worse than ignoring RT, while claiming four times more
precision than it has. A machine confidently asserting a line the player does
not have is the one failure SPEC §0 and §2.1 forbid outright.

So `peak`, `sigma` and `rt_base` are carried as nuisance dimensions. A player
whose hesitation carries no signal drives the `peak` posterior toward 0 and the
RT term stops contributing on its own. Misspecification degrades into
uncertainty rather than into a confident wrong answer, and calibration stays
≥ 0.96 across every misspecification tested.

None of these three is ever reported. They exist to be marginalised away.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from priors.agents import NEAR_LINE_WIDTH
from priors.scenarios import BETA, THETA_E, THETA_I, TraitName
from priors.posterior import build_grid

# -- nuisance grids ---------------------------------------------------------
# Sizing: 33·25·15·11·5·3 = 2,041,875 cells — 8.2 MB float32 on device, ~5 ms
# per update, so well under a second for a whole 30-decision session.

#: Per-player baseline response time.
#:
#: SCHEMA §7 gives LogNormal(log 2000, 0.4), but that prior is deliberately
#: NOT reused here. It is informative enough to matter: it is what lets a
#: uniformly slow response be read as "near the line" rather than "slow
#: player", so a population slower than SCHEMA §7 assumes would be
#: systematically misread. `experiments/rt_base_prior.py` sweeps that — at
#: sd 0.4 a 2.5×-slower population costs accuracy (0.0221, calibration 1.03);
#: at sd 0.8 the channel is flat across every population tested
#: (0.0176–0.0183, calibration ≥ 1.28) at no cost when SCHEMA §7 is right.
#:
#: Vaguer is strictly better here. rt_base is a nuisance parameter we have no
#: verified knowledge of, and nothing is gained by pretending otherwise.
RT_BASE_PRIOR_SD = 0.8
RT_BASE_GRID = np.geomspace(
    2000 * np.exp(-2.4 * RT_BASE_PRIOR_SD), 2000 * np.exp(2.4 * RT_BASE_PRIOR_SD), 11
)

#: Near-line RT inflation. SCHEMA §7 asserts 2.5; we infer it, and 0.0 is on the
#: grid so "this player's hesitation says nothing" is representable.
PEAK_GRID = np.array([0.0, 0.6, 1.3, 2.2, 3.4])

#: Trial-level RT scatter, in log space. SCHEMA §7.1 assumes 0.25.
SIGMA_GRID = np.array([0.22, 0.38, 0.62])

#: Width of the near-line band. Held fixed: robustness testing showed
#: misspecifying it costs little once `peak` is free (0.0197–0.0269 MAE).
RT_BAND_WIDTH = NEAR_LINE_WIDTH

_AXES = ("theta_e", "theta_i", "beta", "rt_base", "peak", "sigma")


@dataclass(frozen=True)
class RTLawSummary:
    """What the model concluded about how this player hesitates. Diagnostic
    only — never a report claim."""

    peak_mean: float
    peak_sd: float
    sigma_mean: float
    rt_base_mean: float

    @property
    def carries_signal(self) -> bool:
        """True when hesitation is informative enough to lean on."""
        return self.peak_mean - self.peak_sd > 0.0


class BehaviouralPosterior:
    """Joint over (θ_e, θ_i, β, rt_base, peak, σ).

    Axis order is fixed and load-bearing. Reported marginals are θ_e (axis 0),
    θ_i (axis 1) and β (axis 2); the rest are nuisance.
    """

    __slots__ = ("theta_e", "theta_i", "beta", "rt_base", "peak", "sigma",
                 "_log_post", "_joint_cache")

    def __init__(self) -> None:
        self.theta_e = build_grid(THETA_E)
        self.theta_i = build_grid(THETA_I)
        self.beta = build_grid(BETA)
        self.rt_base = RT_BASE_GRID
        self.peak = PEAK_GRID
        self.sigma = SIGMA_GRID

        shape = tuple(len(g) for g in self._grids())
        lp = np.zeros(shape, dtype=np.float64)

        # Weak prior on rt_base (see RT_BASE_PRIOR_SD); uniform on everything
        # else, matching SPEC §3.1/§3.2's deliberately conservative choice.
        lp += self._reshape(
            -0.5 * ((np.log(self.rt_base) - np.log(2000.0)) / RT_BASE_PRIOR_SD) ** 2, 3
        )
        self._log_post = lp - _logsumexp(lp)
        self._joint_cache: np.ndarray | None = None

    def _grids(self):
        return (self.theta_e, self.theta_i, self.beta, self.rt_base, self.peak, self.sigma)

    def _reshape(self, arr: np.ndarray, axis: int) -> np.ndarray:
        shape = [1] * 6
        shape[axis] = -1
        return np.asarray(arr).reshape(shape)

    # -- core ---------------------------------------------------------------

    @property
    def log_post(self) -> np.ndarray:
        return self._log_post

    @property
    def joint(self) -> np.ndarray:
        """Cached: exponentiating 2M cells is the dominant cost, and the
        marginals, EIG and predictive all want the same array between updates."""
        if self._joint_cache is None:
            self._joint_cache = np.exp(self._log_post)
        return self._joint_cache

    def _theta_axis(self, trait: TraitName) -> np.ndarray:
        return self._reshape(self.theta_e, 0) if trait == "theta_e" else self._reshape(self.theta_i, 1)

    def choice_log_lik(self, price: float, trait: TraitName, engaged: bool) -> np.ndarray:
        """SPEC §3.4, unchanged."""
        z = self._reshape(self.beta, 2) * (price - self._theta_axis(trait))
        return -np.logaddexp(0.0, z) if engaged else -np.logaddexp(0.0, -z)

    def rt_log_lik(self, price: float, trait: TraitName, rt_ms: float) -> np.ndarray:
        """log N(log rt ; log rt_base + log1p(peak · near), σ²).

        The −log σ normaliser matters: with σ inferred it is no longer a
        constant, and dropping it would make the widest σ win every time.
        """
        near = np.exp(-(((price - self._theta_axis(trait)) / RT_BAND_WIDTH) ** 2))
        mu = np.log(self._reshape(self.rt_base, 3)) + np.log1p(self._reshape(self.peak, 4) * near)
        sigma = self._reshape(self.sigma, 5)
        return -0.5 * ((np.log(max(rt_ms, 1.0)) - mu) / sigma) ** 2 - np.log(sigma)

    def update(
        self,
        price: float,
        trait: TraitName,
        engaged: bool,
        rt_ms: float | None = None,
        weight: float = 1.0,
    ) -> None:
        """Multiplicative update on choice, and on RT when it is available.

        `weight` carries the SPEC §10 argument-screen down-weighting (0.5 for
        `situation`, 0.2 for `misread`) across both channels: a decision the
        player disputes should lose its hesitation evidence too.
        """
        ll = self.choice_log_lik(price, trait, engaged)
        if rt_ms is not None:
            ll = ll + self.rt_log_lik(price, trait, rt_ms)
        self._log_post = self._log_post + weight * ll
        self._log_post -= _logsumexp(self._log_post)
        self._joint_cache = None

    # -- summaries ----------------------------------------------------------

    def _marginal(self, axis: int) -> np.ndarray:
        others = tuple(a for a in range(6) if a != axis)
        return self.joint.sum(axis=others)

    def summarise(self) -> tuple[tuple[float, float], tuple[float, float]]:
        """(θ_e mean, sd), (θ_i mean, sd) from a single contraction.

        `simulate.py` wants all four numbers before and after every decision;
        going through `mean_sd` twice walks the 2M-cell array twice for no
        reason.
        """
        j = self.joint
        me = j.sum(axis=(1, 2, 3, 4, 5))
        mi = j.sum(axis=(0, 2, 3, 4, 5))
        return _mean_sd(self.theta_e, me), _mean_sd(self.theta_i, mi)

    def marginal(self, trait: TraitName) -> np.ndarray:
        return self._marginal(0 if trait == "theta_e" else 1)

    def mean_sd(self, trait: TraitName) -> tuple[float, float]:
        axis = 0 if trait == "theta_e" else 1
        return _mean_sd(self._grids()[axis], self._marginal(axis))

    def beta_mean_sd(self) -> tuple[float, float]:
        return _mean_sd(self.beta, self._marginal(2))

    def trait_beta_marginal(self, trait: TraitName) -> np.ndarray:
        """The (θ, β) marginal the EIG runs on. Exact, not an approximation:
        the choice likelihood is constant along every other axis."""
        keep = (0 if trait == "theta_e" else 1, 2)
        return self.joint.sum(axis=tuple(a for a in range(6) if a not in keep))

    def rt_law(self) -> RTLawSummary:
        pk_mean, pk_sd = _mean_sd(self.peak, self._marginal(4))
        return RTLawSummary(
            peak_mean=pk_mean,
            peak_sd=pk_sd,
            sigma_mean=_mean_sd(self.sigma, self._marginal(5))[0],
            rt_base_mean=_mean_sd(self.rt_base, self._marginal(3))[0],
        )

    def entropy(self) -> float:
        p = self.joint
        nz = p > 0.0
        return float(-np.sum(p[nz] * np.log(p[nz])))

    def predicted_engage(self, price: float, trait: TraitName) -> float:
        """SCHEMA §1 — recorded before the choice is known."""
        w = self.trait_beta_marginal(trait)
        theta = self.theta_e if trait == "theta_e" else self.theta_i
        z = self.beta[None, :] * (price - theta[:, None])
        return float(np.sum(w * np.exp(-np.logaddexp(0.0, z))))


def _logsumexp(a: np.ndarray) -> float:
    m = float(np.max(a))
    if not np.isfinite(m):
        return m
    return m + float(np.log(np.sum(np.exp(a - m))))


def _mean_sd(grid: np.ndarray, marginal: np.ndarray) -> tuple[float, float]:
    mean = float(np.sum(grid * marginal))
    var = float(np.sum(marginal * (grid - mean) ** 2))
    return mean, float(np.sqrt(max(var, 0.0)))
