"""Rubric scoring and judge calibration (SYS-007, SYS-008; D6 "Scoring").

Rubric layer: deterministic, inspectable geometry checks per recognized
maneuver -- 0-10 with itemized plain-language deductions. Structure per
D6 and the AMA rulebook on disk (docs/refs/AMA_RC_Aerobatics_2024-2025):
box/centering/track rules are §15, the per-maneuver downgrade authority
is §19 (FAI F3A Manoeuvre Execution Guide -- wording REQUIRED-FETCH, see
config/rubric.yaml's provenance header). Downgrade *magnitudes* live in
config/rubric.yaml, versioned, because judges' point-charging is exactly
what SYS-008's calibration layer exists to learn (D5 risk R6).

Calibration layer: per-maneuver-class isotonic (monotone) regression
from rubric raw scores to judge scores, numpy PAV (sklearn is not a
project dependency -- deliberate substitution from the lesson's
IsotonicRegression mention; same model class, zero new deps). UNTRAINED
BY DESIGN until maiden64 delivers campaign judge sheets; until then
``ManeuverScore.calibrated`` is None and the report labels raw rubric
scores as uncalibrated (maiden55 consumes this flag).

JUDGE-SHEET CSV CONTRACT (the campaign, maiden64, must produce exactly
this -- also documented in config/judge_sheets/README.md):

    flight_id,judge_id,maneuver_index,maneuver_class,judge_score
    F03,J1,2,loop,7.5

- one row per maneuver per judge per flight;
- ``maneuver_index`` is the 0-based index into that flight's
  ``score_sequence`` output (schedule order), so rubric rows and judge
  rows join on (flight_id, maneuver_index);
- ``maneuver_class`` must match ``CLASSES`` in maiden.maneuver;
- ``judge_score`` in 0-10, half-points allowed (AMA §18.7: two judges,
  scored individually, no consultation -- keep each judge's rows).
"""

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import yaml

from maiden.state import Event, StateSample

_RUBRIC_PATH = Path(__file__).resolve().parents[2] / "config" / "rubric.yaml"

SCORED_CLASSES = ("loop", "roll", "stall_turn", "immelmann")


def load_rubric(path=_RUBRIC_PATH) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


@dataclass(frozen=True)
class Deduction:
    text: str      # plain language: "loop 11.4 m taller than wide"
    points: float  # points charged (already scaled per rubric.yaml)
    tag: str       # machine tag: "roundness", "centering", ...


@dataclass
class ManeuverScore:
    cls: str
    raw: float                     # 10 - sum(deductions), floored at 0
    calibrated: float | None       # None until maiden64 trains Calibration
    deductions: list[Deduction] = field(default_factory=list)

    def line(self) -> str:
        """One VT-20-shaped report line."""
        cal = "" if self.calibrated is None else f" (cal {self.calibrated:.1f})"
        ded = "; ".join(d.text for d in self.deductions) or "no deductions"
        return f"{self.cls:11s} {self.raw:4.1f}{cal}  {ded}"


# ------------------------------------------------------------ geometry


def _fit_circle(s: np.ndarray, z: np.ndarray, iters: int = 10):
    """Circle fit: Kasa algebraic seed, then Gauss-Newton refinement.

    Returns (cs, cz, r, radii). Refinement matters for the oval case --
    the algebraic fit biases the center toward dense arcs.
    """
    A = np.c_[2.0 * s, 2.0 * z, np.ones(len(s))]
    b = s * s + z * z
    (cs, cz, k), *_ = np.linalg.lstsq(A, b, rcond=None)
    r = float(np.sqrt(k + cs * cs + cz * cz))
    for _ in range(iters):
        ds, dz = s - cs, z - cz
        ri = np.hypot(ds, dz)
        r = float(ri.mean())
        # Gauss-Newton step on (cs, cz): residual f_i = ri - r
        J = np.c_[-ds / ri, -dz / ri]
        step, *_ = np.linalg.lstsq(J, -(ri - r), rcond=None)
        cs += float(step[0])
        cz += float(step[1])
    ri = np.hypot(s - cs, z - cz)
    return float(cs), float(cz), float(ri.mean()), ri


