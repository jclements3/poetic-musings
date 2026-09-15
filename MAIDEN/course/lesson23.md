# Lesson 23 — Maneuvers & Scoring [desk]

*Where we are.* The pipeline now turns three station files into a FUSED
track with covariance (lessons 12–13) and proves its accuracy against
truth (lesson 14). But a pilot doesn't fly a track; they fly a *sequence*
— loop, roll, stall turn — and what they want back is a judge's answer:
which maneuver, and how good. This lesson builds the two modules that
close that gap: `maiden/maneuver.py`, which cuts the track into labeled
segments, and `maiden/score.py`, which grades each segment against
deterministic geometry checks and holds the seat for the judge-calibration
layer that can only be trained during the campaign.

## Objectives

- Compute the D6 feature set on a sliding window over FUSED samples:
  curvature, heading rate, vertical-plane angle, altitude and speed
  profiles, and the lateral-acceleration roll proxy.
- Build a rule/template segmenter-classifier for loop, roll, stall turn,
  Immelmann, level leg, and other, with hysteresis on boundaries.
- Train the D6 temporal GRU on twin sequences with randomized
  imperfections and evaluate on held-out twin seeds.
- Implement the rubric scoring layer: itemized deductions, 0–10 per
  maneuver, plain-language output.
- Build the calibration layer (rubric → judge scores) as trainable but
  untrained code, with its campaign data contract documented.

## Concepts

### Features a point-mass track can and cannot see

The FUSED state is position and velocity — no attitude. Everything the
classifier eats must be derivable from that, so be honest about what each
feature observes. On a centered window (width ~0.5 s, step = the fusion
rate):

- **Curvature** κ = |v × a| / |v|³, with a from smoothed differentiation
  of v (Savitzky–Golay; never raw differences — lesson 13 taught you what
  differentiating noise costs). High sustained κ in a vertical plane is a
  loop's signature.
- **Heading rate** ψ̇ from atan2(vE, vN) unwrapped and smoothed. Turns
  and stall-turn pivots live here.
- **Vertical-plane angle**: fit a plane to the window's positions; the
  angle between its normal and the U axis says whether the aircraft is
  maneuvering in a vertical plane (loop, Immelmann ≈ 90°) or a horizontal
  one (level leg ≈ 0°).
- **Altitude and speed profiles**: U(t) and |v|(t) slopes over the
  window. A stall turn is readable almost entirely from these: up-line,
  |v| → near zero, down-line.
- **Roll-rate proxy**: a pure axial roll barely disturbs the flight path
  — the track stays nearly straight, which is exactly why a roll is hard
  for us. The proxy is the lateral acceleration component (a projected
  onto the horizontal unit vector perpendicular to v): a rolling aircraft
  sheds small periodic lateral wobble as lift rotates. It is a weak,
  noisy signal; the lesson says so, and the classifier treats "straight
  track + wobble + level altitude + roll-duration window" as the roll
  template rather than pretending to measure roll angle.

### Two classifiers, in the right order

D6 specifies a temporal CNN/GRU. Reaching for it first would be
malpractice: you'd have no baseline to tell whether 90% is good and no
intuition for which features carry which class. Stage (a) is a
rule/template classifier — a per-window decision tree over the features
above, then segment assembly with hysteresis: a class change must persist
for H consecutive windows (start with H ≈ 5) before a boundary is
declared, which kills flicker at maneuver edges. Stage (a) is fully
buildable today against twin data, is debuggable by reading its rules,
and becomes the baseline row in your results table.

Stage (b) is the D6 model: a small GRU (or temporal CNN — try the GRU
first, it's less shape-fiddly) over the same feature windows, trained on
twin sequences generated with `--imperfect` across many seeds, labels
taken from the twin's ground-truth Events (lesson 06 wrote them precisely
so this lesson wouldn't have to hand-label anything). Fine-tuning on
labeled validation flights happens after the campaign — the model you
train today has never seen a real aircraft, and the lesson's evaluation
says so out loud.

### Scoring is geometry first, judgment second

The rubric layer is deterministic and inspectable: for each recognized
maneuver, geometric checks per the AMA description — loop roundness as
radius variance about the circle fit in the maneuver's vertical plane,
centering as offset of the figure's center from the pattern-box
centerline, track as heading deviation from the box axis, entry/exit
altitude match. Each check emits a deduction with a magnitude and a
sentence ("loop 4 m narrower at the top than the bottom"), and the
maneuver score is 10 minus summed deductions, floored at 0.

Fetch the actual maneuver descriptions from the current AMA Radio Control
Aerobatics rulebook (modelaircraft.org → Competition → Rulebooks; the
Sportsman schedule). The lesson does not restate the rubric — download
the PDF, put the relevant sections in `docs/refs/`, and cite paragraph
numbers in `score.py`'s docstrings. Downgrade *magnitudes* (how many
points per defect) are where human judging is famously nonlinear — which
is why SYS-008 exists. The calibration layer is an isotonic (monotone)
regression from rubric deduction totals to judge scores, per maneuver
type: build the class, its fit/save/load, and its data contract (judge
sheets keyed by flight and maneuver), but it stays untrained until the
campaign delivers judge sheets (lesson 99). Until then `Score.calibrated`
is `None` and the report shows raw rubric scores, labeled as such.

## Doc Trace

