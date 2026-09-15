"""maiden.approach — landing analytics (SYS-009; VT-22 rehearses here).

The approach is where Station C is the star: on final the target's
velocity is nearly all radial to C, so C's v_r is a direct speed check
on the fused estimate (lesson 24 "The approach, as an estimation
problem"). Every number ships with a band — a glideslope quoted without
its fit standard error invites over-reading (D9 "bands matter").

Touchdown honesty: the twin's script ends airborne at ~5 m (kinematic
honesty), so the vertical-speed-zero-at-ground detector may find no
crossing; we then EXTRAPOLATE along the fitted glideslope and say so
(`touchdown_extrapolated=True`). Station C video refinement is a stub
until the field (marked below).
"""

from dataclasses import dataclass, field

import numpy as np

from maiden.state import Event, StateSample

# final-leg direct detection (lesson 24): heading within tolerance of the
# runway axis, altitude monotonically decreasing, closing on the threshold
HEADING_TOL_DEG = 25.0
MIN_LEG_SAMPLES = 50          # 1 s at 50 Hz
DESCENT_EPS_MPS = 0.05        # "monotone" allows this much wobble


@dataclass
class ApproachReport:
    glideslope_deg: float
    glideslope_se_deg: float
    threshold_speed_mps: float | None      # |v| fused at threshold crossing
    threshold_speed_c_mps: float | None    # C v_r / cos(angle) cross-check
    crosscheck_delta_mps: float | None     # fused - C (health indicator)
    touchdown_enu: tuple | None
    touchdown_t: float | None
    touchdown_extrapolated: bool
    final_leg: tuple                       # (t0, t1)
    n_samples: int
    scatter_enu: list = field(default_factory=list)  # session touchdowns
    notes: list = field(default_factory=list)

    def line(self) -> str:
        gs = f"glideslope {self.glideslope_deg:.2f} ± {self.glideslope_se_deg:.2f}°"
        th = ("threshold —" if self.threshold_speed_mps is None
              else f"threshold {self.threshold_speed_mps:.1f} m/s")
        return f"{gs} · {th}"


def _fused_arrays(samples: list[StateSample]):
    t = np.array([s.t_utc for s in samples])
    pos = np.array([s.pos_enu for s in samples], dtype=float)
    vel = np.array([s.vel_enu for s in samples], dtype=float)
    return t, pos, vel


def final_leg_mask(t, pos, vel, runway: dict,
                   events: list[Event] | None = None) -> np.ndarray:
    """Boolean mask of the final approach leg.

    Prefers the tail-of-track direct detection; a TOUCHDOWN Event (twin
    truth or field marker) only caps the right edge when present.
    """
    axis = float(runway["heading_deg"])
    thr = np.asarray(runway["threshold_enu"], float)
    heading = np.degrees(np.arctan2(vel[:, 0], vel[:, 1]))
    hd = np.abs((heading - axis + 180.0) % 360.0 - 180.0)
    dist = np.linalg.norm(pos[:, :2] - thr, axis=1)
    vU = vel[:, 2]

    t_end = t[-1]
    if events:
        td = [e.t_utc for e in events if e.kind == "TOUCHDOWN"]
        if td:
            t_end = min(t_end, td[0])
    ok = (hd <= HEADING_TOL_DEG) & (vU <= DESCENT_EPS_MPS) & (t <= t_end)
    # closing on the threshold: distance decreasing (allow sensor wobble)
    closing = np.gradient(dist) <= 0.5
    ok &= closing
    # take the last contiguous run
    if not ok.any():
        return ok
    idx = np.where(ok)[0]
    breaks = np.where(np.diff(idx) > 1)[0]
    start = idx[breaks[-1] + 1] if breaks.size else idx[0]
    mask = np.zeros_like(ok)
    mask[start:idx[-1] + 1] = True
    return mask


def _cos_boresight(p_enu: np.ndarray, v_enu: np.ndarray,
                   c_pose) -> float:
    """cos(angle between flight path and the C->target line)."""
    u = p_enu - np.asarray(c_pose.pos_enu, float)
    u /= np.linalg.norm(u)
    w = v_enu / np.linalg.norm(v_enu)
    return float(abs(np.dot(u, w)))


