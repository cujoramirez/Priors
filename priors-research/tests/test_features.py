"""features.py must match SCHEMA §8 exactly. A silent feature-order mismatch
between train.py and export.py would be invisible until the app was wrong."""

import numpy as np
import pytest

from priors.agents import sample_population
from priors.features import (
    FEATURE_NAMES, N_FEATURES, build_features, build_targets, normalisation,
)
from priors.scenarios import N_DECISIONS
from priors.simulate import simulate


@pytest.fixture(scope="module")
def res():
    return simulate(sample_population(60, np.random.default_rng(3)), workers=1)


def test_feature_order_matches_schema_8():
    assert FEATURE_NAMES == (
        "price", "engaged", "log_rt_ms", "approach_frac", "backtracks",
        "log_idle_ms", "template_onehot_e", "template_onehot_i", "eye_window",
    )
    assert N_FEATURES == 9


def test_feature_shape(res):
    x = build_features(res)
    assert x.shape == (res.n_agents, N_DECISIONS, N_FEATURES)
    assert x.dtype == np.float32


def test_features_are_finite(res):
    """log(rt_ms) and log(idle_ms+1) are the ones that can go to -inf."""
    assert np.all(np.isfinite(build_features(res)))


def test_template_onehot_is_exclusive(res):
    x = build_features(res)
    e, i = x[..., 6], x[..., 7]
    np.testing.assert_allclose(e + i, 1.0)


def test_onehot_tracks_the_trait(res):
    x = build_features(res)
    np.testing.assert_allclose(x[..., 6], (res.trait == 0).astype(np.float32))


def test_engaged_and_eye_window_are_binary(res):
    x = build_features(res)
    for k in (1, 8):
        assert set(np.unique(x[..., k]).tolist()) <= {0.0, 1.0}


def test_price_survives_round_trip(res):
    np.testing.assert_allclose(build_features(res)[..., 0], res.price, rtol=1e-6)


def test_targets_shape_and_content(res):
    y = build_targets(res)
    assert y.shape == (res.n_agents, 3)
    np.testing.assert_allclose(y[:, 0], res.true_theta_e, rtol=1e-6)
    np.testing.assert_allclose(y[:, 2], np.log(res.true_beta), rtol=1e-6)


def test_index_selection_matches_full_build(res):
    idx = np.array([0, 5, 11])
    np.testing.assert_allclose(build_features(res, idx), build_features(res)[idx])
    np.testing.assert_allclose(build_targets(res, idx), build_targets(res)[idx])


def test_normalisation_is_finite_and_nonzero(res):
    mean, std = normalisation(build_features(res))
    assert mean.shape == std.shape == (N_FEATURES,)
    assert np.all(np.isfinite(mean)) and np.all(std > 0)


def test_padded_rows_are_all_zero_so_the_mask_works():
    """train.py detects padding as an all-zero row. Real rows must never be
    all-zero, or a genuine decision would be masked out."""
    res_ = simulate(sample_population(40, np.random.default_rng(9)), workers=1)
    x = build_features(res_)
    assert np.all(np.abs(x).sum(axis=-1) > 0), "a real decision looks like padding"
