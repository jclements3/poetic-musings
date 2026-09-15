# maiden65 — The gate & D8 [desk]

**Sprint goal.** Run the Phase 1→2 gate across the full campaign, fill D8
from real data, extract the confidence bands every un-instrumented report
will carry, and — on a pass — tag `v0.2-prototype`.

**Depends on.** maiden63 (complete `campaign.csv`), maiden64 (judge table
and calibration layer). No weather gate: this is a desk sprint on data
already flown.

**Read first.** lesson99.md — Verify §"The gate (VT-10, VT-11, VT-12)",
§"On failure", §"Filling D8"; Explore 2 "Break the gate on purpose"; D8
(every table is the schema you are filling); D7 §2 steps 5–6.

**Tasks**

- [ ] `maiden validate --campaign results/campaign/` — record the verdict:
      VT-10 (pos RMS ≤ 1.0 m at 150 m), VT-11 (vel RMS ≤ 1.0 m/s), VT-12
      (continuity ≥ 95 %), each on ≥ 8 of 10 flights.
- [ ] **On failure:** do not touch the thresholds — they are D2's. Work
      the D5 mitigations in risk order (R4 re-survey/recalibrate first,
      then sensor-side, then descope C per R9), re-fly what must be
      re-flown, and re-run. Log every mitigation cycle.
- [ ] Fill D8: summary block (dates, flights, verdict, code tag, station
      serials/cal files), accuracy table from `campaign.csv`, by-maneuver
      rollup, judge-correlation table from maiden64, other-VT table
      imported from `results/` sheets.
- [ ] Write D8 §Anomalies from the maiden63 list — every degraded-sync or
      tracker-loss flight with cause and handling; "unexplained" is a
      finding, not a gap.
- [ ] Extract confidence bands: residual p95s → position/speed/score ±
      bands, with the widen-when-covariance-exceeds-campaign-median rule
      wired into the report path (D8 §Confidence bands).
- [ ] Explore 2: re-run one flight with Station B deleted; record how pos
      RMS degrades and whether the widened covariance would have confessed
      in the report bands — D3's R²/B claim, measured.
- [ ] On a passing gate: tag `v0.2-prototype` at the flown commit.

**Done when**

- The gate verdict (pass, or documented mitigation cycles ending in pass)
  is recorded with `campaign.csv` as evidence.
- D8 has no empty table cell without a dash-and-reason.
- `bands` parameters are committed and consumed by `maiden.report`.
- `v0.2-prototype` is tagged (gate pass) — observe in the data, never
  asserted without it.

**Doc trace.** SYS-002/003/004 (VT-10/11/12), SYS-008 (table), D7 §2
steps 5–6, D8 (all sections), D5 risk register R4/R9 and §CM tags;
lesson99 Verify, Explore 2.
