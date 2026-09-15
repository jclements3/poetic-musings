# maiden59 — Survey day [field]

**Sprint goal.** Complete the field-dependent Phase 0 survey: permanent
station marks with GNSS positions, a tape-checked A–B baseline, and the
digitized field-rule polygons that close D2's TBD on SYS-010 — a full
field session with no flying.

**Depends on.** maiden58. Gates: RCRC field access on a clear day; GNSS
receiver (RTK base if available); tape measure ≥ 75 m or ranging method.

**Read first.** lesson99.md — Build §2 "Field survey completion (first
field session, no flying)"; D1 §Operating site; D3 Figure 2 (why the
baseline carries the error budget).

**Tasks**

- [ ] Set and photograph permanent marks for Stations A, B, C per the D1
      site layout (A at the pilot/judge line, B 50–100 m down the flight
      line, C near the threshold).
- [ ] 5-minute GNSS average at each mark (RTK if the base is up); record
      positions in `config/field/rcrc.yaml` and in each station's TMATS
      survey attributes.
- [ ] Tape-measure the A–B baseline; compare against the GNSS-derived
      distance and record both — this is the sanity check on the whole
      σ ≈ R²σ_θ/B error budget.
- [ ] Walk the flight line and no-fly boundary with the GNSS receiver;
      digitize both polygons into `config/field/rcrc.yaml`.
- [ ] Commit the polygon + D2 row update as one commit, closing the
      SYS-010 TBD per D5 change control.
- [ ] Note sun azimuth/elevation for your usual session hours; pick which
      campaign session will deliberately face the low sun (D7 conditions)
      and record the choice in the campaign notes.

**Done when**

- `config/field/rcrc.yaml` holds surveyed marks for A/B/C, the measured
  baseline, and both field-rule polygons.
- Tape vs. GNSS baseline agreement is recorded (disagreement beyond the
  survey tolerance is a stop-and-fix, not a footnote).
- The SYS-010 TBD-closure commit exists (D2 + config in one commit).
- Photographs of the three marks are in `results/survey/`.

**Doc trace.** GS-004, SYS-010 (TBD closed), D1 §Operating site, D3
Figure 2, D5 change control; lesson99 Build §2.
