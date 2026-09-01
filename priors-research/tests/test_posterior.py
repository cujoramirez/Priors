"""posterior.py implements SPEC §3.4 and nothing else."""

import math

import numpy as np
import pytest

from priors.posterior import Posterior, log_choice_lik
from priors.scenarios import BETA, THETA_E, THETA_I


def spec_p_engage(price, theta, beta):
    """SPEC §3.4, written out literally, for the implementation to match."""
    return 1.0 / (1.0 + math.exp(beta * (price - theta)))


@pytest.mark.parametrize("price", [0.05, 0.3, 0.5, 0.85])
@pytest.mark.parametrize("theta", [0.1, 0.45, 0.8])
@pytest.mark.parametrize("beta", [2.0, 8.0, 30.0])
def test_likelihood_matches_spec_formula(price, theta, beta):
    got = math.exp(float(log_choice_lik(price, True, np.array(theta), np.array(beta))))
    assert got == pytest.approx(spec_p_engage(price, theta, beta), rel=1e-12)


@pytest.mark.parametrize("price", [0.05, 0.5, 0.85])
def test_engage_and_decline_are_complementary(price):
    t, b = np.array(0.4), np.array(12.0)
    pe = math.exp(float(log_choice_lik(price, True, t, b)))
    pd = math.exp(float(log_choice_lik(price, False, t, b)))
    assert pe + pd == pytest.approx(1.0, rel=1e-12)


def test_likelihood_stable_at_extremes():
    """β=30 over the full price range drives the exponent past ±24."""
    for engaged in (True, False):
        v = log_choice_lik(0.85, engaged, np.array(0.05), np.array(30.0))
        assert np.isfinite(v)


def test_prior_is_uniform_and_normalised():
    p = Posterior()
    assert p.joint.shape == (THETA_E.n, THETA_I.n, BETA.n)
    assert p.joint.sum() == pytest.approx(1.0, rel=1e-12)
    assert p.joint.std() == pytest.approx(0.0, abs=1e-18)
    assert p.entropy() == pytest.approx(math.log(THETA_E.n * THETA_I.n * BETA.n), rel=1e-12)


def test_prior_predictive_at_prior_mean_is_half():
    p = Posterior()
    mean, _ = p.mean_sd("theta_e")
    assert p.predicted_engage(mean, "theta_e") == pytest.approx(0.5, abs=1e-9)


def test_update_renormalises():
    p = Posterior()
    for price, engaged in [(0.2, True), (0.7, False), (0.45, True)]:
        p.update(price, "theta_e", engaged)
        assert p.joint.sum() == pytest.approx(1.0, rel=1e-12)


def test_engaging_at_high_price_raises_theta_e():
    p = Posterior()
    before, _ = p.mean_sd("theta_e")
    for _ in range(5):
        p.update(0.75, "theta_e", True)
    after, _ = p.mean_sd("theta_e")
    assert after > before


def test_declining_at_low_price_lowers_theta_e():
    p = Posterior()
    before, _ = p.mean_sd("theta_e")
    for _ in range(5):
        p.update(0.15, "theta_e", False)
    after, _ = p.mean_sd("theta_e")
    assert after < before


def test_evidence_shrinks_sd():
    p = Posterior()
    _, before = p.mean_sd("theta_e")
    for price, engaged in [(0.3, True), (0.6, False), (0.35, True), (0.55, False)]:
        p.update(price, "theta_e", engaged)
    _, after = p.mean_sd("theta_e")
    assert after < before


def test_theta_e_decision_leaves_theta_i_untouched():
    """The two traits share only β. A PATH decision must not move θ_i."""
    p = Posterior()
    before = p.marginal("theta_i").copy()
    for _ in range(6):
        p.update(0.7, "theta_e", True)
    np.testing.assert_allclose(p.marginal("theta_i"), before, rtol=1e-12, atol=1e-15)


def test_theta_i_decision_leaves_theta_e_untouched():
    p = Posterior()
    before = p.marginal("theta_e").copy()
    for _ in range(6):
        p.update(0.5, "theta_i", False)
    np.testing.assert_allclose(p.marginal("theta_e"), before, rtol=1e-12, atol=1e-15)


def test_both_traits_move_beta():
    """β is shared (SPEC §3.3), so either trait's decisions inform it."""
    p = Posterior()
    _, before = p.beta_mean_sd()
    for price, trait, eng in [(0.2, "theta_e", True), (0.8, "theta_e", False),
                              (0.1, "theta_i", True), (0.6, "theta_i", False)]:
        p.update(price, trait, eng)
    _, after = p.beta_mean_sd()
    assert after != pytest.approx(before)