def _heading_deg(v: np.ndarray) -> float:
    """Ground-track heading of a velocity sample (az CW from north)."""
    return float(np.degrees(np.arctan2(v[0], v[1])))


def _axis_dev(h_deg: float, axis_deg: float) -> float:
    """Smallest angle between a heading and the box axis (either sense)."""
    d = (h_deg - axis_deg) % 180.0
    return min(d, 180.0 - d)


def _charge(mag: float, tol: float, pts_per: float, per: float) -> float:
    """Points for a magnitude beyond tolerance at pts_per per `per` units."""
    return max(0.0, mag - tol) * pts_per / per


# ------------------------------------------------- per-class checks


def _score_loop(t, pos, vel, R: dict, box: dict) -> list[Deduction]:
    """Loop: round, centered, on-axis, exit at entry altitude.

    AMA §15 (centering/track: "Center maneuvers should be performed
    centered in the maneuvering area in a plane exactly perpendicular to
    the judges' line of sight"); roundness per §19 -> F3A Execution
    Guide (round, constant radius); structure per D6 §Scoring.
    """
    ded: list[Deduction] = []
    s, z = pos[:, 0], pos[:, 2]
    cs, _cz, r, ri = _fit_circle(s, z)

    sig = float(ri.std())
    pts = _charge(sig, R["roundness_tol_m"], R["roundness_pts_per_m"], 1.0)
    if pts > 0:
        ded.append(Deduction(
            f"loop radius varies {sig:.1f} m about the {r:.0f} m fit",
            round(pts, 2), "roundness"))

    height = float(z.max() - z.min())
    width = float(s.max() - s.min())
    asym = height - width
    pts = _charge(abs(asym), R["shape_tol_m"], R["shape_pts_per_4m"], 4.0)
    if pts > 0:
        shape = "taller than wide" if asym > 0 else "wider than tall"
        ded.append(Deduction(
            f"loop {abs(asym):.1f} m {shape}", round(pts, 2), "roundness"))

    if "loop" in box["center_classes"]:
        off = abs(cs - box["centerline_e_m"])
        pts = _charge(off, R["centering_tol_m"], R["centering_pts_per_15m"], 15.0)
        if pts > 0:
            ded.append(Deduction(
                f"loop centered {off:.0f} m from the centerline",
                round(pts, 2), "centering"))

    # track: cross-box drift of the maneuver plane (N should hold still
    # for a plane perpendicular to the judges' line of sight, §15)
    drift = float(pos[:, 1].std())
    dev = float(np.degrees(np.arctan2(2.0 * drift, width)))
    pts = _charge(dev, R["track_tol_deg"], R["track_pts_per_5deg"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"loop plane wanders {drift:.1f} m across the box",
            round(pts, 2), "track"))

    dalt = float(pos[-1, 2] - pos[0, 2])
    pts = _charge(abs(dalt), R["alt_tol_m"], R["alt_pts_per_5m"], 5.0)
    if pts > 0:
        hilo = "above" if dalt > 0 else "below"
        ded.append(Deduction(
            f"loop exits {abs(dalt):.1f} m {hilo} entry altitude",
            round(pts, 2), "alt_match"))
    return ded


def _score_roll(t, pos, vel, R: dict, box: dict) -> list[Deduction]:
    """Roll: straight line, altitude held, heading held (§15 track;
    §19 -> F3A Execution Guide wording REQUIRED-FETCH)."""
    ded: list[Deduction] = []
    sig = float(pos[:, 2].std())
    pts = _charge(sig, R["alt_hold_tol_m"], R["alt_hold_pts_per_2m"], 2.0)
    if pts > 0:
        ded.append(Deduction(
            f"roll altitude wanders {sig:.1f} m", round(pts, 2), "alt_hold"))

    h0, h1 = _heading_deg(vel[0]), _heading_deg(vel[-1])
    drift = abs((h1 - h0 + 180.0) % 360.0 - 180.0)
    pts = _charge(drift, R["drift_tol_deg"], R["drift_pts_per_5deg"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"roll exits {drift:.1f} deg off entry heading",
            round(pts, 2), "heading"))

    dev = _axis_dev(h0, box["axis_deg"])
    pts = _charge(dev, R["track_tol_deg"], R["track_pts_per_5deg"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"roll line {dev:.1f} deg off the box axis",
            round(pts, 2), "track"))
    return ded


