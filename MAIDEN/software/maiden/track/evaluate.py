"""VT-15 twin-rehearsal evaluation runs (maiden21).

Run:  .venv/bin/python -m maiden.track.evaluate

Three measured runs on rendered twin imagery, real numbers only, written
to results/VT-15/twin/tracks.md (+ track_recall_trace.png):

1. clean sky   — track-level recall/false-tracks vs maiden19's
                 candidate-level numbers;
2. sun crossing — sun placed on the target's mid-window line of sight;
                 dip depth, coast bridging, reacquisition delay;
3. pressure    — 3x renderer noise, false CONFIRMED tracks per minute
                 (logged WITH the noise setting: a false-alarm rate
                 without its noise level is not evidence).

Twin evidence only: the field subset of VT-15 stays open (D7).
"""

import numpy as np

from maiden.camera import CameraModel
from maiden.geo import Pose
from maiden.track.metrics import Report
from maiden.track.session import track_rendered_session
from maiden.track.tracker import TrackerCfg, TrackState
from maiden.twin.model import sportsman
from maiden.twin.render import RenderConfig
from maiden.twin.sensors import azel_from_pos

MODEL = CameraModel(fx=1663 / 2, fy=1663 / 2, cx=480.0, cy=270.0)
POSE = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
WINDOW = (440, 740)
FPS = 30.0


def _run(cfg, truth):
    rep = Report()
    rows = []
    for t, outs, label in track_rendered_session(
            truth, "A", MODEL, POSE, cfg, frame_range=WINDOW):
        rep.add(t, label, outs)
        rows.append((t, outs, label))
    return rep, rows


def _sun_azel(truth):
    """Aim the sun at the target's line of sight mid-window."""
    t_mid = (WINDOW[0] + (WINDOW[1] - WINDOW[0]) * 0.55) / FPS + truth.t[0]
    k = int(np.searchsorted(truth.t, t_mid))
    az, el = azel_from_pos(truth.pos_enu[k:k + 1], POSE)
    return float(az[0]), float(el[0])


def _dip_stats(rep, rows):
    """(dip_min, coast_frames, reacq_delay_s) around the worst window."""
    centers, trace = rep.recall_trace(1.0)
    if not len(trace):
        return None
    k = int(np.nanargmin(trace))
    dip_t = centers[k]
    coast = 0
    reacq = None
    for t, outs, label in rows:
        if label is None or abs(t - dip_t) > 4.0:
            continue
        if outs and all(o.state is TrackState.COASTING for o in outs):
            coast += 1
        if t > dip_t and outs and any(
                o.state is TrackState.CONFIRMED for o in outs):
            reacq = t - dip_t if reacq is None else reacq
    return float(np.nanmin(trace)), coast, reacq


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    truth = sportsman()
    lines = ["# VT-15 twin rehearsal — track level (maiden21)",
             "", ("Twin evidence only; the VT-15 field column stays open "
                  "until the campaign (D7). Camera 960x540, fx=831.5, "
                  f"eval window frames {WINDOW}, TrackerCfg defaults."), ""]

    clean_rep, _ = _run(RenderConfig(width=960, height=540,
                                     noise_sigma=0.01), truth)
    rec = clean_rep.recall_by_bin()
    lines += ["## Clean sky",
              (f"- track recall >=6px: **{rec['>=6px']:.3f}** "
               "(target >= 0.90; candidate-level was 0.985)"),
              f"- recall 4-6px: {rec['4-6px'] if rec['4-6px'] is None else round(rec['4-6px'], 3)}",
              f"- false tracks/frame: {clean_rep.false_per_frame():.4f}", ""]

    sun = _sun_azel(truth)
    sun_cfg = RenderConfig(width=960, height=540, noise_sigma=0.01,
                           sun_azel=sun)
    sun_rep, sun_rows = _run(sun_cfg, truth)
    srec = sun_rep.recall_by_bin()
    dip = _dip_stats(sun_rep, sun_rows)
    lines += ["## Sun crossing",
              (f"- sun at az/el = ({sun[0]:.1f}, {sun[1]:.1f}) deg "
               "(target line of sight, mid-window)"),
              (f"- track recall >=6px: **{srec['>=6px']:.3f}** "
               "(candidate-level sun run was 0.901, windowed dip 0.43)"),
              f"- windowed recall minimum: {dip[0]:.2f}",
              f"- frames emitted while COASTING near the dip: {dip[1]}",
              (f"- reacquisition delay after dip minimum: "
               f"{'not reacquired in window' if dip[2] is None else f'{dip[2]:.2f} s'}"),
              ""]

    # Pressure run spans the WHOLE session (not just the transit window):
    # a per-minute rate needs minutes.  A track is false when, over its
    # emitted lifetime, it was essentially never near the labeled target
    # (< 20% of its label-present emissions within 3x the label size) —
    # this keeps the legitimate track's post-exit coasting from being
    # miscounted as a false track.
    noisy_cfg = RenderConfig(width=960, height=540, noise_sigma=0.03)
    rows = []
    for t, outs, label in track_rendered_session(
            truth, "A", MODEL, POSE, noisy_cfg,
            frame_range=(0, int(truth.t[-1] * FPS))):
        rows.append((t, outs, label))
    minutes = len(rows) / FPS / 60.0
    near = {}
    emitted = {}
    for t, outs, label in rows:
        for o in outs:
            if label is None:
                continue
            u, v, size = label
            emitted[o.track_id] = emitted.get(o.track_id, 0) + 1
            if np.hypot(o.u - u, o.v - v) <= max(4.0, size) * 3:
                near[o.track_id] = near.get(o.track_id, 0) + 1
    only_dark = {o.track_id for _, outs, lab in rows if lab is None
                 for o in outs} - set(emitted)
    false_ids = only_dark | {
        tid for tid, n in emitted.items() if near.get(tid, 0) / n < 0.2}
    lines += [("## False-track pressure (renderer noise_sigma = 0.03, 3x, "
               "full session)"),
              (f"- false CONFIRMED/COASTING tracks: {len(false_ids)} in "
               f"{minutes:.1f} min -> **{len(false_ids) / minutes:.2f}/min** "
               "(target <= 1/min)"),
              ("- bird/junk injection: renderer has no bird model yet — "
               "deferred with lesson 10 Explore 3; rate above is "
               "noise-only and labeled as such."), ""]

    fig, ax = plt.subplots(figsize=(7, 4))
    for rep, lbl in ((clean_rep, "clean"), (sun_rep, "sun crossing")):
        c, tr = rep.recall_trace(1.0)
        ax.plot(c, tr, label=f"tracks, {lbl}")
    ax.set_xlabel("t (s)")
    ax.set_ylabel("windowed recall")
    ax.legend()
    ax.set_title("maiden21 track recall (twin rehearsal)")
    fig.tight_layout()
    fig.savefig("results/VT-15/twin/track_recall_trace.png", dpi=120)
    with open("results/VT-15/twin/tracks.md", "w") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))
    _ = TrackerCfg  # documented defaults are what ran


if __name__ == "__main__":
    main()
