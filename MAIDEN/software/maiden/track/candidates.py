"""Candidate generation (lesson 10): sky model -> residual -> components.

The chain, per D6's two-stage tracker and lesson 10 §Concepts:

    frames -> temporal median (N strided) -> |frame - median|
           -> threshold (k * per-pixel sigma) -> open 3x3 / close 5x5
           -> connected components -> Candidate(u, v, area, ...)

Median depth: N=25 at stride 3 spans ~2.5 s of 30 fps video — long
enough that the aircraft (tens of px/frame) never pollutes its own
background, short enough to follow slow sky changes. Lesson 10 Explore 2
sweeps this; the value here is the defended default.

Everything is O(pixels); the sky model is plain NumPy so its state is
inspectable (SkyModel.median, SkyModel.sigma are arrays you can look at).
"""

from dataclasses import dataclass

import cv2
import numpy as np

SIGMA_FLOOR = 1.0   # counts; sky gradient is smooth, sensor noise isn't zero


@dataclass
class Candidate:
    u: float
    v: float
    area: int
    bbox: tuple      # (x, y, w, h)
    contrast: float  # mean |residual| in component / local sigma
    coherence: float | None = None   # px displacement vs nearest prev; None first


class SkyModel:
    """Rolling temporal median + per-pixel sigma over N strided frames."""

    def __init__(self, n: int = 25, stride: int = 3):
        self.n = n
        self.stride = stride
        self._buf = []
        self._count = 0
        self.median = None
        self.sigma = None

    @property
    def ready(self) -> bool:
        return self.median is not None

    def update(self, image: np.ndarray):
        self._count += 1
        if (self._count - 1) % self.stride:
            return
        self._buf.append(image.astype(np.float32))
        if len(self._buf) > self.n:
            self._buf.pop(0)
        if len(self._buf) >= max(3, self.n // 3):
            stack = np.stack(self._buf)
            self.median = np.median(stack, axis=0)
            self.sigma = np.maximum(stack.std(axis=0), SIGMA_FLOOR)

    def residual(self, image: np.ndarray) -> np.ndarray:
        return np.abs(image.astype(np.float32) - self.median)


def propose(residual: np.ndarray, sigma: np.ndarray, *,
            k: float = 4.0, min_area: int = 3) -> list[Candidate]:
    """Threshold -> morphology (open 3x3, close 5x5) -> components."""
    mask = (residual > k * sigma).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, labels, stats, centroids = cv2.connectedComponentsWithStats(mask)
    out = []
    for i in range(1, n):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        x, y, w, h = (int(stats[i, s]) for s in
                      (cv2.CC_STAT_LEFT, cv2.CC_STAT_TOP,
                       cv2.CC_STAT_WIDTH, cv2.CC_STAT_HEIGHT))
        comp = labels[y:y + h, x:x + w] == i
        res = residual[y:y + h, x:x + w][comp]
        sig = sigma[y:y + h, x:x + w][comp]
        out.append(Candidate(
            u=float(centroids[i, 0]), v=float(centroids[i, 1]),
            area=area, bbox=(x, y, w, h),
            contrast=float(res.mean() / max(sig.mean(), 1e-6))))
    return out


def link_coherence(prev: list[Candidate], cur: list[Candidate]):
    """Fill cur[i].coherence with the centroid displacement to the nearest
    previous-frame candidate (px). Simple one-frame memory; maiden20's
    Kalman gating replaces this."""
    if not prev:
        return cur
    pu = np.array([[c.u, c.v] for c in prev])
    for c in cur:
        d = np.hypot(pu[:, 0] - c.u, pu[:, 1] - c.v)
        c.coherence = float(d.min())
    return cur
