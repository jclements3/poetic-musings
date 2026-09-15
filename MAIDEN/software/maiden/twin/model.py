"""Scripted Sportsman flight model. Kinematic, not aerodynamic. SW-004.

Every primitive is built in a local frame (start at the origin, fly along
+x, +y left, +z up) and rigid-transformed into the field frame. Positions
and velocities are analytic per primitive — nothing is finite-differenced
here. Attitude is path-consistent (yaw from horizontal velocity, pitch
from climb angle, roll from the primitive's script), per lesson 06.
"""
import itertools
from dataclasses import dataclass, field

import numpy as np

from maiden.state import Event

DT = 0.01                        # 100 Hz truth
G = 9.80665


@dataclass
class Imperfections:
    loop_ovality: float = 0.0    # 0 = round; 0.1 = radius varies +-10%
    roll_drift_deg: float = 0.0  # heading drift across a full roll
    alt_mismatch_m: float = 0.0  # exit vs entry altitude error
    center_offset_m: float = 0.0 # sequence displaced along the box


@dataclass
class Truth:
    t: np.ndarray                # (N,) seconds from sequence start
    pos_enu: np.ndarray          # (N, 3)
    vel_enu: np.ndarray          # (N, 3)
    att_rpy: np.ndarray          # (N, 3) degrees
    events: list[Event] = field(default_factory=list)


# ---------------------------------------------------------------- frame math

def _rot_heading(heading_deg: float) -> np.ndarray:
    """Local (fwd, left, up) -> ENU for a compass heading (CW from north)."""
    psi = np.radians(heading_deg)
    s, c = np.sin(psi), np.cos(psi)
    return np.array([[s, -c, 0.0], [c, s, 0.0], [0.0, 0.0, 1.0]])


def _to_field(p0, heading_deg, pos_l, vel_l) -> tuple[np.ndarray, np.ndarray]:
    rot = _rot_heading(heading_deg)
    return np.asarray(p0) + pos_l @ rot.T, vel_l @ rot.T


def _att(vel_enu, roll_deg, fallback_yaw_deg) -> np.ndarray:
    """(roll, pitch, yaw) deg; yaw forward-filled through vertical flight."""
    vh = np.hypot(vel_enu[:, 0], vel_enu[:, 1])
    yaw = np.degrees(np.arctan2(vel_enu[:, 0], vel_enu[:, 1]))
    bad = vh < 0.5
    if bad.any():
        idx = np.where(~bad, np.arange(len(yaw)), 0)
        np.maximum.accumulate(idx, out=idx)
        yaw = yaw[idx]
        if bad[0]:
            first_good = np.argmax(~bad) if (~bad).any() else None
            yaw[: (first_good or len(yaw))] = (
                fallback_yaw_deg if first_good is None else yaw[first_good]
            )
    pitch = np.degrees(np.arctan2(vel_enu[:, 2], vh))
    roll = np.broadcast_to(roll_deg, yaw.shape).astype(float)
    return np.stack([roll, pitch, yaw], axis=1)


def _times(t_end_nominal: float) -> tuple[np.ndarray, float]:
    """Round a duration to the 100 Hz grid; samples include both endpoints."""
    n = max(2, round(t_end_nominal / DT))
    t = np.arange(n + 1) * DT
    return t, n * DT


def _blend(v0: float, v1: float, t: np.ndarray, t_total: float):
    """Cosine speed blend v0->v1 and its analytic distance integral."""
    v = v0 + (v1 - v0) * 0.5 * (1.0 - np.cos(np.pi * t / t_total))
    s = v0 * t + 0.5 * (v1 - v0) * (
        t - (t_total / np.pi) * np.sin(np.pi * t / t_total)
    )
    return v, s


# ------------------------------------------------------------ line segments

def _line(p0, heading_deg, length_m, v0, v1, alt0, alt1,
          roll0=0.0, roll1=0.0) -> Truth:
    """Straight ground track, cosine speed blend, linear roll slew.

    Altitude follows its own cosine blend alt0 -> alt1 with zero vertical
    speed at both ends, so a climbing or descending leg joins level
    neighbours without an impulsive pushover (the g-police watch for it).
    """
    dz = alt1 - alt0
    t, t_total = _times(2.0 * length_m / (v0 + v1))
    v, s = _blend(v0, v1, t, t_total)
    z = 0.5 * dz * (1.0 - np.cos(np.pi * t / t_total))
    vz = 0.5 * dz * (np.pi / t_total) * np.sin(np.pi * t / t_total)
    pos_l = np.stack([s, np.zeros_like(s), z], axis=1)
    vel_l = np.stack([v, np.zeros_like(v), vz], axis=1)
    pos, vel = _to_field(p0, heading_deg, pos_l, vel_l)
    roll = roll0 + (roll1 - roll0) * t / t_total
    return Truth(t, pos, vel, _att(vel, roll, heading_deg))


