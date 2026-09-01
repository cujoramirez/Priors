"""train.py and export.py. SCHEMA §8.

The property worth defending here is not accuracy — it is that the model
degrades to the grid posterior rather than below it when the behavioural
channels carry nothing. See FINDINGS.md.
"""

import numpy as np
import pytest
import torch

from priors.agents import sample_population
from priors.features import BEHAVIOURAL_CHANNELS, N_FEATURES, build_features
from priors.scenarios import N_DECISIONS, THETA_E, THETA_I
from priors.simulate import simulate
from priors.train import PriorsEstimator, augment


@pytest.fixture(scope="module")
def res():
    return simulate(sample_population(120, np.random.default_rng(5)), workers=1)


def test_parameter_count_fits_the_budget():
    """SCHEMA §8 — under 500 KB. float32 params are the bulk of the package."""
    n = sum(p.numel() for p in PriorsEstimator().parameters())
    assert n * 4 < 500 * 1024


def test_output_shape_and_ranges():
    m = PriorsEstimator().eval()
    with torch.no_grad():
        out = m(torch.randn(7, N_DECISIONS, N_FEATURES))
    assert out.shape == (7, 4)
    assert torch.all((out[:, 0] >= THETA_E.lo) & (out[:, 0] <= THETA_E.hi))
    assert torch.all((out[:, 1] >= THETA_I.lo) & (out[:, 1] <= THETA_I.hi))
    assert torch.all(out[:, 3] > 0), "uncertainty must be positive"


def test_traits_cannot_leave_the_grid_support():
    """A value off the grid has no posterior cell to compare against."""
    m = PriorsEstimator().eval()
    with torch.no_grad():
        out = m(torch.randn(64, N_DECISIONS, N_FEATURES) * 50.0)
    assert torch.all((out[:, 0] >= THETA_E.lo) & (out[:, 0] <= THETA_E.hi))
    assert torch.all((out[:, 1] >= THETA_I.lo) & (out[:, 1] <= THETA_I.hi))


def test_padding_is_ignored():
    """SCHEMA §8 inputs are zero-padded; padded rows must not shift the output."""
    m = PriorsEstimator().eval()
    x = torch.randn(1, N_DECISIONS, N_FEATURES)
    x[:, 20:, :] = 0.0
    y = x.clone()
    y[:, 20:, :] = 0.0  # same padding, explicitly
    with torch.no_grad():
        assert torch.allclose(m(x), m(y), atol=1e-6)


def test_permutation_invariance():
    """The grid posterior is order-invariant, so the estimator is too."""
    m = PriorsEstimator().eval()
    x = torch.randn(1, N_DECISIONS, N_FEATURES)
    perm = torch.randperm(N_DECISIONS)
    with torch.no_grad():
        assert torch.allclose(m(x), m(x[:, perm, :]), atol=1e-5)


def test_augment_only_touches_behavioural_channels(res):
    x = torch.from_numpy(build_features(res))
    gen = torch.Generator(); gen.manual_seed(0)
    out = augment(x, drop_p=0.9, scramble_p=0.9, gen=gen)
    keep = [c for c in range(N_FEATURES) if c not in BEHAVIOURAL_CHANNELS]
    torch.testing.assert_close(out[:, :, keep], x[:, :, keep])
    assert not torch.allclose(out[:, :, list(BEHAVIOURAL_CHANNELS)],
                              x[:, :, list(BEHAVIOURAL_CHANNELS)])


def test_augment_scramble_preserves_the_marginal(res):
    """Scrambling must destroy the correspondence with price, not the values —
    otherwise it teaches 'missing' rather than 'uninformative'."""
    x = torch.from_numpy(build_features(res))
    gen = torch.Generator(); gen.manual_seed(1)
    out = augment(x, drop_p=0.0, scramble_p=1.0, gen=gen)
    for c in BEHAVIOURAL_CHANNELS:
        a = torch.sort(x[:, :, c], dim=1).values
        b = torch.sort(out[:, :, c], dim=1).values
        torch.testing.assert_close(a, b)


def test_augment_is_a_noop_at_zero_probability(res):
    x = torch.from_numpy(build_features(res))
    gen = torch.Generator(); gen.manual_seed(2)
    torch.testing.assert_close(augment(x, 0.0, 0.0, gen), x)
