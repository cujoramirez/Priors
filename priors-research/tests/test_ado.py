"""ado.py implements SPEC §5, §5.1, §6.1."""

import itertools

import numpy as np
import pytest

from priors.ado import (
    Design,
    SelectionState,
    _blocked_by_curiosity,
    candidate_prices,
    eig_direct,
    expected_information_gain,
    select_design,
)
from priors.agents import p_engage, sample_population
from priors.posterior import Posterior
from priors.scenarios import (
    PRICE_JITTER,
    REPEAT_TOLERANCE,
    TEMPLATES,
    TEMPLATES_BY_TRAIT,
    TRAIT_SCHEDULE,
)


# -- EIG ---------------------------------------------------------------------


def test_twelve_candidate_prices_span_the_range():
    for trait, lo, hi in [("theta_e", 0.05, 0.85), ("theta_i", 0.02, 0.70)]:
        pr = candidate_prices(trait)
        assert len(pr) == 12
        assert pr[0] == pytest.approx(lo) and pr[-1] == pytest.approx(hi)


def test_fast_eig_matches_the_literal_spec_form():
    """SPEC §5.3 as written vs the mutual-information form actually used."""
    post = Posterior()
    for price, eng in [(0.3, True), (0.62, False), (0.44, True)]:
        post.update(price, "theta_e", eng)
    prices = candidate_prices("theta_e")
    fast = expected_information_gain(post, prices, "theta_e")
    slow = np.array([eig_direct(post, float(p), "theta_e") for p in prices])
    np.testing.assert_allclose(fast, slow, rtol=1e-10, atol=1e-12)


def test_eig_matches_spec_form_for_theta_i_too():
    post = Posterior()
    post.update(0.25, "theta_i", True)
    prices = candidate_prices("theta_i")
    fast = expected_information_gain(post, prices, "theta_i")
    slow = np.array([eig_direct(post, float(p), "theta_i") for p in prices])
    np.testing.assert_allclose(fast, slow, rtol=1e-10, atol=1e-12)


def test_eig_is_non_negative_and_bounded_by_one_bit():
    """A binary response cannot yield more than log 2 nats."""
    post = Posterior()
    post.update(0.4, "theta_e", True)
    eig = expected_information_gain(post, candidate_prices("theta_e"), "theta_e")
    assert np.all(eig >= -1e-12)
    assert np.all(eig <= np.log(2.0) + 1e-12)


def test_eig_is_identical_across_templates_of_one_trait():
    """The degeneracy this module is built around: under SPEC §3.4 the
    likelihood never sees the template's identity, only its trait."""
    post = Posterior()
    post.update(0.35, "theta_e", True)
    prices = np.array([0.2, 0.45, 0.7])
    ref = expected_information_gain(post, prices, "theta_e")
    for tid in TEMPLATES_BY_TRAIT["theta_e"]:
        assert TEMPLATES[tid].trait == "theta_e"
        np.testing.assert_allclose(
            expected_information_gain(post, prices, TEMPLATES[tid].trait), ref, rtol=1e-15
        )


def test_eig_peaks_near_the_posterior_mean():
    """The most informative question is the one the player is torn on."""
    post = Posterior()
    for _ in range(8):
        post.update(0.25, "theta_e", True)
    for _ in range(8):
        post.update(0.65, "theta_e", False)
    mean, _ = post.mean_sd("theta_e")
    prices = np.linspace(0.05, 0.85, 81)
    best = float(prices[int(np.argmax(expected_information_gain(post, prices, "theta_e")))])
    assert abs(best - mean) < 0.12


# -- curiosity override ------------------------------------------------------


def test_override_blocks_only_a_run_of_three():
    """SPEC §5.1 — blocked once the previous two slots BOTH used it."""
    st = SelectionState()
    assert _blocked_by_curiosity(st) is None
    st.recent = ["PATH"]
    assert _blocked_by_curiosity(st) is None
    st.recent = ["PATH", "DETOUR"]
    assert _blocked_by_curiosity(st) is None
    st.recent = ["DETOUR", "PATH", "PATH"]
    assert _blocked_by_curiosity(st) == "PATH"


