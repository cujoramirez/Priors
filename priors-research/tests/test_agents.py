"""agents.py implements SCHEMA §7, §7.1, §7.2."""

import numpy as np
import pytest

from priors import agents as ag
from priors.scenarios import BETA, THETA_E, THETA_I

N = 40_000


@pytest.fixture(scope="module")
def pop():
    return ag.sample_population(N, np.random.default_rng(20260901))


def test_population_size(pop):
    assert len(pop) == N


def test_traits_stay_inside_grid_support(pop):
    """Agents outside the grid could never be recovered — the estimator has no
    cell to put them in."""
    assert pop.theta_e.min() >= THETA_E.lo and pop.theta_e.max() <= THETA_E.hi
    assert pop.theta_i.min() >= THETA_I.lo and pop.theta_i.max() <= THETA_I.hi
    assert pop.beta.min() >= BETA.lo and pop.beta.max() <= BETA.hi


def test_theta_e_matches_beta_2_3_scaled(pop):
    """Beta(2,3) has mean 2/5; scaled to [0.05, 0.85] that is 0.37."""
    expected = THETA_E.lo + (THETA_E.hi - THETA_E.lo) * (2.0 / 5.0)
    assert pop.theta_e.mean() == pytest.approx(expected, abs=0.01)


def test_theta_i_matches_beta_2_4_scaled(pop):
    """Beta(2,4) has mean 2/6; scaled to [0.02, 0.70] that is 0.2467."""
    expected = THETA_I.lo + (THETA_I.hi - THETA_I.lo) * (2.0 / 6.0)
    assert pop.theta_i.mean() == pytest.approx(expected, abs=0.01)


def test_beta_is_clipped_lognormal(pop):
    """Median of LogNormal(log 8, 0.5) is 8, comfortably inside [2, 30]."""
    assert np.median(pop.beta) == pytest.approx(8.0, abs=0.4)


def test_rt_base_median_is_1500ms(pop):
    """RT_BASE_LOGNORM's median moved to 1500ms (SPEC §8.3, in-world hesitation
    replaces button-click latency); see implementation plan Task 2."""
    assert np.median(pop.rt_base_ms) == pytest.approx(1500.0, rel=0.05)


def test_population_is_reproducible():
    a = ag.sample_population(500, np.random.default_rng(11))
    b = ag.sample_population(500, np.random.default_rng(11))
    np.testing.assert_array_equal(a.theta_e, b.theta_e)
    np.testing.assert_array_equal(a.beta, b.beta)


def test_agent_indexing_round_trips(pop):
    a = pop[123]
    assert a.theta_e == pop.theta_e[123]
    assert a.theta_for("theta_e") == a.theta_e
    assert a.theta_for("theta_i") == a.theta_i


# -- choice model ------------------------------------------------------------


def test_p_engage_matches_spec_formula():
    for price, theta, beta in [(0.3, 0.5, 8.0), (0.7, 0.2, 20.0), (0.05, 0.85, 2.0)]:
        expected = 1.0 / (1.0 + np.exp(beta * (price - theta)))
        assert float(ag.p_engage(price, theta, beta)) == pytest.approx(expected, rel=1e-12)


def test_p_engage_is_half_at_the_line():
    assert float(ag.p_engage(0.4, 0.4, 17.0)) == pytest.approx(0.5, rel=1e-12)


def test_p_engage_does_not_overflow_at_extremes():
    v = ag.p_engage(np.array([0.0, 1.0]), np.array([1.0, 0.0]), np.array([30.0, 30.0]))
    assert np.all(np.isfinite(v)) and np.all((v >= 0) & (v <= 1))


def test_respond_frequency_tracks_the_model():
    rng = np.random.default_rng(3)
    theta, beta, price = 0.5, 10.0, 0.4
    draws = ag.respond(price, np.full(60_000, theta), np.full(60_000, beta), rng)
    assert draws.mean() == pytest.approx(float(ag.p_engage(price, theta, beta)), abs=0.01)


