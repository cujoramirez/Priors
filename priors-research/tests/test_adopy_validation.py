"""Validate our ADO against ADOpy. SPEC §5:

    "Reference implementation: validate against ADOpy in Python before
     porting. Ported Swift version must match Python's chosen design on a
     fixed seed within one grid step."

ADOpy is a validation-only dependency. Release 0.4.1 predates NumPy 1.24, so it
needs `compat.adopy_shim` — see that module for why that is safe.

Two differences between the libraries are deliberate and are controlled for
here rather than tolerated:

1. **`noise_ratio`.** ADOpy floors the likelihood as `log((1 − 2ε)·L + ε)`,
   ε = 1e-7 by default. That is a lapse term; SPEC §3.4 specifies a pure
   logistic with no lapse. Where L is tiny the floor shifts log L by several
   percent. These tests set `noise_ratio=0` so both sides evaluate the SPEC
   model. If a lapse rate is ever wanted, it belongs in SPEC §3.4 first.

2. **On-grid designs only.** ADOpy can update only on designs drawn from its
   own `grid_design`. Feeding it an off-grid price makes it snap to a
   neighbour while we use the exact value, which looks like a disagreement and
   is not one. Every update below uses a price from the shared 12-point grid.

The comparison runs on a single trait. That is not a simplification: a θ_e
decision's likelihood is constant along the θ_i axis, so the (θ_e, β) marginal
of our joint posterior *is* the two-parameter posterior ADOpy maintains.
"""

from __future__ import annotations

import numpy as np
import pytest

from compat.adopy_shim import install, load_adopy

# The shim must be installed before anything touches adopy, importorskip included.
install()
pytest.importorskip("adopy", reason="ADOpy is validation-only")

from priors.ado import candidate_prices, expected_information_gain  # noqa: E402
from priors.posterior import Posterior  # noqa: E402
from priors.scenarios import BETA, THETA_E  # noqa: E402

PRICE_GRID = candidate_prices("theta_e")
PRICE_GRID_STEP = float(np.diff(PRICE_GRID)[0])

TRUE_THETA, TRUE_BETA = 0.42, 9.0


def spec_p_engage(price: float, theta: float, beta: float) -> float:
    return 1.0 / (1.0 + np.exp(beta * (price - theta)))


def build_engine():
    """An ADOpy engine on exactly our grids, evaluating exactly SPEC §3.4."""
    ad = load_adopy()

    def compute_log_lik(p, theta, beta, y):
        z = beta * (p - theta)
        return np.where(y == 1, -np.logaddexp(0.0, z), -np.logaddexp(0.0, -z))

    task = ad.Task(designs=["p"], responses=["y"], name="PATH")
    model = ad.Model(task=task, params=["theta", "beta"], func=compute_log_lik)
    return ad.Engine(
        task=task,
        model=model,
        grid_design={"p": PRICE_GRID},
        grid_param={
            "theta": np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n),
            "beta": np.geomspace(BETA.lo, BETA.hi, BETA.n),
        },
        grid_response={"y": np.array([0, 1])},
        dtype=np.float64,
        noise_ratio=0.0,
    )


def test_grids_are_identical_before_anything_else():
    """If the grids differ, every later comparison is meaningless.

    Tolerance is float32 epsilon because that is how ADOpy stores its grids.
    """
    eng = build_engine()
    gp = np.asarray(eng.grid_param)
    assert gp.dtype == np.float32, "ADOpy grid storage changed; revisit tolerances"
    ours = Posterior()
    np.testing.assert_allclose(np.unique(gp[:, 0]), ours.theta_e, rtol=1e-6)
    np.testing.assert_allclose(np.unique(gp[:, 1]), ours.beta, rtol=1e-6)


def test_priors_matches_adopy_on_a_fixed_sequence():
    """SPEC §5 — the chosen design must agree within one grid step."""
    rng = np.random.default_rng(20260901)
    eng, post = build_engine(), Posterior()

    drift = []
    for _ in range(20):
        ours = float(PRICE_GRID[int(np.argmax(expected_information_gain(post, PRICE_GRID, "theta_e")))])
        theirs = float(eng.get_design("optimal")["p"])
        drift.append(abs(ours - theirs))

        engaged = bool(rng.random() < spec_p_engage(theirs, TRUE_THETA, TRUE_BETA))
        post.update(theirs, "theta_e", engaged)
        eng.update({"p": theirs}, {"y": int(engaged)})

    worst = max(drift)
    assert worst <= PRICE_GRID_STEP + 1e-9, (
        f"chosen design drifted {worst:.4f} from ADOpy, "
        f"more than one grid step ({PRICE_GRID_STEP:.4f})"
    )


