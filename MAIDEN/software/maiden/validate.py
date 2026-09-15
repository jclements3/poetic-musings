"""maiden.validate — D7 verification-against-truth, steps 1-6.

Implements D7 §Verification against 6-DOF truth one-to-one; code comments
carry the D7 step numbers. Step 7 (judge correlation) needs humans and
lives in lesson 99 / maiden64.

Design decisions (lesson 14):
- Step 1 is a CHECK, not a knob. Both sides carry IRIG-B/GPS time
  (SYS-006); we verify it. During validation truth exists, so the
  target's own motion is the common event: truth is projected through
  each station's pose and cross-correlated with that station's measured
  az stream. A shifted station shows up as a lag, localized to the
  offending station, resolved to well under a frame time by parabolic
  refinement of the correlation peak. Any offset beyond the budget flags
  the session degraded and is recorded — never silently applied.
- Steps 2-3: truth is interpolated onto the fused 50 Hz epoch grid,
  never the estimate onto truth — filter artifacts must not be smoothed
  away. Twin truth arrives already in ENU; real GNSS truth arrives as
  LLA and goes through geo.enu_from_lla with the surveyed origin.
- Attitude residuals are emitted as ABSENT (None), not zero — the fused
  track does not estimate attitude yet (D8: "where estimable").
- Pass thresholds are SYS-002/003/004's numbers, held in module
  config/thresholds.yaml (maiden28) — D2 remains the authority.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from maiden.geo import enu_from_lla
from maiden.twin.sensors import azel_from_pos

# SYS-002 / SYS-003 / SYS-004 pass criteria (VT-10/11/12 field tests;
# exercised in sim as rehearsal). Single numeric home (maiden28):
# config/thresholds.yaml — D2 is the authority for the values.
_REPO_ROOT = Path(__file__).resolve().parents[2]
THRESHOLDS_FILE = _REPO_ROOT / "config" / "thresholds.yaml"


def load_thresholds(path=THRESHOLDS_FILE) -> dict:
    """The SYS numbers, from their one code-readable home."""
    import yaml

    with open(path) as f:
        return yaml.safe_load(f)


_T = load_thresholds()
POS_RMS_MAX_M = float(_T["SYS-002"]["pos_rms_m"])
VEL_RMS_MAX_MPS = float(_T["SYS-003"]["vel_rms_mps"])
CONTINUITY_MIN = float(_T["SYS-004"]["continuity"])
SYNC_BUDGET_S = float(_T["SYS-006"]["sync_budget_s"])


# --------------------------------------------------------------- tracks

@dataclass
class Track:
    """A time-stamped trajectory: truth, fused, or converted."""

    t: np.ndarray                 # (n,) UTC seconds
    pos: np.ndarray               # (n, 3) ENU metres
    vel: np.ndarray               # (n, 3) ENU m/s
    att: np.ndarray | None = None  # (n, 3) roll/pitch/yaw deg, or None
    valid: np.ndarray | None = None  # (n,) bool; None means all valid

    @classmethod
    def from_truth_npz(cls, path) -> tuple[Track, dict]:
        """Twin sidecar: ENU truth + events + sync_event_utc."""
        d = np.load(path, allow_pickle=True)
        t = d["t"] + float(d["epoch_utc"])
        meta = {
            "sync_event_utc": float(d["sync_event_utc"]),
            "event_t": d["event_t"] + float(d["epoch_utc"]),
            "event_kind": [str(k) for k in d["event_kind"]],
            "seed": int(d["seed"]),
        }
        return cls(t=t, pos=d["pos_enu"], vel=d["vel_enu"],
                   att=d["att_rpy"]), meta

    @classmethod
    def from_lla(cls, t, lat, lon, alt, vel_enu, origin_lla,
                 att=None) -> Track:
        """D7 step 2: real GNSS truth LLA -> surveyed field ENU frame."""
        pos = np.array([enu_from_lla(origin_lla, (la, lo, al))
                        for la, lo, al in zip(lat, lon, alt)])
        return cls(t=np.asarray(t, float), pos=pos,
                   vel=np.asarray(vel_enu, float), att=att)

    @classmethod
    def from_fused_npz(cls, path) -> Track:
        d = np.load(path)
        return cls(t=d["t_utc"], pos=d["pos_enu"], vel=d["vel_enu"],
                   valid=d["valid"].astype(bool))

    @classmethod
    def from_fused_samples(cls, samples) -> Track:
        from maiden.fuse import is_valid
        samples = list(samples)
        return cls(
            t=np.array([s.t_utc for s in samples]),
            pos=np.array([s.pos_enu for s in samples], float),
            vel=np.array([s.vel_enu for s in samples], float),
            valid=np.array([is_valid(s) for s in samples]),
        )


# ------------------------------------------------------- step 1: align

@dataclass
class AlignResult:
    """Step 1 outcome. Offsets are station-minus-truth, seconds."""

    offsets_s: dict = field(default_factory=dict)
    budget_s: float = SYNC_BUDGET_S
    degraded: bool = False
    worst_station: str | None = None
    note: str = ""

    @property
    def sync(self) -> str:
        """The D8 Sync column: 'ok' | 'degraded(+100.0ms)'."""
        if not self.degraded:
            return "ok"
        off = self.offsets_s.get(self.worst_station, 0.0)
        return f"degraded({off * 1e3:+.1f}ms)"


def _xcorr_offset(t_a, y_a, t_b, y_b, max_lag_s=0.5, dt=0.01):
    """Lag of series b relative to a (b late => positive), by minimizing
    the mean-square difference J(tau) = mean((a(t) - b(t + tau))^2) over
    a FIXED evaluation window, with parabolic refinement of the minimum.

    The fixed window matters: a varying overlap biases unnormalized
    correlation toward zero lag (the longest-overlap segment always has
    the most energy). Resolution well under the tracker frame time for
    smooth az trajectories.
    """
    t0, t1 = max(t_a[0], t_b[0]) + max_lag_s, min(t_a[-1], t_b[-1]) - max_lag_s
    if t1 - t0 < 1.0:
        raise ValueError("streams do not overlap enough to align")
    grid = np.arange(t0, t1, dt)
    a = np.interp(grid, t_a, y_a)
    # exclude grid points that fall in gaps of the observed stream
    # (dropouts, sun outage): np.interp would bridge them linearly and
    # bias the fit. The gap is dilated by max_lag so the mask holds for
    # every tau evaluated.
    frame = 2 / 30
    mask = np.ones(len(grid), bool)
    gaps = np.flatnonzero(np.diff(t_b) > frame)
    for g in gaps:
        s, e = t_b[g] - max_lag_s - frame, t_b[g + 1] + max_lag_s + frame
        mask &= ~((grid >= s) & (grid <= e))
    if mask.sum() < 50:
        raise ValueError("too few gap-free samples to align")
    taus = np.arange(-max_lag_s, max_lag_s + dt / 2, dt)
    # variance, not raw MSE: the two az series differ by a constant
    # (true-north vs station frame, unwrap origin) that must not couple
    # into the lag estimate.
    j = np.array([np.var((a - np.interp(grid + tau, t_b, y_b))[mask])
                  for tau in taus])
    i = int(np.argmin(j))
    if 0 < i < len(j) - 1:
        c0, c1, c2 = j[i - 1], j[i], j[i + 1]
        denom = c0 - 2 * c1 + c2
        frac = 0.5 * (c0 - c2) / denom if denom != 0 else 0.0
    else:
        frac = 0.0
    # b sampled at (t + tau) matches a(t) when b's timestamps are shifted
    # late by tau: a shift of +100 ms minimizes J at tau = +100 ms.
    return taus[i] + frac * dt


def align(truth: Track, station_samples: dict, poses: dict,
          budget_s: float = SYNC_BUDGET_S,
          sync_event_utc: float | None = None) -> AlignResult:
    """D7 step 1: verify per-station time alignment against truth.

    For each station, project truth through its pose (az series) and
    cross-correlate with the station's measured az stream. During
    validation the aircraft's own motion is the common event; the clap
    (sync_event_utc) is additionally checked to lie inside the overlap.
    """
    res = AlignResult(budget_s=budget_s)
    worst = 0.0
    for sid, samples in sorted(station_samples.items()):
        obs = [(s.t_utc, s.az_deg) for s in samples if s.az_deg is not None]
        if len(obs) < 20:
            res.note += f"{sid}: too few az samples to check; "
            continue
        t_obs, az_obs = map(np.array, zip(*obs))
        az_true = azel_from_pos(truth.pos, poses[sid])[0]
        # unwrap both so the correlation isn't disturbed by the ±180 seam
        off = _xcorr_offset(truth.t, np.unwrap(np.radians(az_true)),
                            t_obs, np.unwrap(np.radians(az_obs)))
        res.offsets_s[sid] = float(off)
        if abs(off) > abs(worst):
            worst = off
            res.worst_station = sid
    # frame-time resolution floor: never flag below what the tracker
    # frame interval can resolve (30 fps -> 33 ms; epoch grid 20 ms).
    resolvable = max(budget_s, 0.5 * 1 / 30)
    if abs(worst) > resolvable:
        res.degraded = True
        res.note += (f"station {res.worst_station} offset "
                     f"{worst * 1e3:+.1f} ms exceeds budget "
                     f"{budget_s * 1e3:.1f} ms (recorded, not hidden)")
    if sync_event_utc is not None and not (
            truth.t[0] <= sync_event_utc <= truth.t[-1]):
        res.degraded = True
        res.note += "; sync event outside truth span"
    return res


# --------------------------------------------- steps 2-3: residuals

@dataclass
class Residuals:
    t: np.ndarray          # (n,) epochs that entered the set
    r_pos: np.ndarray      # (n, 3) fused - truth, ENU
    r_vel: np.ndarray      # (n, 3)
    att_absent: bool = True  # D8 "where estimable" — not yet


def residuals(fused: Track, truth: Track) -> Residuals:
    """D7 step 3: per-sample residuals on the fused epoch grid.

    Truth is interpolated to the fused epochs (never the reverse).
    Only validity-flagged epochs enter; ends are trimmed to overlap —
    no extrapolation.
    """
    # copy: `&=` on the caller's own valid array would silently corrupt
    # the Track for any later use (review finding, pinned regression)
    ok = (np.ones(len(fused.t), bool) if fused.valid is None
          else fused.valid.copy())
    ok &= (fused.t >= truth.t[0]) & (fused.t <= truth.t[-1])
    te = fused.t[ok]
    tp = np.column_stack([np.interp(te, truth.t, truth.pos[:, i])
                          for i in range(3)])
    tv = np.column_stack([np.interp(te, truth.t, truth.vel[:, i])
                          for i in range(3)])
    return Residuals(t=te, r_pos=fused.pos[ok] - tp,
                     r_vel=fused.vel[ok] - tv)


# ------------------------------------------------- step 4: rollups

@dataclass
class SegmentTable:
    """Optional maneuver segmentation: rows of (label, t0, t1).

    Real labels arrive with maiden51's classifier; until then twin
    sessions get generic labels from paired MANEUVER_START/END events.
    """

    rows: list  # [(label, t0, t1), ...]

    @classmethod
    def from_events(cls, event_t, event_kind) -> SegmentTable:
        rows, stack = [], []
        n = 0
        for t, k in zip(event_t, event_kind):
            if k == "MANEUVER_START":
                stack.append(t)
            elif k == "MANEUVER_END" and stack:
                n += 1
                rows.append((f"maneuver-{n}", stack.pop(), t))
        return cls(rows=rows)


def _metrics(r_pos, r_vel):
    if len(r_pos) == 0:
        # an all-gated / no-overlap session must FAIL, not crash:
        # nan metrics make flight_passes() False and render as 'nan'
        nan3 = [float("nan")] * 3
        return {"pos_rms": float("nan"), "pos_p95": float("nan"),
                "vel_rms": float("nan"),
                "per_axis": {"pos_rms_enu": nan3, "vel_rms_enu": nan3}}
    n_pos = np.linalg.norm(r_pos, axis=1)
    n_vel = np.linalg.norm(r_vel, axis=1)
    return {
        "pos_rms": float(np.sqrt(np.mean(n_pos ** 2))),
        "pos_p95": float(np.percentile(n_pos, 95)),
        "vel_rms": float(np.sqrt(np.mean(n_vel ** 2))),
        "per_axis": {  # free, and localizes problems (D8 JSON only)
            "pos_rms_enu": [float(x) for x in
                            np.sqrt(np.mean(r_pos ** 2, axis=0))],
            "vel_rms_enu": [float(x) for x in
                            np.sqrt(np.mean(r_vel ** 2, axis=0))],
        },
    }


def rollup(res: Residuals, segments: SegmentTable | None = None,
           continuity: float = 1.0) -> dict:
    """D7 step 4: RMS / p95 / continuity per flight and per segment.

    Scalar-norm RMS — that is how SYS-002/003 are phrased and how
    VT-10/11 are judged. Per-axis detail rides along in the JSON.
    """
    out = {"ALL": {**_metrics(res.r_pos, res.r_vel),
                   "n": len(res.t), "continuity": continuity}}
    for label, t0, t1 in (segments.rows if segments else []):
        m = (res.t >= t0) & (res.t <= t1)
        if m.sum() < 2:
            out[label] = {"n": int(m.sum()), "note": "insufficient samples"}
            continue
        out[label] = {**_metrics(res.r_pos[m], res.r_vel[m]),
                      "n": int(m.sum())}
    return out


@dataclass
class FlightMetrics:
    flight: str
    aircraft: str
    sequence: str
    pos_rms: float
    pos_p95: float
    vel_rms: float
    continuity: float
    sync: str            # "ok" | "degraded(+8.2ms)"
    passed: bool


def flight_passes(pos_rms, vel_rms, continuity) -> bool:
    """VT-10/11/12 per-flight criteria (SYS-002/003/004)."""
    return (pos_rms <= POS_RMS_MAX_M and vel_rms <= VEL_RMS_MAX_MPS
            and continuity >= CONTINUITY_MIN)


# ------------------------------------------------- step 5: the gate

def gate(flights: list[FlightMetrics], need: int = 8, of: int = 10) -> bool:
    """D7 step 5, pure function — CI calls this (maiden28).

    Judges the first `of` flights; a campaign with fewer flights than
    `of` is judged on what exists but can only pass with >= need passes.
    """
    judged = flights[:of]
    return sum(1 for f in judged if f.passed) >= need


# ------------------------------------------------- step 6: bands

def bands(all_res: list[Residuals]) -> dict:
    """D7 step 6: residual stats -> confidence-band parameters (D8).

    maiden55 stamps these onto un-instrumented pilot reports — the
    mechanism by which validation earns MAIDEN 'the right to score
    aircraft that carry nothing' (D1 S3).
    """
    p = np.concatenate([np.linalg.norm(r.r_pos, axis=1) for r in all_res])
    s = np.concatenate([np.linalg.norm(r.r_vel, axis=1) for r in all_res])
    if len(p) == 0:  # same guard as _metrics: fail loudly downstream, not here
        return {"position_p95_m": float("nan"), "speed_p95_mps": float("nan"),
                "n_samples": 0,
                "provenance": "EMPTY residual set — session unusable"}
    return {
        "position_p95_m": float(np.percentile(p, 95)),
        "speed_p95_mps": float(np.percentile(s, 95)),
        "n_samples": len(p),
        "provenance": "twin rehearsal until campaign data (VT-10/11/12)",
    }


# ---------------------------------------------------- session runner

ACC_HDR = ("| Flight | Aircraft | Sequence | Pos RMS (m) | Pos p95 (m) "
           "| Vel RMS (m/s) | Continuity | Sync | Pass |")
MAN_HDR = "| Maneuver | n | Pos RMS (m) | Vel RMS (m/s) | Continuity | Notes |"


def run_session(session_dir, flight_name=None) -> dict:
    """Fuse, ingest truth, run steps 1-6, write report.json/report.md."""
    from maiden.fuse import fuse, poses_from_session
    from maiden.ingest import load

    session_dir = Path(session_dir)
    npz = session_dir / "truth.npz"
    if npz.exists():
        truth, meta = Track.from_truth_npz(npz)
        segments = SegmentTable.from_events(meta["event_t"],
                                            meta["event_kind"])
        sync_event = meta["sync_event_utc"]
        aircraft, sequence = "twin", "sportsman"
    else:  # real session: converted airborne file (maiden49 onward)
        raise NotImplementedError(
            "real-session truth ingest lands with maiden49's converter; "
            "twin sessions carry truth.npz")

    station_samples = {}
    for p in sorted(session_dir.glob("STATION_*.ch10")):
        sid = p.name.split("_")[1]
        station_samples[sid] = list(load(p))
    poses = poses_from_session(session_dir)

    a = align(truth, station_samples, poses, sync_event_utc=sync_event)

    all_samples = [s for ss in station_samples.values() for s in ss]
    (fused_samples, stats) = fuse(all_samples, poses)[:2]
    fused = Track.from_fused_samples(fused_samples)

    res = residuals(fused, truth)
    span = fused.t[-1] - fused.t[0] if len(fused.t) > 1 else 0.0
    continuity = (min(stats.valid_time / span, 1.0) if span else 0.0)
    roll = rollup(res, segments, continuity=continuity)

    fm = FlightMetrics(
        flight=flight_name or session_dir.name,
        aircraft=aircraft, sequence=sequence,
        pos_rms=roll["ALL"]["pos_rms"], pos_p95=roll["ALL"]["pos_p95"],
        vel_rms=roll["ALL"]["vel_rms"], continuity=continuity,
        sync=a.sync,
        passed=flight_passes(roll["ALL"]["pos_rms"], roll["ALL"]["vel_rms"],
                             continuity) and not a.degraded,
    )
    report = {
        "flight": fm.__dict__,
        "align": {"offsets_s": a.offsets_s, "degraded": a.degraded,
                  "note": a.note},
        "rollup": roll,
        "bands": bands([res]),
    }
    _write_reports(session_dir, [fm], {fm.flight: roll}, report["bands"])
    (session_dir / "report.json").write_text(json.dumps(report, indent=2))
    return report


def _fmt_row(fm: FlightMetrics) -> str:
    return (f"| {fm.flight} | {fm.aircraft} | {fm.sequence} "
            f"| {fm.pos_rms:.3f} | {fm.pos_p95:.3f} | {fm.vel_rms:.3f} "
            f"| {fm.continuity:.4f} | {fm.sync} "
            f"| {'PASS' if fm.passed else 'FAIL'} |")


def _write_reports(out_dir, flights, rollups, band_params,
                   verdict=None) -> None:
    lines = ["# Validation report (generated by maiden.validate)", "",
             "## Accuracy vs 6-DOF truth", "", ACC_HDR,
             "|" + "---|" * 9]
    lines += [_fmt_row(f) for f in flights]
    lines += ["", "## By maneuver type", "", MAN_HDR, "|" + "---|" * 6]
    for roll in rollups.values():
        for label, m in roll.items():
            if label == "ALL" and len(rollups) > 1:
                continue
            note = m.get("note", "" if label == "ALL"
                         else "labels pending maiden51")
            cont = m.get("continuity")
            lines.append(
                f"| {label} | {m.get('n', 0)} "
                f"| {m.get('pos_rms', float('nan')):.3f} "
                f"| {m.get('vel_rms', float('nan')):.3f} "
                f"| {'' if cont is None else f'{cont:.4f}'} | {note} |")
    if verdict is not None:
        lines += ["", (f"**Campaign gate: "
                       f"{'PASS' if verdict else 'FAIL'}** (>=8 of 10)")]
    lines += ["", "## Confidence bands", "",
              (f"position p95 = {band_params['position_p95_m']:.3f} m, "
               f"speed p95 = {band_params['speed_p95_mps']:.3f} m/s "
               f"({band_params['provenance']})")]
    Path(out_dir, "report.md").write_text("\n".join(lines) + "\n")


def run_campaign(campaign_dir) -> dict:
    """A directory of session dirs -> combined tables + gate verdict."""
    campaign_dir = Path(campaign_dir)
    flights, rollups = [], {}
    for sd in sorted(p for p in campaign_dir.iterdir() if p.is_dir()):
        rep = run_session(sd)
        fm = FlightMetrics(**rep["flight"])
        flights.append(fm)
        rollups[fm.flight] = rep["rollup"]
    verdict = gate(flights)
    # bands from the campaign-wide residual set: reuse per-session values
    # weighted by sample count (exact percentile needs raw residuals;
    # per-session p95s are combined conservatively by max)
    band_params = {
        "position_p95_m": max(r["bands"]["position_p95_m"] for r in
                              (json.loads((campaign_dir / f.flight /
                                           "report.json").read_text())
                               for f in flights)),
        "speed_p95_mps": max(json.loads(
            (campaign_dir / f.flight / "report.json").read_text()
        )["bands"]["speed_p95_mps"] for f in flights),
        "n_samples": sum(json.loads(
            (campaign_dir / f.flight / "report.json").read_text()
        )["bands"]["n_samples"] for f in flights),
        "provenance": "campaign" if verdict else "twin rehearsal",
    }
    out = {"flights": [f.__dict__ for f in flights],
           "gate": verdict, "bands": band_params}
    _write_reports(campaign_dir, flights, rollups, band_params, verdict)
    (campaign_dir / "report.json").write_text(json.dumps(out, indent=2))
    bdir = Path("results/validate")
    bdir.mkdir(parents=True, exist_ok=True)
    (bdir / "bands.json").write_text(json.dumps(band_params, indent=2))
    return out


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(prog="maiden validate")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--session")
    g.add_argument("--campaign")
    args = ap.parse_args(argv)
    if args.session:
        rep = run_session(args.session)
        fm = rep["flight"]
        print(f"{fm['flight']}: pos RMS {fm['pos_rms']:.3f} m, "
              f"vel RMS {fm['vel_rms']:.3f} m/s, "
              f"continuity {fm['continuity']:.4f}, sync {fm['sync']} "
              f"-> {'PASS' if fm['passed'] else 'FAIL'}")
    else:
        out = run_campaign(args.campaign)
        print(f"campaign: {sum(f['passed'] for f in out['flights'])}"
              f"/{len(out['flights'])} flights pass -> gate "
              f"{'PASS' if out['gate'] else 'FAIL'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