def _score_stall_turn(t, pos, vel, R: dict, box: dict) -> list[Deduction]:
    """Stall turn: exit at entry altitude on the box axis (§15; upline
    verticality wording per §19 REQUIRED-FETCH -- the twin's composed
    stall turn is judged here on its entry/exit lines, which §15 says
    "are part of the maneuver and are always judged")."""
    ded: list[Deduction] = []
    dalt = float(pos[-1, 2] - pos[0, 2])
    pts = _charge(abs(dalt), R["alt_tol_m"], R["alt_pts_per_5m"], 5.0)
    if pts > 0:
        hilo = "above" if dalt > 0 else "below"
        ded.append(Deduction(
            f"stall turn exits {abs(dalt):.1f} m {hilo} entry altitude",
            round(pts, 2), "alt_match"))

    dev = _axis_dev(_heading_deg(vel[-1]), box["axis_deg"])
    pts = _charge(dev, R["track_tol_deg"], R["track_pts_per_5deg"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"stall turn exit line {dev:.1f} deg off the box axis",
            round(pts, 2), "track"))
    return ded


def _score_immelmann(t, pos, vel, R: dict, box: dict) -> list[Deduction]:
    """Immelmann: round half-loop, gains 2R, exits reversed (§19
    downgrade wording REQUIRED-FETCH; geometry per D6)."""
    ded: list[Deduction] = []
    s, z = pos[:, 0], pos[:, 2]
    # half-loop portion: samples below the top, before the roll-off --
    # use the climbing arc (z rising monotonically covers the half loop)
    top = int(np.argmax(z))
    _cs, _cz, r, ri = _fit_circle(s[: top + 1], z[: top + 1])
    sig = float(ri.std())
    pts = _charge(sig, R["roundness_tol_m"], R["roundness_pts_per_m"], 1.0)
    if pts > 0:
        ded.append(Deduction(
            f"immelmann half-loop radius varies {sig:.1f} m",
            round(pts, 2), "roundness"))

    gain = float(pos[-1, 2] - pos[0, 2])
    err = abs(gain - 2.0 * r)
    pts = _charge(err, R["gain_tol_m"], R["gain_pts_per_5m"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"immelmann gains {gain:.0f} m vs {2 * r:.0f} m for its radius",
            round(pts, 2), "alt_match"))

    h0, h1 = _heading_deg(vel[0]), _heading_deg(vel[-1])
    rev = abs((h1 - h0 - 180.0 + 180.0) % 360.0 - 180.0)
    pts = _charge(rev, R["reversal_tol_deg"], R["reversal_pts_per_5deg"], 5.0)
    if pts > 0:
        ded.append(Deduction(
            f"immelmann exits {rev:.1f} deg short of reversed heading",
            round(pts, 2), "heading"))
    return ded


_CHECKS = {
    "loop": _score_loop,
    "roll": _score_roll,
    "stall_turn": _score_stall_turn,
    "immelmann": _score_immelmann,
}


# ------------------------------------------------------------ entry point


