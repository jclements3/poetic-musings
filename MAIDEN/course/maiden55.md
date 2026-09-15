# maiden55 — The One-Page Report [desk]

**Sprint goal.** Render the pilot's page: scores table with ± bands,
per-maneuver geometry overlays, top-3 deductions, JSON sidecar, and
Station A clips — with band provenance visible and honest.

**Depends on.** maiden53 (scores), maiden27 (`bands.json` residual
stats). The approach panel and field-rule flags render from stubs until
maiden56/maiden57 fill them.

**Read first.** lesson24.md — *Bands, or the report's honesty budget*
and *One page means one page*, plus the `maiden/report.py` items in the
Build section.

**Tasks**

- [x] `software/maiden/report.py`: `Bands` — loads
      `results/campaign/bands.json` or the twin-rehearsal file, tagging
      provenance; implements the D8 widening rule (band widens by
      √(trace ratio) of the relevant covariance block whenever live EKF
      covariance exceeds the campaign median).
- [x] `render(flight, out_dir)` — one Letter-size page via matplotlib
      `PdfPages`: scores table (raw-vs-calibrated labeling per
      maiden54), per-maneuver overlay (flown solid, ideal dashed,
      judge's-view projection from Station A's pose, gray band =
      position confidence), top-3 deductions in plain language, panel
      slots for approach and rule flags.
- [x] Layout constants at module top; every panel a function so tests
      can render panels in isolation.
- [x] JSON sidecar: everything on the page plus machine-readable detail
      (all deductions, all Events, band provenance) — byte-identical
      across runs of the same session.
- [ ] Clip cutting: ±5 s around each maneuver from Station A video via
      `ffmpeg -ss ... -c copy` (keyframe-snapped, deliberately not
      re-encoded); twin sessions log "no video channel" and move on.
- [x] Band footer: until the campaign runs, the page says "bands: twin
      rehearsal — not yet field-validated". Non-negotiable.
- [x] Explore: the band-abuse test — drop B's measurements in a twin
      run and confirm the overlay's gray band visibly widens and the
      score ± grows. A reader must *see* degraded geometry without a
      footnote.

**Done when**

- `render()` produces a one-page PDF from a twin session matching D9
  §Reading the pilot report element-for-element (approach/rules panels
  may show their maiden56/57-pending stubs).
- Two runs of the same session yield byte-identical JSON sidecars.
- Band provenance is visible on the page and in the sidecar; the
  widening rule has a unit test with hand-computed expected widths.

**Doc trace.** SYS-011 (the artifact); D6 §Report; D9 §Reading the pilot
report and its "bands matter" paragraph; D8 §Confidence bands (widening
rule).


---

**Execution notes (maiden55, desk).** All tasks done. `report.py`:
`Bands` (campaign-else-rehearsal load, provenance tag, widening =
sqrt(median live tr(P_pos) / CAMPAIGN_MEDIAN_TR_POS_M2), placeholder
median 0.04 m^2 from the maiden25 headline, unit-tested at factor 2.0),
`render()` one Letter page via PdfPages (page count asserted = 1),
every panel a function, deterministic sidecar (byte-identical across
runs, tested), band footer non-negotiable and tested, twin-provenance
footer. Clips: ffmpeg exists on this host but a raw .ch10 is not fed to
it — field path extracts Ch 2 TS payloads to .ts first (maiden41);
command construction dry-run tested. Band-abuse Explore folded into
test_band_abuse_visibly_widens. Sidecar archaeology: loop roundness
recoverable from deduction tags (tested).
