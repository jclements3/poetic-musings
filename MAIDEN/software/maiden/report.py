"""maiden.report — the one-page pilot report (SYS-011; D6 §Report, D9).

One Letter page: scores table with ± bands, per-maneuver overlays from
the judge's view (flown solid, ideal dashed, gray band = position
confidence), approach panel, field-rule flags, top-3 deductions.
JSON sidecar carries everything plus machine detail, byte-identical
across runs (no timestamps, sorted keys). Clips cut ±5 s around each
maneuver from Station A video via keyframe-snapped `ffmpeg -c copy`;
twin sessions log "no video channel" and move on.

Bands (D8 §Confidence bands, the report's honesty budget): the campaign
residual stats set the floor; the live EKF covariance WIDENS a band by
sqrt(trace ratio) whenever it exceeds the campaign median. Until the
campaign runs, the floor comes from twin rehearsal and the footer says
so — that footer is not decoration.
"""

import json
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

from maiden.approach import ApproachReport
from maiden.geo import Pose
from maiden.score import ManeuverScore
from maiden.state import Event, StateSample
from maiden.twin.sensors import station_azel

SCHEMA_VERSION = 1

# --- layout constants (module top per the card) -----------------------------
PAGE_W_IN, PAGE_H_IN = 8.5, 11.0          # US Letter
MARGIN = 0.05
N_OVERLAY_COLS = 4

# --- band constants ---------------------------------------------------------
# Campaign median of trace(P_pos) — PLACEHOLDER until the validation
# campaign (maiden65) writes the real number into results/campaign/.
# 0.04 m^2 is the median of the maiden25 imperfect-twin headline run
# (sqrt(trace) ~ 0.2 m); revisit with campaign data. D8 widening rule.
CAMPAIGN_MEDIAN_TR_POS_M2 = 0.04
# Per-maneuver score band floor, points. PLACEHOLDER until judge-sheet
# spread exists (maiden64); the widening factor scales it.
SCORE_BAND_FLOOR_PTS = 0.5

_REPO_ROOT = Path(__file__).resolve().parents[2]
BANDS_CAMPAIGN = _REPO_ROOT / "results" / "campaign" / "bands.json"
BANDS_REHEARSAL = _REPO_ROOT / "results" / "validate" / "bands.json"


class Bands:
    """Confidence bands with provenance + the D8 widening rule."""

    def __init__(self, path=None):
        p = Path(path) if path else (
            BANDS_CAMPAIGN if BANDS_CAMPAIGN.exists() else BANDS_REHEARSAL)
        with open(p) as f:
            d = json.load(f)
        self.position_p95_m = float(d["position_p95_m"])
        self.speed_p95_mps = float(d["speed_p95_mps"])
        self.provenance = d.get("provenance", "unknown")
        self.source = str(p)

    @property
    def field_validated(self) -> bool:
        return self.provenance == "campaign"

    def widen_factor(self, cov_traces: np.ndarray) -> float:
        """sqrt(median live tr(P_pos) / campaign median), floored at 1."""
        if cov_traces.size == 0:
            return 1.0
        med = float(np.median(cov_traces))
        return max(1.0, float(np.sqrt(med / CAMPAIGN_MEDIAN_TR_POS_M2)))

    def footer(self) -> str:
        if self.field_validated:
            return f"bands: validation campaign ({self.source})"
        return "bands: twin rehearsal — not yet field-validated"


@dataclass
class FlightData:
    """Everything render() needs for one flight."""
    session: str
    name: str
    samples: list[StateSample]                 # FUSED
    events: list[Event]                        # maneuver + rule events
    scores: list[ManeuverScore]
    approach: ApproachReport | None
    pose_a: Pose
    bands: Bands
    rules_status: str = "PLACEHOLDER_PENDING_SURVEY"
    provenance: str = "twin"                   # "twin" | "field"
    video_a: Path | None = None
    meta: dict = field(default_factory=dict)


# --- panels (each a function so tests render them in isolation) -------------

def _maneuver_window(fd: FlightData, cls: str):
    ev = [e for e in fd.events if e.kind in ("MANEUVER_START", "MANEUVER_END")
          and (e.data.get("class") or e.data.get("maneuver")) == cls]
    starts = [e.t_utc for e in ev if e.kind == "MANEUVER_START"]
    ends = [e.t_utc for e in ev if e.kind == "MANEUVER_END"]
    if not starts or not ends:
        return None
    return min(starts), max(ends)


