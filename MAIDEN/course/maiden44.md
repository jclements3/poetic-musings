# maiden44 — Survey & Calibration Drill [field]

**Sprint goal.** Run the D6 survey & calibration procedure end to end on
the real station and retire VT-06 and VT-07 with field evidence.

**Depends on.** maiden43 (Station 1 assembled). Weather gate: two calm
days — VT-06 requires surveying the same mark on **two different days**,
so this sprint spans two short field visits.

**Read first.** Lesson 20: *The survey & calibration procedure, for real
this time* and its Verify section; lesson 09's calibration drill is the
rehearsal this executes.

**Tasks**

- [ ] Run the 5-step procedure as one drill: tripod + level + ground mark;
      5-minute GNSS average; landmark heading sight verified against a
      second landmark (agreement within 0.2° or find the bad coordinate);
      12-pose checkerboard to ≤ 0.5 px; corner-reflector boresight walk.
- [ ] Time each step — the baseline for GS-006's 15-minute deploy (no
      pass/fail yet; that's maiden60).
- [ ] **VT-06:** repeat the survey of the same mark on a second day;
      compare position and heading (and against the RTK reference if the
      maiden47 F9P decision provides one). Log both surveys and deltas to
      `results/VT-06/`.
- [ ] **VT-07:** rerun lesson 09's hold-out intrinsics check on the real
      station camera *in its case* (window glass now in the optical path).
      Log the report to `results/VT-07/` (remaining serials added in
      maiden46).
- [ ] Run lesson 20 Explore 3 back at the desk: perturb a twin station
      heading by 0.5°, compare fused-position shift at 150 m against D3's
      R²·σ_θ/B prediction; pin the number in `docs/` margin notes.
- [ ] Fill D8's rows for VT-06 and VT-07 (station 1 entry).

**Done when**

- VT-06 pass: ≤ 0.1 m position, ≤ 0.2° heading between days — evidence in
  `results/VT-06/` (**observe in the field**).
- VT-07 pass: ≤ 0.5 px on hold-out poses through the case window —
  evidence in `results/VT-07/` (**observe on bench/field**).
- Step timings recorded; the heading-sensitivity number is committed.

**Doc trace.** GS-004, GS-005; VT-06, VT-07; D6 survey/calibration
procedure; D3 Figure 2; D5 risk R4.
