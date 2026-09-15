# maiden54 — Calibration Layer (Untrained) [desk]

**Sprint goal.** Build the rubric→judge calibration layer — trainable,
saveable, loadable, contract-documented — and leave it honestly untrained
until maiden64 delivers real judge sheets.

**Depends on.** maiden53 (rubric scores). Trains for real in maiden64.

**Read first.** lesson23.md — the calibration paragraphs in *Scoring is
geometry first, judgment second*, and the `Calibration` item in the
Build section.

**Tasks**

- [x] `Calibration` class in `score.py`: per-maneuver-class isotonic
      regression (sklearn `IsotonicRegression`) from rubric deduction
      totals to judge scores; `fit(judge_sheets)`, `save`, `load`.
- [x] Document the judge-sheet CSV schema in the docstring — keyed by
      flight and maneuver; this is the data contract the campaign
      (maiden64) must produce, so write it as a contract, not a wish.
- [x] Wire the untrained path: `ManeuverScore.calibrated` is `None`
      until a fit exists, and the report must label raw rubric scores as
      such (maiden55 consumes this flag).
- [x] Smoke-test fit/save/load on a *synthetic* sheet (labeled synthetic
      — this proves the plumbing, not SYS-008; say so in the test name).
- [x] Explore: lesson 23's "judge yourself" drill — score one twin
      session by eye from Station A's synthetic geometry, compare your
      sheet to the rubric's. Your self-disagreement previews D5 risk R6
      and what r ≥ 0.8 actually demands; keep the sheet in
      `results/VT-21/rehearsal/`.

**Done when**

- `Calibration` round-trips fit/save/load on the synthetic sheet;
  monotonicity holds by construction.
- The judge-sheet CSV schema is documented and referenced from
  lesson 99's campaign procedure (check the pointer resolves).
- The `calibrated=None` path flows through `score_sequence` without
  special-casing downstream.

**Doc trace.** SYS-008 / VT-21 (cannot bind before the campaign — the
code ships now, the fit happens in maiden64); D5 risk R6; D8 judge
correlation table is where the result lands.

---

**Execution notes (maiden54, desk).** Calibration = numpy PAV isotonic
(sklearn is not a project dependency — deliberate substitution from the
card's IsotonicRegression mention; same model class, no new deps).
Fit/save/load round-trips on a labeled-synthetic sheet; monotonicity
asserted across the full 0-10 range; calibrated=None flows through
score_sequence untouched and `ManeuverScore.line()` omits the "cal"
field when untrained (maiden55's flag). Judge-sheet CSV contract in
`config/judge_sheets/README.md` + score.py docstring. Judge-yourself
drill done for real: results/VT-21/rehearsal/self_judge.md (mean |delta|
0.45 pts, itemization-vs-gestalt finding, two fold-back notes).
**Unresolved done-when item, for the orchestrator:** lesson99.md and
maiden64.md do not yet reference config/judge_sheets/README.md — the
pointer does not resolve; those files are outside this sprint's scope.