def _ideal_xy(cls, t, pos):
    """Rubric reference shape fit to entry conditions, ENU. Honest and
    geometric: loop/immelmann = best-fit circle arc in the vertical
    plane; roll/stall exit = level line at entry altitude."""
    if cls in ("loop", "immelmann"):
        s = np.hypot(pos[:, 0] - pos[0, 0], pos[:, 1] - pos[0, 1])
        z = pos[:, 2]
        # circle through (s, z) — algebraic fit
        A = np.column_stack([s, z, np.ones_like(s)])
        b = s * s + z * z
        try:
            c = np.linalg.lstsq(A, b, rcond=None)[0]
        except np.linalg.LinAlgError:
            return None
        cs, cz = c[0] / 2, c[1] / 2
        r = np.sqrt(c[2] + cs * cs + cz * cz)
        th = np.linspace(0, 2 * np.pi if cls == "loop" else np.pi, 100)
        return cs + r * np.cos(th), cz + r * np.sin(th), s, z
    s = np.hypot(pos[:, 0] - pos[0, 0], pos[:, 1] - pos[0, 1])
    z = pos[:, 2]
    return (np.array([s[0], s[-1]]), np.array([z[0], z[0]]), s, z)


def panel_overlay(ax, fd: FlightData, cls: str):
    """Judge's-view overlay: az/el from Station A, gray confidence band."""
    win = _maneuver_window(fd, cls)
    ax.set_title(cls.replace("_", " "), fontsize=8)
    ax.tick_params(labelsize=6)
    if win is None:
        ax.text(0.5, 0.5, "not flown", ha="center", va="center",
                transform=ax.transAxes, fontsize=7)
        return
    t0, t1 = win
    sel = [s for s in fd.samples if t0 <= s.t_utc <= t1
           and s.pos_enu is not None]
    if len(sel) < 10:
        ax.text(0.5, 0.5, "no track", ha="center", va="center",
                transform=ax.transAxes, fontsize=7)
        return
    pos = np.array([s.pos_enu for s in sel], float)
    az, el = station_azel(pos, fd.pose_a)
    az = np.unwrap(np.radians(az)) * 180 / np.pi

    # gray band: per-sample half-angle from sqrt(tr(P_pos)) at range
    rng = np.linalg.norm(pos - np.asarray(fd.pose_a.pos_enu), axis=1)
    tr = np.array([float(np.trace(s.cov[:3, :3])) if s.cov is not None
                   else 0.0 for s in sel])
    half_deg = np.degrees(np.sqrt(tr) / np.maximum(rng, 1.0))
    half_deg *= fd.bands.widen_factor(tr)
    ax.fill_between(az, el - half_deg, el + half_deg,
                    color="0.8", lw=0, zorder=1)
    ax.plot(az, el, "-", color="C0", lw=1.2, zorder=3, label="flown")

    # ideal, projected through the same view
    ide = _ideal_xy(cls, np.array([s.t_utc for s in sel]), pos)
    if ide is not None:
        xs, zs, s_flown, _ = ide
        # map arc-length back onto the flown ground track for projection
        e = np.interp(np.clip(xs, s_flown.min(), s_flown.max()),
                      s_flown, pos[:, 0])
        n = np.interp(np.clip(xs, s_flown.min(), s_flown.max()),
                      s_flown, pos[:, 1])
        p_ideal = np.column_stack([e, n, zs])
        azi, eli = station_azel(p_ideal, fd.pose_a)
        azi = np.unwrap(np.radians(azi)) * 180 / np.pi
        ax.plot(azi, eli, "--", color="0.3", lw=0.9, zorder=2,
                label="ideal")
    ax.set_xlabel("az °", fontsize=6)
    ax.set_ylabel("el °", fontsize=6)


