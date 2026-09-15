"""Maneuver segmentation and recognition (SW-003; D6 "Maneuver
segmentation and recognition").

Stage (a): `segment_rules` — an inspectable per-window decision tree over
windowed track features, assembled into segments with hysteresis, then a
segment-level geometric template pass that separates loop / Immelmann /
stall turn (per-window those three are all "vertical-plane, high
curvature" and genuinely ambiguous; net altitude change, heading
reversal, and minimum speed disambiguate them at segment level).

Stage (b): `segment_gru` — the learned classifier behind the same Event
contract. NAME PINNED by maiden52's card; the current implementation is
a temporal-context MLP in NumPy (weights in software/maiden/data/), a
deliberate stand-in for the D6 GRU: no torch on the build machine, and
the field fine-tune pass after the campaign will revisit the
architecture. See results/VT-16/rehearsal/MODEL_CARD.md.

THE ROLL PROBLEM, stated honestly (lesson 23): a pure axial roll barely
disturbs the flight path. The twin's roll primitive holds a perfectly
straight, altitude-held line — from position and velocity alone a twin
roll is *mathematically identical* to a level leg. Consequences:

- On tracks that carry attitude (TRUTH; FUSED only "if estimable", D6),
  the roll-rate feature is direct and rolls are easy.
- On attitude-free tracks the only signal is the lateral-acceleration
  wobble a real rolling airframe sheds as its lift vector rotates. The
  twin does not model that wobble (fold-back note: a wobble knob in
  twin.Imperfections would let the twin rehearse this properly); the
  training pipeline injects a parameterized wobble during roll windows
  as a clearly-labeled augmentation, and the sweep in
  results/VT-16/rehearsal/ records roll recall vs wobble amplitude.
  The physical wobble level is a campaign question, not a twin answer.

Events emitted use data={"class": c, "maneuver": c, "conf": q} — "class"
per maiden51's card, "maneuver" mirroring the twin's ground-truth key so
comparison code reads either.
"""

from dataclasses import dataclass

import numpy as np
from scipy.signal import savgol_filter

from maiden.state import Event, StateSample

CLASSES = ("level_leg", "loop", "roll", "stall_turn", "immelmann", "other")

# feature/windowing constants (50 Hz fusion epochs assumed by default)
SG_SEC = 0.5          # Savitzky-Golay smoothing span
WIN_SEC = 0.5         # plane-fit / wobble window half-width
STRIDE_SEC = 0.1      # feature-frame stride (10 Hz windows)

# rule thresholds, tuned on twin seeds 0-3, recorded in maiden51's card
K_VERT = 0.008        # 1/m: curvature above this = turning hard (r<125 m)
K_STRAIGHT = 0.004
VPLANE_VERT = 55.0    # deg: plane normal within 35 deg of horizontal
ALT_SLOPE_LEVEL = 2.0  # m/s
V_SLOW = 8.0          # m/s: stall-turn territory
ROLLRATE_ON = 45.0    # deg/s: attitude path
MIN_ROLL_WIN = 20     # windows (2 s): minimum credible roll duration
WOBBLE_ON = 0.35      # m/s^2: lateral-wobble RMS threshold (proxy path)


@dataclass
class FeatureFrame:
    t: np.ndarray            # (W,) window-center times
    kappa: np.ndarray        # curvature 1/m (SG-smoothed accel)
    psi_dot: np.ndarray      # deg/s unwrapped smoothed heading rate
    vplane_deg: np.ndarray   # plane-normal vs U angle: 0 horiz, 90 vert
    planarity: np.ndarray    # 0..1 confidence of the plane fit
    alt: np.ndarray          # m
    alt_slope: np.ndarray    # m/s
    speed: np.ndarray        # m/s
    speed_slope: np.ndarray  # m/s^2
    wobble: np.ndarray       # lateral-accel RMS about window mean, m/s^2
    roll_rate: np.ndarray | None  # deg/s, only when track carries att_rpy


def _track_arrays(samples: list[StateSample]):
    t = np.array([s.t_utc for s in samples])
    pos = np.array([s.pos_enu for s in samples], dtype=float)
    vel = np.array([s.vel_enu for s in samples], dtype=float)
    att = None
    if samples and samples[0].att_rpy is not None:
        att = np.array([s.att_rpy for s in samples], dtype=float)
    return t, pos, vel, att


