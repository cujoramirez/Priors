"""Amortised estimator. SCHEMA §8.

    Input:  [30, 9] zero-padded
    Output: [4] — [theta_e_hat, theta_i_hat, log_beta_hat, uncertainty_hat]

**Architecture note.** The grid posterior is order-invariant — multiplicative
updates commute, and `test_posterior.py::test_update_order_does_not_matter`
pins that. So the estimand this network approximates does not depend on
decision order either, and the encoder is deliberately permutation-invariant:
a per-decision MLP followed by masked mean/max pooling. A sequence model would
have to spend capacity learning to ignore order, and would overfit whatever
ordering the ADO schedule happens to produce.

**Role, per SCHEMA §8 and SPEC §2.8.** This never produces a claim. It is fast
intuition and continuous-feature handling. If it disagrees with the grid
posterior by more than 2 SD the disagreement is logged, not surfaced.

`uncertainty_hat` is trained by Gaussian NLL against θ_e, so it is a calibrated
predicted SD rather than an arbitrary confidence score. A model that cannot say
how unsure it is has no business near this project.
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
import torch
import torch.nn as nn

from priors.features import (
    BEHAVIOURAL_CHANNELS, N_FEATURES, build_features, build_targets, normalisation,
)
from priors.scenarios import N_DECISIONS, THETA_E, THETA_I
from priors.simulate import SimulationResult


class PriorsEstimator(nn.Module):
    """~13k parameters, comfortably inside the 500 KB budget."""

    def __init__(self, hidden: int = 64):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(N_FEATURES, hidden), nn.GELU(),
            nn.Linear(hidden, hidden), nn.GELU(),
        )
        self.head = nn.Sequential(
            nn.Linear(hidden * 2, hidden), nn.GELU(),
            nn.Linear(hidden, 4),
        )
        self.register_buffer("mean", torch.zeros(N_FEATURES))
        self.register_buffer("std", torch.ones(N_FEATURES))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # A padded row is all-zero across every feature (SCHEMA §8).
        mask = (x.abs().sum(dim=-1, keepdim=True) > 0).float()
        h = self.encoder((x - self.mean) / self.std) * mask

        n = mask.sum(dim=1).clamp(min=1.0)
        mean_pool = h.sum(dim=1) / n
        max_pool = h.masked_fill(mask == 0, -1e4).max(dim=1).values
        raw = self.head(torch.cat([mean_pool, max_pool], dim=-1))

        # Squash the traits onto their SPEC §3.1/§3.2 supports so the network
        # cannot emit a value the grid has no cell for.
        theta_e = THETA_E.lo + (THETA_E.hi - THETA_E.lo) * torch.sigmoid(raw[:, 0])
        theta_i = THETA_I.lo + (THETA_I.hi - THETA_I.lo) * torch.sigmoid(raw[:, 1])
        log_beta = raw[:, 2]
        uncertainty = nn.functional.softplus(raw[:, 3]) + 1e-3
        return torch.stack([theta_e, theta_i, log_beta, uncertainty], dim=-1)


def gaussian_nll(pred_mean, pred_sd, target):
    return (torch.log(pred_sd) + 0.5 * ((target - pred_mean) / pred_sd) ** 2).mean()


def augment(x: torch.Tensor, drop_p: float, scramble_p: float, gen: torch.Generator
            ) -> torch.Tensor:
    """Break the behavioural channels on a fraction of each batch.

    Without this the network learns SCHEMA §7.1's generator formula and skips
    the choice channel entirely: an unaugmented model scores 0.0103 intact but
    0.1092 with the behavioural channels scrambled — worse than the choice-only
    grid posterior it is supposed to approximate. Since SCHEMA §7.1 states
    outright that those features are modelled correlates rather than observed
    ones, a model leaning on them is measuring our own assumption.

    Dropping (zeroing) teaches it to fall back on choice. Scrambling —
    preserving each channel's marginal while destroying its correspondence
    with price — teaches it that an uninformative channel is uninformative,
    rather than that a *missing* one is.
    """
    x = x.clone()
    n, t, _ = x.shape
    ch = torch.tensor(BEHAVIOURAL_CHANNELS, device=x.device)

    drop = torch.rand(n, len(ch), generator=gen, device=x.device) < drop_p
    x[:, :, ch] = x[:, :, ch] * (~drop).float().unsqueeze(1)

    scram = torch.rand(n, generator=gen, device=x.device) < scramble_p
    if scram.any():
        idx = torch.argsort(torch.rand(int(scram.sum()), t, generator=gen, device=x.device), dim=1)
        sub = x[scram][:, :, ch]
        x[scram] = x[scram].index_copy(
            2, ch, torch.gather(sub, 1, idx.unsqueeze(-1).expand(-1, -1, len(ch)))
        )
    return x


def train(res: SimulationResult, epochs: int = 40, batch: int = 512, seed: int = 0,
          holdout: float = 0.10, device: str = "cpu",
          drop_p: float = 0.30, scramble_p: float = 0.25) -> tuple[PriorsEstimator, dict]:
    rng = np.random.default_rng(seed)
    n = res.n_agents
    perm = rng.permutation(n)
    n_val = int(n * holdout)
    val_idx, train_idx = perm[:n_val], perm[n_val:]

    xtr, ytr = build_features(res, train_idx), build_targets(res, train_idx)
    xva, yva = build_features(res, val_idx), build_targets(res, val_idx)

    model = PriorsEstimator().to(device)
    mean, std = normalisation(xtr)
    model.mean.copy_(torch.from_numpy(mean))
    model.std.copy_(torch.from_numpy(std))

    xtr_t = torch.from_numpy(xtr).to(device); ytr_t = torch.from_numpy(ytr).to(device)
    xva_t = torch.from_numpy(xva).to(device); yva_t = torch.from_numpy(yva).to(device)

    gen = torch.Generator(device=device); gen.manual_seed(seed)
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)

    history = []
    for ep in range(epochs):
        model.train()
        order = torch.randperm(len(xtr_t), device=device)
        total = 0.0
        for i in range(0, len(order), batch):
            b = order[i:i + batch]
            out = model(augment(xtr_t[b], drop_p, scramble_p, gen))
            loss = (
                gaussian_nll(out[:, 0], out[:, 3], ytr_t[b, 0])
                + nn.functional.mse_loss(out[:, 1], ytr_t[b, 1]) * 4.0
                + nn.functional.mse_loss(out[:, 2], ytr_t[b, 2]) * 0.5
            )
            opt.zero_grad(); loss.backward(); opt.step()
            total += float(loss.detach()) * len(b)
        sched.step()

        model.eval()
        with torch.no_grad():
            v = model(xva_t)
            mae_e = float((v[:, 0] - yva_t[:, 0]).abs().mean())
            mae_i = float((v[:, 1] - yva_t[:, 1]).abs().mean())
        history.append({"epoch": ep, "train_loss": total / len(order),
                        "val_mae_theta_e": mae_e, "val_mae_theta_i": mae_i})
        if ep % 5 == 0 or ep == epochs - 1:
            print(f"  epoch {ep:3d}  loss={total/len(order):8.4f}  "
                  f"val MAE θ_e={mae_e:.4f}  θ_i={mae_i:.4f}")

    model.eval()
    with torch.no_grad():
        v = model(xva_t).cpu().numpy()
    y = yva
    err_e = v[:, 0] - y[:, 0]
    rmse_e = float(np.sqrt((err_e ** 2).mean()))
    grid_e = res.mean_e_after[val_idx, -1]

    with torch.no_grad():
        blind = xva_t.clone()
        blind[:, :, torch.tensor(BEHAVIOURAL_CHANNELS)] = 0.0
        v_blind = model(blind).cpu().numpy()
    mae_blind = float(np.abs(v_blind[:, 0] - y[:, 0]).mean())

    report = {
        "n_train": len(train_idx), "n_val": len(val_idx),
        "val_mae_theta_e_no_behaviour": mae_blind,
        "params": sum(p.numel() for p in model.parameters()),
        "val_mae_theta_e": float(np.abs(err_e).mean()),
        "val_mae_theta_i": float(np.abs(v[:, 1] - y[:, 1]).mean()),
        "val_mae_log_beta": float(np.abs(v[:, 2] - y[:, 2]).mean()),
        "val_rmse_theta_e": rmse_e,
        "val_bias_theta_e": float(err_e.mean()),
        "calibration_theta_e": float(v[:, 3].mean() / max(rmse_e, 1e-12)),
        "grid_posterior_mae_theta_e": float(np.abs(grid_e - y[:, 0]).mean()),
        "mean_abs_disagreement_with_grid": float(np.abs(v[:, 0] - grid_e).mean()),
        "frac_disagree_over_2sd": float(
            (np.abs(v[:, 0] - grid_e) > 2 * res.sd_e_after[val_idx, -1]).mean()
        ),
        "history": history,
    }
    return model, report


def main() -> int:
    ap = argparse.ArgumentParser(description="SCHEMA §8 amortised estimator")
    ap.add_argument("--sim", default="out/sim50k_rt.npz")
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--out", default="out")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    print(f"loading {args.sim}")
    res = SimulationResult.load(args.sim)
    print(f"training on {res.n_agents:,} agents, 10% held out\n")
    model, report = train(res, epochs=args.epochs)

    torch.save(model.state_dict(), os.path.join(args.out, "estimator.pt"))
    with open(os.path.join(args.out, "train_report.json"), "w") as f:
        json.dump(report, f, indent=2)

    print(f"\n  parameters           {report['params']:,}  "
          f"({report['params']*4/1024:.0f} KB float32)")
    print(f"  val MAE θ_e          {report['val_mae_theta_e']:.4f}"
          f"   (grid posterior: {report['grid_posterior_mae_theta_e']:.4f})")
    print(f"  val MAE θ_i          {report['val_mae_theta_i']:.4f}")
    print(f"  val MAE log β        {report['val_mae_log_beta']:.4f}")
    print(f"  bias θ_e             {report['val_bias_theta_e']:+.4f}")
    print(f"  calibration θ_e      {report['calibration_theta_e']:.2f}   (1.0 is honest)")
    print(f"  disagreement > 2 SD  {report['frac_disagree_over_2sd']*100:.1f}%  "
          f"(logged, never surfaced — SCHEMA §8)")
    print(f"  MAE θ_e w/o behaviour {report['val_mae_theta_e_no_behaviour']:.4f}"
          f"   (must stay near the grid posterior, not collapse)")
    print(f"\nwrote {args.out}/estimator.pt and {args.out}/train_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