def panel_scores(ax, fd: FlightData):
    ax.axis("off")
    factor = fd.bands.widen_factor(_cov_traces(fd.samples))
    pm = SCORE_BAND_FLOOR_PTS * factor
    rows = []
    for sc in fd.scores:
        shown = sc.calibrated if sc.calibrated is not None else sc.raw
        tag = "cal" if sc.calibrated is not None else "raw"
        rows.append([sc.cls.replace("_", " "), f"{shown:.1f} ± {pm:.1f}",
                     tag, f"{len(sc.deductions)}"])
    tbl = ax.table(cellText=rows or [["—", "—", "—", "—"]],
                   colLabels=["maneuver", "score", "basis", "deductions"],
                   loc="upper left", cellLoc="left")
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(7)
    tbl.scale(1.0, 1.1)
    ax.set_title("Scores", loc="left", fontsize=9)


def panel_deductions(ax, fd: FlightData):
    ax.axis("off")
    ded = [(d.points, f"{sc.cls.replace('_', ' ')}: {d.text}")
           for sc in fd.scores for d in sc.deductions]
    ded.sort(key=lambda x: -x[0])
    lines = [f"• {txt}  (−{pts:.1f})" for pts, txt in ded[:3]]
    ax.text(0, 1, "Top deductions\n" + ("\n".join(lines) or "none"),
            va="top", fontsize=7, transform=ax.transAxes)


def panel_approach(ax, fd: FlightData):
    ax.axis("off")
    ap = fd.approach
    if ap is None:
        ax.text(0, 1, "Approach\n(no landing detected this flight)",
                va="top", fontsize=7, transform=ax.transAxes)
        return
    xchk = ("—" if ap.crosscheck_delta_mps is None else
            f"{ap.threshold_speed_c_mps:.1f} m/s "
            f"(Δ {ap.crosscheck_delta_mps:+.1f})")
    td = ("—" if ap.touchdown_enu is None else
          f"({ap.touchdown_enu[0]:.0f}, {ap.touchdown_enu[1]:.0f}) m"
          + (" [extrapolated]" if ap.touchdown_extrapolated else ""))
    txt = (f"Approach\n"
           f"glideslope {ap.glideslope_deg:.2f} ± {ap.glideslope_se_deg:.2f}°\n"
           f"threshold speed {ap.threshold_speed_mps:.1f} m/s\n"
           f"C radar cross-check {xchk}\n"
           f"touchdown {td}")
    if ap.notes:
        txt += "\n" + "\n".join(f"({n})" for n in ap.notes)
    ax.text(0, 1, txt, va="top", fontsize=7, transform=ax.transAxes)


def panel_rules(ax, fd: FlightData):
    ax.axis("off")
    cr = [e for e in fd.events if e.kind == "RULE_CROSSING"]
    lines = [f"• {e.data['name']}: {'enter' if e.data['enter'] else 'exit'}"
             f" at t={e.t_utc:.1f}s "
             f"({e.data['pos_enu'][0]:.0f}, {e.data['pos_enu'][1]:.0f}) m"
             for e in cr]
    hdr = "Field-rule flags (informational — MAIDEN does not adjudicate)"
    if fd.rules_status == "PLACEHOLDER_PENDING_SURVEY":
        hdr += "\n[rule geometry PLACEHOLDER — pending Phase 0 survey]"
    ax.text(0, 1, hdr + "\n" + ("\n".join(lines) or "no crossings"),
            va="top", fontsize=7, transform=ax.transAxes)


def _cov_traces(samples):
    return np.array([float(np.trace(s.cov[:3, :3])) for s in samples
                     if s.cov is not None])


# --- clips ------------------------------------------------------------------

def clip_commands(fd: FlightData, out_dir: Path) -> list[list[str]]:
    """ffmpeg -c copy commands, ±5 s around each maneuver. Keyframe-
    snapped, deliberately not re-encoded (100x faster; 10-min clock)."""
    if fd.video_a is None:
        return []
    t_ref = fd.samples[0].t_utc if fd.samples else 0.0
    cmds = []
    for sc in fd.scores:
        win = _maneuver_window(fd, sc.cls)
        if win is None:
            continue
        ss = max(0.0, win[0] - t_ref - 5.0)
        dur = (win[1] - win[0]) + 10.0
        cmds.append(["ffmpeg", "-y", "-ss", f"{ss:.2f}", "-t", f"{dur:.2f}",
                     "-i", str(fd.video_a), "-c", "copy",
                     str(out_dir / f"clip_{sc.cls}.mp4")])
    return cmds