def features(samples: list[StateSample], rate_hz: float) -> FeatureFrame:
    """Windowed features from a FUSED or TRUTH track (pos/vel; att used
    iff present). Never raw-differences anything (lesson 13's lesson)."""
    t, pos, vel, att = _track_arrays(samples)
    dt = 1.0 / rate_hz
    sg = max(5, int(SG_SEC * rate_hz) | 1)
    acc = savgol_filter(vel, sg, 3, deriv=1, delta=dt, axis=0)
    speed = np.linalg.norm(vel, axis=1)
    speed_sm = savgol_filter(speed, sg, 3)
    speed_slope = savgol_filter(speed, sg, 3, deriv=1, delta=dt)
    heading = np.degrees(np.unwrap(np.arctan2(vel[:, 0], vel[:, 1])))
    psi_dot = savgol_filter(heading, sg, 3, deriv=1, delta=dt)
    alt = pos[:, 2]
    alt_slope = savgol_filter(alt, sg, 3, deriv=1, delta=dt)

    cross = np.cross(vel, acc)
    kappa = np.linalg.norm(cross, axis=1) / np.maximum(speed, 1.0) ** 3

    # lateral acceleration: a projected on the horizontal unit vector
    # perpendicular to v (the roll-wobble proxy; weak, and zero for the
    # unaugmented twin -- see module docstring)
    vh = vel.copy()
    vh[:, 2] = 0.0
    vh_n = np.linalg.norm(vh, axis=1, keepdims=True)
    vh = vh / np.maximum(vh_n, 1e-6)
    lat_hat = np.stack([-vh[:, 1], vh[:, 0], np.zeros(len(vh))], axis=1)
    a_lat = np.einsum("ij,ij->i", acc, lat_hat)

    roll_rate_full = None
    if att is not None:
        roll_unwrapped = np.degrees(np.unwrap(np.radians(att[:, 0])))
        roll_rate_full = np.abs(
            savgol_filter(roll_unwrapped, sg, 3, deriv=1, delta=dt))

    half = int(WIN_SEC * rate_hz)
    stride = max(1, int(STRIDE_SEC * rate_hz))
    idx = np.arange(half, len(t) - half, stride)

    vplane = np.zeros(len(idx))
    planarity = np.zeros(len(idx))
    wobble = np.zeros(len(idx))
    for k, i in enumerate(idx):
        w = pos[i - half:i + half + 1]
        c = w - w.mean(axis=0)
        _, sv, vt = np.linalg.svd(c, full_matrices=False)
        normal = vt[2]
        vplane[k] = np.degrees(np.arccos(min(1.0, abs(normal[2]))))
        planarity[k] = 1.0 - (sv[2] / max(sv[1], 1e-9))
        aw = a_lat[i - half:i + half + 1]
        wobble[k] = float(np.std(aw - aw.mean()))

    rr = roll_rate_full[idx] if roll_rate_full is not None else None
    return FeatureFrame(
        t=t[idx], kappa=kappa[idx], psi_dot=psi_dot[idx],
        vplane_deg=vplane, planarity=planarity, alt=alt[idx],
        alt_slope=alt_slope[idx], speed=speed_sm[idx],
        speed_slope=speed_slope[idx], wobble=wobble, roll_rate=rr)


# ------------------------------------------------------------- stage (a)

# coarse per-window labels the decision tree emits before segment
# refinement; VERT covers loop/immelmann/stall-turn arcs alike
_VERT, _SLOW, _ROLL, _LEVEL, _OTHER = range(5)


