# maiden25 — Dropouts & continuity [desk]

**Sprint goal.** Finish `maiden.fuse`: the full measurement scheduler with
50 Hz epoch publishing, coasting through gaps, track-validity and
continuity accounting — then run the imperfect three-station twin and
measure yourself against the SYS-002/003/004 numbers in sim.

**Depends on.** maiden24 (v_r + gating), maiden12 (twin `--imperfect`
sessions with dropouts and sun-crossing).

**Read first.** lesson13.md — *Concepts* "Epochs, lag, and the
measurement queue" and "Coasting, validity, and continuity", then *Build*
(order of work items 3–6), *Verify*, and *Explore*.

## Tasks

- [x] Implement the full `fuse(samples, stations, epoch_hz=50.0)`
      scheduler: sort, init (maiden22), predict/update per measurement
      with gating, coast through gaps, publish valid-flagged FUSED
      samples with covariance on the uniform 50 Hz epoch grid. Keep
      `fuse_azel_only` working — CI uses it as a degraded-mode test.
- [x] Implement `FuseStats` (n_updates, n_gated, coast_time, valid_time)
      and the validity rule: valid while √trace(P_pos) ≤ 3 m (course
      constant — record the "revisit after the campaign" comment).
- [x] Continuity accounting exactly in SYS-004's sense: valid-epoch time
      over total sequence time, per flight.
- [x] CLI: `maiden fuse --session DIR` → `fused.npz` + a stats line, for
      twin or real session directories alike.
- [x] **Headline run**: full twin, three stations, `--imperfect`. Record
      per flight into `results/lesson13/`: position RMS, velocity RMS,
      continuity. Thresholds cited from D2 (hardcode-with-TODO until
      maiden28's `config/thresholds.yaml` lands).
- [x] Ablate the v_r updates back out and record the velocity-RMS delta —
      D3's architecture decision, measured.
- [ ] Explore — station-out ablations (A+B, A+C, B+C, A+B+C) and the
      baseline-extension geometry-torture pass; confirm C rescues the
      initializer's singular direction.

## Done when

- `maiden fuse --session <twin dir>` runs the imperfect twin end to end;
  pos RMS, vel RMS, and continuity meet the SYS-002/003/004 thresholds in
  sim and the numbers are logged in `results/lesson13/`. (Necessary, not
  sufficient — VT-10/11/12 bind only on the field campaign.)
- Gate-rejection rate on the clean twin is below 1% and you know the
  number; >1% on any run sends you to the model, not the gate.
- FUSED StateSamples carry a 6×6 covariance and a validity flag on a
  uniform 50 Hz grid — the contract maiden26's residual pipeline and
  D8's confidence bands consume.

## Doc trace

SYS-001–SYS-004 all exercised end-to-end on twin data; D6 §Fusion EKF
design element complete (common-epoch lag, missing-measurement handling,
published covariance); VT-10/11/12 sim rehearsal; VT-17 now fully
checkable (formalized in maiden26–27).

---
**Build note (executed).** Headline (twin seed 303, --imperfect, .ch10
round trip): pos RMS 0.219 m, vel RMS 0.909 m/s, continuity 1.0000,
gate rate 0.089% (14571 updates / 13 gated) — all inside the
SYS-002/003/004 sim-rehearsal thresholds; VT-10/11/12 still bind only in
the field. v_r ablation: vel RMS 1.608 → 0.909 m/s, D3's architecture
decision measured. Evidence: results/lesson13/. CLI is
`python -m maiden.fuse --session DIR` (or `maiden fuse` once the
orchestrator adds the one-line cli.py dispatch — cli.py was outside this
sprint's file scope). Validity is a derived property (is_valid();
IF-4 stays frozen). Station-out ablation table (A+C/B+C rows) left
unticked — the geometry insight it targets landed via the collinearity
discovery in maiden24's note instead.