def cut_clips(fd: FlightData, out_dir: Path) -> list[str]:
    if fd.video_a is None:
        return ["no video channel — clips skipped"]
    if shutil.which("ffmpeg") is None:
        return ["ffmpeg not on this host — clip commands written, not run"]
    logs = []
    for cmd in clip_commands(fd, out_dir):
        r = subprocess.run(cmd, capture_output=True, check=False)
        logs.append(f"{'ok' if r.returncode == 0 else 'FAIL'}: {cmd[-1]}")
    return logs


# --- sidecar ----------------------------------------------------------------

def sidecar(fd: FlightData) -> dict:
    """Machine-readable everything; deterministic (no timestamps)."""
    factor = fd.bands.widen_factor(_cov_traces(fd.samples))
    return {
        "schema_version": SCHEMA_VERSION,
        "session": fd.session,
        "flight": fd.name,
        "provenance": fd.provenance,
        "bands": {
            "position_p95_m": fd.bands.position_p95_m,
            "speed_p95_mps": fd.bands.speed_p95_mps,
            "provenance": fd.bands.provenance,
            "widen_factor": round(factor, 4),
            "score_band_pts": round(SCORE_BAND_FLOOR_PTS * factor, 3),
        },
        "scores": [{
            "class": sc.cls, "raw": sc.raw, "calibrated": sc.calibrated,
            "deductions": [{"text": d.text, "points": d.points,
                            "tag": d.tag} for d in sc.deductions],
        } for sc in fd.scores],
        "events": [{"t": e.t_utc, "kind": e.kind, "data": e.data}
                   for e in fd.events],
        "approach": None if fd.approach is None else {
            "glideslope_deg": fd.approach.glideslope_deg,
            "glideslope_se_deg": fd.approach.glideslope_se_deg,
            "threshold_speed_mps": fd.approach.threshold_speed_mps,
            "threshold_speed_c_mps": fd.approach.threshold_speed_c_mps,
            "crosscheck_delta_mps": fd.approach.crosscheck_delta_mps,
            "touchdown_enu": fd.approach.touchdown_enu,
            "touchdown_extrapolated": fd.approach.touchdown_extrapolated,
            "notes": fd.approach.notes,
        },
        "rules_status": fd.rules_status,
        "meta": fd.meta,
    }


# --- the page ---------------------------------------------------------------

def render(fd: FlightData, out_dir) -> dict:
    """One Letter page + sidecar + clips. Returns paths."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    pdf_path = out_dir / f"{fd.name}.pdf"
    json_path = out_dir / f"{fd.name}.json"

    fig = plt.figure(figsize=(PAGE_W_IN, PAGE_H_IN))
    gs = fig.add_gridspec(4, N_OVERLAY_COLS, height_ratios=[1.1, 1.0, 0.9, 0.15],
                          left=MARGIN, right=1 - MARGIN,
                          top=0.93, bottom=0.03, hspace=0.55, wspace=0.35)
    fig.suptitle(f"MAIDEN flight report — {fd.name} ({fd.session})",
                 fontsize=11)

    panel_scores(fig.add_subplot(gs[0, :2]), fd)
    panel_deductions(fig.add_subplot(gs[0, 2:]), fd)
    classes = [sc.cls for sc in fd.scores][:N_OVERLAY_COLS]
    for i in range(N_OVERLAY_COLS):
        ax = fig.add_subplot(gs[1, i])
        if i < len(classes):
            panel_overlay(ax, fd, classes[i])
        else:
            ax.axis("off")
    panel_approach(fig.add_subplot(gs[2, :2]), fd)
    panel_rules(fig.add_subplot(gs[2, 2:]), fd)

    axf = fig.add_subplot(gs[3, :])
    axf.axis("off")
    axf.text(0, 0.5, fd.bands.footer(), fontsize=7, style="italic")
    if fd.provenance == "twin":
        axf.text(1, 0.5, "TWIN SESSION — synthetic data", fontsize=7,
                 style="italic", ha="right")

    with PdfPages(pdf_path) as pdf:
        pdf.savefig(fig)
    plt.close(fig)

    with open(json_path, "w") as f:
        json.dump(sidecar(fd), f, indent=1, sort_keys=True)
        f.write("\n")

    clip_log = cut_clips(fd, out_dir)
    return {"pdf": str(pdf_path), "sidecar": str(json_path),
            "clips": clip_log}