def test_design_choice_picks_the_same_grid_index_every_time():
    """Within one grid step is the SPEC bar; in practice the agreement is exact.

    Asserting the weaker bar alone would hide a systematic one-step drift, so
    this pins the chosen index. Indices, not prices — see the float32 note.
    """
    rng = np.random.default_rng(5150)
    eng, post = build_engine(), Posterior()
    for step in range(20):
        ours = int(np.argmax(expected_information_gain(post, PRICE_GRID, "theta_e")))
        theirs_price = float(eng.get_design("optimal")["p"])
        theirs = int(np.argmin(np.abs(PRICE_GRID - theirs_price)))
        assert ours == theirs, f"step {step}: chose index {ours}, ADOpy chose {theirs}"

        engaged = bool(rng.random() < spec_p_engage(theirs_price, TRUE_THETA, TRUE_BETA))
        post.update(theirs_price, "theta_e", engaged)
        eng.update({"p": theirs_price}, {"y": int(engaged)})


def test_posterior_summaries_track_adopy():
    """Beyond design choice — the posteriors themselves agree to ~1e-9."""
    rng = np.random.default_rng(3)
    eng, post = build_engine(), Posterior()
    for _ in range(25):
        price = float(PRICE_GRID[rng.integers(0, len(PRICE_GRID))])
        engaged = bool(rng.random() < spec_p_engage(price, TRUE_THETA, TRUE_BETA))
        post.update(price, "theta_e", engaged)
        eng.update({"p": price}, {"y": int(engaged)})

    mean, sd = post.mean_sd("theta_e")
    assert mean == pytest.approx(float(eng.post_mean["theta"]), abs=1e-8)
    assert sd == pytest.approx(float(eng.post_sd["theta"]), abs=1e-8)


def test_beta_marginal_tracks_adopy():
    """β is the shared nuisance parameter (SPEC §3.3); it must agree too."""
    rng = np.random.default_rng(77)
    eng, post = build_engine(), Posterior()
    for _ in range(25):
        price = float(PRICE_GRID[rng.integers(0, len(PRICE_GRID))])
        engaged = bool(rng.random() < spec_p_engage(price, 0.35, 11.0))
        post.update(price, "theta_e", engaged)
        eng.update({"p": price}, {"y": int(engaged)})
    mean, _ = post.beta_mean_sd()
    assert mean == pytest.approx(float(eng.post_mean["beta"]), abs=1e-6)


def test_our_eig_matches_adopy_mutual_information():
    """Our fast MI form against ADOpy's own, per design."""
    eng, post = build_engine(), Posterior()
    for price, engaged in [(PRICE_GRID[3], True), (PRICE_GRID[7], False), (PRICE_GRID[5], True)]:
        post.update(float(price), "theta_e", engaged)
        eng.update({"p": float(price)}, {"y": int(engaged)})
    ours = expected_information_gain(post, PRICE_GRID, "theta_e")
    theirs = np.asarray(eng.mutual_info, dtype=np.float64).ravel()
    np.testing.assert_allclose(ours, theirs, rtol=1e-7, atol=1e-9)


def test_noise_ratio_is_the_only_likelihood_difference():
    """Pins the ε explanation above, so a future divergence is not misread."""
    ad = load_adopy()

    def compute_log_lik(p, theta, beta, y):
        z = beta * (p - theta)
        return np.where(y == 1, -np.logaddexp(0.0, z), -np.logaddexp(0.0, -z))

    def engine_with(noise):
        task = ad.Task(designs=["p"], responses=["y"])
        model = ad.Model(task=task, params=["theta", "beta"], func=compute_log_lik)
        return ad.Engine(
            task=task, model=model, grid_design={"p": PRICE_GRID},
            grid_param={"theta": np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n),
                        "beta": np.geomspace(BETA.lo, BETA.hi, BETA.n)},
            grid_response={"y": np.array([0, 1])}, dtype=np.float64, noise_ratio=noise,
        )

    gp = np.asarray(engine_with(0.0).grid_param)
    theta_col, beta_col = gp[:, 0], gp[:, 1]
    z = beta_col * (float(PRICE_GRID[5]) - theta_col)
    ours = -np.logaddexp(0.0, z)

    clean = np.asarray(engine_with(0.0).log_lik)[5, :, 1]
    floored = np.asarray(engine_with(1e-7).log_lik)[5, :, 1]
    assert np.abs(clean - ours).max() < 1e-6      # SPEC model, reproduced
    assert np.abs(floored - ours).max() > 1e-4    # lapse floor, visible
