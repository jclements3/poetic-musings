# Detector sweep (maiden20) — twin rehearsal evidence

q derivation: worst px accel 131 px/s^2 at fx=832 (960x540), tau 0.5 s -> q = 8625 px^2/s^3 (TrackerCfg default 9000).

| thr | clean recall | clean false/frame | 3x-noise recall | 3x-noise false/frame |
|--|--|--|--|--|
| 0.3 | 0.985 | 0.000 | 0.985 | 0.000 |
| 0.34 | 0.985 | 0.000 | 0.985 | 0.000 |
| 0.38 | 0.985 | 0.000 | 0.985 | 0.000 |
| 0.42 | 0.985 | 0.000 | 0.985 | 0.000 |
| 0.46 | 0.985 | 0.000 | 0.985 | 0.000 |
| 0.5 | 0.985 | 0.000 | 0.980 | 0.000 |
| 0.54 | 0.985 | 0.000 | 0.980 | 0.000 |
| 0.58 | 0.980 | 0.000 | 0.980 | 0.000 |
| 0.62 | 0.980 | 0.000 | 0.980 | 0.000 |

FINDING: on twin imagery the curve is flat — zero false
accepts at every threshold, clean and 3x noise alike, because
propose()'s adaptive k*sigma threshold + morphology already
reject the noise before scoring. The detector threshold's
discrimination work begins with field clutter (birds, bugs,
lens flare) that the twin renderer honestly does not model.
Operating point: SCORE_THRESHOLD = 0.42, the plateau center
(max margin against both recall loss above 0.58 and future
clutter below), to be re-swept on labeled field frames
(VT-15 field subset, lesson 99).
