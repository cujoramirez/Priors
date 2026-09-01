"""Adaptive Design Optimisation. SPEC §5, §5.1, §6.1.

    EIG(d) = H[posterior] − E_y[ H[posterior | y, d] ]

Two things are worth knowing before reading this module.

**EIG cannot choose the template.** Under SPEC §3.4 the likelihood of a
response depends only on the price and which trait the template maps to —
never on the template's identity. So PATH, DETOUR and TRADE have *identical*
EIG at the same price, as do ERROR, CREDIT and GIVE. "ADO picks the template"
(SPEC §5.1) is therefore always an exact tie, and something outside EIG has to
break it. This module breaks it by proportional spread (`_template_priority`),
which is what actually delivers the variety the curiosity override is reaching
for. That tie-break is an engineering decision, not a SPEC quote.

**EIG is computed as mutual information.** `H[posterior] − E_y H[posterior|y]`
equals `H[Y] − E_params H[Y|params]`, because mutual information is symmetric.
The second form needs no posterior renormalisation per outcome and runs on the
2-D `(θ, β)` marginal rather than all 12,375 cells — the likelihood is constant
along the other trait's axis, so the reduction is exact, not an approximation.
`eig_direct` implements the SPEC form literally; `test_ado.py` asserts the two
agree to 1e-12. The Swift port should carry the fast form and the same test.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from priors.posterior import Posterior
from priors.scenarios import (
    CURIOSITY_RUN_LIMIT,
    FALSIFICATION_SD_THRESHOLD,
    N_PRICE_CANDIDATES,
    PRICE_JITTER,
    REPEAT_SOURCE_INSTANCE,
    REPEAT_TARGET_INSTANCE,
    REPEAT_TEMPLATE,
    REPEAT_TOLERANCE,
    TEMPLATES,
    TEMPLATES_BY_TRAIT,
    TRAIT_GRIDS,
    TRAIT_SCHEDULE,
    TemplateID,
    TraitName,
)


#: Two candidate prices equidistant from the posterior mean have mathematically
#: identical EIG — at the uniform prior, indices 5 and 6 differ by 1.7e-16, pure
#: float noise. NumPy and Swift disagree on which is larger, so a bare argmax
#: makes the Swift port diverge at slot 0 and cascade from there.
#:
#: The tie-break is therefore explicit: take the first price better by more than
#: this tolerance. Both implementations then agree by construction, which is
#: stronger than SPEC §5's "within one grid step" and much easier to test.
EIG_TIE_TOLERANCE = 1e-12


def argmax_eig(eigs: np.ndarray) -> int:
    """First index whose EIG exceeds the running best by more than the tie
    tolerance. Deterministic across languages; see EIG_TIE_TOLERANCE."""
    best = 0
    for k in range(1, len(eigs)):
        if eigs[k] > eigs[best] + EIG_TIE_TOLERANCE:
            best = k
    return best


def candidate_prices(trait: TraitName, n: int = N_PRICE_CANDIDATES) -> np.ndarray:
    """SPEC §5.2 — 12 candidate prices spanning the template's valid range."""
    grid = TRAIT_GRIDS[trait]
    return np.linspace(grid.lo, grid.hi, n, dtype=np.float64)


def _binary_entropy(p: np.ndarray) -> np.ndarray:
    """Entropy of a Bernoulli, in nats, safe at p ∈ {0, 1}."""
    p = np.clip(p, 1e-300, 1.0 - 1e-16)
    return -(p * np.log(p) + (1.0 - p) * np.log1p(-p))


def _trait_marginal(post, trait: TraitName) -> tuple[np.ndarray, np.ndarray]:
    """The `(θ, β)` marginal and its θ axis, for the trait in play.

    Accepts either `Posterior` or `rt_posterior.BehaviouralPosterior`; both
    expose `trait_beta_marginal`.
    """
    theta = post.theta_e if trait == "theta_e" else post.theta_i
    return post.trait_beta_marginal(trait), theta


def expected_information_gain(
    post, prices: np.ndarray, trait: TraitName
) -> np.ndarray:
    """EIG in nats for each candidate price. SPEC §5.3, mutual-information form."""
    w, theta = _trait_marginal(post, trait)          # (n_theta, n_beta), (n_theta,)
    beta = post.beta

    z = beta[None, None, :] * (
        np.asarray(prices, dtype=np.float64)[:, None, None] - theta[None, :, None]
    )
    p_engage = np.exp(-np.logaddexp(0.0, z))          # (n_prices, n_theta, n_beta)

    predictive = np.tensordot(p_engage, w, axes=([1, 2], [0, 1]))
    expected_conditional = np.tensordot(_binary_entropy(p_engage), w, axes=([1, 2], [0, 1]))
    return _binary_entropy(predictive) - expected_conditional


def eig_direct(post: Posterior, price: float, trait: TraitName) -> float:
    """SPEC §5.3 written out literally, over the full joint. Reference only —
    `expected_information_gain` is the same number, computed cheaply."""
    h_before = post.entropy()
    total = 0.0
    for engaged in (True, False):
        ll = post.log_lik(price, trait, engaged)
        log_unnorm = post.log_post + ll
        m = float(np.max(log_unnorm))
        log_py = m + float(np.log(np.sum(np.exp(log_unnorm - m))))
        p_out = np.exp(log_unnorm - log_py)
        nz = p_out > 0.0
        total += float(np.exp(log_py)) * float(-np.sum(p_out[nz] * np.log(p_out[nz])))
    return h_before - total


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Design:
    """One selected design, ready to present."""

    slot: int
    template: TemplateID
    trait: TraitName
    price: float
    skin: str
    instance: int
    eig: float
    price_rule: str  # "eig" | "repeat" | "falsification"
    curiosity_override: bool
    is_repeat_of: int | None = None


