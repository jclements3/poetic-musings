"""Regressions from the adversarial fusion/validate review.

Two confirmed bugs, both fixed in validate.py:
1. residuals() aliased the caller's fused.valid array and `&=`'d the
   truth-overlap mask into it — silently corrupting the Track for any
   later use.
2. An empty residual set (all epochs gated/invalid, or no truth overlap)
   crashed np.percentile inside _metrics()/bands() — a diverged session
   must FAIL its flight row, not take down the campaign run.
"""

import numpy as np

from maiden.validate import Track, _metrics, bands, flight_passes, residuals, rollup


def _fused(n=50, t0=100.0, valid=None):
    return Track(t=t0 + np.arange(n) * 0.02, pos=np.zeros((n, 3)),
                 vel=np.zeros((n, 3)), valid=valid)


def _truth(n=200, t0=100.0, dt=0.01):
    return Track(t=t0 + np.arange(n) * dt, pos=np.zeros((n, 3)),
                 vel=np.zeros((n, 3)))


def test_residuals_does_not_mutate_caller_valid():
    valid = np.ones(50, bool)
    fused = _fused(valid=valid)
    truth = _truth(n=60)          # covers only part of the fused span
    residuals(fused, truth)
    assert fused.valid.all(), "residuals() must not clobber Track.valid"


def test_empty_residuals_fail_instead_of_crashing():
    fused = _fused(valid=np.zeros(50, bool))
    res = residuals(fused, _truth())
    assert len(res.t) == 0

    roll = rollup(res)            # crashed before the fix
    m = roll["ALL"]
    assert np.isnan(m["pos_rms"]) and np.isnan(m["vel_rms"])
    # nan metrics must read as a FAILED flight, never a pass
    assert not flight_passes(m["pos_rms"], m["vel_rms"], 1.0)

    b = bands([res])              # crashed before the fix
    assert b["n_samples"] == 0 and np.isnan(b["position_p95_m"])


def test_metrics_empty_direct():
    m = _metrics(np.zeros((0, 3)), np.zeros((0, 3)))
    assert np.isnan(m["pos_p95"])
