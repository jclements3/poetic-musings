# maiden51 — Features & Rule Segmenter [desk]

**Sprint goal.** Turn FUSED tracks into labeled maneuver segments the
inspectable way: the windowed feature set plus a rule/template classifier
with hysteresis, validated against the twin's ground-truth Events.

**Depends on.** maiden25 (full 3-station fusion runs on twin data),
maiden10 (twin `sportsman()` truth with `MANEUVER_START`/`MANEUVER_END`
Events).

**Read first.** lesson23.md — *Features a point-mass track can and
cannot see* and *Two classifiers, in the right order* (stage (a) only),
plus the `maiden/maneuver.py` items in the Build section.

**Tasks**

- [x] `software/maiden/maneuver.py`:
      `features(samples, rate_hz) -> FeatureFrame` — centered ~0.5 s
      windows; curvature κ = |v × a|/|v|³ with Savitzky–Golay-smoothed a
      (never raw differences), unwrapped smoothed heading rate,
      vertical-plane angle from a plane fit, altitude/speed slopes, and
      the lateral-acceleration roll proxy (documented as the weak signal
      it is).
- [x] `segment_rules(ff) -> list[Event]` — per-window decision tree over
      the features, segment assembly with hysteresis (class change must
      persist H ≈ 5 consecutive windows), classes: loop, roll, stall
      turn, Immelmann, level leg, other. Emits the same Event contract
      stage (b) will use.
- [x] `software/tests/test_maneuver_rules.py`: on a clean twin session,
      every scripted maneuver found, classes correct, boundaries within
      ~1 s of twin Events; seeded and tolerance-explicit.
- [x] Explore: generate a twin loop with 20% vertical ellipticity — note
      which features move first; shrink to 5% and find where stage (a)
      loses it. Keep the notes; maiden52 compares.

**Done when**

- `pytest software/tests/test_maneuver_rules.py` passes on a clean twin
  session.
- Feature arrays are visibly sane on a plotted twin sequence (loop shows
  the κ/vertical-plane signature; stall turn shows the speed-profile
  signature).
- The roll-proxy limitation is documented in the module docstring, not
  discovered later in the field.

**Doc trace.** SW-003 (stage (a) baseline); VT-16 is the field test —
today's numbers are rehearsal; D6 §Maneuver segmentation; D5 risk R6
context.

---

**Execution notes (maiden51, desk).** All tasks done. Features + rule
segmenter in `software/maiden/maneuver.py`; 4/4 maneuvers on every
tested seed with zero spurious segments, boundaries <= 0.1 s (test
tolerance 1 s). Two rule additions earned during tuning: steep straight
lines (climb angle > ~37 deg) count as aerobatic (stall-turn up/down
lines otherwise fragment the segment), and rolls hugging an aerobatic
segment are suppressed (an Immelmann exits through its own half roll).
The attitude-free roll limitation is pinned as a test
(`test_attitude_free_roll_limitation_is_pinned`), not discovered later.
Ellipticity probe in results/VT-16/rehearsal/sweeps.md: kappa CV moves
first (0.174 at 20%, 0.104 at 5%); vplane unmoved; stage (a) holds at
both.