def test_override_removes_the_blocked_template_when_alternatives_exist():
    post = Posterior()
    st = SelectionState()
    st.recent = ["PATH", "PATH"]
    d = select_design(post, 0, st, np.random.default_rng(0))  # slot 0 is θ_e
    assert d.curiosity_override is True
    assert d.template != "PATH"


def test_override_yields_when_it_would_empty_the_pool():
    """SPEC §5.1 — quota feasibility wins."""
    post = Posterior()
    st = SelectionState()
    st.recent = ["PATH", "PATH"]
    for tid in ("DETOUR", "TRADE"):
        st.remaining[tid] = 0
    d = select_design(post, 0, st, np.random.default_rng(0))
    assert d.template == "PATH"
    assert d.curiosity_override is False


# -- full session ------------------------------------------------------------


def run_session(seed=0, agent_seed=1, jitter=True):
    rng = np.random.default_rng(seed)
    agent = sample_population(1, np.random.default_rng(agent_seed))[0]
    post, st = Posterior(), SelectionState()
    designs, responses = [], []
    for slot in range(len(TRAIT_SCHEDULE)):
        d = select_design(post, slot, st, rng, jitter=jitter)
        engaged = bool(rng.random() < p_engage(d.price, agent.theta_for(d.trait), agent.beta))
        st.commit(d)
        post.update(d.price, d.trait, engaged)
        designs.append(d)
        responses.append(engaged)
    return agent, designs, responses, post, st


def test_session_exhausts_every_quota_exactly():
    _, designs, _, _, st = run_session()
    assert len(designs) == 30
    for tid, t in TEMPLATES.items():
        assert st.used[tid] == t.instances
        assert st.remaining[tid] == 0


def test_slot_traits_follow_the_authored_schedule():
    _, designs, _, _, _ = run_session()
    assert [d.trait for d in designs] == list(TRAIT_SCHEDULE)
    for d in designs:
        assert TEMPLATES[d.template].trait == d.trait


def test_no_template_appears_three_times_running():
    for seed in range(6):
        _, designs, _, _, _ = run_session(seed=seed, agent_seed=seed + 100)
        runs = [len(list(g)) for _, g in itertools.groupby(d.template for d in designs)]
        assert max(runs) <= 2, f"seed {seed}"


def test_instance_numbers_are_sequential_per_template():
    _, designs, _, _, _ = run_session()
    seen = {}
    for d in designs:
        seen[d.template] = seen.get(d.template, 0) + 1
        assert d.instance == seen[d.template]


def test_prices_stay_inside_the_template_range():
    for seed in range(5):
        _, designs, _, _, _ = run_session(seed=seed, agent_seed=seed + 7)
        for d in designs:
            t = TEMPLATES[d.template]
            assert t.price_lo - 1e-12 <= d.price <= t.price_hi + 1e-12


def test_repeat_instance_is_repriced_within_tolerance():
    """SPEC §4 — PATH #11 within ±0.03 of PATH #3."""
    for seed in range(6):
        _, designs, _, _, _ = run_session(seed=seed, agent_seed=seed + 30)
        by_inst = {d.instance: d for d in designs if d.template == "PATH"}
        assert 3 in by_inst and 11 in by_inst
        src, tgt = by_inst[3], by_inst[11]
        assert tgt.price_rule == "repeat"
        assert tgt.is_repeat_of == src.slot
        assert abs(tgt.price - src.price) <= REPEAT_TOLERANCE + 1e-12


def test_jitter_stays_within_spec_bound():
    """SPEC §5.4 — ±0.02, and only on EIG-chosen prices."""
    post, st = Posterior(), SelectionState()
    rng = np.random.default_rng(3)
    plain = select_design(post, 0, st, rng, jitter=False)
    for _ in range(40):
        d = select_design(post, 0, SelectionState(), rng, jitter=True)
        assert d.price_rule == "eig"
        assert abs(d.price - plain.price) <= PRICE_JITTER + 1e-12


