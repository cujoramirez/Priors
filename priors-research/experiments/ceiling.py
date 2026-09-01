"""Information ceiling for theta_e recovery. Answers: is SPEC 13.1 reachable AT ALL?

Run: PYTHONPATH=. .venv/bin/python experiments/ceiling.py

Spends all 30 decisions on theta_e with EIG-optimal pricing and no template,
quota, curiosity or jitter constraints -- a design strictly better than anything
SPEC section 4 permits. Whatever this cannot reach, no scheduling change can.
"""
import numpy as np
from concurrent.futures import ProcessPoolExecutor
from priors.posterior import Posterior
from priors.ado import expected_information_gain, candidate_prices
from priors.agents import sample_population, p_engage

PRICES = candidate_prices("theta_e")

def run(args):
    te, bt, seed, oracle = args
    n = len(te); out = np.zeros((n, 30))
    for i in range(n):
        rng = np.random.default_rng([seed, i]); post = Posterior()
        if oracle:                      # collapse beta onto its true value
            j = int(np.argmin(np.abs(post.beta - bt[i])))
            lp = np.full(post.log_post.shape, -np.inf); lp[:, :, j] = 0.0
            post._log_post = lp - np.log(np.exp(lp[:, :, j]).sum())
        for k in range(30):
            p = float(PRICES[int(np.argmax(expected_information_gain(post, PRICES, "theta_e")))])
            y = bool(rng.random() < p_engage(p, te[i], bt[i]))
            post.update(p, "theta_e", y)
            out[i, k] = post.mean_sd("theta_e")[0]
    return out

if __name__ == "__main__":
    N = 20000
    pop = sample_population(N, np.random.default_rng(20260901))
    print(f"n={N}, 30 theta_e decisions each, EIG-optimal pricing, no template constraints\n")
    for oracle in (False, True):
        chunks = [(pop.theta_e[a:a+500], pop.beta[a:a+500], 20260901, oracle)
                  for a in range(0, N, 500)]
        with ProcessPoolExecutor(max_workers=10) as ex:
            est = np.concatenate(list(ex.map(run, chunks)), axis=0)
        mae = np.abs(est - pop.theta_e[:, None]).mean(axis=0)
        tag = "beta KNOWN (oracle)" if oracle else "beta estimated jointly"
        print(f"  {tag:24s}  MAE@10={mae[9]:.4f}  MAE@15={mae[14]:.4f}  "
              f"MAE@20={mae[19]:.4f}  MAE@30={mae[29]:.4f}")
        if not oracle:
            hi = pop.beta >= 8
            m = np.abs(est - pop.theta_e[:, None])[hi].mean(axis=0)
            print(f"  {'  ^ decisive half only':24s}  MAE@10={m[9]:.4f}  MAE@15={m[14]:.4f}  "
                  f"MAE@20={m[19]:.4f}  MAE@30={m[29]:.4f}")
