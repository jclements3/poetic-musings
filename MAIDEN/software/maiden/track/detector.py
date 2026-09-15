"""Candidate scoring detector (lesson 11, maiden20).

    score = w_a * size_plausibility + w_c * contrast_norm + w_m * motion

A weighted score, not a verdict: the threshold that turns scores into
detections belongs to the caller (StationTracker), and the whole thing is
a pure function of (candidates, context) so the D6 YOLO-class detector —
deferred until labeled field frames exist, per lesson 11 — can drop in
behind the same signature.

Terms, each in [0, 1]:

- size_plausibility: log-normal plausibility of the blob area.  Without
  range knowledge it uses a broad prior centered on AREA_PRIOR_PX2 (a
  6-16 px target: the SW-002 regime).  When `context.expected_size_px`
  is known it sharpens to a Gaussian in log(area / expected_area).
  Forward hook, noted not built: fused range from maiden24/25 can feed
  expected_size_px = fx * span / R back into this term.
- contrast_norm: saturating contrast / (contrast + C_HALF); candidate
  contrast is already sigma-normalized by maiden19's propose().
- motion: with a track prediction, exp(-d^2 / (2 * gate_px^2)) on the
  distance to it; otherwise falls back on the candidate's one-frame
  coherence (exp(-coherence / COH_SCALE_PX)), neutral 0.5 when unknown.

Weights and threshold are the maiden20 sweep's knee (sweep_detector.py;
curve in results/VT-15/twin/detector_sweep.png), not guesses.
"""

from dataclasses import dataclass

import numpy as np

AREA_PRIOR_PX2 = 60.0      # broad prior center (area of a ~9 px ellipse blob)
AREA_PRIOR_LOGSIGMA = 1.6  # ~5x each way at 1 sigma: deliberately loose
AREA_KNOWN_LOGSIGMA = 0.6  # with expected size from a track/fused range
C_HALF = 4.0               # contrast giving 0.5 on the saturating map
COH_SCALE_PX = 12.0        # coherence e-fold (twin mover: ~2-6 px/frame)

# Sweep-chosen operating point (see sweep_detector.py; regenerate with
# `python -m maiden.track.sweep_detector`).  Committed, not magic.
W_AREA, W_CONTRAST, W_MOTION = 0.25, 0.45, 0.30
SCORE_THRESHOLD = 0.42


@dataclass
class Context:
    """What the scorer may know this frame. All optional."""

    predicted_uv: tuple | None = None    # track prediction (u, v)
    gate_px: float = 12.0                # motion e-fold vs prediction
    expected_size_px: float | None = None  # from fused range (forward hook)


def _size_plausibility(area, ctx: Context):
    if ctx.expected_size_px is not None:
        expected_area = np.pi * (ctx.expected_size_px / 2.0) ** 2 / 2.0
        logsig = AREA_KNOWN_LOGSIGMA
    else:
        expected_area, logsig = AREA_PRIOR_PX2, AREA_PRIOR_LOGSIGMA
    z = np.log(np.maximum(area, 1.0) / expected_area) / logsig
    return np.exp(-0.5 * z * z)


def _motion(cands, ctx: Context):
    if ctx.predicted_uv is not None:
        pu, pv = ctx.predicted_uv
        d2 = np.array([(c.u - pu) ** 2 + (c.v - pv) ** 2 for c in cands])
        return np.exp(-d2 / (2.0 * ctx.gate_px**2))
    return np.array([0.5 if c.coherence is None
                     else float(np.exp(-c.coherence / COH_SCALE_PX))
                     for c in cands])


def score(candidates, context: Context | None = None) -> np.ndarray:
    """Score each candidate in [0, 1]. Pure function of its inputs."""
    if not candidates:
        return np.zeros(0)
    ctx = context or Context()
    area = np.array([c.area for c in candidates], dtype=float)
    contrast = np.array([c.contrast for c in candidates], dtype=float)
    s = (W_AREA * _size_plausibility(area, ctx)
         + W_CONTRAST * contrast / (contrast + C_HALF)
         + W_MOTION * _motion(candidates, ctx))
    return s
