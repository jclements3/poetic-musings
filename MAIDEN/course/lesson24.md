# Lesson 24 — Report, Approach, Field Rules [desk]

*Where we are.* Every stage of the pipeline now exists: ingest, tracker,
fusion, validation, maneuvers, scores. What the pilot receives, though, is
none of those — it's one page of paper, handed over at the field within
ten minutes of the SD pull. This lesson builds the last mile:
`maiden/report.py` and the approach/field-rule analytics that feed it, plus
the `maiden run --session` command D9 promises, which chains the whole
pipeline. When this lesson is done, the software track is
feature-complete for the Prototype milestone.

## Objectives

- Compute approach metrics: glideslope fit, threshold speed, touchdown
  point, and the session landing scatter.
- Implement the field-rule checker over polygons in
  `config/field/rcrc.yaml`, emitting crossing Events.
- Generate the one-page PDF per D6/D9: scores with ± bands, geometry
  overlays, approach panel, top-3 deductions, plus the JSON sidecar and
  Station A clips.
- Wire confidence bands from lesson 14's residual stats with the D8
  covariance-widening rule.
- Build `maiden run --session` and profile the 10-minute budget on a
  full twin session.

## Concepts

### The approach, as an estimation problem

A landing approach is the one flight phase where Station C is the star:
its radar looks straight up the centerline, so the target's velocity is
nearly all radial — the geometry that made v_r a weak constraint in the
pattern box makes it a direct speed measurement on final. The analytics:

- **Final-leg segmentation**: from the maneuver Events, take the last
  level/descending leg before touchdown; or detect directly — heading
  within tolerance of runway heading, altitude monotonically decreasing,
  distance-to-threshold decreasing.
- **Glideslope**: fit U against along-track distance-to-threshold over
  the final leg. Report the angle *with its fit standard error* — a
  glideslope quoted without a band invites over-reading, and D9's
  "bands matter" paragraph is explicit about this.
- **Threshold speed**: |v| from the FUSED track at threshold crossing,
  cross-checked against Station C's v_r (corrected by the cosine of the
  small angle between flight path and C's boresight). The VT-22 shape is
  agreement with truth within 1 m/s on validation flights; today you
  rehearse it against twin truth.
- **Touchdown**: vertical speed crossing zero at ground height, refined
  by Station C video in the field (the video refinement is a stub today
  — mark it; twin has no imagery of the flare). Touchdown scatter is
  just the session's touchdown points plotted against the target mark.

### Field rules are geometry, and the geometry is a TBD

SYS-010 needs the flight line and no-fly polygons — which D2 lists as TBD
pending the Phase 0 survey. The checker is buildable now against a
*placeholder* `rcrc.yaml` (schema: named polygons in field-frame ENU,
each with a rule class and a plain-language name); the real vertices get
digitized during lesson 20's field session, at which point you close the
D2 TBD with a commit touching D2 and this config together, per D5 change
control. Crossing detection is segment-vs-polygon intersection on the
FUSED track, hysteresis of a few samples so covariance-wide jitter at a
boundary doesn't emit twenty Events. Each crossing is an
`Event(kind="RULE_CROSSING", data={"rule": ..., "enter": bool, ...})` —
informational; MAIDEN does not adjudicate (D9 says so; the report's
wording must too).

### Bands, or the report's honesty budget

Every number on the page carries a ±. The recipe (D8 §Confidence bands):
the campaign's residual statistics set the *floor* — position p95, speed
p95, per-maneuver score spread — and the live EKF covariance *widens* a
band whenever it exceeds the campaign median for that quantity (scale by
√(trace ratio) of the relevant block). Until the campaign runs, the floor
comes from twin rehearsal residuals and the report footer must say
"bands: twin rehearsal — not yet field-validated". That footer is not
decoration; handing a pilot a confident-looking number with an unearned
band is exactly the failure mode this project exists to remove.

### One page means one page

