"""Core ML feature construction. SCHEMA §8.

    Input: [30, 9] float, zero-padded. Per decision:
      [price, engaged, log(rt_ms), approach_frac, backtracks,
       log(idle_ms+1), template_onehot_e, template_onehot_i, eye_window]

Kept in its own module so `train.py` and `export.py` cannot drift apart on the
feature order — the order below is the contract, and a mismatch would be
silent.
"""

from __future__ import annotations

import numpy as np

from priors.scenarios import N_DECISIONS

N_FEATURES = 9
FEATURE_NAMES = (
    "price", "engaged", "log_rt_ms", "approach_frac", "backtracks",
    "log_idle_ms", "template_onehot_e", "template_onehot_i", "eye_window",
)


#: Indices of the four behavioural channels. SCHEMA §7.1 calls these modelled
#: correlates, not observed ones, so `train.py` augments against over-reliance.
BEHAVIOURAL_CHANNELS = (2, 3, 4, 5)


def build_features(res, idx: np.ndarray | None = None) -> np.ndarray:
    """`(n, 30, 9)` float32 from a `SimulationResult`, in SCHEMA §8 order."""
    sl = slice(None) if idx is None else idx
    trait = res.trait[sl]
    x = np.stack(
        [
            res.price[sl],
            res.engaged[sl].astype(np.float64),
            np.log(np.maximum(res.rt_ms[sl], 1.0)),
            res.approach_frac[sl],
            res.backtracks[sl].astype(np.float64),
            np.log(res.idle_ms[sl] + 1.0),
            (trait == 0).astype(np.float64),   # template_onehot_e
            (trait == 1).astype(np.float64),   # template_onehot_i
            res.eye_window[sl].astype(np.float64),
        ],
        axis=-1,
    ).astype(np.float32)
    assert x.shape[1:] == (N_DECISIONS, N_FEATURES), x.shape
    return x


def build_targets(res, idx: np.ndarray | None = None) -> np.ndarray:
    """`(n, 3)` — theta_e, theta_i, log_beta. Uncertainty is learned, not given."""
    sl = slice(None) if idx is None else idx
    return np.stack(
        [res.true_theta_e[sl], res.true_theta_i[sl], np.log(res.true_beta[sl])], axis=-1
    ).astype(np.float32)


def normalisation(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per-feature mean/std over real (non-padded) rows."""
    flat = x.reshape(-1, N_FEATURES)
    mean = flat.mean(axis=0)
    std = np.maximum(flat.std(axis=0), 1e-3)
    return mean.astype(np.float32), std.astype(np.float32)