def _window_tree(ff: FeatureFrame) -> np.ndarray:
    n = len(ff.t)
    lab = np.full(n, _OTHER)
    for i in range(n):
        vertish = (ff.kappa[i] > K_VERT and ff.vplane_deg[i] > VPLANE_VERT
                   and ff.planarity[i] > 0.5)
        rolling = (ff.roll_rate[i] > ROLLRATE_ON if ff.roll_rate is not None
                   else ff.wobble[i] > WOBBLE_ON)
        # steep lines are aerobatic too: a stall turn's up/down lines are
        # straight (kappa ~ 0) but climb at > ~37 deg
        steep = abs(ff.alt_slope[i]) > 0.6 * max(ff.speed[i], 1.0)
        if vertish or steep or ff.speed[i] < V_SLOW:
            lab[i] = _SLOW if ff.speed[i] < V_SLOW else _VERT
        elif (ff.kappa[i] < K_STRAIGHT
              and abs(ff.alt_slope[i]) < ALT_SLOPE_LEVEL and rolling):
            lab[i] = _ROLL
        elif (ff.kappa[i] < K_STRAIGHT
              and abs(ff.alt_slope[i]) < ALT_SLOPE_LEVEL):
            lab[i] = _LEVEL
    return lab


def _runs_with_hysteresis(lab: np.ndarray, h: int):
    """Collapse per-window labels to runs; a class change must persist
    h consecutive windows before a boundary is declared."""
    runs = []
    cur, start, cand, cand_n = lab[0], 0, None, 0
    for i in range(1, len(lab)):
        if lab[i] == cur:
            cand, cand_n = None, 0
            continue
        if lab[i] == cand:
            cand_n += 1
        else:
            cand, cand_n = lab[i], 1
        if cand_n >= h:
            boundary = i - cand_n + 1
            runs.append((cur, start, boundary))
            cur, start, cand, cand_n = cand, boundary, None, 0
    runs.append((cur, start, len(lab)))
    return runs


def _refine_aerobatic(ff: FeatureFrame, i0: int, i1: int) -> tuple[str, float]:
    """Segment-level template: loop vs immelmann vs stall turn."""
    seg = slice(i0, i1)
    v_min = float(ff.speed[seg].min())
    d_alt = float(ff.alt[i1 - 1] - ff.alt[i0])
    # heading reversal via horizontal velocity direction at the ends
    reversed_ = abs(abs(_heading_delta(ff, i0, i1)) - 180.0) < 45.0
    if v_min < V_SLOW * 0.75:
        return "stall_turn", 0.9
    if reversed_ and d_alt > 10.0:
        return "immelmann", 0.85
    if not reversed_ and abs(d_alt) < 12.0:
        return "loop", 0.85
    return "other", 0.4


def _heading_delta(ff: FeatureFrame, i0: int, i1: int) -> float:
    # psi_dot integrated over the segment (deg), wrapped to [-180, 180]
    dt = np.diff(ff.t[i0:i1]).mean() if i1 - i0 > 1 else 0.1
    total = float(np.sum(ff.psi_dot[i0:i1 - 1]) * dt)
    return (total + 180.0) % 360.0 - 180.0


def _emit(events, t0, t1, cls, conf):
    d = {"class": cls, "maneuver": cls, "conf": round(conf, 2)}
    events.append(Event(float(t0), "MANEUVER_START", dict(d)))
    events.append(Event(float(t1), "MANEUVER_END", dict(d)))


def segment_rules(ff: FeatureFrame, h: int = 5) -> list[Event]:
    """Stage (a): decision tree + hysteresis + geometric templates."""
    lab = _window_tree(ff)
    runs = _runs_with_hysteresis(lab, h)

    # merge VERT/SLOW runs, bridging short non-aerobatic gaps: a stall
    # turn is VERT-SLOW-VERT and its lines can flicker LEVEL for a few
    # windows; a gap under ~1.5 s does not end a maneuver
    gap = int(1.5 / STRIDE_SEC / 10 * 10)   # windows (15 at 10 Hz)
    merged: list[list] = []
    for r in runs:
        aero = r[0] in (_VERT, _SLOW)
        if (merged and aero and merged[-1][0] == _VERT
                and r[1] - merged[-1][2] <= gap):
            merged[-1][2] = r[2]
        elif aero and merged and merged[-1][0] == _VERT or aero:
            merged.append([_VERT, r[1], r[2]])
        else:
            merged.append(list(r))
    # second pass: bridge aerobatic runs separated by short gaps
    bridged: list[list] = []
    for r in merged:
        if (bridged and r[0] == _VERT and bridged[-1][0] == _VERT
                and r[1] - bridged[-1][2] <= gap):
            bridged[-1][2] = r[2]
        else:
            bridged.append(r)

    aero_spans = []
    events: list[Event] = []
    for cls_id, i0, i1 in bridged:
        if i1 - i0 < h or cls_id != _VERT:
            continue
        cls, conf = _refine_aerobatic(ff, i0, i1)
        aero_spans.append((ff.t[i0], ff.t[i1 - 1]))
        _emit(events, ff.t[i0], ff.t[i1 - 1], cls, conf)
    for cls_id, i0, i1 in bridged:
        if i1 - i0 < h or cls_id != _ROLL:
            continue
        t0, t1 = ff.t[i0], ff.t[i1 - 1]
        # a "roll" hugging an aerobatic segment is that maneuver's own
        # roll (an Immelmann exits through a half roll) -- suppress it
        near = any(t0 <= b + 1.0 and t1 >= a - 1.0 for a, b in aero_spans)
        if not near:
            _emit(events, t0, t1, "roll", 0.7)
    events.sort(key=lambda e: e.t_utc)
    return events


