"""Does banding the price cost recovery? SPEC-GAME.md §2.2-2.3.

The diegetic-pricing proposal replaces the printed number with one of a small
set of authored phrases plus a visual intensity. A player reading "you cannot
see the far end" instead of "62%" is not answering the exact price ADO chose —
they are answering the band's rough midpoint, blurred by whatever noise their
own perception of "how dark is dark" adds on top.

This is a measurement change, not a presentation change: it is the STIMULUS
that gets noisier, not the inference. The full ADO + BehaviouralPosterior loop
still selects and logs the exact continuous `design.price` it always did, and
`experiments/rt_channel.py` / the real pipeline (`priors.evaluate --rt`) is
what produced the 0.0217 baseline this compares against. Only the response
generation changes: choice and all four behavioural channels (SCHEMA §7.1) are
now driven by

    p_hat = band_midpoint(price) + Normal(0, sigma)

instead of the true price, because a player cannot act on, or hesitate near, a
number they were never shown. The posterior update after the fact still
conditions on the true price, exactly as SCHEMA §1 logs it — the researcher
knows what was authored; the player only ever felt the band.

Run: PYTHONPATH=. .venv/bin/python experiments/perceived_price.py
"""

from __future__ import annotations

import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np

from priors.agents import AgentPopulation, p_engage, sample_behaviour, sample_population
from priors.ado import SelectionState, select_design
from priors.rt_posterior import BehaviouralPosterior
from priors.scenarios import TRAIT_GRIDS

TARGET_DECISION = 15
BASELINE_MAE = 0.0217  # FINDINGS.md — full pipeline, choice + hesitation, no banding.
COST_BUDGET = 0.01     # SPEC-GAME.md §2.3 — band count goes up if this is exceeded.


def band_midpoint(price: float, trait: str, n_bands: int) -> float:
    """The authored phrase's representative price — SPEC-GAME.md §2.2's ladder,
    generalised to `n_bands` so the count can be swept."""
    lo, hi = TRAIT_GRIDS[trait].lo, TRAIT_GRIDS[trait].hi
    edges = np.linspace(lo, hi, n_bands + 1)
    idx = int(np.clip(np.searchsorted(edges, price, side="right") - 1, 0, n_bands - 1))
    return 0.5 * (edges[idx] + edges[idx + 1])


def _run_chunk(args) -> np.ndarray:
    pop: AgentPopulation
    pop, offset, seed, n_bands, sigma, n_dec = args
    n = len(pop)
    est = np.zeros(n)
    sd = np.zeros(n)

    for i in range(n):
        agent = pop[i]
        rng = np.random.default_rng([seed, offset + i])
        post = BehaviouralPosterior()
        state = SelectionState()

        for slot in range(n_dec):
            design = select_design(post, slot, state, rng)
            trait = design.trait
            theta = agent.theta_for(trait)

            if n_bands is None:
                p_hat = design.price  # baseline: unbanded, exact price shown
            else:
                mid = band_midpoint(design.price, trait, n_bands)
                p_hat = float(np.clip(mid + rng.normal(0.0, sigma), 0.0, 1.0))

            engaged = bool(rng.random() < p_engage(p_hat, theta, agent.beta))
            beh = sample_behaviour(
                np.array([p_hat]), np.array([theta]), np.array([agent.rt_base_ms]), rng
            )

            state.commit(design)
            # Inference conditions on the TRUE authored price, per SCHEMA §1 —
            # the log records what was designed, not what was felt.
            post.update(design.price, trait, engaged, rt_ms=float(beh.rt_ms[0]))

        (me, se), _ = post.summarise()
        est[i] = me
        sd[i] = se

    return np.stack([est, sd])


def evaluate(pop: AgentPopulation, n_bands: int | None, sigma: float,
             n_dec: int = TARGET_DECISION, seed: int = 20260901, workers: int = 10,
             chunk_size: int = 150):
    n = len(pop)
    chunks = [
        (pop.slice(a, min(a + chunk_size, n)), a, seed, n_bands, sigma, n_dec)
        for a in range(0, n, chunk_size)
    ]
    with ProcessPoolExecutor(max_workers=workers) as ex:
        r = np.concatenate(list(ex.map(_run_chunk, chunks)), axis=1)
    est, sd = r
    err = est - pop.theta_e
    rmse = float(np.sqrt((err ** 2).mean()))
    mae = float(np.abs(err).mean())
    cal = float(sd.mean() / max(rmse, 1e-12))
    return mae, cal


if __name__ == "__main__":
    N = 1500
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N} agents, decision {TARGET_DECISION}. Full ADO + BehaviouralPosterior "
          f"pipeline (templates, quotas, curiosity, jitter). cal = posterior SD / RMSE.\n")
    print(f"  {'condition':40s} {'MAE':>7}  {'cal':>5}  {'vs baseline ' + str(BASELINE_MAE):>18}")
    print("  " + "-" * 78)

    t0 = time.time()
    mae0, cal0 = evaluate(pop, None, 0.0)
    print(f"  {'no banding (sanity check)':40s} {mae0:.4f}  {cal0:5.2f}  "
          f"{'reproduces FINDINGS.md' if abs(mae0 - BASELINE_MAE) < 0.01 else 'DIVERGES from FINDINGS.md':>18}")

    rows = []
    for n_bands in (7,):
        for sigma in (0.02, 0.05, 0.10):
            mae, cal = evaluate(pop, n_bands, sigma)
            cost = mae - mae0
            verdict = "within budget" if cost <= COST_BUDGET else "OVER BUDGET"
            label = f"{n_bands} bands, sigma={sigma}"
            print(f"  {label:40s} {mae:.4f}  {cal:5.2f}  {f'+{cost:.4f} {verdict}':>18}")
            rows.append((n_bands, sigma, mae, cal, cost))

    print(f"\n  elapsed: {time.time()-t0:.0f}s")
    print("\nIf any row is OVER BUDGET, re-run with n_bands in (9, 12, 15) added to the loop above.")