def approach_metrics(samples: list[StateSample], events: list[Event],
                     fld: dict, c_samples: list[StateSample] | None = None,
                     c_pose=None) -> ApproachReport | None:
    """SYS-009 analytics on a FUSED track. `fld` = parsed rcrc.yaml.

    Returns None when no final leg is found (no landing this flight).
    """
    runway = fld["runway"]
    notes = []
    if runway.get("status") == "PLACEHOLDER_PENDING_SURVEY":
        notes.append("runway geometry PLACEHOLDER_PENDING_SURVEY")
    t, pos, vel = _fused_arrays(samples)
    m = final_leg_mask(t, pos, vel, runway, events)
    if m.sum() < MIN_LEG_SAMPLES:
        return None
    tl, pl, vl = t[m], pos[m], vel[m]

    # glideslope: U against along-track distance-to-threshold, with se
    thr = np.asarray(runway["threshold_enu"], float)
    ground = float(runway.get("ground_height_m", 0.0))
    d = np.linalg.norm(pl[:, :2] - thr, axis=1)
    A = np.vstack([d, np.ones_like(d)]).T
    coef, res, *_ = np.linalg.lstsq(A, pl[:, 2], rcond=None)
    slope, intercept = coef
    n = len(d)
    sigma2 = float(res[0]) / (n - 2) if res.size and n > 2 else 0.0
    se_slope = np.sqrt(sigma2 / float(np.sum((d - d.mean()) ** 2)))
    gs = float(np.degrees(np.arctan(slope)))
    gs_se = float(np.degrees(se_slope / (1.0 + slope * slope)))

    # threshold speed: |v| interpolated at the minimum threshold distance
    # (the twin may terminate short of the mark; then we report at closest
    # approach and say so)
    i_thr = int(np.argmin(d))
    v_thr = float(np.linalg.norm(vl[i_thr]))
    if d[i_thr] > 20.0:
        notes.append(f"threshold not crossed; speed at closest "
                     f"approach ({d[i_thr]:.0f} m out)")
    t_thr = float(tl[i_thr])

    # Station C cross-check: nearest C v_r within 0.2 s, cosine-corrected
    v_c = delta = None
    if c_samples and c_pose is not None:
        cs = [(s.t_utc, s.v_r) for s in c_samples if s.v_r is not None]
        if cs:
            ct = np.array([c[0] for c in cs])
            j = int(np.argmin(np.abs(ct - t_thr)))
            if abs(ct[j] - t_thr) <= 0.2:
                cosang = _cos_boresight(pl[i_thr], vl[i_thr], c_pose)
                if cosang > 0.2:
                    v_c = float(abs(cs[j][1]) / cosang)
                    delta = v_thr - v_c
                else:
                    notes.append("C geometry too oblique for cross-check")

    # touchdown: first U crossing of ground height; else extrapolate the
    # glideslope fit (twin script ends airborne — kinematic honesty)
    extrapolated = False
    below = np.where(pl[:, 2] <= ground + 0.05)[0]
    if below.size:
        i = int(below[0])
        td_enu, td_t = tuple(pl[i]), float(tl[i])
    else:
        extrapolated = True
        d_ground = (ground - intercept) / slope if slope != 0 else 0.0
        heading = np.arctan2(vl[-1, 0], vl[-1, 1])
        along = d[-1] - d_ground     # distance still to fly
        td_enu = (float(pl[-1, 0] + along * np.sin(heading)),
                  float(pl[-1, 1] + along * np.cos(heading)), ground)
        td_t = float(tl[-1] + along / max(np.linalg.norm(vl[-1]), 1.0))
        notes.append("touchdown extrapolated along glideslope fit "
                     "(track ends airborne)")
    # TODO(field): refine touchdown with Station C video (VT-22) — stub.

    return ApproachReport(
        glideslope_deg=gs, glideslope_se_deg=gs_se,
        threshold_speed_mps=v_thr, threshold_speed_c_mps=v_c,
        crosscheck_delta_mps=delta,
        touchdown_enu=td_enu, touchdown_t=td_t,
        touchdown_extrapolated=extrapolated,
        final_leg=(float(tl[0]), float(tl[-1])), n_samples=int(m.sum()),
        scatter_enu=[td_enu], notes=notes)
