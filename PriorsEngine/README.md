# PriorsEngine

Pure logic. No SwiftUI, no SpriteKit, no UIKit — if you find yourself importing
a UI framework, you're in the wrong repo (SPEC §12). The only external import
in `Sources/` is CoreML.

`SPEC.md`, `SCHEMA.md` and `COPY.md` are symlinks to the repo root. They are the
contract. Editing them here edits them for all three projects.

## Layout

| File | Contract |
|---|---|
| `Scenarios.swift` | SPEC §3, §4, §4.1, §4.2, §5.1 — pure data |
| `Posterior.swift` | SPEC §3.4 — grid posterior over (θ_e, θ_i, β) |
| `ADOSelector.swift` | SPEC §5, §5.1, §6.1 — EIG design selection |
| `EventTriggers.swift` | SPEC §6.1–6.4 — falsification, shadow, eye, gaming |
| `ClaimGenerator.swift` | SPEC §9 — claims with receipts, ordered per §9.2 |
| `Estimator.swift` | SCHEMA §8 — Core ML wrapper, produces no claims |
| `Models/` | SCHEMA §1–6 — Codable |

## The golden fixtures

`Tests/PriorsEngineTests/Fixtures/golden.json` is **generated, not hand-written**.
It comes from `priors-research`, which is itself validated against ADOpy, so the
verification chain runs ADOpy → Python → Swift.

Regenerate after any change to the Python reference:

```sh
cd ../priors-research
PYTHONPATH=. .venv/bin/python scripts/make_golden.py
cd ../PriorsEngine && swift test
```

`PosteriorGoldenTests` compares all 12 steps of a fixed decision sequence, and
`ADOSelectorGoldenTests` reproduces a full 30-slot session design for design.
Both hold to 1e-9 — far tighter than SPEC §5's "within one grid step", because
the two implementations compute the same arithmetic and anything beyond
floating-point noise is a real divergence.

## Three things not to undo

1. **`Claim` cannot be constructed without receipts.** `init` has a
   `precondition`, `Claim.make` returns nil, and `init(from:)` rejects an empty
   array so a persisted claim can't come back to life. SPEC §9.1.
2. **EIG ties are broken by explicit tolerance**, not by whichever float is
   larger. At the uniform prior two candidate prices are mathematically
   identical and differ by 1.7e-16; NumPy and Swift disagree on the sign, which
   made the port diverge at slot 0 and cascade. See `eigTieTolerance`.
3. **`Estimator` produces no claims and surfaces no opinion.** SPEC §2.8. It is
   also the most brittle component in the system — the research repo found it
   will learn the synthetic generator's behavioural formula instead of the task
   unless trained with channel augmentation. Keep it away from anything a
   player reads.