def test_zero_weight_is_a_no_op():
    p = Posterior()
    p.update(0.4, "theta_e", True)
    before = p.log_post.copy()
    p.update(0.9, "theta_e", False, weight=0.0)
    np.testing.assert_allclose(p.log_post, before, rtol=1e-12, atol=1e-14)


def test_down_weighting_moves_less_than_full_weight():
    """SPEC §10 — 'situation' down-weights to 0.5, 'misread' to 0.2."""
    obs = [(0.25, "theta_e", True), (0.70, "theta_e", True), (0.40, "theta_e", False)]
    full = Posterior.from_observations(obs).mean_sd("theta_e")[0]
    half = Posterior.from_observations(obs, [1.0, 0.5, 1.0]).mean_sd("theta_e")[0]
    light = Posterior.from_observations(obs, [1.0, 0.2, 1.0]).mean_sd("theta_e")[0]
    dropped = Posterior.from_observations(obs, [1.0, 0.0, 1.0]).mean_sd("theta_e")[0]
    # The disputed decision (engage at 0.70) pushes θ_e up; less weight, less push.
    assert dropped < light < half < full


def test_refit_concedes_uncertainty_never_the_observation():
    """SPEC §10 — after a refit the band widens. The machine does not fold."""
    obs = [(0.25, "theta_e", True), (0.70, "theta_e", True), (0.40, "theta_e", False)]
    _, sd_full = Posterior.from_observations(obs).mean_sd("theta_e")
    _, sd_refit = Posterior.from_observations(obs, [1.0, 0.5, 1.0]).mean_sd("theta_e")
    assert sd_refit > sd_full


def test_from_observations_matches_sequential_updates():
    obs = [(0.2, "theta_e", True), (0.5, "theta_i", False), (0.65, "theta_e", False)]
    seq = Posterior()
    for price, trait, eng in obs:
        seq.update(price, trait, eng)
    np.testing.assert_allclose(
        Posterior.from_observations(obs).log_post, seq.log_post, rtol=1e-12, atol=1e-14
    )


def test_from_observations_rejects_mismatched_weights():
    with pytest.raises(ValueError):
        Posterior.from_observations([(0.2, "theta_e", True)], weights=[1.0, 1.0])


def test_update_order_does_not_matter():
    """Multiplicative updates commute; the posterior is order-invariant."""
    obs = [(0.2, "theta_e", True), (0.75, "theta_e", False), (0.3, "theta_i", True)]
    a = Posterior.from_observations(obs)
    b = Posterior.from_observations(list(reversed(obs)))
    np.testing.assert_allclose(a.log_post, b.log_post, rtol=1e-10, atol=1e-13)


def test_copy_is_independent():
    p = Posterior()
    p.update(0.4, "theta_e", True)
    q = p.copy()
    q.update(0.8, "theta_e", False)
    assert p.mean_sd("theta_e") != q.mean_sd("theta_e")


def test_predicted_engage_is_a_probability_and_decreases_with_price():
    p = Posterior()
    for _ in range(4):
        p.update(0.35, "theta_e", True)
    vals = [p.predicted_engage(x, "theta_e") for x in np.linspace(0.05, 0.85, 12)]
    assert all(0.0 <= v <= 1.0 for v in vals)
    assert all(b <= a + 1e-12 for a, b in zip(vals, vals[1:]))


def test_snapshot_shapes_match_schema_section_4():
    snap = Posterior().snapshot()
    assert len(snap.theta_e_grid) == len(snap.theta_e_marginal) == THETA_E.n
    assert len(snap.theta_i_grid) == len(snap.theta_i_marginal) == THETA_I.n
    assert sum(snap.theta_e_marginal) == pytest.approx(1.0, rel=1e-12)
    assert sum(snap.theta_i_marginal) == pytest.approx(1.0, rel=1e-12)
    assert BETA.lo <= snap.beta_mean <= BETA.hi


def test_recovers_a_known_agent():
    """End to end: 60 informative trials should land near the truth."""
    rng = np.random.default_rng(7)
    true_theta, true_beta = 0.42, 10.0
    p = Posterior()
    for price in rng.uniform(0.05, 0.85, 60):
        engaged = rng.random() < spec_p_engage(float(price), true_theta, true_beta)
        p.update(float(price), "theta_e", bool(engaged))
    mean, sd = p.mean_sd("theta_e")
    assert abs(mean - true_theta) < 0.06
    assert sd < 0.10