# ------------------------------------------------------------- stage (b)

_CTX = 8            # context stack: +-8 windows = +-0.8 s at 10 Hz
_FEATS = 9          # per-window feature vector length (no roll_rate:
#                     stage (b) is the attitude-free path by design)


def _matrix(ff: FeatureFrame) -> np.ndarray:
    x = np.stack([ff.kappa * 100.0, ff.psi_dot / 30.0,
                  ff.vplane_deg / 90.0, ff.planarity,
                  (ff.alt - 40.0) / 40.0, ff.alt_slope / 10.0,
                  ff.speed / 25.0, ff.speed_slope / 5.0,
                  ff.wobble / 1.0], axis=1)
    return x


def _stack_context(x: np.ndarray) -> np.ndarray:
    n = len(x)
    pads = [np.clip(np.arange(n) + k, 0, n - 1)
            for k in range(-_CTX, _CTX + 1)]
    return np.concatenate([x[p] for p in pads], axis=1)


class TemporalMLP:
    """(2*_CTX+1)*_FEATS -> 64 -> 32 -> 6 softmax, Adam, NumPy."""

    def __init__(self, rng: np.random.Generator):
        d = (2 * _CTX + 1) * _FEATS
        s = [d, 64, 32, len(CLASSES)]
        self.w = [rng.normal(0, np.sqrt(2.0 / s[i]), (s[i], s[i + 1]))
                  for i in range(3)]
        self.b = [np.zeros(s[i + 1]) for i in range(3)]

    def logits(self, x):
        h = x
        acts = [x]
        for i in range(2):
            h = np.maximum(h @ self.w[i] + self.b[i], 0.0)
            acts.append(h)
        return h @ self.w[2] + self.b[2], acts

    def predict(self, x):
        return self.logits(x)[0].argmax(axis=1)

    def train(self, x, y, class_w, epochs=250, lr=1e-3, seed=0):
        rng = np.random.default_rng(seed)
        m = [np.zeros_like(w) for w in self.w] + [np.zeros_like(b)
                                                  for b in self.b]
        v = [np.zeros_like(a) for a in m]
        t_adam = 0
        for _ in range(epochs):
            idx = rng.permutation(len(x))
            for lo in range(0, len(x), 512):
                bi = idx[lo:lo + 512]
                xb, yb = x[bi], y[bi]
                z, acts = self.logits(xb)
                z -= z.max(axis=1, keepdims=True)
                p = np.exp(z)
                p /= p.sum(axis=1, keepdims=True)
                gz = p
                gz[np.arange(len(yb)), yb] -= 1.0
                gz *= class_w[yb][:, None] / len(yb)
                grads_w, grads_b = [], []
                g = gz
                for i in (2, 1, 0):
                    grads_w.insert(0, acts[i].T @ g)
                    grads_b.insert(0, g.sum(axis=0))
                    if i:
                        g = (g @ self.w[i].T) * (acts[i] > 0)
                t_adam += 1
                params = self.w + self.b
                grads = grads_w + grads_b
                for j, (pm, gr) in enumerate(zip(params, grads)):
                    m[j] = 0.9 * m[j] + 0.1 * gr
                    v[j] = 0.999 * v[j] + 0.001 * gr * gr
                    mh = m[j] / (1 - 0.9 ** t_adam)
                    vh = v[j] / (1 - 0.999 ** t_adam)
                    pm -= lr * mh / (np.sqrt(vh) + 1e-8)

    def save(self, path):
        np.savez(path, **{f"w{i}": w for i, w in enumerate(self.w)},
                 **{f"b{i}": b for i, b in enumerate(self.b)},
                 classes=np.array(CLASSES), ctx=_CTX, feats=_FEATS)

    @classmethod
    def load(cls, path):
        z = np.load(path, allow_pickle=False)
        obj = cls(np.random.default_rng(0))
        obj.w = [z[f"w{i}"] for i in range(3)]
        obj.b = [z[f"b{i}"] for i in range(3)]
        return obj