def _roll_line(p0, heading_deg, length_m, v, roll0, roll1,
               drift_deg=0.0, alt_shear_m=0.0) -> Truth:
    """Constant-speed line with roll slew; optional constant-rate heading
    drift (a gentle arc) and a linear altitude shear."""
    t, t_total = _times(length_m / v)
    omega = np.radians(drift_deg) / t_total
    if abs(drift_deg) < 1e-9:
        x = v * t
        y = np.zeros_like(t)
        vx = np.full_like(t, v)
        vy = np.zeros_like(t)
    else:
        x = (v / omega) * np.sin(omega * t)
        y = (v / omega) * (np.cos(omega * t) - 1.0)
        vx = v * np.cos(omega * t)
        vy = -v * np.sin(omega * t)
    z = alt_shear_m * t / t_total
    vz = np.full_like(t, alt_shear_m / t_total)
    pos_l = np.stack([x, y, z], axis=1)
    vel_l = np.stack([vx, vy, vz], axis=1)
    pos, vel = _to_field(p0, heading_deg, pos_l, vel_l)
    roll = roll0 + (roll1 - roll0) * t / t_total
    return Truth(t, pos, vel, _att(vel, roll, heading_deg))


# ------------------------------------------------------------ vertical arcs

def _vert_arc(p0, heading_deg, radius_m, v, th0, th1,
              ovality=0.0, alt_shear_m=0.0) -> Truth:
    """Arc of a vertical circle in the plane of `heading_deg`.

    theta = 0 is the bottom, tangent along +x; theta grows nose-up.
    pos_local = (r(th) sin th, 0, r(th)(1 - cos th)) with
    r(th) = radius * (1 + ovality*(1 - cos th))  — r(0) = radius so the
    entry speed matches the inbound leg; the top bulges (egg-shaped).
    alt_shear_m is spread linearly over the arc (loop alt mismatch).
    """
    span = th1 - th0
    t, t_total = _times(abs(span) * radius_m / v)
    thdot = span / t_total
    th = th0 + thdot * t
    r = radius_m * (1.0 + ovality * (1.0 - np.cos(th)))
    rp = radius_m * ovality * np.sin(th)          # dr/dtheta
    x = r * np.sin(th)
    z = r * (1.0 - np.cos(th)) + alt_shear_m * (th - th0) / span
    vx = thdot * (rp * np.sin(th) + r * np.cos(th))
    vz = thdot * (rp * (1.0 - np.cos(th)) + r * np.sin(th)) \
        + thdot * alt_shear_m / span
    zeros = np.zeros_like(t)
    pos_l = np.stack([x - x[0], zeros, z - z[0]], axis=1)
    vel_l = np.stack([vx, zeros, vz], axis=1)
    pos, vel = _to_field(p0, heading_deg, pos_l, vel_l)
    return Truth(t, pos, vel, _att(vel, 0.0, heading_deg))


def _hairpin(p0, heading_deg, radius_m, v) -> Truth:
    """Stall-turn turnaround: up -> down, displaced 2r along +x."""
    t, t_total = _times(np.pi * radius_m / v)
    phi = (np.pi / t_total) * t
    x = radius_m * (1.0 - np.cos(phi))
    z = radius_m * np.sin(phi)
    vx = v * np.sin(phi)
    vz = v * np.cos(phi)
    zeros = np.zeros_like(t)
    pos_l = np.stack([x, zeros, z], axis=1)
    vel_l = np.stack([vx, zeros, vz], axis=1)
    pos, vel = _to_field(p0, heading_deg, pos_l, vel_l)
    return Truth(t, pos, vel, _att(vel, 0.0, heading_deg))


def _vert_line(p0, up: bool, height_m, v0, v1, yaw_deg=0.0) -> Truth:
    """Vertical line, cosine speed blend; yaw held at the entry heading."""
    t, t_total = _times(2.0 * height_m / (v0 + v1))
    v, s = _blend(v0, v1, t, t_total)
    sign = 1.0 if up else -1.0
    zeros = np.zeros_like(t)
    pos = np.asarray(p0) + np.stack([zeros, zeros, sign * s], axis=1)
    vel = np.stack([zeros, zeros, sign * v], axis=1)
    return Truth(t, pos, vel, _att(vel, 0.0, yaw_deg))


