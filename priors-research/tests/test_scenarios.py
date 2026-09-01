"""scenarios.py is pure data quoted from SPEC. These tests assert the quotes."""

import itertools

import pytest

from priors import scenarios as s


def test_six_templates_exactly():
    assert set(s.TEMPLATES) == {"PATH", "DETOUR", "ERROR", "CREDIT", "GIVE", "TRADE"}


@pytest.mark.parametrize(
    "tid,trait,instances",
    [
        ("PATH", "theta_e", 12),
        ("DETOUR", "theta_e", 4),
        ("ERROR", "theta_i", 4),
        ("CREDIT", "theta_i", 3),
        ("GIVE", "theta_i", 4),
        ("TRADE", "theta_e", 3),
    ],
)
def test_template_table_matches_spec_section_4(tid, trait, instances):
    t = s.TEMPLATES[tid]
    assert t.trait == trait
    assert t.instances == instances


def test_instances_total_thirty():
    """SPEC §4 — 'Total: 30 decisions.'"""
    assert s.total_instances() == s.N_DECISIONS == 30


def test_grid_sizes_match_spec_section_3():
    assert (s.THETA_E.lo, s.THETA_E.hi, s.THETA_E.n) == (0.05, 0.85, 33)
    assert (s.THETA_I.lo, s.THETA_I.hi, s.THETA_I.n) == (0.02, 0.70, 25)
    assert (s.BETA.lo, s.BETA.hi, s.BETA.n, s.BETA.log) == (2.0, 30.0, 15, True)
    assert s.N_POSTERIOR_CELLS == 12_375


def test_price_range_is_trait_prior_support():
    """SPEC §4.1 — no template invents a range of its own."""
    for t in s.TEMPLATES.values():
        grid = s.TRAIT_GRIDS[t.trait]
        assert (t.price_lo, t.price_hi) == (grid.lo, grid.hi)


def test_trade_maps_to_theta_e():
    """SPEC §4.2 — price is P(gamble pays nothing), so TRADE stays on θ_e."""
    assert s.TEMPLATES["TRADE"].trait == "theta_e"


def test_schedule_length_and_trait_counts():
    assert len(s.TRAIT_SCHEDULE) == 30
    assert s.TRAIT_SCHEDULE.count("theta_e") == 19
    assert s.TRAIT_SCHEDULE.count("theta_i") == 11


def test_quotas_exactly_fill_their_trait_slots():
    """The feasibility invariant the ADO selector relies on.

    Per trait, template quotas sum to exactly the number of slots of that
    trait. That is what lets the selector pick any template with remaining
    quota without ever painting itself into a corner.
    """
    for trait, tids in s.TEMPLATES_BY_TRAIT.items():
        quota = sum(s.TEMPLATES[t].instances for t in tids)
        assert quota == s.TRAIT_SCHEDULE.count(trait), trait


def test_every_template_reachable_from_its_trait_pool():
    pooled = set(itertools.chain.from_iterable(s.TEMPLATES_BY_TRAIT.values()))
    assert pooled == set(s.TEMPLATES)
    for trait, tids in s.TEMPLATES_BY_TRAIT.items():
        assert all(s.TEMPLATES[t].trait == trait for t in tids)


def test_trait_runs_never_exceed_two():
    """A run of three θ_e slots would let one template appear three times in a
    row, which the curiosity override (SPEC §5.1) forbids."""
    runs = [len(list(g)) for _, g in itertools.groupby(s.TRAIT_SCHEDULE)]
    assert max(runs) <= 2


def test_repeat_pair_constants():
    """SPEC §4 — PATH #11 re-priced within ±0.03 of PATH #3."""
    assert s.REPEAT_TEMPLATE == "PATH"
    assert s.REPEAT_SOURCE_INSTANCE == 3
    assert s.REPEAT_TARGET_INSTANCE == 11
    assert s.REPEAT_TOLERANCE == 0.03
    assert s.REPEAT_TARGET_INSTANCE <= s.TEMPLATES["PATH"].instances


def test_event_constants():
    assert s.FALSIFICATION_SD_THRESHOLD == 0.06     # SPEC §6.1
    assert s.EYE_DECISION_INDEX_RANGE == (14, 20)   # SPEC §6.3
    assert s.EYE_WINDOW_SECONDS == 240.0            # SCHEMA §1
    assert s.N_PRICE_CANDIDATES == 12               # SPEC §5.2
    assert s.PRICE_JITTER == 0.02                   # SPEC §5.4


def test_every_template_has_at_least_one_skin():
    for t in s.TEMPLATES.values():
        assert len(t.skins) >= 1