def segment_gru(ff: FeatureFrame, model_path, h: int = 5) -> list[Event]:
    """Stage (b) inference. Same Event contract as segment_rules — the
    caller can't tell which ran. (Name pinned by maiden52's card; the
    model behind it is currently a temporal-context MLP — module
    docstring and MODEL_CARD.md explain.)"""
    model = TemporalMLP.load(model_path)
    pred = model.predict(_stack_context(_matrix(ff)))
    runs = _runs_with_hysteresis(pred, h)
    events: list[Event] = []
    for cls_id, i0, i1 in runs:
        cls = CLASSES[cls_id]
        if cls in ("level_leg", "other") or i1 - i0 < h:
            continue
        # a Sportsman roll takes seconds; sub-2 s "rolls" are edge noise
        if cls == "roll" and i1 - i0 < MIN_ROLL_WIN:
            continue
        _emit(events, ff.t[i0], ff.t[i1 - 1], cls, 0.8)
    return events


# ----------------------------------------------------- twin data plumbing

def labels_from_events(ff: FeatureFrame, events) -> np.ndarray:
    """Per-window integer labels from twin ground-truth Events."""
    y = np.full(len(ff.t), CLASSES.index("level_leg"))
    starts = [(e.t_utc, e.data.get("maneuver") or e.data.get("class"))
              for e in events if e.kind == "MANEUVER_START"]
    ends = {e.t_utc: (e.data.get("maneuver") or e.data.get("class"))
            for e in events if e.kind == "MANEUVER_END"}
    for t0, name in starts:
        t1 = min((t for t, n in ends.items() if n == name and t > t0),
                 default=None)
        if t1 is None or name not in CLASSES:
            continue
        y[(ff.t >= t0) & (ff.t <= t1)] = CLASSES.index(name)
    return y


def truth_to_samples(truth, rate_hz=50.0, *, noise_pos=0.0, noise_vel=0.0,
                     wobble_m=0.0, drop_att=False, seed=0):
    """Twin Truth -> StateSample track at rate_hz.

    noise_*: additive Gaussian, matched to the fusion-residual scale
    (results/lesson13: pos RMS 0.219 m, vel RMS 0.909 m/s) when used as
    a cheap FUSED stand-in for training.
    wobble_m: lateral sinusoidal displacement amplitude injected during
    roll event windows — the augmentation described in the module
    docstring, NOT twin physics.
    """
    rng = np.random.default_rng(seed)
    step = max(1, round(100.0 / rate_hz))
    sl = slice(None, None, step)
    t = truth.t[sl].copy()
    pos = truth.pos_enu[sl].copy()
    vel = truth.vel_enu[sl].copy()
    att = None if drop_att else truth.att_rpy[sl].copy()

    if wobble_m > 0.0:
        rolls = [(e.t_utc, ee.t_utc)
                 for e in truth.events if e.kind == "MANEUVER_START"
                 and e.data.get("maneuver") == "roll"
                 for ee in truth.events if ee.kind == "MANEUVER_END"
                 and ee.data.get("maneuver") == "roll"
                 and ee.t_utc > e.t_utc]
        for t0, t1 in rolls:
            m = (t >= t0) & (t <= t1)
            if not m.any():
                continue
            dur = t1 - t0
            phase = 2.0 * np.pi * (t[m] - t0) / dur   # one lift rotation
            vh = vel[m].copy()
            vh[:, 2] = 0.0
            vh /= np.maximum(np.linalg.norm(vh, axis=1, keepdims=True),
                             1e-6)
            lat = np.stack([-vh[:, 1], vh[:, 0], np.zeros(m.sum())], axis=1)
            pos[m] += wobble_m * np.sin(phase)[:, None] * lat
            w = 2.0 * np.pi / dur
            vel[m] += wobble_m * w * np.cos(phase)[:, None] * lat

    if noise_pos:
        pos += rng.normal(0, noise_pos, pos.shape)
    if noise_vel:
        vel += rng.normal(0, noise_vel, vel.shape)

    src = "TRUTH" if att is not None else "FUSED"
    return [StateSample(t_utc=float(t[i]), source=src,
                        pos_enu=tuple(pos[i]), vel_enu=tuple(vel[i]),
                        att_rpy=tuple(att[i]) if att is not None else None)
            for i in range(len(t))]