# ---------------------------------------------------------------- primitives

def level_leg(p0, heading_deg, length_m, v0, v1, alt) -> Truth:
    """Straight and level, trapezoidal (cosine-blended) speed profile."""
    p0 = np.asarray(p0, dtype=float)
    assert abs(p0[2] - alt) < 1e-6, "level_leg: p0 altitude != alt"
    return _line(p0, heading_deg, length_m, v0, v1, alt, alt)


def loop(p0, heading_deg, radius_m, v, ovality=0.0, alt_shear_m=0.0) -> Truth:
    """Full vertical circle in the heading plane, constant nominal speed."""
    return _vert_arc(p0, heading_deg, radius_m, v, 0.0, 2.0 * np.pi,
                     ovality=ovality, alt_shear_m=alt_shear_m)


def roll(p0, heading_deg, length_m, v, drift_deg=0.0) -> Truth:
    """Straight line, altitude held, roll slewed 0 -> 360 deg."""
    return _roll_line(p0, heading_deg, length_m, v, 0.0, 360.0,
                      drift_deg=drift_deg)


def stall_turn(p0, heading_deg, upline_m, v_entry) -> Truth:
    """Pull to vertical, bleed to ~2 m/s, hairpin, regain, pull out.

    Exits on the reciprocal heading at the entry altitude, displaced
    2*r_turn along the entry direction.
    """
    v_min = 2.0
    r_pull = max(24.0, v_entry**2 / (2.8 * G))
    r_turn = 3.0
    rot = _rot_heading(heading_deg)
    up = _vert_arc(p0, heading_deg, r_pull, v_entry, 0.0, np.pi / 2.0)
    p = up.pos_enu[-1]
    climb = _vert_line(p, True, upline_m, v_entry, v_min, heading_deg)
    p = climb.pos_enu[-1]
    turn = _hairpin(p, heading_deg, r_turn, v_min)
    p = turn.pos_enu[-1]
    dive = _vert_line(p, False, upline_m, v_min, v_entry,
                      heading_deg + 180.0)
    p = dive.pos_enu[-1]
    # pull-out: down -> reciprocal horizontal, radius r_pull
    t, t_total = _times((np.pi / 2.0) * r_pull / v_entry)
    phi = (np.pi / (2.0 * t_total)) * t
    x = -r_pull * (1.0 - np.cos(phi))
    z = -r_pull * np.sin(phi)
    vx = -v_entry * np.sin(phi)
    vz = -v_entry * np.cos(phi)
    zeros = np.zeros_like(t)
    pos = p + np.stack([x, zeros, z], axis=1) @ rot.T
    vel = np.stack([vx, zeros, vz], axis=1) @ rot.T
    out = Truth(t, pos, vel, _att(vel, 0.0, heading_deg + 180.0))
    return concat([up, climb, turn, dive, out])


def immelmann(p0, heading_deg, radius_m, v, drift_deg=0.0) -> Truth:
    """Half loop up + half roll to upright, by composition."""
    half = _vert_arc(p0, heading_deg, radius_m, v, 0.0, np.pi)
    p = half.pos_enu[-1]
    out = _roll_line(p, heading_deg + 180.0, 2.4 * v, v, 180.0, 360.0,
                     drift_deg=drift_deg)
    return concat([half, out])


# ------------------------------------------------------------------- concat

def concat(parts: list[Truth]) -> Truth:
    """Join parts; assert C0 position and C0 speed continuity at seams."""
    if isinstance(parts[0], tuple):  # defensive: (name, Truth) misuse
        raise TypeError("concat takes list[Truth]")
    t = [parts[0].t]
    pos = [parts[0].pos_enu]
    vel = [parts[0].vel_enu]
    att = [parts[0].att_rpy]
    events = list(parts[0].events)
    offset = parts[0].t[-1]
    for prev, nxt in itertools.pairwise(parts):
        gap = np.linalg.norm(nxt.pos_enu[0] - prev.pos_enu[-1])
        dspeed = abs(np.linalg.norm(nxt.vel_enu[0])
                     - np.linalg.norm(prev.vel_enu[-1]))
        assert gap < 1e-3, f"concat seam: position gap {gap:.4f} m >= 1 mm"
        assert dspeed < 0.1, f"concat seam: speed gap {dspeed:.3f} m/s >= 0.1"
        t.append(nxt.t[1:] + offset)
        pos.append(nxt.pos_enu[1:])
        vel.append(nxt.vel_enu[1:])
        att.append(nxt.att_rpy[1:])
        events += [Event(e.t_utc + offset, e.kind, e.data)
                   for e in nxt.events]
        offset += nxt.t[-1]
    return Truth(np.concatenate(t), np.vstack(pos), np.vstack(vel),
                 np.vstack(att), events)


