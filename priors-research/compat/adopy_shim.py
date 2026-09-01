"""ADOpy 0.4.1 predates NumPy 1.24, which removed `np.int`/`np.float`/`np.bool`.

Six call sites in adopy still use them. Restoring the aliases before import is
enough to make the package fully functional — verified end to end, not just at
import time.

ADOpy is a validation-only dependency (SPEC §5: "validate against ADOpy in
Python before porting"). Nothing on the shipping path imports it, so the shim
never runs outside the test suite.
"""

from __future__ import annotations

import numpy as np

_ALIASES = (("int", int), ("float", float), ("bool", bool))


def install() -> None:
    for name, target in _ALIASES:
        if not hasattr(np, name):
            setattr(np, name, target)


def load_adopy():
    """Install the shim and return the adopy module, or raise ImportError."""
    install()
    import adopy  # noqa: PLC0415

    return adopy