def _gen_track(seed, *, wobble_m, rng_off=0):
    """One imperfect twin seed as a FUSED-like (attitude-free, noisy)
    feature frame + labels. Noise scale = fusion-residual scale
    (results/lesson13 headline: pos 0.219 m, vel 0.909 m/s incl. lag)."""
    from maiden.twin.model import Imperfections, sportsman
    rng = np.random.default_rng(1000 + seed + rng_off)
    imp = Imperfections(
        loop_ovality=float(rng.uniform(0.0, 0.2)),
        roll_drift_deg=float(rng.uniform(-6.0, 6.0)),
        alt_mismatch_m=float(rng.uniform(-5.0, 5.0)),
        center_offset_m=float(rng.uniform(-10.0, 10.0)))
    tr = sportsman(imp, seed=seed)
    samples = truth_to_samples(tr, 50.0, noise_pos=0.25, noise_vel=0.35,
                               wobble_m=wobble_m, drop_att=True, seed=seed)
    ff = features(samples, 50.0)
    return ff, labels_from_events(ff, tr.events), tr


def _long_leg_track(seed):
    """Plain long level legs (no maneuvers) as training negatives."""
    from maiden.twin.model import level_leg
    rng = np.random.default_rng(5000 + seed)
    p = np.array([-150.0, 150.0, float(rng.uniform(30.0, 60.0))])
    length = float(rng.uniform(150.0, 300.0))
    v = float(rng.uniform(18.0, 30.0))
    tr = level_leg(p, float(rng.uniform(0, 360)), length, v, v, p[2])
    samples = truth_to_samples(tr, 50.0, noise_pos=0.25, noise_vel=0.35,
                               drop_att=True, seed=seed)
    ff = features(samples, 50.0)
    return ff, np.full(len(ff.t), CLASSES.index("level_leg"))


