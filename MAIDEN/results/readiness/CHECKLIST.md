# Prototype readiness checklist (maiden58 pre-draft)

Draft prepared at the end of the 21 Aug 2026 desk build run, against D5's
CDR+TRR entry criteria. maiden58 signs this only when every row is green;
today it shows exactly where the milestone stands. Status keys: GREEN
(done, evidence linked), SIM (verified in simulation only — field/bench
still binds), OPEN (not started / hardware-gated).

| Entry criterion (D5) | Status | Evidence |
|---|---|---|
| D4, D6, D7 complete; D2 baselined | OPEN | D6 carries two build-run revisions (decimation, FFT resource note); D2 baseline commit is maiden58's call |
| Digital twin runs in CI | GREEN | `make ci` GREEN; scripts/replay.py, seeds 1001–1003 |
| Ingest interface (VT-14) | GREEN | results/VT-14/summary.md; D8 row filled |
| Twin pipeline (VT-17) | GREEN | results/VT-17/consistency.md; D8 row filled |
| CI regression gate (VT-18) | GREEN | results/VT-18/drill.md; D8 row filled |
| Fusion accuracy/continuity (VT-10/11/12) | SIM | pos 0.219 m / vel 0.909 m/s / continuity 1.000 on imperfect twin; field campaign binds |
| Tracker (VT-15) | SIM | recall 0.985 clean / 0.951 sun on twin renders; labeled field frames bind |
| Maneuver recognition (VT-16) | SIM | 100% held-out-by-seed on twin; validation flights bind |
| Scoring demo (VT-20) | SIM | rubric scores with itemized deductions on twin sessions |
| Approach metrics (VT-22) | SIM | glideslope Δ0.02°, threshold speed Δ0.09 m/s vs twin truth |
| Station 1 bench-tested (VT-01–07) | OPEN | parts on hardware/BOM.md; procedures written (VT-02: results/VT-02/PROCEDURE.md) |
| Three stations built | OPEN | maiden43–46 |
| Airborne logger + converter (VT-08/09/13) | OPEN | converter code GREEN on synthetic fixture; real H743 log binds (maiden47) |
| Validation-campaign flight cards ready | OPEN | lesson99 / maiden58 |

Known engineering debts carried into the bench phase (all documented in
course/maiden00.md §Status): FFT BRAM rewrite before PnR; Station C must
sit off the flight line (rank-2 finding); rubric box-axis projection
when the survey sets a rotated axis; RTC 48-bit wrap unhandled
(irrelevant at session length); ingest day-late-increment hardening at
maiden41.
