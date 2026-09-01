"""What happens when humans' RT does NOT obey the SCHEMA 7 model?

experiments/rt_channel.py shows the RT channel cutting MAE@15 by 68%. But it
measures the estimator inverting exactly the generator that made the data.
Real hesitation will differ. The question that decides whether RT is usable is
not "how much does it help when we are right" but "what does it do when we are
wrong" -- specifically whether it stays honest or becomes confidently wrong.

The estimator always assumes SCHEMA 7: peak 2.5, width 0.08, sigma 0.25.
The generator varies. `cal` is mean posterior SD / RMSE: 1.0 is honest,
below 1.0 is OVERCONFIDENT and is the failure that matters, because a
confident wrong claim is worse here than an uncertain one (SPEC 0).

Run: PYTHONPATH=. .venv/bin/python experiments/rt_robustness.py
"""
from __future__ import annotations

import numpy as np
from concurrent.futures import ProcessPoolExecutor

from priors.agents import sample_population
from priors.scenarios import BETA, THETA_E

TH = np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n)
BE = np.geomspace(BETA.lo, BETA.hi, BETA.n)
RB = np.geomspace(2000*np.exp(-2.4*0.4), 2000*np.exp(2.4*0.4), 13)
PRICES = np.linspace(THETA_E.lo, THETA_E.hi, 12)

ASSUMED_PEAK, ASSUMED_WIDTH, ASSUMED_SIGMA = 2.5, 0.08, 0.25

_lp_rb = -0.5*((np.log(RB)-np.log(2000.0))/0.4)**2
_lp_rb -= np.log(np.sum(np.exp(_lp_rb)))
TH3, BE3, RB3 = TH[:, None, None], BE[None, :, None], RB[None, None, :]


def eig(logp):
    w = np.exp(logp).sum(axis=2)
    z = BE[None, None, :]*(PRICES[:, None, None]-TH[None, :, None])
    pe = np.exp(-np.logaddexp(0.0, z))
    def H(q):
        q = np.clip(q, 1e-300, 1-1e-16); return -(q*np.log(q)+(1-q)*np.log1p(-q))
    return H(np.tensordot(pe, w, axes=([1,2],[0,1]))) - np.tensordot(H(pe), w, axes=([1,2],[0,1]))


def run(args):
    te, bt, rbt, seed, use_rt, gpeak, gwidth, gsigma = args
    n = len(te); est = np.zeros(n); sd = np.zeros(n)
    for i in range(n):
        rng = np.random.default_rng([seed, i])
        logp = np.broadcast_to(_lp_rb, (len(TH), len(BE), len(RB))).copy() - np.log(len(TH)*len(BE))
        for _ in range(15):                                   # decision 15
            p = float(PRICES[int(np.argmax(eig(logp)))])
            y = bool(rng.random() < 1/(1+np.exp(bt[i]*(p-te[i]))))
            # GENERATOR: the world's真 RT law, which the estimator does not know
            g_near = np.exp(-((p-te[i])/gwidth)**2)
            rt = rbt[i]*(1+gpeak*g_near)*rng.lognormal(0.0, gsigma)

            z = bt[i]*0  # noqa - keep shape clarity
            logp = logp + np.where(y, -np.logaddexp(0.0, BE3*(p-TH3)),
                                      -np.logaddexp(0.0, -BE3*(p-TH3)))
            if use_rt:
                # ESTIMATOR: always assumes SCHEMA 7
                a_near = np.exp(-((p-TH3)/ASSUMED_WIDTH)**2)
                mu = np.log(RB3) + np.log1p(ASSUMED_PEAK*a_near)
                logp = logp - 0.5*((np.log(rt)-mu)/ASSUMED_SIGMA)**2
            logp -= logp.max(); logp -= np.log(np.exp(logp).sum())
        marg = np.exp(logp).sum(axis=(1, 2))
        m = float((TH*marg).sum())
        est[i] = m; sd[i] = float(np.sqrt(((TH-m)**2*marg).sum()))
    return np.stack([est, sd])


def evaluate(pop, use_rt, gpeak, gwidth, gsigma, seed=20260901):
    N = len(pop)
    chunks = [(pop.theta_e[a:a+400], pop.beta[a:a+400], pop.rt_base_ms[a:a+400],
               seed, use_rt, gpeak, gwidth, gsigma) for a in range(0, N, 400)]
    with ProcessPoolExecutor(max_workers=10) as ex:
        r = np.concatenate(list(ex.map(run, chunks)), axis=1)
    est, sd = r[0], r[1]
    err = est - pop.theta_e
    rmse = float(np.sqrt((err**2).mean()))
    return float(np.abs(err).mean()), float(sd.mean()/max(rmse, 1e-12)), float(err.mean())


if __name__ == "__main__":
    N = 8000
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N} per cell, MAE at decision 15. Estimator always assumes "
          f"peak={ASSUMED_PEAK}, width={ASSUMED_WIDTH}, sigma={ASSUMED_SIGMA}\n")
    mae, cal, bias = evaluate(pop, False, 2.5, 0.08, 0.25)
    print(f"  {'choice only (baseline)':38s} MAE={mae:.4f}  cal={cal:.2f}  bias={bias:+.4f}\n")
    print(f"  {'GENERATOR (the real world)':38s} {'MAE':>6}  {'cal':>4}  {'bias':>7}")
    print("  " + "-"*66)
    cases = [
        ("matches SCHEMA 7 exactly",        2.5, 0.08, 0.25),
        ("weaker hesitation (peak 1.0)",    1.0, 0.08, 0.25),
        ("much weaker (peak 0.5)",          0.5, 0.08, 0.25),
        ("NO near-line effect (peak 0)",    0.0, 0.08, 0.25),
        ("narrower band (width 0.05)",      2.5, 0.05, 0.25),
        ("wider band (width 0.12)",         2.5, 0.12, 0.25),
        ("noisier RT (sigma 0.5)",          2.5, 0.08, 0.50),
        ("very noisy RT (sigma 0.8)",       2.5, 0.08, 0.80),
        ("weak + noisy + wide",             1.0, 0.12, 0.50),
    ]
    for label, pk, wd, sg in cases:
        mae, cal, bias = evaluate(pop, True, pk, wd, sg)
        flag = "  <-- OVERCONFIDENT" if cal < 1.0 else ""
        print(f"  {label:38s} {mae:.4f}  {cal:4.2f}  {bias:+.4f}{flag}")