D6 fixes the layout: scores table, per-maneuver overlay (flown solid,
ideal dashed, judge's-view projection, gray band = position confidence),
approach panel, top-3 deductions in plain language, field-rule flags.
Build it as matplotlib figures composed onto a single Letter-size page
(`PdfPages`), because matplotlib is already a dependency and its
determinism is testable. The JSON sidecar carries everything on the page
plus machine-readable detail (all deductions, all Events, band
provenance) for the member archive. Clips: cut ±5 s around each maneuver
from Station A video with `ffmpeg -ss ... -c copy` — keyframe-snapped
cutting is fine for a training aid and 100× faster than re-encoding,
which matters for the 10-minute clock. In twin sessions there is no
video; the clip step logs "no video channel" and moves on.

## Doc Trace

- **SYS-009** (approach speed and glideslope with confidence bands) →
  the approach analytics; **VT-22** verifies against truth in the
  campaign; twin rehearsal today.
- **SYS-010** (field-rule flags) → the checker; **VT-23** is the
  deliberate safe crossing in Phase 2. This lesson closes *code*; the
  polygon TBD in D2 closes after lesson 20's survey.
- **SYS-011** (report ≤ 10 min from SD pull) → the pipeline CLI and the
  budget table; **VT-24** is the stopwatch demonstration at the field.
- **D9** §Session workflow step 6 defines `maiden run --session today`;
  §Reading the pilot report defines the page this lesson renders; its
  "bands matter" paragraph governs the band footer.
- **D8** §Confidence bands defines the widening rule implemented here.

## Build

`software/maiden/approach.py`:

- `approach_metrics(samples, events, field) -> ApproachReport` —
  glideslope (angle ± se), threshold speed (fused + C-radar cross-check),
  touchdown ENU, per the concepts above. `field` is the parsed
  `rcrc.yaml` (runway heading, threshold and target marks).

`software/maiden/rules.py`:

- `load_rules(path) -> FieldRules`; `check(samples, rules) ->
  list[Event]`. Placeholder polygons ship in `config/field/rcrc.yaml`
  with a `status: PLACEHOLDER_PENDING_SURVEY` key the report surfaces.

`software/maiden/report.py`:

- `Bands` — loads `results/campaign/bands.json` (or the twin-rehearsal
  file, tagging provenance), applies the widening rule given per-segment
  EKF covariance.
- `render(flight, out_dir)` — the PDF (one page), the JSON sidecar, the
  clip cuts. Layout constants at module top; every panel a function so
  tests can render panels in isolation.

`software/maiden/cli.py` (extend):

- `maiden run --session DIR` — ingest → track (skipped for twin
  sessions with tracker channels already present) → fuse → maneuvers →
  score → approach → rules → report, one PDF + sidecar per detected
  flight, with a stage-by-stage wall-clock table printed at the end.
  This is D9's command; keep its UX matched to D9's wording.

## Verify

1. End-to-end on a clean twin session: `maiden run --session
   data/twin/clean/` produces a one-page PDF per flight. Check by eye
   against D9 §Reading the pilot report: every element present, band
   footer shows twin-rehearsal provenance.
2. Approach rehearsal (`software/tests/test_approach.py`): on a twin
   session with scripted landings, glideslope within tolerance of the
   twin's scripted value and threshold speed within 1 m/s of twin truth
   (VT-22's number, rehearsed). Record results in
   `results/VT-22/rehearsal/`.
3. Rules: a twin flight scripted through a placeholder no-fly polygon
   yields exactly one enter and one exit Event with sensible
   time/location; a clean flight yields none.
4. The clock: run the full pipeline on a *full-length* twin session
   (Sportsman sequence ×2 plus landings) on the actual host you'll take
   to the field. Print the stage table, commit it to
   `results/VT-24/rehearsal/`. **Observe on your machine** — if the
   total (plus a real SD copy time estimate) exceeds ~7 of the 10
   minutes, profile now: the usual suspects are video decode and figure
   rendering, and Phase 2 hardening (D5) is where you spend headroom,
   not the demo morning.
5. Determinism: two runs of the same session produce byte-identical JSON
   sidecars (PDF metadata may differ; the sidecar must not).

## Explore

- **Band abuse test.** Feed the report a segment with artificially
  inflated covariance (drop B's measurements in the twin). Does the
  overlay's gray band visibly widen, and does the score's ± grow? A
  reader should *see* degraded geometry without reading a footnote.
- **The judge's view.** The overlay projects into Station A's view.
  Render the same maneuver from B's pose. Which defects are visible from
  A but invisible from B? (This is why the judge sits where the judge
  sits — and why centering deductions need the box geometry, not just
  the track.)
- **Ten minutes, adversarially.** Simulate the worst realistic session:
  3 flights, full video channels, host on battery power-save. Where does
  the budget break first? File the finding as a D5 risk-register note if
  it's material.
- **Sidecar archaeology.** Write a tiny script that answers, from
  sidecars alone, "how has my loop roundness trended across sessions?"
  If the sidecar schema can't answer it, fix the schema now — the member
  archive (D1's club uses) will ask exactly this.

## Checkpoint

- `maiden run --session` chains the full pipeline on a twin session and
  emits one-page PDFs + deterministic JSON sidecars.
- Approach rehearsal numbers recorded in `results/VT-22/rehearsal/`;
  threshold speed within 1 m/s of twin truth.
- Rule checker emits correct crossing Events on a scripted violation;
  `rcrc.yaml` placeholder is flagged in the report pending the survey.
- Stage-timing table committed to `results/VT-24/rehearsal/` with total
  comfortably inside the 10-minute budget.
- Band provenance (twin rehearsal vs. campaign) is visible on the page
  and in the sidecar.
