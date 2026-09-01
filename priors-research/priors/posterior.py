"""Grid posterior over (θ_e, θ_i, β). SPEC §3.4.

    P(engage | p, θ, β) = 1 / (1 + exp(β · (p − θ)))

Joint over 33 × 25 × 15 = 12,375 cells. Multiplicative update after every
decision, renormalise. That is the whole model.

Everything is done in log space: β reaches 30 and prices reach 0.85, so
β·(p−θ) reaches ~24 and a naive exp() loses precision well before that.

This module is the reference for `PriorsEngine/Posterior.swift`, which must
reproduce it on a fixed decision sequence. Keep the two structurally aligned.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Sequence

import numpy as np

from priors.scenarios import BETA, THETA_E, THETA_I, GridSpec, TraitName


def build_grid(spec: GridSpec) -> np.ndarray:
    """Materialise a parameter axis. Log-spaced axes use geomspace (SPEC §3.3)."""
    if spec.log:
        return np.geomspace(spec.lo, spec.hi, spec.n, dtype=np.float64)
    return np.linspace(spec.lo, spec.hi, spec.n, dtype=np.float64)


@dataclass(frozen=True)
class PosteriorSnapshot:
    """SCHEMA §4. Plain values only — safe to serialise straight to JSON."""

    theta_e_mean: float
    theta_e_sd: float
    theta_e_grid: list[float]
    theta_e_marginal: list[float]
    theta_i_mean: float
    theta_i_sd: float
    theta_i_grid: list[float]
    theta_i_marginal: list[float]
    beta_mean: float
    beta_sd: float


def log_choice_lik(
    price: float,
    engaged: bool,
    theta: np.ndarray,
    beta: np.ndarray,
) -> np.ndarray:
    """log P(response | price, θ, β) for the SPEC §3.4 choice model.

    ``-logaddexp(0, z)`` is log(sigmoid(-z)), evaluated without overflow.
    """
    z = beta * (price - theta)
    return -np.logaddexp(0.0, z) if engaged else -np.logaddexp(0.0, -z)


class Posterior:
    """Joint posterior over (θ_e, θ_i, β).

    Axis order is fixed and load-bearing: ``(theta_e, theta_i, beta)``.
    A θ_e decision is constant along axis 1; a θ_i decision along axis 0.
    """

    __slots__ = ("theta_e", "theta_i", "beta", "_log_post", "_te", "_ti", "_b")

    def __init__(self) -> None:
        self.theta_e = build_grid(THETA_E)
        self.theta_i = build_grid(THETA_I)
        self.beta = build_grid(BETA)

        # Broadcast views, shaped for the joint. Built once.
        self._te = self.theta_e[:, None, None]
        self._ti = self.theta_i[None, :, None]
        self._b = self.beta[None, None, :]

        # SPEC §3.1/§3.2 — uniform prior over each grid's support.
        shape = (THETA_E.n, THETA_I.n, BETA.n)
        self._log_post = np.full(shape, -np.log(float(np.prod(shape))), dtype=np.float64)

    # -- core ---------------------------------------------------------------

    @property
    def log_post(self) -> np.ndarray:
        return self._log_post

    @property
    def joint(self) -> np.ndarray:
        """Normalised joint posterior, shape (33, 25, 15)."""
        return np.exp(self._log_post)

    def copy(self) -> "Posterior":
        other = Posterior.__new__(Posterior)
        other.theta_e, other.theta_i, other.beta = self.theta_e, self.theta_i, self.beta
        other._te, other._ti, other._b = self._te, self._ti, self._b
        other._log_post = self._log_post.copy()
        return other

    def _theta_axis(self, trait: TraitName) -> np.ndarray:
        return self._te if trait == "theta_e" else self._ti

    def log_lik(self, price: float, trait: TraitName, engaged: bool) -> np.ndarray:
        """Log-likelihood of one response across the whole joint grid."""
        return log_choice_lik(price, engaged, self._theta_axis(trait), self._b)

    def update(
        self,
        price: float,
        trait: TraitName,
        engaged: bool,
        weight: float = 1.0,
    ) -> None:
        """Multiplicative update, then renormalise. SPEC §3.4.

        ``weight`` supports the argument screen (SPEC §10), which refits with a
        disputed decision down-weighted to 0.5 (``situation``) or 0.2
        (``misread``). weight=1.0 is the ordinary in-play update.
        """
        self._log_post = self._log_post + weight * self.log_lik(price, trait, engaged)
        self._log_post -= _logsumexp(self._log_post)

    # -- summaries ----------------------------------------------------------

    def marginal(self, trait: TraitName) -> np.ndarray:
        joint = self.joint
        return joint.sum(axis=(1, 2)) if trait == "theta_e" else joint.sum(axis=(0, 2))

    def beta_marginal(self) -> np.ndarray:
        return self.joint.sum(axis=(0, 1))

    def mean_sd(self, trait: TraitName) -> tuple[float, float]:
        grid = self.theta_e if trait == "theta_e" else self.theta_i
        return _mean_sd(grid, self.marginal(trait))

    def beta_mean_sd(self) -> tuple[float, float]:
        return _mean_sd(self.beta, self.beta_marginal())

    def trait_beta_marginal(self, trait: TraitName) -> np.ndarray:
        """The (θ, β) marginal the ADO EIG runs on. Exact, not an
        approximation: the choice likelihood is constant along the other
        trait's axis. `rt_posterior.BehaviouralPosterior` exposes the same
        method, so `ado.py` works with either."""
        joint = self.joint
        return joint.sum(axis=1) if trait == "theta_e" else joint.sum(axis=0)

    def entropy(self) -> float:
        """Shannon entropy of the joint, in nats. Used by the ADO EIG (SPEC §5.3)."""
        p = self.joint
        nz = p > 0.0
        return float(-np.sum(p[nz] * np.log(p[nz])))

    def predicted_engage(self, price: float, trait: TraitName) -> float:
        """Posterior predictive P(engage), marginalising over (θ, β).

        SCHEMA §1: this must be recorded *before* the choice is known. That is
        what makes the prediction ledger honest.
        """
        z = self._b * (price - self._theta_axis(trait))
        return float(np.sum(self.joint * np.exp(-np.logaddexp(0.0, z))))

    def snapshot(self) -> PosteriorSnapshot:
        e_mean, e_sd = self.mean_sd("theta_e")
        i_mean, i_sd = self.mean_sd("theta_i")
        b_mean, b_sd = self.beta_mean_sd()
        return PosteriorSnapshot(
            theta_e_mean=e_mean,
            theta_e_sd=e_sd,
            theta_e_grid=self.theta_e.tolist(),
            theta_e_marginal=self.marginal("theta_e").tolist(),
            theta_i_mean=i_mean,
            theta_i_sd=i_sd,
            theta_i_grid=self.theta_i.tolist(),
            theta_i_marginal=self.marginal("theta_i").tolist(),
            beta_mean=b_mean,
            beta_sd=b_sd,
        )

    # -- refit --------------------------------------------------------------

    @classmethod
    def from_observations(
        cls,
        observations: Iterable[tuple[float, TraitName, bool]],
        weights: Sequence[float] | None = None,
    ) -> "Posterior":
        """Rebuild from scratch. Backs the SPEC §10 refit, which re-runs the
        whole sequence with one decision down-weighted rather than trying to
        divide it back out."""
        obs = list(observations)
        w = [1.0] * len(obs) if weights is None else list(weights)
        if len(w) != len(obs):
            raise ValueError(f"weights length {len(w)} != observations length {len(obs)}")
        post = cls()
        for (price, trait, engaged), wi in zip(obs, w):
            post.update(price, trait, engaged, weight=wi)
        return post


def _logsumexp(a: np.ndarray) -> float:
    m = float(np.max(a))
    if not np.isfinite(m):
        return m
    return m + float(np.log(np.sum(np.exp(a - m))))


def _mean_sd(grid: np.ndarray, marginal: np.ndarray) -> tuple[float, float]:
    mean = float(np.sum(grid * marginal))
    var = float(np.sum(marginal * (grid - mean) ** 2))
    return mean, float(np.sqrt(max(var, 0.0)))
