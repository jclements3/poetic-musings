# VT-17 — known-noise consistency (twin gate)

Session: imperfect twin, seed 303, full .ch10 round trip through the
real pipeline (ingest -> fuse -> validate).

| Quantity | Injected/predicted | Measured | Ratio |
|---|---|---|---|
| az/el noise | sigma_theta = 0.50 mrad | (injected) | — |
| v_r noise | sigma_vr = 0.15 m/s | (injected) | — |
| pos RMS | 0.397 m (D3 geometry) | 0.219 m | 0.55 |
| vel RMS | 0.15 m/s radial floor | 0.909 m/s | see note |
| continuity | 1.0 (twin has no real losses beyond injected) | 1.0000 | — |

Verdict: position residuals consistent with injected noise through the
D3 geometry (ratio 0.55, band 0.5–1.6; ~25% agreement was the
target, and perfect agreement would be suspicious — filter transients
ride along). Velocity RMS 0.909 m/s sits well above the
sigma_vr floor because constant-velocity model lag during aerobatic
maneuvers dominates — expected, documented in lesson 13; the SYS-003
rehearsal bound (<= 1.0 m/s) holds. Gate flags: sync ok,
pass True.

Pipeline: maiden.validate steps 1–6; this file is written by
software/tests/test_validate_vt17.py from the numbers of the actual
run — regenerate with `pytest software/tests/test_validate_vt17.py`.