def test_falsification_prices_at_the_posterior_mean():
    """SPEC §6.1 — once SD θ_e < 0.06, the next PATH is genuinely 50/50."""
    post = Posterior()
    rng = np.random.default_rng(0)
    for _ in range(40):  # drive SD below the threshold
        post.update(0.30, "theta_e", True)
        post.update(0.50, "theta_e", False)
    mean, sd = post.mean_sd("theta_e")
    assert sd < 0.06
    st = SelectionState()
    d = select_design(post, 0, st, rng)
    assert d.template == "PATH" and d.price_rule == "falsification"
    assert d.price == pytest.approx(mean, abs=1e-9)
    assert post.predicted_engage(d.price, "theta_e") == pytest.approx(0.5, abs=0.02)


def test_falsification_fires_only_once():
    post = Posterior()
    for _ in range(40):
        post.update(0.30, "theta_e", True)
        post.update(0.50, "theta_e", False)
    st = SelectionState()
    rng = np.random.default_rng(0)
    d1 = select_design(post, 0, st, rng)
    st.commit(d1)
    assert d1.price_rule == "falsification"
    assert st.falsification_fired
    d2 = select_design(post, 1, st, rng)
    assert d2.price_rule != "falsification"


def test_selection_is_deterministic_for_a_fixed_seed():
    a = run_session(seed=99, agent_seed=5)[1]
    b = run_session(seed=99, agent_seed=5)[1]
    assert [(d.template, round(d.price, 12)) for d in a] == [
        (d.template, round(d.price, 12)) for d in b
    ]


def test_selection_state_rejects_an_exhausted_trait():
    post = Posterior()
    st = SelectionState()
    for tid in TEMPLATES_BY_TRAIT["theta_e"]:
        st.remaining[tid] = 0
    with pytest.raises(RuntimeError, match="no template with quota left"):
        select_design(post, 0, st, np.random.default_rng(0))


def test_eig_tie_break_is_explicit_not_float_luck():
    """At the uniform prior, prices equidistant from the mean have identical
    EIG. A bare argmax picks whichever float noise favours, which differs
    between NumPy and Swift and makes the port diverge at slot 0."""
    from priors.ado import EIG_TIE_TOLERANCE, argmax_eig

    post = Posterior()
    eigs = expected_information_gain(post, candidate_prices("theta_e"), "theta_e")
    assert abs(eigs[5] - eigs[6]) < 1e-14, "expected a near-exact tie here"
    assert argmax_eig(eigs) == 5, "ties must resolve to the lower index"

    # And the rule is genuinely a tolerance, not a rounding artefact.
    assert argmax_eig(np.array([0.1, 0.1 + EIG_TIE_TOLERANCE / 2])) == 0
    assert argmax_eig(np.array([0.1, 0.1 + EIG_TIE_TOLERANCE * 10])) == 1


def test_jitter_false_makes_the_whole_session_deterministic():
    """Including the repeat re-pricing. Without this the golden fixtures the
    Swift port checks against are not reproducible."""
    def run():
        post, st = Posterior(), SelectionState()
        rng = np.random.default_rng(0)
        out = []
        for slot in range(len(TRAIT_SCHEDULE)):
            d = select_design(post, slot, st, rng, jitter=False)
            st.commit(d)
            post.update(d.price, d.trait, d.price < 0.45)
            out.append((d.template, d.price, d.price_rule))
        return out

    a, b = run(), run()
    assert a == b
    assert any(r == "repeat" for _, _, r in a), "repeat rule never fired"


def test_repeat_price_equals_source_when_jitter_is_off():
    post, st = Posterior(), SelectionState()
    rng = np.random.default_rng(0)
    designs = []
    for slot in range(len(TRAIT_SCHEDULE)):
        d = select_design(post, slot, st, rng, jitter=False)
        st.commit(d)
        post.update(d.price, d.trait, d.price < 0.45)
        designs.append(d)
    by_inst = {d.instance: d for d in designs if d.template == "PATH"}
    assert by_inst[11].price == pytest.approx(by_inst[3].price, abs=1e-12)
