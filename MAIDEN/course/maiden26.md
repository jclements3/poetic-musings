# maiden26 — Residual pipeline [desk]

**Sprint goal.** Implement D7's verification-against-truth steps 1–3 —
time-alignment as a *check*, truth frame transform, per-sample residuals —
and prove them on twin sessions where the answers are known.

**Depends on.** maiden25 (fused epoch grid with validity flags),
maiden02 (`geo.enu_from_lla`), maiden14–15 (ingest incl. TRUTH streams).

**Read first.** lesson14.md — *Concepts* "The seven steps, from the D7
figure", "Step 1 — alignment is a check, not a knob", and "Step 2–3 —
comparing apples to apples", plus the *Build* implementation notes.

## Tasks

- [x] Start `software/maiden/validate.py` with
      `align(fused, truth, budget_s)`: locate the sync event (clap —
      accelerometer spike in truth, transient at Station A; twin sessions
      use the event time in the truth sidecar — add it to the twin now if
      lesson 07 didn't, ~five lines) and confirm both streams agree
      within the SYS-006 budget. On disagreement: apply the offset,
      flag the session degraded-sync, and *record* the offset — never
      silently.
- [x] Frame transform: truth GNSS LLA + velocity →
      `geo.enu_from_lla` with the session's surveyed origin from Station
      A's TMATS descriptor (maiden14's object).
- [x] `residuals(fused, truth)`: interpolate *truth* onto the fused 50 Hz
      epoch grid (never the estimate — filter artifacts must not be
      smoothed away), `np.interp` per component, trimmed to overlap, no
      extrapolation. r_pos and r_vel as 3-vectors; the attitude column
      emitted as absent, not zero.
- [x] Only validity-flagged epochs enter the residual set.
- [x] **Zero-noise identity test**: twin with all noise off, fused track
      replaced by truth-resampled-to-epochs → every RMS ~0, continuity
      1.0. This catches sign and interpolation bugs first.
- [x] **Alignment tripwire test**: copy a twin session, shift one
      station's timestamps +100 ms; the event check must flag it, report
      the offset to within a frame time, and mark the session degraded.

## Done when

- `align` and `residuals` pass the zero-noise identity and the alignment
  tripwire, and both are committed as pytest tests.
- Degraded sync is impossible to produce silently: the flag and the
  recorded offset appear in the outputs.
- You can explain, without notes, why truth is interpolated to the fused
  epochs and not the other way around.

## Doc trace

D7 §Verification against 6-DOF truth, steps 1–3 (code comments carry the
D7 step numbers); SYS-006 (the alignment budget being checked); VT-17
groundwork — the metrics, gate, and consistency runs land in maiden27.

---

**Execution notes (maiden26, desk).** `align`/`residuals` built in
`software/maiden/validate.py`; tests in `test_validate.py` (zero-noise
identity, clean-session alignment, tripwire). Decisions of record:
(1) the alignment check compares each STATION stream against
truth-projected az (the aircraft's own motion is the common event) —
better localized than fused-vs-truth and it names the offending
station; the clap time is checked for containment. (2) The estimator is
variance-of-difference over a fixed window with parabolic refinement;
gaps (sun outage) are masked with max-lag dilation — both choices were
forced by real failures, recorded in the docstrings. (3) The tripwire
shifts the ingested stream (+100 ms) rather than re-encoding packets —
equivalent, and the offset is recovered to well within a frame time
(clean-session offsets sit at µs level). Real-session (LLA) truth path
is `Track.from_lla`, exercised fully when maiden49's converter lands.
