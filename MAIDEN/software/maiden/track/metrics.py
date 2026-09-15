"""Tracker metrics harness (lessons 10-11, VT-15's rehearsal instrument).

Accepts anything with .u/.v per frame — candidates now, tracks in
maiden21 — against a labels_*.npz sidecar from the twin renderer.
Twin-based numbers are VT-15 rehearsal / CI proxy evidence only, never
the field subset D7 calls for (recorded as such in results/VT-15/twin/).
"""

from dataclasses import dataclass, field

import numpy as np

SIZE_BINS = ((6.0, np.inf), (4.0, 6.0), (0.0, 4.0))
BIN_NAMES = (">=6px", "4-6px", "<4px")


@dataclass
class FrameResult:
    t: float
    labeled: bool
    size_px: float | None
    hit: bool
    n_false: int


@dataclass
class Report:
    frames: list = field(default_factory=list)

    def add(self, t, label, items, match_radius=None):
        """label: (u, v, size_px) or None; items: objects with .u/.v."""
        if label is None:
            self.frames.append(FrameResult(t, False, None, False, len(items)))
            return
        u, v, size = label
        r = match_radius if match_radius is not None else max(4.0, size)
        d = np.array([np.hypot(it.u - u, it.v - v) for it in items]) \
            if items else np.array([])
        hit = bool(d.size and d.min() <= r)
        n_false = int(d.size - (d <= r).sum())
        self.frames.append(FrameResult(t, True, size, hit, n_false))

    def recall_by_bin(self):
        out = {}
        for name, (lo, hi) in zip(BIN_NAMES, SIZE_BINS):
            fs = [f for f in self.frames if f.labeled and lo <= f.size_px < hi]
            out[name] = (sum(f.hit for f in fs) / len(fs)) if fs else None
        return out

    def false_per_frame(self):
        return float(np.mean([f.n_false for f in self.frames])) \
            if self.frames else 0.0

    def recall_trace(self, win_s: float = 1.0):
        """(t_centers, recall) over labeled frames, boxcar-windowed —
        the trace that makes the sun-crossing dip visible."""
        fs = [f for f in self.frames if f.labeled]
        if not fs:
            return np.array([]), np.array([])
        t = np.array([f.t for f in fs])
        hit = np.array([f.hit for f in fs], dtype=float)
        centers = np.arange(t[0], t[-1], win_s / 2)
        rec = np.array([
            hit[(t >= c - win_s / 2) & (t < c + win_s / 2)].mean()
            if ((t >= c - win_s / 2) & (t < c + win_s / 2)).any() else np.nan
            for c in centers])
        return centers, rec