def train_main(argv=None) -> int:
    """`python -m maiden.maneuver train` — the maiden52 training run.

    Deterministic (fixed seeds), CPU-only, documented runtime. Writes
    weights to software/maiden/data/maneuver_mlp_v1.npz and the
    confusion matrix / comparison table / sweeps to
    results/VT-16/rehearsal/. (The card's train/train_maneuver.py lives
    here because maneuver.py owns the model classes.)
    """
    import argparse
    import time
    from pathlib import Path

    ap = argparse.ArgumentParser(prog="maiden.maneuver train")
    ap.add_argument("--train-seeds", type=int, default=14)
    ap.add_argument("--heldout-seeds", type=int, default=6)
    ap.add_argument("--wobble-m", type=float, default=1.0)
    ap.add_argument("--epochs", type=int, default=250)
    ap.add_argument("--out", default=None)
    ap.add_argument("--results", default=None)
    args = ap.parse_args(argv)

    t_start = time.time()
    root = Path(__file__).resolve().parents[2]
    out = Path(args.out or Path(__file__).parent / "data"
               / "maneuver_mlp_v1.npz")
    res = Path(args.results or root.parent / "results" / "VT-16"
               / "rehearsal")
    if not res.parent.parent.exists():   # running from repo root layout
        res = Path("results/VT-16/rehearsal")
    res.mkdir(parents=True, exist_ok=True)
    out.parent.mkdir(parents=True, exist_ok=True)

    train_seeds = range(args.train_seeds)
    held_seeds = range(100, 100 + args.heldout_seeds)

    xs, ys = [], []
    for s in train_seeds:
        ff, y, _ = _gen_track(s, wobble_m=args.wobble_m)
        xs.append(_stack_context(_matrix(ff)))
        ys.append(y)
        # duration-shortcut killer: without these, the model learns
        # "long straight segment = roll" (the twin's rolls are its only
        # long straight parts) and calls any 8 s level leg a roll —
        # falsified by the long-leg probe in sweeps.md. Long plain legs
        # as explicit negatives force the wobble channel to carry roll.
        for k in (0, 1):
            ff2, y2 = _long_leg_track(s + 1000 * k)
            xs.append(_stack_context(_matrix(ff2)))
            ys.append(y2)
    x = np.concatenate(xs)
    y = np.concatenate(ys)
    counts = np.bincount(y, minlength=len(CLASSES)).astype(float)
    class_w = np.where(counts > 0, counts.sum() / np.maximum(counts, 1.0),
                       0.0)
    class_w /= class_w[class_w > 0].mean()

    model = TemporalMLP(np.random.default_rng(20260821))
    model.train(x, y, class_w, epochs=args.epochs, seed=20260821)
    model.save(out)

    # held-out evaluation: window confusion + segment-level per-class
    conf = np.zeros((len(CLASSES), len(CLASSES)), dtype=int)
    seg_hits: dict[str, list] = {c: [] for c in CLASSES}
    rule_hits: dict[str, list] = {c: [] for c in CLASSES}
    for s in held_seeds:
        ff, yy, tr = _gen_track(s, wobble_m=args.wobble_m)
        pred = model.predict(_stack_context(_matrix(ff)))
        for a, b in zip(yy, pred):
            conf[a, b] += 1
        for name, p, _, _ in match_segments(
                segment_gru_pred(ff, model), tr.events):
            seg_hits[name].append(p == name)
        for name, p, _, _ in match_segments(segment_rules(ff), tr.events):
            rule_hits[name].append(p == name)

    def acc(d):
        return {c: (100.0 * np.mean(v) if v else None)
                for c, v in d.items() if v}

    mlp_acc, rules_acc = acc(seg_hits), acc(rule_hits)
    runtime = time.time() - t_start

    lines = [
        "# VT-16 rehearsal — twin-only evidence",
        "",
        "Learned-classifier rehearsal on held-out twin seeds. **VT-16",
        "binds on validation flights**; these are twin numbers.",
        (f"Training: {args.train_seeds} seeds, held-out {args.heldout_seeds}"
        f" seeds (split BY SEED), wobble augmentation {args.wobble_m} m,"),
        (f"epochs {args.epochs}, deterministic seed 20260821, runtime"
        f" {runtime:.0f} s CPU."),
        "",
        "## Segment-level per-class accuracy (held-out seeds, %)",
        "",
        "| class | rules (a), no att | MLP (b) |",
        "|---|---|---|",
    ]
    for c in ("loop", "roll", "stall_turn", "immelmann"):
        r = rules_acc.get(c)
        m = mlp_acc.get(c)
        lines.append(f"| {c} | {r if r is not None else '—'} |"
                     f" {m if m is not None else '—'} |")
    lines += ["", "## Window confusion matrix (rows=truth, cols=pred)",
              "", "| | " + " | ".join(CLASSES) + " |",
              "|---" * (len(CLASSES) + 1) + "|"]
    for i, c in enumerate(CLASSES):
        lines.append(f"| {c} | " + " | ".join(str(v) for v in conf[i])
                     + " |")
    (res / "confusion.md").write_text("\n".join(lines) + "\n")
    np.savez(res / "confusion.npz", conf=conf, classes=np.array(CLASSES))
    print("\n".join(lines))
    print(f"\nmodel -> {out}\nresults -> {res}")
    return 0


def segment_gru_pred(ff: FeatureFrame, model: "TemporalMLP",
                     h: int = 5) -> list[Event]:
    """segment_gru with an already-loaded model (training/eval path)."""
    pred = model.predict(_stack_context(_matrix(ff)))
    runs = _runs_with_hysteresis(pred, h)
    events: list[Event] = []
    for cls_id, i0, i1 in runs:
        cls = CLASSES[cls_id]
        if cls in ("level_leg", "other") or i1 - i0 < h:
            continue
        # a Sportsman roll takes seconds; sub-2 s "rolls" are edge noise
        if cls == "roll" and i1 - i0 < MIN_ROLL_WIN:
            continue
        _emit(events, ff.t[i0], ff.t[i1 - 1], cls, 0.8)
    return events


