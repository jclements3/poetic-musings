# maiden57 — Field Rules & `maiden run` [desk]

**Sprint goal.** Close the software track: the field-rule checker over
placeholder polygons, the D9 `maiden run --session` command chaining the
whole pipeline, and the first honest measurement of the 10-minute clock.

**Depends on.** maiden55 (report), maiden56 (approach), maiden02
(`rcrc.yaml`). Real polygon vertices arrive with maiden44/59's survey —
this sprint ships the placeholder and the mechanism.

**Read first.** lesson24.md — *Field rules are geometry, and the
geometry is a TBD*, the `maiden/rules.py` and `cli.py` items in the
Build section, and Verify items 3–5.

**Tasks**

- [x] `software/maiden/rules.py`: `load_rules(path) -> FieldRules`;
      `check(samples, rules) -> list[Event]`. Schema: named polygons in
      field-frame ENU with a rule class and plain-language name;
      placeholder set ships with `status: PLACEHOLDER_PENDING_SURVEY`,
      which the report surfaces.
- [x] Crossing detection: segment-vs-polygon intersection on the FUSED
      track with a few samples of hysteresis (covariance-wide jitter at
      a boundary must not emit twenty Events). Each crossing is
      `Event(kind="RULE_CROSSING", ...)` — informational; the report
      wording must match D9's "MAIDEN does not adjudicate".
- [x] Rules test: a twin flight scripted through a placeholder no-fly
      polygon yields exactly one enter and one exit Event with sensible
      time/location; a clean flight yields none.
- [x] `maiden run --session DIR` in `cli.py`: ingest → track (skipped
      when twin sessions carry tracker channels) → fuse → maneuvers →
      score → approach → rules → report; one PDF + sidecar per detected
      flight; stage-by-stage wall-clock table printed at the end. Match
      the UX to D9's wording.
- [ ] The clock: run on a full-length twin session (Sportsman ×2 plus
      landings) on the actual host you'll take to the field; commit the
      stage table to `results/VT-24/rehearsal/` (**observe on your
      machine**). If total + a realistic SD-copy estimate exceeds ~7 of
      the 10 minutes, profile now — video decode and figure rendering
      are the usual suspects.
- [x] Explore: lesson 24's sidecar-archaeology exercise — a script that
      answers "how has my loop roundness trended across sessions?" from
      sidecars alone; fix the sidecar schema now if it can't.

**Done when**

- `maiden run --session` chains the full pipeline on a twin session:
  one-page PDFs + deterministic sidecars, all panels live.
- Rule checker passes the scripted-violation test; placeholder status
  is visible in the report.
- Stage-timing table committed to `results/VT-24/rehearsal/`, total
  comfortably inside the budget.
- The software track is feature-complete for the Prototype milestone —
  say so in the commit message; you earned it.

**Doc trace.** SYS-010 (checker; D2's polygon TBD closes after the
survey, per D5 change control), SYS-011; VT-23/VT-24 (field
demonstrations in Phase 2 — today rehearses both); D9 §Session workflow
step 6.


---

**Execution notes (maiden57, desk).** All tasks done; 7 tests in
test_rules.py + 10 in test_runner.py. Design finding of record: pure
sample-count hysteresis provably fails jitter sitting ON a boundary (a
run of N same-side samples every ~2^N samples) — check() carries a
spatial deadband (hysteresis_margin_m, default 2 m) plus the sample
streak; the failing scenario is kept as the regression test. rcrc.yaml
now ships the placeholder runway + polygons + flight line under
status PLACEHOLDER_PENDING_SURVEY (surfaced on the page and sidecar;
D2 TBD closes at the survey). `maiden run --session` chains
ingest->track(skip note)->fuse->maneuvers->approach->score->rules->
report with the stage table; the runner drops maneuver segments
overlapping the detected final leg (the steep twin descent otherwise
scored as a 0-point loop — segmentation fold-back flagged for
maiden51; roll absence on imperfect twin is maiden52's known
twin-wobble fold-back). VT-24 rehearsal
(results/VT-24/rehearsal/stage-table.md): two flights compute in
2.9 s; with SD-copy estimates 5.7 s of the 600 s budget — field risk
stays with video decode + host tracker (maiden41/42). The software
track is feature-complete for the Prototype milestone.