# -- near-line behaviour -----------------------------------------------------


def test_near_line_peaks_at_one_on_the_line():
    assert float(ag.near_line(0.4, 0.4)) == pytest.approx(1.0)
    assert float(ag.near_line(0.4 + ag.NEAR_LINE_WIDTH, 0.4)) == pytest.approx(np.exp(-1.0))


def test_rt_multiplier_matches_schema_7():
    """`1 + 2.5 · exp(−((p − θ)/0.08)²)` — 3.5 at the line, →1 far from it."""
    assert float(ag.rt_near_line_mult(0.4, 0.4)) == pytest.approx(3.5)
    assert float(ag.rt_near_line_mult(0.9, 0.1)) == pytest.approx(1.0, abs=1e-6)


def test_rt_inflates_near_the_line():
    rng = np.random.default_rng(5)
    base = np.full(30_000, 2000.0)
    at = ag.sample_behaviour(np.full(30_000, 0.4), np.full(30_000, 0.4), base, rng)
    far = ag.sample_behaviour(np.full(30_000, 0.8), np.full(30_000, 0.2), base, rng)
    assert np.median(at.rt_ms) > 2.5 * np.median(far.rt_ms)


def test_behaviour_features_all_peak_near_the_line():
    """SCHEMA §7.1 — one latent cause, so all four move together."""
    rng = np.random.default_rng(6)
    n = 30_000
    base = np.full(n, 2000.0)
    at = ag.sample_behaviour(np.full(n, 0.4), np.full(n, 0.4), base, rng)
    far = ag.sample_behaviour(np.full(n, 0.85), np.full(n, 0.15), base, rng)
    assert at.approach_frac.mean() > far.approach_frac.mean()
    assert at.backtracks.mean() > far.backtracks.mean()
    assert np.median(at.idle_ms) > np.median(far.idle_ms)


def test_behaviour_features_stay_in_range():
    rng = np.random.default_rng(7)
    n = 20_000
    price = rng.uniform(0.05, 0.85, n)
    theta = rng.uniform(0.05, 0.85, n)
    b = ag.sample_behaviour(price, theta, np.full(n, 2000.0), rng)
    assert np.all((b.approach_frac >= 0.0) & (b.approach_frac <= 1.0))
    assert np.all(b.backtracks >= 0)
    assert np.all(b.idle_ms > 0.0) and np.all(b.rt_ms >= 1.0)


def test_rt_trial_noise_can_be_disabled():
    rng = np.random.default_rng(8)
    n = 100
    b = ag.sample_behaviour(
        np.full(n, 0.4), np.full(n, 0.4), np.full(n, 2000.0), rng, rt_trial_noise_sd=0.0
    )
    np.testing.assert_allclose(b.rt_ms, 2000.0 * 3.5, rtol=1e-12)


# -- timing (SCHEMA §7.2) ----------------------------------------------------


def test_decisions_fit_inside_the_session():
    rng = np.random.default_rng(9)
    rt = rng.lognormal(np.log(2200), 0.4, size=(500, 30))
    tp, td, session = ag.sample_decision_times(rt, rng)
    assert np.all(td[:, -1] <= session + 1e-6)
    assert np.all(tp[:, 0] > 0.0)


def test_decision_times_are_monotonic():
    rng = np.random.default_rng(10)
    rt = rng.lognormal(np.log(2200), 0.4, size=(200, 30))
    tp, td, _ = ag.sample_decision_times(rt, rng)
    assert np.all(np.diff(tp, axis=1) > 0)
    assert np.all(td > tp)


def test_session_length_is_eleven_to_thirteen_minutes():
    rng = np.random.default_rng(12)
    rt = rng.lognormal(np.log(2200), 0.4, size=(2000, 30))
    _, _, session = ag.sample_decision_times(rt, rng)
    assert session.min() >= 660.0 and session.max() <= 780.0
