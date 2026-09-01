"""Recovery evaluation. SPEC §13.1 — the go/no-go.

    "MAE of θ_e on held-out synthetic players vs decision count.
     Target: MAE < 0.06 by decision 15."

If that target is missed, the scenario design is wrong and everything
downstream is wasted effort. This module exists to find that out on day 3
rather than day 12, so it reports the failure plainly instead of reaching for
a summary statistic that flatters it.

Alongside MAE it reports bias and calibration. Bias separates two very
different failures: a genuinely uninformative design, versus an estimator
shrinking everyone toward the prior mean. Calibration checks whether the
posterior SD is honest about its own error — a confident wrong answer is
worse here than an uncertain one, per SPEC §0.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass, asdict

import numpy as np

from priors.agents import sample_population
from priors.scenarios import N_DECISIONS
from priors.simulate import SimulationResult, simulate

TARGET_MAE = 0.06
TARGET_DECISION = 15  # 1-based, per SPEC §13


@dataclass
class TraitCurves:
    mae: list[float]
    rmse: list[float]
    bias: list[float]
    mean_sd: list[float]
    sd_error_ratio: list[float]  # posterior SD ÷ actual RMSE; 1.0 is honest


def _curves(estimates: np.ndarray, sds: np.ndarray, truth: np.ndarray) -> TraitCurves:
    err = estimates - truth[:, None]
    rmse = np.sqrt((err ** 2).mean(axis=0))
    return TraitCurves(
        mae=np.abs(err).mean(axis=0).tolist(),
        rmse=rmse.tolist(),
        bias=err.mean(axis=0).tolist(),
        mean_sd=sds.mean(axis=0).tolist(),
        sd_error_ratio=(sds.mean(axis=0) / np.maximum(rmse, 1e-12)).tolist(),
    )


def evaluate(res: SimulationResult) -> dict:
    theta_e = _curves(res.mean_e_after, res.sd_e_after, res.true_theta_e)
    theta_i = _curves(res.mean_i_after, res.sd_i_after, res.true_theta_i)

    # How much evidence each trait has actually seen by each decision index.
    is_e = res.trait == 0
    counts_e = np.cumsum(is_e, axis=1).mean(axis=0)
    counts_i = np.cumsum(~is_e, axis=1).mean(axis=0)

    at15 = theta_e.mae[TARGET_DECISION - 1]
    return {
        "n_agents": res.n_agents,
        "theta_e": asdict(theta_e),
        "theta_i": asdict(theta_i),
        "mean_theta_e_decisions_by_index": counts_e.tolist(),
        "mean_theta_i_decisions_by_index": counts_i.tolist(),
        "target": {
            "metric": "MAE theta_e at decision 15",
            "target": TARGET_MAE,
            "observed": at15,
            "passed": bool(at15 < TARGET_MAE),
        },
    }


def plot(report: dict, path: str) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    x = np.arange(1, N_DECISIONS + 1)
    e, i = report["theta_e"], report["theta_i"]
    fig, axes = plt.subplots(1, 3, figsize=(16, 4.6))

    ax = axes[0]
    ax.plot(x, e["mae"], marker="o", ms=3, label=r"$\theta_e$ (exploration)")
    ax.plot(x, i["mae"], marker="s", ms=3, label=r"$\theta_i$ (integrity)")
    ax.axhline(TARGET_MAE, ls="--", c="crimson", lw=1)
    ax.axvline(TARGET_DECISION, ls=":", c="grey", lw=1)
    obs = report["target"]["observed"]
    ok = report["target"]["passed"]
    ax.plot([TARGET_DECISION], [obs], marker="*", ms=16,
            c="seagreen" if ok else "crimson", zorder=5)
    ax.annotate(f"{obs:.4f}\n{'PASS' if ok else 'FAIL'}",
                (TARGET_DECISION, obs), textcoords="offset points", xytext=(10, 6),
                color="seagreen" if ok else "crimson", fontweight="bold")
    ax.text(TARGET_DECISION + 0.4, TARGET_MAE + 0.004, "target 0.06", color="crimson", fontsize=8)
    ax.set(xlabel="decisions seen", ylabel="mean absolute error",
           title=f"Recovery MAE  (n={report['n_agents']:,})")
    ax.legend(); ax.grid(alpha=0.3)

    ax = axes[1]
    ax.plot(x, e["bias"], marker="o", ms=3, label=r"$\theta_e$")
    ax.plot(x, i["bias"], marker="s", ms=3, label=r"$\theta_i$")
    ax.axhline(0, c="black", lw=0.8)
    ax.set(xlabel="decisions seen", ylabel="mean signed error",
           title="Bias — shrinkage toward the prior")
    ax.legend(); ax.grid(alpha=0.3)

    ax = axes[2]
    ax.plot(x, e["sd_error_ratio"], marker="o", ms=3, label=r"$\theta_e$")
    ax.plot(x, i["sd_error_ratio"], marker="s", ms=3, label=r"$\theta_i$")
    ax.axhline(1.0, ls="--", c="crimson", lw=1)
    ax.set(xlabel="decisions seen", ylabel="posterior SD ÷ RMSE",
           title="Calibration — below 1.0 is overconfident")
    ax.legend(); ax.grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def format_table(report: dict) -> str:
    e, i = report["theta_e"], report["theta_i"]
    ce = report["mean_theta_e_decisions_by_index"]
    ci = report["mean_theta_i_decisions_by_index"]
    lines = [
        f"{'dec':>4} {'n_e':>5} {'MAE_e':>8} {'bias_e':>8} {'SD_e':>7} {'cal_e':>6}"
        f" | {'n_i':>5} {'MAE_i':>8} {'bias_i':>8} {'SD_i':>7} {'cal_i':>6}",
        "-" * 96,
    ]
    for k in range(N_DECISIONS):
        mark = "  <-- target" if k + 1 == TARGET_DECISION else ""
        lines.append(
            f"{k+1:>4} {ce[k]:>5.1f} {e['mae'][k]:>8.4f} {e['bias'][k]:>8.4f}"
            f" {e['mean_sd'][k]:>7.4f} {e['sd_error_ratio'][k]:>6.2f}"
            f" | {ci[k]:>5.1f} {i['mae'][k]:>8.4f} {i['bias'][k]:>8.4f}"
            f" {i['mean_sd'][k]:>7.4f} {i['sd_error_ratio'][k]:>6.2f}{mark}"
        )
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="SPEC §13.1 recovery evaluation")
    ap.add_argument("--n", type=int, default=50_000)
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--workers", type=int, default=None)
    ap.add_argument("--out", default="out")
    ap.add_argument("--sim-cache", default=None, help="path to a saved simulation .npz")
    ap.add_argument("--rt", action="store_true",
                    help="read hesitation as well as choice (rt_posterior)")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    if args.sim_cache and os.path.exists(args.sim_cache):
        print(f"loading simulation from {args.sim_cache}")
        res = SimulationResult.load(args.sim_cache)
    else:
        channel = "choice + hesitation" if args.rt else "choice only"
        print(f"simulating {args.n:,} agents (SCHEMA §7), inference: {channel}...")
        pop = sample_population(args.n, np.random.default_rng(args.seed))
        res = simulate(pop, seed=args.seed, workers=args.workers, use_rt=args.rt)
        if args.sim_cache:
            res.save(args.sim_cache)
            print(f"saved simulation to {args.sim_cache}")

    report = evaluate(res)
    print()
    print(format_table(report))

    with open(os.path.join(args.out, "recovery.json"), "w") as f:
        json.dump(report, f, indent=2)
    plot(report, os.path.join(args.out, "recovery.png"))

    t = report["target"]
    print()
    print("=" * 96)
    print(f"SPEC §13.1 go/no-go: MAE θ_e at decision {TARGET_DECISION}"
          f" = {t['observed']:.4f}  (target < {t['target']})")
    print("VERDICT:", "PASS" if t["passed"] else "FAIL — scenario design needs rethinking")
    print("=" * 96)
    print(f"\nwrote {args.out}/recovery.png and {args.out}/recovery.json")
    return 0 if t["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
