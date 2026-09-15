"""maiden.rules — field-rule checker (SYS-010; VT-23 demonstrates in P2).

Geometry from config/field/rcrc.yaml `field_rules`. Until the Phase 0
survey closes D2's polygon TBD, the shipped vertices carry
`status: PLACEHOLDER_PENDING_SURVEY` and every report surfaces that.

Crossings are informational Events — MAIDEN does not adjudicate (D9).
Hysteresis is spatial AND temporal: a state flip needs
`hysteresis_samples` consecutive samples at least `hysteresis_margin_m`
beyond the boundary. Pure sample-count hysteresis provably fails under
covariance-wide jitter sitting ON a boundary (a run of N same-side
samples happens every ~2^N samples); the distance deadband is what
actually keeps a hovering estimate from emitting twenty Events
(found by test_boundary_jitter_hysteresis, kept as the regression).
"""

from dataclasses import dataclass

import numpy as np
import yaml

from maiden.state import Event, StateSample


@dataclass
class Polygon:
    name: str
    kind: str
    vertices: np.ndarray   # (V, 2) closed ring, ENU [E, N]


@dataclass
class FieldRules:
    status: str
    hysteresis: int
    polygons: list[Polygon]
    flight_line: np.ndarray | None   # (V, 2) polyline
    margin_m: float = 2.0            # spatial deadband (see module doc)


def load_rules(path) -> FieldRules:
    with open(path) as f:
        cfg = yaml.safe_load(f)
    fr = cfg.get("field_rules") or {}
    polys = []
    for p in fr.get("no_fly_polygons", []):
        v = np.asarray(p["vertices_enu"], float)
        if v.ndim != 2 or v.shape[0] < 3 or v.shape[1] != 2:
            raise ValueError(f"polygon {p['name']!r}: need >=3 [E,N] "
                             f"vertices, got shape {v.shape}")
        polys.append(Polygon(p["name"], p["kind"], v))
    fl = fr.get("flight_line")
    return FieldRules(
        status=fr.get("status", "PLACEHOLDER_PENDING_SURVEY"),
        hysteresis=int(fr.get("hysteresis_samples", 5)),
        polygons=polys,
        flight_line=np.asarray(fl["vertices_enu"], float) if fl else None,
        margin_m=float(fr.get("hysteresis_margin_m", 2.0)))


def _inside(pt: np.ndarray, ring: np.ndarray) -> bool:
    """Ray-casting point-in-polygon, E/N plane."""
    x, y = pt
    v = ring
    n = len(v)
    inside = False
    for i in range(n):
        x1, y1 = v[i]
        x2, y2 = v[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                inside = not inside
    return inside


def _seg_dist(pt: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    ab = b - a
    tt = np.clip(np.dot(pt - a, ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0)
    return float(np.linalg.norm(pt - (a + tt * ab)))


def _poly_signed(pt: np.ndarray, ring: np.ndarray) -> float:
    """Signed distance to the polygon boundary: positive inside."""
    d = min(_seg_dist(pt, ring[i], ring[(i + 1) % len(ring)])
            for i in range(len(ring)))
    return d if _inside(pt, ring) else -d


def _line_signed(pt: np.ndarray, line: np.ndarray) -> float:
    """Signed N-distance to the flight line: positive on the pits side
    (smaller N), piecewise-linearly interpolated in E."""
    e, n = pt
    e0, e1 = line[0, 0], line[-1, 0]
    if e <= min(e0, e1) or e >= max(e0, e1):
        n_line = line[0, 1] if abs(e - e0) < abs(e - e1) else line[-1, 1]
    else:
        n_line = float(np.interp(e, line[:, 0], line[:, 1]))
    return n_line - n


def check(samples: list[StateSample], rules: FieldRules) -> list[Event]:
    """RULE_CROSSING Events (enter/exit per zone) over a FUSED track."""
    pts = [(s.t_utc, np.asarray(s.pos_enu[:2], float)) for s in samples
           if s.pos_enu is not None]
    events: list[Event] = []
    zones: list = [("no_overflight", p.name,
                    lambda pt, ring=p.vertices: _poly_signed(pt, ring))
                   for p in rules.polygons]
    if rules.flight_line is not None:
        zones.append(("flight_line", "flight line",
                      lambda pt: _line_signed(pt, rules.flight_line)))

    for kind, name, signed in zones:
        state = False
        streak = 0
        for t, pt in pts:
            sd = signed(pt)
            # deep on the other side of the current state?
            deep = (sd > rules.margin_m) if not state else (sd < -rules.margin_m)
            streak = streak + 1 if deep else 0
            if streak >= rules.hysteresis:
                state = not state
                streak = 0
                events.append(Event(t, "RULE_CROSSING", {
                    "rule": kind, "name": name, "enter": state,
                    "pos_enu": [float(pt[0]), float(pt[1])],
                    "status": rules.status,
                }))
    events.sort(key=lambda e: e.t_utc)
    return events