def score_sequence(
    events: list[Event],
    samples: list[StateSample],
    calibration: "Calibration | None" = None,
    rubric: dict | None = None,
) -> list[ManeuverScore]:
    """Score every recognized maneuver in schedule order (VT-20 shape).

    `events` may be twin ground truth or maiden.maneuver output -- both
    carry MANEUVER_START/END with a class under "class" or "maneuver".
    `samples` is the flown track (FUSED or TRUTH StateSamples).
    """
    rub = rubric if rubric is not None else load_rubric()
    box = rub["box"]
    t = np.array([sp.t_utc for sp in samples])
    pos = np.array([sp.pos_enu for sp in samples], dtype=float)
    vel = np.array([sp.vel_enu for sp in samples], dtype=float)

    def _cls(e):
        return e.data.get("class") or e.data.get("maneuver")

    starts = [e for e in events if e.kind == "MANEUVER_START"]
    ends = [e for e in events if e.kind == "MANEUVER_END"]
    out: list[ManeuverScore] = []
    for st in sorted(starts, key=lambda e: e.t_utc):
        cls = _cls(st)
        if cls not in _CHECKS:
            continue
        en = min((e for e in ends
                  if _cls(e) == cls and e.t_utc > st.t_utc),
                 key=lambda e: e.t_utc, default=None)
        if en is None:
            continue
        m = (t >= st.t_utc) & (t <= en.t_utc)
        if m.sum() < 10:
            continue
        ded = _CHECKS[cls](t[m], pos[m], vel[m], rub[cls], box)
        raw = max(0.0, 10.0 - sum(d.points for d in ded))
        cal = None
        if calibration is not None and calibration.trained:
            cal = calibration.apply(cls, raw)
        out.append(ManeuverScore(cls, round(raw, 2), cal, ded))
    return out


# ------------------------------------------------------------ calibration


class Calibration:
    """Per-class monotone map rubric raw -> judge score (SYS-008).

    numpy PAV isotonic regression (deliberate stand-in for sklearn's
    IsotonicRegression -- no new dependency; identical model class).
    Ships UNTRAINED: `trained` is False and `apply` is unreachable via
    score_sequence until maiden64 fits it on campaign judge sheets in
    the CSV contract at the top of this module. VT-21 (r >= 0.8) binds
    there, not here.
    """

    def __init__(self):
        self._maps: dict[str, tuple[np.ndarray, np.ndarray]] = {}

    @property
    def trained(self) -> bool:
        return bool(self._maps)

    @staticmethod
    def _pav(x: np.ndarray, y: np.ndarray):
        """Pool-adjacent-violators: monotone nondecreasing fit of y on x."""
        order = np.argsort(x, kind="stable")
        xs, ys = x[order], y[order].astype(float)
        w = np.ones_like(ys)
        # classic stack-based PAV
        vals, wts, cnts = [], [], []
        for yi, wi in zip(ys, w):
            vals.append(yi)
            wts.append(wi)
            cnts.append(1)
            while len(vals) > 1 and vals[-2] > vals[-1]:
                wt = wts[-1] + wts[-2]
                v = (vals[-1] * wts[-1] + vals[-2] * wts[-2]) / wt
                vals[-2:] = [v]
                wts[-2:] = [wt]
                cnts[-2:] = [cnts[-1] + cnts[-2]]
            # loop continues until monotone
        fit = np.repeat(vals, cnts)
        return xs, fit

    def fit(self, rows: list[dict]) -> "Calibration":
        """rows: dicts with maneuver_class, rubric_raw, judge_score
        (join of score_sequence output and judge-sheet CSV rows)."""
        by: dict[str, list[tuple[float, float]]] = {}
        for r in rows:
            by.setdefault(str(r["maneuver_class"]), []).append(
                (float(r["rubric_raw"]), float(r["judge_score"])))
        for cls, pairs in by.items():
            if len(pairs) < 2:
                continue
            x = np.array([p[0] for p in pairs])
            y = np.array([p[1] for p in pairs])
            self._maps[cls] = self._pav(x, y)
        return self

    def apply(self, cls: str, raw: float) -> float | None:
        if cls not in self._maps:
            return None
        xs, fit = self._maps[cls]
        return float(np.interp(raw, xs, fit))

    def save(self, path):
        arrs = {}
        for cls, (xs, fit) in self._maps.items():
            arrs[f"{cls}__x"] = xs
            arrs[f"{cls}__y"] = fit
        np.savez(path, **arrs)

    @classmethod
    def load(cls, path) -> "Calibration":
        c = cls()
        with np.load(path) as z:
            names = {k.rsplit("__", 1)[0] for k in z.files}
            for name in names:
                c._maps[name] = (z[f"{name}__x"], z[f"{name}__y"])
        return c
