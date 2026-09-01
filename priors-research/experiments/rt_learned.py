"""Learn the RT law per player instead of assuming it.

rt_robustness.py shows that FIXING the SCHEMA 7 RT parameters is unsafe: when
the real near-line effect is absent, the estimator is confidently wrong
(MAE 0.139, calibration 0.26) -- worse than ignoring RT entirely.

The fix is to stop asserting the RT law and infer it. `peak` and `sigma` become
nuisance dimensions alongside rt_base. If a player's hesitation carries no
signal, the posterior over `peak` concentrates near 0 and the RT term stops
contributing on its own. Misspecification becomes uncertainty instead of bias,
which is what SPEC 0 asks for.

Note the -log(sigma) normaliser: with sigma inferred it is no longer a
constant, and omitting it would make the widest sigma always win.

Run: PYTHONPATH=. .venv/bin/python experiments/rt_learned.py
"""
from __future__ import annotations

import numpy as np
from concurrent.futures import ProcessPoolExecutor

from priors.agents import sample_population
from priors.scenarios import BETA, THETA_E

TH = np.linspace(THETA_E.lo, THETA_E.hi, THETA_E.n)      # 33  theta_e
BE = np.geomspace(BETA.lo, BETA.hi, BETA.n)              # 15  beta
RB = np.geomspace(2000*np.exp(-2.4*0.4), 2000*np.exp(2.4*0.4), 11)  # 11 rt_base
PK = np.array([0.0, 0.4, 0.9, 1.7, 2.6, 3.6])            #  6  near-line peak
SG = np.array([0.22, 0.35, 0.55, 0.85])                  #  4  RT noise
WIDTH = 0.08
PRICES = np.linspace(THETA_E.lo, THETA_E.hi, 12)

_lp_rb = -0.5*((np.log(RB)-np.log(2000.0))/0.4)**2
_lp_rb -= np.log(np.exp(_lp_rb).sum())

TH5 = TH[:, None, None, None, None]
BE5 = BE[None, :, None, None, None]
RB5 = RB[None, None, :, None, None]
PK5 = PK[None, None, None, :, None]
SG5 = SG[None, None, None, None, :]
SHAPE = (len(TH), len(BE), len(RB), len(PK), len(SG))


def prior():
    lp = np.zeros(SHAPE)
    lp += _lp_rb[None, None, :, None, None]          # SCHEMA 7 population prior
    lp -= np.log(len(TH)*len(BE)*len(PK)*len(SG))    # uniform elsewhere
    return lp - np.log(np.exp(lp).sum())


def eig(logp):
    w = np.exp(logp).sum(axis=(2, 3, 4))
    z = BE[None, None, :]*(PRICES[:, None, None]-TH[None, :, None])
    pe = np.exp(-np.logaddexp(0.0, z))
    def H(q):
        q = np.clip(q, 1e-300, 1-1e-16); return -(q*np.log(q)+(1-q)*np.log1p(-q))
    return H(np.tensordot(pe, w, axes=([1,2],[0,1]))) - np.tensordot(H(pe), w, axes=([1,2],[0,1]))


def run(args):
    te, bt, rbt, seed, gpeak, gwidth, gsigma, n_dec = args
    n = len(te); est = np.zeros(n); sd = np.zeros(n); pk_hat = np.zeros(n)
    a_near = np.exp(-((PRICES[:, None]-TH[None, :])/WIDTH)**2)   # (12, 33)
    for i in range(n):
        rng = np.random.default_rng([seed, i])
        logp = prior()
        for _ in range(n_dec):
            di = int(np.argmax(eig(logp)))
            p = float(PRICES[di])
            y = bool(rng.random() < 1/(1+np.exp(bt[i]*(p-te[i]))))
            rt = rbt[i]*(1+gpeak*np.exp(-((p-te[i])/gwidth)**2))*rng.lognormal(0.0, gsigma)

            logp = logp + np.where(y, -np.logaddexp(0.0, BE5*(p-TH5)),
                                      -np.logaddexp(0.0, -BE5*(p-TH5)))
            mu = np.log(RB5) + np.log1p(PK5*a_near[di][:, None, None, None, None])
            logp = logp - 0.5*((np.log(rt)-mu)/SG5)**2 - np.log(SG5)
            logp -= logp.max(); logp -= np.log(np.exp(logp).sum())

        pj = np.exp(logp)
        marg = pj.sum(axis=(1, 2, 3, 4))
        m = float((TH*marg).sum())
        est[i] = m
        sd[i] = float(np.sqrt(((TH-m)**2*marg).sum()))
        pk_hat[i] = float((PK*pj.sum(axis=(0, 1, 2, 4))).sum())
    return np.stack([est, sd, pk_hat])


def evaluate(pop, gpeak, gwidth, gsigma, n_dec=15, seed=20260901):
    N = len(pop)
    chunks = [(pop.theta_e[a:a+250], pop.beta[a:a+250], pop.rt_base_ms[a:a+250],
               seed, gpeak, gwidth, gsigma, n_dec) for a in range(0, N, 250)]
    with ProcessPoolExecutor(max_workers=10) as ex:
        r = np.concatenate(list(ex.map(run, chunks)), axis=1)
    est, sd, pk = r
    err = est - pop.theta_e
    rmse = float(np.sqrt((err**2).mean()))
    return float(np.abs(err).mean()), float(sd.mean()/max(rmse, 1e-12)), float(pk.mean())


if __name__ == "__main__":
    N = 6000
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N} per cell, decision 15. RT law INFERRED (peak, sigma, rt_base all nuisance).")
    print("cal = posterior SD / RMSE. 1.0 is honest, below 1.0 is overconfident.")
    print("peak_hat = what the model concluded about this population's hesitation.\n")
    print(f"  {'GENERATOR (the real world)':34s} {'MAE':>6}  {'cal':>4}  {'peak_hat':>8}   {'vs choice-only 0.0645'}")
    print("  " + "-"*82)
    for label, pk, wd, sg in [
        ("matches SCHEMA 7 exactly",     2.5, 0.08, 0.25),
        ("weaker hesitation (peak 1.0)", 1.0, 0.08, 0.25),
        ("much weaker (peak 0.5)",       0.5, 0.08, 0.25),
        ("NO near-line effect (peak 0)", 0.0, 0.08, 0.25),
        ("narrower band (width 0.05)",   2.5, 0.05, 0.25),
        ("wider band (width 0.12)",      2.5, 0.12, 0.25),
        ("noisier RT (sigma 0.5)",       2.5, 0.08, 0.50),
        ("very noisy RT (sigma 0.8)",    2.5, 0.08, 0.80),
        ("weak + noisy + wide",          1.0, 0.12, 0.50),
    ]:
        mae, cal, pkh = evaluate(pop, pk, wd, sg)
        verdict = "better" if mae < 0.0645 else "WORSE"
        flag = "  <-- OVERCONFIDENT" if cal < 0.95 else ""
        print(f"  {label:34s} {mae:.4f}  {cal:4.2f}  {pkh:8.2f}   {verdict}{flag}")