@dataclass
class SelectionState:
    """Mutable bookkeeping across a session's 30 slots."""

    remaining: dict[TemplateID, int] = field(
        default_factory=lambda: {tid: t.instances for tid, t in TEMPLATES.items()}
    )
    used: dict[TemplateID, int] = field(
        default_factory=lambda: {tid: 0 for tid in TEMPLATES}
    )
    last_slot: dict[TemplateID, int] = field(
        default_factory=lambda: {tid: -(10**6) for tid in TEMPLATES}
    )
    recent: list[TemplateID] = field(default_factory=list)
    repeat_source_price: float | None = None
    repeat_source_slot: int | None = None
    falsification_fired: bool = False

    def commit(self, design: Design) -> None:
        self.remaining[design.template] -= 1
        self.used[design.template] += 1
        self.last_slot[design.template] = design.slot
        self.recent.append(design.template)
        if (
            design.template == REPEAT_TEMPLATE
            and design.instance == REPEAT_SOURCE_INSTANCE
        ):
            self.repeat_source_price = design.price
            self.repeat_source_slot = design.slot
        if design.price_rule == "falsification":
            self.falsification_fired = True


def _blocked_by_curiosity(state: SelectionState) -> TemplateID | None:
    """SPEC §5.1 — a template is blocked once the previous two slots both used
    it. That caps any template at a run of two."""
    tail = state.recent[-CURIOSITY_RUN_LIMIT:]
    if len(tail) == CURIOSITY_RUN_LIMIT and len(set(tail)) == 1:
        return tail[0]
    return None


def _template_priority(state: SelectionState, tid: TemplateID) -> float:
    """Highest-averages (D'Hondt) spread: quota ÷ (times used + 1).

    Keeps each template's share of its trait's slots close to its quota share
    throughout the session, instead of front-loading the large quota and
    leaving a run of identical scenarios at the end.
    """
    return TEMPLATES[tid].instances / (state.used[tid] + 1.0)


def select_design(
    post,
    slot: int,
    state: SelectionState,
    rng: np.random.Generator,
    jitter: bool = True,
) -> Design:
    """Choose the template and price for one slot. SPEC §5, §5.1, §6.1."""
    trait = TRAIT_SCHEDULE[slot]

    eligible = [t for t in TEMPLATES_BY_TRAIT[trait] if state.remaining[t] > 0]
    if not eligible:
        raise RuntimeError(f"slot {slot}: no template with quota left for {trait}")

    # Curiosity override, unless honouring it would leave nothing to present.
    blocked = _blocked_by_curiosity(state)
    override = bool(blocked in eligible and len(eligible) > 1)
    if override:
        eligible = [t for t in eligible if t != blocked]

    prices = candidate_prices(trait)
    eigs = expected_information_gain(post, prices, trait)
    best = argmax_eig(eigs)
    best_price, best_eig = float(prices[best]), float(eigs[best])

    # Every eligible template shares `best_eig`, so this is a pure tie-break.
    template = max(
        eligible,
        key=lambda t: (
            _template_priority(state, t),
            slot - state.last_slot[t],
            -list(TEMPLATES).index(t),
        ),
    )

    instance = state.used[template] + 1
    lo, hi = TEMPLATES[template].price_lo, TEMPLATES[template].price_hi
    price_rule, is_repeat_of = "eig", None
    mean_e, sd_e = post.mean_sd("theta_e")

    if (
        template == REPEAT_TEMPLATE
        and instance == REPEAT_TARGET_INSTANCE
        and state.repeat_source_price is not None
    ):
        # SPEC §4 — re-price within ±0.03 of the source instance for
        # test-retest. Takes precedence over falsification pricing, which is
        # not tied to a specific instance and simply fires at the next PATH.
        #
        # `jitter` gates this offset too. It is not cosmetic jitter — the ±0.03
        # spread is what makes the pair a re-test rather than a repeat — but
        # `jitter=False` has to make the whole selection deterministic, or the
        # golden fixtures cannot be reproduced by the Swift port.
        offset = rng.uniform(-REPEAT_TOLERANCE, REPEAT_TOLERANCE) if jitter else 0.0
        price = float(np.clip(state.repeat_source_price + offset, lo, hi))
        price_rule, is_repeat_of = "repeat", state.repeat_source_slot
    elif (
        template == REPEAT_TEMPLATE
        and not state.falsification_fired
        and sd_e < FALSIFICATION_SD_THRESHOLD
    ):
        # SPEC §6.1 — the hardest possible decision for this player.
        price = float(np.clip(mean_e, lo, hi))
        price_rule = "falsification"
    else:
        offset = rng.uniform(-PRICE_JITTER, PRICE_JITTER) if jitter else 0.0
        price = float(np.clip(best_price + offset, lo, hi))

    skins = TEMPLATES[template].skins
    return Design(
        slot=slot,
        template=template,
        trait=trait,
        price=price,
        skin=skins[(instance - 1) % len(skins)],
        instance=instance,
        eig=best_eig,
        price_rule=price_rule,
        curiosity_override=override,
        is_repeat_of=is_repeat_of,
    )
