"""Does the RT channel depend on the rt_base prior being right about humans?

rt_posterior carries SCHEMA 7's LogNormal(log 2000, 0.4) prior on rt_base. That
prior is informative: it is what lets a uniformly slow response be read as
"near the line" rather than "slow player". If real players are simply slower
than SCHEMA 7 assumes, that reasoning inverts into a confident wrong answer.

Sweeps the true population median rt_base against the prior width the estimator
carries. cal = mean posterior SD / RMSE; below ~0.95 is overconfident.

Run: PYTHONPATH=. .venv/bin/python experiments/rt_base_prior.py
"""
from __future__ import annotations

import numpy as np
from concurrent.futures import ProcessPoolExecutor

from priors.agents import NEAR_LINE_WIDTH, RT_NEAR_LINE_PEAK, sample_population
from priors.scenarios import BETA, THETA_E

TH = np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n)
BE = np.geomspace(BETA.lo, BETA.hi, BETA.n)
PK = np.array([0.0, 0.6, 1.3, 2.2, 3.4])
SG = np.array([0.22, 0.38, 0.62])
PRICES = np.linspace(THETA_E.lo, THETA_E.hi, 12)
WIDTH = NEAR_LINE_WIDTH


def make_rb(prior_sd):
    """Grid spans +/-2.4 prior SD, so a wider prior also widens the grid."""
    rb = np.geomspace(2000*np.exp(-2.4*prior_sd), 2000*np.exp(2.4*prior_sd), 11)
    lp = -0.5*((np.log(rb)-np.log(2000.0))/prior_sd)**2
    return rb, lp - np.log(np.exp(lp).sum())


def run(args):
    te, bt, rbt, seed, prior_sd = args
    RB, lp_rb = make_rb(prior_sd)
    TH5, BE5 = TH[:, None, None, None, None], BE[None, :, None, None, None]
    RB5, PK5, SG5 = RB[None, None, :, None, None], PK[None, None, None, :, None], SG[None, None, None, None, :]
    shape = (len(TH), len(BE), len(RB), len(PK), len(SG))
    a_near = np.exp(-((PRICES[:, None]-TH[None, :])/WIDTH)**2)

    n = len(te); est = np.zeros(n); sd = np.zeros(n)
    for i in range(n):
        rng = np.random.default_rng([seed, i])
        logp = np.broadcast_to(lp_rb[None, None, :, None, None], shape).copy()
        logp = logp - np.log(len(TH)*len(BE)*len(PK)*len(SG))
        logp -= np.log(np.exp(logp).sum())
        for _ in range(15):
            w = np.exp(logp).sum(axis=(2, 3, 4))
            z = BE[None, None, :]*(PRICES[:, None, None]-TH[None, :, None])
            pe = np.exp(-np.logaddexp(0.0, z))
            def H(q):
                q = np.clip(q, 1e-300, 1-1e-16); return -(q*np.log(q)+(1-q)*np.log1p(-q))
            di = int(np.argmax(H(np.tensordot(pe, w, axes=([1,2],[0,1])))
                               - np.tensordot(H(pe), w, axes=([1,2],[0,1]))))
            p = float(PRICES[di])
            y = bool(rng.random() < 1/(1+np.exp(bt[i]*(p-te[i]))))
            rt = rbt[i]*(1+RT_NEAR_LINE_PEAK*np.exp(-((p-te[i])/WIDTH)**2))*rng.lognormal(0.0, 0.25)

            logp = logp + np.where(y, -np.logaddexp(0.0, BE5*(p-TH5)),
                                      -np.logaddexp(0.0, -BE5*(p-TH5)))
            mu = np.log(RB5) + np.log1p(PK5*a_near[di][:, None, None, None, None])
            logp = logp - 0.5*((np.log(rt)-mu)/SG5)**2 - np.log(SG5)
            logp -= logp.max(); logp -= np.log(np.exp(logp).sum())
        marg = np.exp(logp).sum(axis=(1, 2, 3, 4))
        m = float((TH*marg).sum()); est[i] = m
        sd[i] = float(np.sqrt(((TH-m)**2*marg).sum()))
    return np.stack([est, sd])


def evaluate(pop, rb_mult, prior_sd, seed=20260901):
    N = len(pop); rbt = pop.rt_base_ms*rb_mult
    chunks = [(pop.theta_e[a:a+250], pop.beta[a:a+250], rbt[a:a+250], seed, prior_sd)
              for a in range(0, N, 250)]
    with ProcessPoolExecutor(max_workers=10) as ex:
        r = np.concatenate(list(ex.map(run, chunks)), axis=1)
    est, sd = r
    err = est - pop.theta_e
    rmse = float(np.sqrt((err**2).mean()))
    return float(np.abs(err).mean()), float(sd.mean()/max(rmse, 1e-12))


if __name__ == "__main__":
    N = 4000
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N} per cell, decision 15. Estimator prior is always centred on 2000ms.\n")
    print(f"  {'true population median':26s} " + "".join(f"{'prior sd '+str(s):>22s}" for s in (0.4, 0.8)))
    print("  " + "-"*72)
    for mult, label in [(1.0, "2000ms (matches)"), (1.6, "3200ms (1.6x slower)"),
                        (2.5, "5000ms (2.5x slower)"), (0.6, "1200ms (faster)")]:
        cells = []
        for psd in (0.4, 0.8):
            mae, cal = evaluate(pop, mult, psd)
            flag = " !" if cal < 0.95 else "  "
            cells.append(f"{mae:.4f} / cal {cal:4.2f}{flag}")
        print(f"  {label:26s} " + "".join(f"{c:>22s}" for c in cells))
