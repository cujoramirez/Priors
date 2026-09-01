"""Scenario templates and session structure. SPEC §3, §4, §4.1, §4.2, §5.1.

Pure data. No logic lives here — selection is `ado.py`, inference is
`posterior.py`. Anything in this module is a value quoted from the contract,
and every constant carries the section it came from.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Mapping, Sequence

TraitName = Literal["theta_e", "theta_i"]
TemplateID = Literal["PATH", "DETOUR", "ERROR", "CREDIT", "GIVE", "TRADE"]


# --------------------------------------------------------------------------
# Parameter grids — SPEC §3.1, §3.2, §3.3
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class GridSpec:
    """A discretised parameter axis. `log` selects geometric spacing."""

    lo: float
    hi: float
    n: int
    log: bool = False


#: θ_e — exploration threshold. Uniform over [0.05, 0.85], 33 points. SPEC §3.1
THETA_E = GridSpec(lo=0.05, hi=0.85, n=33)

#: θ_i — integrity threshold. Uniform over [0.02, 0.70], 25 points. SPEC §3.2
THETA_I = GridSpec(lo=0.02, hi=0.70, n=25)

#: β — decisiveness. 2.0–30.0, 15 points, log-spaced. SPEC §3.3
BETA = GridSpec(lo=2.0, hi=30.0, n=15, log=True)

#: 33 × 25 × 15 = 12,375 cells. SPEC §3.4
N_POSTERIOR_CELLS = THETA_E.n * THETA_I.n * BETA.n

TRAIT_GRIDS: Mapping[TraitName, GridSpec] = {
    "theta_e": THETA_E,
    "theta_i": THETA_I,
}


# --------------------------------------------------------------------------
# Templates — SPEC §4, §4.1
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Template:
    """One scenario template.

    `price_lo`/`price_hi` are the trait's prior support (SPEC §4.1): candidate
    prices outside it carry almost no information, and a 30-decision budget
    cannot afford them.
    """

    id: TemplateID
    trait: TraitName
    price_means: str
    instances: int
    skins: tuple[str, ...]

    @property
    def price_lo(self) -> float:
        return TRAIT_GRIDS[self.trait].lo

    @property
    def price_hi(self) -> float:
        return TRAIT_GRIDS[self.trait].hi


TEMPLATES: Mapping[TemplateID, Template] = {
    t.id: t
    for t in (
        Template(
            id="PATH",
            trait="theta_e",
            price_means="P(lose 1 lantern)",
            instances=12,
            skins=("unlit path", "cellar door", "gap in hedge"),
        ),
        Template(
            id="DETOUR",
            trait="theta_e",
            price_means="P(waste 90s)",
            instances=4,
            skins=("long way round", "closed gate"),
        ),
        Template(
            id="ERROR",
            trait="theta_i",
            price_means="cost of going back",
            instances=4,
            skins=("wrong house", "dropped lantern"),
        ),
        Template(
            id="CREDIT",
            trait="theta_i",
            price_means="size of undeserved reward",
            instances=3,
            skins=("villager thanks you for another's work",),
        ),
        Template(
            id="GIVE",
            trait="theta_i",
            price_means="cost of giving",
            instances=4,
            skins=("villager needs your lantern",),
        ),
        # TRADE price is P(gamble pays nothing) = 1 - p_win, so the SPEC §3.4
        # choice model applies unchanged with no per-template sign flip. SPEC §4.2
        Template(
            id="TRADE",
            trait="theta_e",
            price_means="P(gamble pays nothing) = 1 - p_win",
            instances=3,
            skins=("certain 1 vs p-chance of 3",),
        ),
    )
}

#: SPEC §4 — "Total: 30 decisions."
N_DECISIONS = 30

TEMPLATES_BY_TRAIT: Mapping[TraitName, tuple[TemplateID, ...]] = {
    "theta_e": ("PATH", "DETOUR", "TRADE"),
    "theta_i": ("ERROR", "CREDIT", "GIVE"),
}


# --------------------------------------------------------------------------
# Slot schedule — SPEC §5.1
# --------------------------------------------------------------------------

#: The trait of each of the 30 slots. Authored, not adaptive: ADO chooses which
#: eligible template fills a slot and at what price, but never the trait.
#:
#: Spread so the 11 θ_i slots sit as evenly as possible among the 19 θ_e slots
#: (θ_e runs cap at 2; θ_i never repeats back-to-back).
TRAIT_SCHEDULE: Sequence[TraitName] = (
    "theta_e", "theta_e", "theta_i", "theta_e", "theta_e",
    "theta_i", "theta_e", "theta_e", "theta_i", "theta_e",
    "theta_i", "theta_e", "theta_e", "theta_i", "theta_e",
    "theta_e", "theta_i", "theta_e", "theta_e", "theta_i",
    "theta_e", "theta_i", "theta_e", "theta_e", "theta_i",
    "theta_e", "theta_e", "theta_i", "theta_e", "theta_i",
)


# --------------------------------------------------------------------------
# Design selection constants — SPEC §4, §5, §6.1
# --------------------------------------------------------------------------

#: SPEC §5.2 — "12 candidate prices spanning its valid range."
N_PRICE_CANDIDATES = 12

#: SPEC §5.4 — "Add ±0.02 jitter so prices don't look mechanical."
PRICE_JITTER = 0.02

#: SPEC §5 curiosity override — a template is blocked once the previous two
#: slots BOTH used it, capping any template at a run of two.
CURIOSITY_RUN_LIMIT = 2

#: SPEC §4 — PATH instance #11 is re-priced within ±0.03 of PATH instance #3.
#: These are 1-based PATH *occurrence* counts, not slot indices.
REPEAT_TEMPLATE: TemplateID = "PATH"
REPEAT_SOURCE_INSTANCE = 3
REPEAT_TARGET_INSTANCE = 11
REPEAT_TOLERANCE = 0.03

#: SPEC §6.1 — once posterior SD for θ_e drops below this, the next PATH is
#: priced at the posterior mean: genuinely 50/50 for that player.
FALSIFICATION_SD_THRESHOLD = 0.06

#: SPEC §6.3 — the eye fires once, at a decision index drawn from this
#: inclusive range.
EYE_DECISION_INDEX_RANGE = (14, 20)

#: SCHEMA §1 — eye_window is true within ±240s of eye_timestamp.
EYE_WINDOW_SECONDS = 240.0


def total_instances() -> int:
    return sum(t.instances for t in TEMPLATES.values())