def match_segments(pred_events, truth_events, tol_s=2.0):
    """Segment-level scoring: match predicted maneuvers to ground truth
    by midpoint proximity; returns (per-class hits, misses, confusions)."""
    def spans(evts, key):
        out = []
        for e in evts:
            if e.kind != "MANEUVER_START":
                continue
            name = e.data.get(key) or e.data.get("maneuver")
            end = min((x.t_utc for x in evts if x.kind == "MANEUVER_END"
                       and (x.data.get(key) or x.data.get("maneuver"))
                       == name and x.t_utc > e.t_utc), default=None)
            if end is not None:
                out.append((name, e.t_utc, end))
        return out

    truth = spans(truth_events, "maneuver")
    pred = spans(pred_events, "class")
    results = []
    for name, t0, t1 in truth:
        mid = 0.5 * (t0 + t1)
        best = None
        for pname, p0, p1 in pred:
            if p0 - tol_s <= mid <= p1 + tol_s:
                best = pname
                break
        results.append((name, best, t0, t1))
    return results



def sweep_main(argv=None) -> int:
    """`python -m maiden.maneuver sweep` — maiden52's roll-recall sweep
    plus maiden51's ellipticity probe; writes results/VT-16/rehearsal/.
    """
    from pathlib import Path

    from maiden.twin.model import Imperfections, sportsman

    res = Path("results/VT-16/rehearsal")
    res.mkdir(parents=True, exist_ok=True)
    model = TemporalMLP.load(Path(__file__).parent / "data"
                             / "maneuver_mlp_v1.npz")

    lines = ["# Roll recall vs wobble amplitude (twin augmentation)",
             "",
             "The twin sheds zero roll wobble (see maneuver.py docstring);",
             "amplitude below is injected augmentation. The physical level",
             "for the club airframes is a campaign question — record the",
             "measured value here after the first instrumented flights.",
             "", "| wobble (m) | rules roll recall | MLP roll recall |",
             "|---|---|---|"]
    for amp in (0.0, 0.25, 0.5, 1.0, 2.0):
        r_hits, m_hits = [], []
        for s in range(200, 206):
            ff, _, tr = _gen_track(s, wobble_m=amp)
            for name, p, _, _ in match_segments(segment_rules(ff),
                                                tr.events):
                if name == "roll":
                    r_hits.append(p == "roll")
            for name, p, _, _ in match_segments(
                    segment_gru_pred(ff, model), tr.events):
                if name == "roll":
                    m_hits.append(p == "roll")
        lines.append(f"| {amp} | {100.0 * np.mean(r_hits):.0f}% |"
                     f" {100.0 * np.mean(m_hits):.0f}% |")

    lines += ["", "# Ellipticity probe (maiden51 Explore)", ""]
    for ov in (0.20, 0.05):
        tr = sportsman(Imperfections(loop_ovality=ov), seed=0)
        ff = features(truth_to_samples(tr, 50.0), 50.0)
        lo = (ff.t >= 5.2) & (ff.t <= 14.8)
        kv = float(np.std(ff.kappa[lo]) / np.mean(ff.kappa[lo]))
        found = any(n == p == "loop" for n, p, _, _ in
                    match_segments(segment_rules(ff), tr.events))
        lines.append(f"- ovality {ov}: loop-window kappa CV = {kv:.3f}; "
                     f"stage (a) still classifies loop: {found}. "
                     "(kappa variance moves first; vplane is unmoved — "
                     "an elliptical loop is still planar.)")
    (res / "sweeps.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    import sys as _sys
    if _sys.argv[1:2] == ["train"]:
        raise SystemExit(train_main(_sys.argv[2:]))
    if _sys.argv[1:2] == ["sweep"]:
        raise SystemExit(sweep_main(_sys.argv[2:]))
    print("usage: python -m maiden.maneuver train|sweep [...]",
          file=_sys.stderr)
    raise SystemExit(2)