# ---------------------------------------------------------------- sequence

def sportsman(imp: Imperfections | None = None, seed: int = 0) -> Truth:
    """The sequence, flown in the box: takeoff leg, upwind entry, loop,
    roll, stall turn, immelmann, level legs between, landing approach.
    Emits MANEUVER_START/MANEUVER_END Events with data={"maneuver": name}
    at every boundary, plus TAKEOFF / SCORED_START / SCORED_END /
    TOUCHDOWN markers.
    """
    imp = imp if imp is not None else Imperfections()
    rng = np.random.default_rng(seed)
    jitter = 1.0 + 0.05 * (rng.random(4) - 0.5)   # deterministic per seed
    box_n = 150.0
    alt = 40.0
    v = 25.0

    parts: list[tuple[str | None, Truth]] = []

    def heading_of(tr: Truth) -> float:
        vE, vN = tr.vel_enu[-1, 0], tr.vel_enu[-1, 1]
        return float(np.degrees(np.arctan2(vE, vN)))

    # takeoff / climb-in leg (kinematic honesty: the script starts airborne)
    p = np.array([-220.0, box_n, alt])
    tr = level_leg(p, 90.0, 40.0, 15.0, 18.0 * jitter[0], alt)
    parts.append(("takeoff_leg", tr))
    p = tr.pos_enu[-1]

    tr = level_leg(p, 90.0, 60.0, 18.0 * jitter[0], v, alt)
    parts.append((None, tr))
    p = tr.pos_enu[-1]

    tr = loop(p, 90.0, 38.0, v, ovality=imp.loop_ovality,
              alt_shear_m=imp.alt_mismatch_m)
    parts.append(("loop", tr))
    p = tr.pos_enu[-1]

    a2 = alt + imp.alt_mismatch_m
    tr = _line(p, 90.0, 40.0, v, v * jitter[1], a2, a2)
    parts.append((None, tr))
    p = tr.pos_enu[-1]

    tr = roll(p, 90.0, 100.0, v * jitter[1], drift_deg=imp.roll_drift_deg)
    parts.append(("roll", tr))
    p, h = tr.pos_enu[-1], heading_of(tr)

    tr = _line(p, h, 40.0, v * jitter[1], v, p[2], p[2])
    parts.append((None, tr))
    p = tr.pos_enu[-1]

    tr = stall_turn(p, h, 40.0, v)
    parts.append(("stall_turn", tr))
    p, h = tr.pos_enu[-1], heading_of(tr)

    tr = _line(p, h, 40.0, v, v * jitter[2], p[2], p[2])
    parts.append((None, tr))
    p = tr.pos_enu[-1]

    tr = immelmann(p, h, 30.0, v * jitter[2])
    parts.append(("immelmann", tr))
    p, h = tr.pos_enu[-1], heading_of(tr)

    tr = _line(p, h, 30.0, v * jitter[2], 20.0, p[2], p[2])
    parts.append((None, tr))
    p = tr.pos_enu[-1]

    # descending approach out of the scored window
    tr = _line(p, h, 300.0, 20.0, 15.0 * jitter[3], p[2], 5.0)
    parts.append(("approach", tr))

    seq = concat([tr for _, tr in parts])

    # maneuver-boundary events from the parts' cumulative durations
    events: list[Event] = [Event(0.0, "TAKEOFF", {})]
    t0 = 0.0
    scored = [i for i, (name, _) in enumerate(parts)
              if name in ("loop", "roll", "stall_turn", "immelmann")]
    for i, (name, tr) in enumerate(parts):
        t_end = t0 + tr.t[-1]
        if name in ("loop", "roll", "stall_turn", "immelmann"):
            events.append(Event(t0, "MANEUVER_START", {"maneuver": name}))
            events.append(Event(t_end, "MANEUVER_END", {"maneuver": name}))
        if scored and i == scored[0]:
            events.insert(1, Event(t0, "SCORED_START", {}))
        if scored and i == scored[-1]:
            events.append(Event(t_end, "SCORED_END", {}))
        t0 = t_end
    events.append(Event(seq.t[-1], "TOUCHDOWN", {}))
    events.sort(key=lambda e: e.t_utc)
    seq.events = events

    seq.pos_enu[:, 0] += imp.center_offset_m
    return seq