- **SW-003** (recognition, ≥ 90% on validation flights) is this lesson's
  requirement, verified by **VT-16** — on *field* data. Today's held-out
  twin accuracy is a rehearsal number; record it, don't confuse it.
- **SYS-007** (score a Sportsman sequence, 0–10 per maneuver) shapes the
  rubric layer; **VT-20** is its demonstration and can run on twin data.
- **SYS-008** / **VT-21** (judge correlation r ≥ 0.8) is the calibration
  layer's requirement; it cannot be exercised before the campaign. The
  code ships now, the fit happens in lesson 99.
- **D5 risk R6** (judging criteria partly subjective) is mitigated
  exactly here: deterministic rubric + monotone calibration is the
  design answer. If the campaign shows r < 0.8, the fallback discussion
  belongs in D8's lessons-learned, not in silent rubric tweaks.
- D6 §Maneuver segmentation and §Scoring govern both modules.

## Build

`software/maiden/maneuver.py`:

- `features(samples: list[StateSample], rate_hz: float) -> FeatureFrame`
  — the windowed feature arrays above; a dataclass of aligned NumPy
  arrays plus the window timestamps.
- `segment_rules(ff: FeatureFrame) -> list[Event]` — stage (a). Emits
  `MANEUVER_START`/`MANEUVER_END` Events with `data={"class": ...,
  "conf": ...}`; hysteresis parameter H exposed.
- `segment_gru(ff, model_path) -> list[Event]` — stage (b) inference,
  same Event contract, so downstream code can't tell which ran.
- `train/train_maneuver.py` — generates N twin sessions across seeds
  with imperfections, builds (features, label) windows from twin Events,
  trains the GRU (PyTorch, ~2 layers, hidden ≤ 64 — this must run on
  your CPU), holds out entire seeds (never windows — windows leak),
  writes the model + a confusion matrix to `results/VT-16/rehearsal/`.

`software/maiden/score.py`:

- `Deduction(text: str, points: float, tag: str)` and
  `ManeuverScore(cls, raw: float, calibrated: float | None,
  deductions: list[Deduction])`.
- Per-class check functions (`_score_loop`, `_score_roll`, ...): circle
  fit (algebraic fit, then geometric refinement) in the maneuver plane
  for loops/Immelmanns; line fits for legs and up/down-lines; centerline
  and heading geometry from `config/field/rcrc.yaml` plus the box
  definition. Every check cites its AMA paragraph.
- `Calibration` — per-class isotonic regression (sklearn
  `IsotonicRegression`), `fit(judge_sheets)`, `save/load`, and a
  docstring specifying the judge-sheet CSV schema the campaign must
  produce.
- `score_sequence(events, samples) -> list[ManeuverScore]` — the module
  entry point the report will call.

## Verify

All on twin data; **no fabricated numbers — run and record yours**:

1. Stage (a) on a clean twin session: every scripted maneuver found,
   classes correct, boundaries within ~1 s of twin Events. Write this as
   `software/tests/test_maneuver_rules.py` with tolerances, seeded.
2. Stage (b): train, then evaluate on ≥ 5 held-out seeds. Record
   per-class accuracy and the confusion matrix in
   `results/VT-16/rehearsal/`. The VT-16 bar is ≥ 90% per maneuver — if
   the twin rehearsal can't clear it, the field certainly won't; iterate
   features before reaching for a bigger model.
3. VT-20 shape check: `score_sequence` on a twin `--imperfect` session
   prints one 0–10 line per maneuver with itemized plain-language
   deductions. Confirm a *clean* twin session scores near 10 with
   near-empty deduction lists — the null test that catches sign errors
   in every geometry check at once.
4. Determinism: same session, same scores, bit-for-bit (seeded, no dict
   iteration order leaks) — CI will rely on this.

## Explore

- **Break a rule, watch the tree.** Generate a twin loop with 20%
  vertical ellipticity. Which features move first? Now shrink it to 5% —
  where does stage (a) lose it, and does the GRU do better or just
  differently?
- **The roll problem, quantified.** Sweep the twin's roll lateral-wobble
  amplitude toward zero and plot both classifiers' roll recall. Decide
  what wobble level is physical for your airframe (you'll find out for
  real in the campaign) and write the number and its uncertainty into
  the model card.
- **Judge yourself.** Score a twin session by eye from the Station A
  synthetic geometry (pretend to be a judge), then compare your sheet to
  the rubric's. Your disagreement with yourself is a preview of R6 and
  of what r ≥ 0.8 actually demands.
- **Doc friction check.** SW-003's class list omits the reversal and
  half-reverse-cuban present in some Sportsman schedules. Check the
  current AMA schedule against D2; if it drifted, revise D2/D6/D7 per
  D5 change control now, not during the campaign.

## Checkpoint

- `pytest software/tests/test_maneuver_rules.py` passes; stage (a) finds
  and labels all maneuvers on a clean twin session.
- A trained GRU exists with held-out-seed confusion matrix committed
  under `results/VT-16/rehearsal/`; you know your per-class numbers.
- `score_sequence` produces deterministic 0–10 scores with itemized
  plain-language deductions on twin sessions; clean twin ≈ 10s.
- `Calibration` fits, saves, loads on synthetic sheets; contract for the
  campaign's judge CSV is documented; `calibrated=None` path works.
- AMA rulebook sections are in `docs/refs/` and cited from `score.py`.
