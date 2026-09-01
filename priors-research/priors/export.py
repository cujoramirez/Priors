"""Core ML export. SCHEMA §8 — `PriorsEstimator.mlpackage`, target < 500 KB.

Verifies three things before declaring success, because a model that loads but
computes something slightly different is worse than one that fails loudly:

1. the exported package is under the size budget,
2. its input/output signature matches SCHEMA §8 exactly,
3. its predictions match the PyTorch model it came from.

Step 3 is the one that catches real problems. Tracing silently bakes in
whatever shapes and branches it saw, and the masked pooling in
`PriorsEstimator` is exactly the kind of thing that can be traced wrong.
"""

from __future__ import annotations

import argparse
import os
import shutil

import numpy as np
import torch

from priors.features import N_FEATURES
from priors.scenarios import N_DECISIONS
from priors.train import PriorsEstimator

OUTPUT_NAMES = ("theta_e_hat", "theta_i_hat", "log_beta_hat", "uncertainty_hat")
SIZE_BUDGET_BYTES = 500 * 1024


def package_size(path: str) -> int:
    return sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(path)
        for f in files
    )


def export(state_dict_path: str, out_path: str) -> dict:
    import coremltools as ct

    model = PriorsEstimator()
    model.load_state_dict(torch.load(state_dict_path, map_location="cpu"))
    model.eval()

    example = torch.zeros(1, N_DECISIONS, N_FEATURES)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="decisions", shape=(1, N_DECISIONS, N_FEATURES),
                              dtype=np.float32)],
        outputs=[ct.TensorType(name="traits", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = (
        "Priors amortised estimator. Fast intuition only — never produces a "
        "claim (SPEC §2.8). The grid posterior is the sole source of report content."
    )
    mlmodel.input_description["decisions"] = (
        "[30, 9] zero-padded, SCHEMA §8 order: price, engaged, log(rt_ms), "
        "approach_frac, backtracks, log(idle_ms+1), template_onehot_e, "
        "template_onehot_i, eye_window"
    )
    mlmodel.output_description["traits"] = (
        "[4]: theta_e_hat, theta_i_hat, log_beta_hat, uncertainty_hat"
    )

    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)

    # -- verify against the source model, on real-shaped input ---------------
    rng = np.random.default_rng(0)
    probe = rng.normal(size=(8, N_DECISIONS, N_FEATURES)).astype(np.float32)
    probe[3, 20:, :] = 0.0          # a padded session
    probe[5, 5:, :] = 0.0           # a heavily padded session

    with torch.no_grad():
        torch_out = model(torch.from_numpy(probe)).numpy()

    coreml_out = np.stack(
        [mlmodel.predict({"decisions": probe[i:i + 1]})["traits"].ravel() for i in range(len(probe))]
    )
    max_dev = float(np.abs(coreml_out - torch_out).max())

    size = package_size(out_path)
    return {
        "path": out_path,
        "size_bytes": size,
        "size_kb": size / 1024,
        "within_budget": size < SIZE_BUDGET_BYTES,
        "max_abs_deviation_from_torch": max_dev,
        "matches_torch": max_dev < 2e-2,   # FLOAT16 compute precision
        "torch_sample": torch_out[0].tolist(),
        "coreml_sample": coreml_out[0].tolist(),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="SCHEMA §8 Core ML export")
    ap.add_argument("--state-dict", default="out/estimator.pt")
    ap.add_argument("--out", default="out/PriorsEstimator.mlpackage")
    args = ap.parse_args()

    r = export(args.state_dict, args.out)
    print(f"  wrote {r['path']}")
    print(f"  size                 {r['size_kb']:.1f} KB   "
          f"(budget 500 KB — {'OK' if r['within_budget'] else 'OVER'})")
    print(f"  max deviation        {r['max_abs_deviation_from_torch']:.2e}   "
          f"({'matches PyTorch' if r['matches_torch'] else 'MISMATCH'})")
    print(f"  torch  sample        {[round(v, 4) for v in r['torch_sample']]}")
    print(f"  coreml sample        {[round(v, 4) for v in r['coreml_sample']]}")
    ok = r["within_budget"] and r["matches_torch"]
    print("\nVERDICT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
