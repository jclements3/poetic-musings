"""Per-station track management (lesson 11, maiden21).

State machine (lesson 11 §Track management):

    TENTATIVE --(M of N confirms, default 3 of 5)--> CONFIRMED
    CONFIRMED --(miss)--> COASTING --(hit)--> CONFIRMED
    COASTING  --(K consecutive misses, default 15)--> DEAD

Association is gated nearest-neighbor on the Kalman Mahalanobis distance
(gate 9.21 = chi^2 2-dof 99%): adequate because D1 pins one aircraft in
the box; the two-target swap failure is a known Phase 2 item.

`conf` — THE MECHANICAL DEFINITION (fusion de-weights by this; D9's
"wide band != bad pilot" story traces here):

    conf = score_ema * age_ramp * coast_decay
      score_ema   — EMA (alpha 0.3) of the detector scores of the hits
                    this track has consumed, in [0, 1]
      age_ramp    — min(1, hits / M): a track that just confirmed has
                    conf below a long-lived one
      coast_decay — COAST_DECAY ** frames_since_hit (0.85): strictly
                    monotone decreasing while coasting, restored only by
                    a hit (which resets frames_since_hit)

Bounded in [0, 1] by construction; only CONFIRMED and (flagged) COASTING
tracks are emitted, per lesson 11.
"""

from dataclasses import dataclass, field
from enum import Enum

import numpy as np

from maiden.track.detector import SCORE_THRESHOLD, Context, score
from maiden.track.kalman2d import Kalman2D


class TrackState(Enum):
    TENTATIVE = "TENTATIVE"
    CONFIRMED = "CONFIRMED"
    COASTING = "COASTING"
    DEAD = "DEAD"


@dataclass
class TrackerCfg:
    dt: float = 1.0 / 30.0
    # q from the twin's worst pixel acceleration, not guessed: 131 px/s^2
    # at fx ~= 831 (960x540 eval camera), tau ~= 0.5 s => a^2*tau ~= 9e3.
    # Scales with fx^2 for other cameras (sweep_detector.py recomputes).
    q: float = 9000.0
    sigma_px: float = 1.0
    gate: float = 9.21             # chi^2 2-dof 99%
    m_confirm: int = 3             # M of N
    n_window: int = 5
    k_dead: int = 15               # consecutive misses -> DEAD
    score_threshold: float = SCORE_THRESHOLD
    score_ema_alpha: float = 0.3
    coast_decay: float = 0.85
    emit_coasting: bool = True     # see emit.py docstring for the decision


@dataclass
class TrackOut:
    """What emitters consume: pixel state + confidence + provenance."""

    track_id: int
    u: float
    v: float
    conf: float
    state: TrackState
    bbox: tuple = (0, 0, 0, 0)


@dataclass
class _Track:
    kf: Kalman2D
    cfg: TrackerCfg
    track_id: int
    state: TrackState = TrackState.TENTATIVE
    hits: int = 1
    frames_since_hit: int = 0
    score_ema: float = 0.0
    window: list = field(default_factory=list)   # last N hit/miss booleans
    last_bbox: tuple = (0, 0, 0, 0)

    def note(self, hit: bool, det_score: float = 0.0, bbox=None):
        self.window.append(hit)
        if len(self.window) > self.cfg.n_window:
            self.window.pop(0)
        if hit:
            self.hits += 1
            self.frames_since_hit = 0
            a = self.cfg.score_ema_alpha
            self.score_ema = (1 - a) * self.score_ema + a * det_score
            if bbox is not None:
                self.last_bbox = bbox
        else:
            self.frames_since_hit += 1

    def step_state(self):
        if self.state is TrackState.TENTATIVE:
            if sum(self.window) >= self.cfg.m_confirm:
                self.state = TrackState.CONFIRMED
            elif (len(self.window) == self.cfg.n_window
                  and not any(self.window)):
                self.state = TrackState.DEAD
        elif self.state is TrackState.CONFIRMED and self.frames_since_hit:
            self.state = TrackState.COASTING
        elif self.state is TrackState.COASTING:
            if self.frames_since_hit == 0:
                self.state = TrackState.CONFIRMED
            elif self.frames_since_hit >= self.cfg.k_dead:
                self.state = TrackState.DEAD

    @property
    def conf(self) -> float:
        age_ramp = min(1.0, self.hits / self.cfg.m_confirm)
        decay = self.cfg.coast_decay ** self.frames_since_hit
        return float(np.clip(self.score_ema * age_ramp * decay, 0.0, 1.0))


class StationTracker:
    """One per station. consume(candidates) -> list[TrackOut] per frame.

    Camera geometry deliberately does NOT live here — emit.py owns
    px->az/el so the tracker is testable on bare pixel scripts.
    """

    def __init__(self, cfg: TrackerCfg | None = None):
        self.cfg = cfg or TrackerCfg()
        self.tracks: list[_Track] = []
        self._next_id = 1

    def _spawn(self, cand, det_score):
        kf = Kalman2D(self.cfg.dt, self.cfg.q, self.cfg.sigma_px)
        kf.start((cand.u, cand.v))
        t = _Track(kf=kf, cfg=self.cfg, track_id=self._next_id,
                   last_bbox=cand.bbox)
        t.score_ema = det_score
        t.window.append(True)
        self.tracks.append(t)
        self._next_id += 1

    def consume(self, candidates) -> list[TrackOut]:
        cfg = self.cfg
        for tr in self.tracks:
            tr.kf.predict()
        # score against the best (single) prediction context — D1's
        # one-aircraft world; multi-aircraft is Phase 2
        ctx = Context(predicted_uv=self.tracks[0].kf.uv) if self.tracks \
            else Context()
        s = score(candidates, ctx)
        used = set()
        for tr in self.tracks:
            best, best_m = None, cfg.gate
            for i, c in enumerate(candidates):
                if i in used or s[i] < cfg.score_threshold:
                    continue
                m = tr.kf.mahalanobis((c.u, c.v))
                if m < best_m:
                    best, best_m = i, m
            if best is None:
                tr.note(False)
            else:
                used.add(best)
                c = candidates[best]
                tr.kf.update((c.u, c.v))
                tr.note(True, float(s[best]), c.bbox)
            tr.step_state()
        self.tracks = [t for t in self.tracks if t.state is not TrackState.DEAD]
        # unassociated, above-threshold candidates spawn TENTATIVE tracks
        for i, c in enumerate(candidates):
            if i not in used and s[i] >= cfg.score_threshold:
                self._spawn(c, float(s[i]))
        out = []
        for tr in self.tracks:
            if tr.state is TrackState.CONFIRMED or (
                    tr.state is TrackState.COASTING and cfg.emit_coasting):
                u, v = tr.kf.uv
                out.append(TrackOut(tr.track_id, u, v, tr.conf,
                                    tr.state, tr.last_bbox))
        return out
