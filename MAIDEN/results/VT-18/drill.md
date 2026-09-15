# VT-18 — CI regression-gate drill (evidence)

**Date:** 2026-08-21 · **Gate:** `make ci` → `scripts/replay.py`
(canonical twin seeds 1001–1003, `--imperfect`, thresholds from
`config/thresholds.yaml`). Performed locally against the exact scripts
the GitHub workflow runs (`make ci` ≡ `.github/workflows/ci.yml` by
construction); repeat on GitHub after any major CI change — the
standing rule is at the bottom.

## Injected bug

One line in `software/maiden/fuse.py`'s epoch scheduler:

```python
# before                                   # injected
ok = ekf.update_vr(z, stations[src])       ok = True  # v_r update dropped
```

A silently dropped radial-velocity update — plausible (a refactor that
loses a branch), and **accuracy-red, not crash-red**: the pipeline runs
to completion, position stays well inside SYS-002, and only the
velocity threshold rings.

## Red run (verbatim excerpts, replay exit code 1)

```
[replay] seed 1001: FAIL (sync=ok)
  SYS-002 pos RMS: 0.335 m vs 1.0 (+66.5% margin) [ok]
  SYS-003 vel RMS: 2.244 m/s vs 1.0 (-124.4% margin) [BREACH]
  SYS-004 continuity: 1.000  vs 0.95 (+5.3% margin) [ok]
[replay] seed 1002: FAIL (sync=ok)
  SYS-003 vel RMS: 1.756 m/s vs 1.0 (-75.6% margin) [BREACH]
[replay] seed 1003: FAIL (sync=ok)
  SYS-003 vel RMS: 1.774 m/s vs 1.0 (-77.4% margin) [BREACH]
[replay] RESULT: RED
```

**Threshold that caught it: SYS-003** (vel RMS ≤ 1.0 m/s), on all three
seeds — consistent with the maiden25 ablation (velocity RMS 1.6 m/s
without radials on seed 303).

## Revert + green run

`fuse.py` restored byte-identically (verified by `diff` against the
pre-drill copy). Replay exit code 0:

```
  SYS-003 vel RMS: 0.952 m/s vs 1.0 (+4.8% margin) [ok]   (seed 1001)
  SYS-003 vel RMS: 0.920 m/s vs 1.0 (+8.0% margin) [ok]   (seed 1002)
  SYS-003 vel RMS: 0.909 m/s vs 1.0 (+9.1% margin) [ok]   (seed 1003)
[replay] RESULT: GREEN
```

Note the standing thin-margin flag on seed 1001 (+4.8% on SYS-003):
real headroom on velocity is single-digit percent — the first metric a
field regression will breach.

## Also proven this drill

- **Corrupted-threshold check** (maiden28 Done-when): `pos_rms_m: 0.0`
  → all three seeds BREACH SYS-002, replay exits 1; file restored
  byte-identically.
- **Regeneration**: `data/twin-ci/` deleted → full set rebuilt from
  seeds + source hash; second run cache-hits on `MANIFEST.json`.

## Standing rule

Repeat this drill after any major CI change (workflow restructure,
thresholds refactor, twin source change that moves the cache key), and
once on GitHub Actions after the first push of this workflow. An
untested regression gate is a smoke detector with no battery.
