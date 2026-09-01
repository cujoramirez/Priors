"""Does response time carry recoverable information about theta?

The choice-only ceiling (experiments/ceiling.py) is 0.0652 MAE at decision 15.
That ceiling assumes the only evidence is the binary choice. But SCHEMA 7/7.1
make RT peak exactly at the player's line:

    rt = rt_base * (1 + 2.5 * exp(-((p - theta)/0.08)^2)) * LogNormal(0, 0.25)

So a long hesitation at p=0.42 says "theta is near 0.42" regardless of which
way the player went. Choice gives the DIRECTION of theta relative to p; RT
gives the DISTANCE. They are complementary.

rt_base is unknown per player, so it is carried as a nuisance dimension with
its known population prior (SCHEMA 7). It is never reported.

Run: PYTHONPATH=. .venv/bin/python experiments/rt_channel.py
"""
from __future__ import annotations

import numpy as np
from concurrent.futures import ProcessPoolExecutor

from priors.agents import NEAR_LINE_WIDTH, RT_NEAR_LINE_PEAK, RT_TRIAL_NOISE_SD, sample_population
from priors.scenarios import BETA, THETA_E

TH = np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n)          # 33
BE = np.geomspace(BETA.lo, BETA.hi, BETA.n)                  # 15
RB = np.geomspace(2000*np.exp(-2.4*0.4), 2000*np.exp(2.4*0.4), 13)   # 13 nuisance
PRICES = np.linspace(THETA_E.lo, THETA_E.hi, 12)

# Population prior on rt_base: LogNormal(log 2000, 0.4). Proper, and known.
_lp_rb = -0.5*((np.log(RB)-np.log(2000.0))/0.4)**2
_lp_rb -= np.log(np.sum(np.exp(_lp_rb)))

TH3, BE3, RB3 = TH[:, None, None], BE[None, :, None], RB[None, None, :]


def choice_ll(price, engaged, th, be):
    z = be*(price-th)
    return -np.logaddexp(0.0, z) if engaged else -np.logaddexp(0.0, -z)


def rt_ll(price, rt_ms, th, rb):
    """log N(log rt ; log rb + log(1 + 2.5*near), 0.25^2)."""
    near = np.exp(-((price-th)/NEAR_LINE_WIDTH)**2)
    mu = np.log(rb) + np.log1p(RT_NEAR_LINE_PEAK*near)
    return -0.5*((np.log(rt_ms)-mu)/RT_TRIAL_NOISE_SD)**2


def eig(logp, prices):
    p = np.exp(logp)
    w = p.sum(axis=2)                                   # marginalise rt_base -> (th, be)
    z = BE[None, None, :]*(prices[:, None, None]-TH[None, :, None])
    pe = np.exp(-np.logaddexp(0.0, z))
    def H(q):
        q = np.clip(q, 1e-300, 1-1e-16)
        return -(q*np.log(q)+(1-q)*np.log1p(-q))
    pred = np.tensordot(pe, w, axes=([1, 2], [0, 1]))
    cond = np.tensordot(H(pe), w, axes=([1, 2], [0, 1]))
    return H(pred)-cond


def run(args):
    te, bt, rbt, seed, mode = args
    n = len(te)
    out = np.zeros((n, 30))
    for i in range(n):
        rng = np.random.default_rng([seed, i])
        logp = np.broadcast_to(_lp_rb, (len(TH), len(BE), len(RB))).copy()
        logp = logp - np.log(len(TH)*len(BE))
        for k in range(30):
            p = float(PRICES[int(np.argmax(eig(logp, PRICES)))])
            near = np.exp(-((p-te[i])/NEAR_LINE_WIDTH)**2)
            y = bool(rng.random() < 1/(1+np.exp(bt[i]*(p-te[i]))))
            rt = rbt[i]*(1+RT_NEAR_LINE_PEAK*near)*rng.lognormal(0.0, RT_TRIAL_NOISE_SD)

            logp = logp + choice_ll(p, y, TH3, BE3)
            if mode != "choice":
                logp = logp + rt_ll(p, rt, TH3, RB3)
            logp -= logp.max()
            logp -= np.log(np.exp(logp).sum())

            marg = np.exp(logp).sum(axis=(1, 2))
            out[i, k] = float((TH*marg).sum())
    return out


if __name__ == "__main__":
    N = 20000
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N}, 30 theta_e decisions, EIG-optimal pricing\n")
    base = None
    for mode in ("choice", "choice+rt"):
        chunks = [(pop.theta_e[a:a+400], pop.beta[a:a+400], pop.rt_base_ms[a:a+400], 20260901, mode)
                  for a in range(0, N, 400)]
        with ProcessPoolExecutor(max_workers=10) as ex:
            est = np.concatenate(list(ex.map(run, chunks)), axis=0)
        err = np.abs(est - pop.theta_e[:, None])
        mae = err.mean(axis=0)
        tag = "choice only (ceiling)" if mode == "choice" else "choice + RT"
        line = (f"  {tag:22s}  MAE@10={mae[9]:.4f}  MAE@15={mae[14]:.4f}  "
                f"MAE@20={mae[19]:.4f}  MAE@30={mae[29]:.4f}")
        if base is not None:
            line += f"   ({(base-mae[14])/base*100:+.0f}% @15)"
        else:
            base = mae[14]
        print(line)
        if mode == "choice+rt":
            for lo, hi, lbl in [(2, 5.2, "beta 2.0-5.2 (indecisive)"), (12.2, 30, "beta 12.2-30 (decisive)")]:
                m = (pop.beta >= lo) & (pop.beta <= hi)
                print(f"      {lbl:28s} MAE@15={err[m][:, 14].mean():.4f}")
            print(f"      {'fraction under 0.06 @15':28s} {(err[:, 14] < 0.06).mean()*100:.1f}%")
