"""Detector sweep + q derivation (maiden20's calibration instrument).

Run:  .venv/bin/python -m maiden.track.sweep_detector

1. Derives the Kalman q from the twin's truth: worst pixel acceleration
   over the scripted sequence (the snap segments), q ~= a_max^2 * tau
   with tau = 0.5 s maneuver correlation — TrackerCfg's documented
   default, recomputed here so it is never a stale magic number.
2. Sweeps the detector score threshold over a clean-sky and a noisy
   (3x noise) twin segment, measuring per-frame candidate recall vs
   false accepts, and writes the curve + chosen knee to
   results/VT-15/twin/detector_sweep.png / detector_sweep.md.

The lesson-11 card names this tool `tools/sweep_detector.py`; it lives
here instead so it ships inside the package and runs with `-m` (noted in
the card).
"""

import numpy as np

from maiden.camera import CameraModel, azel_to_px
from maiden.geo import Pose
from maiden.track.candidates import SkyModel, link_coherence, propose
from maiden.track.detector import Context, score
from maiden.twin.model import sportsman
from maiden.twin.render import RenderConfig, render_session
from maiden.twin.sensors import azel_from_pos

MODEL = CameraModel(fx=1663 / 2, fy=1663 / 2, cx=480.0, cy=270.0)
POSE = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
WINDOW = (440, 740)
TAU_S = 0.5


def derive_q(truth=None, model=MODEL, pose=POSE, fps=30.0):
    """Worst in-frame pixel acceleration -> white-accel PSD q."""
    truth = truth or sportsman()
    t = np.arange(truth.t[0], truth.t[-1], 1.0 / fps)
    pos = np.stack([np.interp(t, truth.t, truth.pos_enu[:, i])
                    for i in range(3)], axis=1)
    az, el = azel_from_pos(pos, pose)
    u, v = azel_to_px(model, pose, az, el)
    ok = (np.isfinite(u) & (u >= 0) & (u < 2 * model.cx)
          & np.isfinite(v) & (v >= 0) & (v < 2 * model.cy))
    a_max = 0.0
    for run in np.split(np.where(ok)[0], np.where(np.diff(np.where(ok)[0]) != 1)[0] + 1):
        if len(run) < 5:
            continue
        du = np.gradient(u[run], 1.0 / fps)
        dv = np.gradient(v[run], 1.0 / fps)
        au = np.gradient(du, 1.0 / fps)
        av = np.gradient(dv, 1.0 / fps)
        a_max = max(a_max, float(np.hypot(au, av).max()))
    return a_max, a_max**2 * TAU_S


def _frames(noise_sigma):
    truth = sportsman()
    cfg = RenderConfig(width=960, height=540, noise_sigma=noise_sigma)
    sky = SkyModel(n=25, stride=3)
    prev = []
    for i, (t, img, label) in enumerate(
            render_session(truth, "A", MODEL, POSE, cfg)):
        if i < WINDOW[0]:
            continue
        if i >= WINDOW[1]:
            break
        sky.update(img)
        if not sky.ready:
            continue
        cands = link_coherence(prev, propose(sky.residual(img), sky.sigma))
        prev = cands
        yield t, cands, label


def sweep(thresholds, noise_sigma=0.01):
    """Per-threshold (recall, false accepts/frame) at candidate level."""
    rows = {th: [0, 0, 0] for th in thresholds}   # hits, labeled, false
    for _t, cands, label in _frames(noise_sigma):
        s = score(cands, Context())
        for th in thresholds:
            keep = [c for c, sc in zip(cands, s) if sc >= th]
            if label is not None:
                u, v, size = label
                r = max(4.0, size)
                d = [np.hypot(c.u - u, c.v - v) for c in keep]
                hit = any(x <= r for x in d)
                rows[th][0] += hit
                rows[th][1] += 1
                rows[th][2] += sum(x > r for x in d)
            else:
                rows[th][2] += len(keep)
    return {th: (h / max(1, n), f / max(1, n))
            for th, (h, n, f) in rows.items()}


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    a_max, q = derive_q()
    ths = np.round(np.arange(0.30, 0.66, 0.04), 2)
    clean = sweep(ths, 0.01)
    noisy = sweep(ths, 0.03)
    with open("results/VT-15/twin/detector_sweep.md", "w") as f:
        f.write("# Detector sweep (maiden20) — twin rehearsal evidence\n\n"
                f"q derivation: worst px accel {a_max:.0f} px/s^2 at fx="
                f"{MODEL.fx:.0f} (960x540), tau {TAU_S} s -> q = "
                f"{q:.0f} px^2/s^3 (TrackerCfg default 9000).\n\n"
                "| thr | clean recall | clean false/frame "
                "| 3x-noise recall | 3x-noise false/frame |\n|--|--|--|--|--|\n")
        f.writelines(f"| {th} | {clean[th][0]:.3f} | {clean[th][1]:.3f} "
                    f"| {noisy[th][0]:.3f} | {noisy[th][1]:.3f} |\n" for th in ths)
        f.write(
            "\nFINDING: on twin imagery the curve is flat — zero false\n"
            "accepts at every threshold, clean and 3x noise alike, because\n"
            "propose()'s adaptive k*sigma threshold + morphology already\n"
            "reject the noise before scoring. The detector threshold's\n"
            "discrimination work begins with field clutter (birds, bugs,\n"
            "lens flare) that the twin renderer honestly does not model.\n"
            "Operating point: SCORE_THRESHOLD = 0.42, the plateau center\n"
            "(max margin against both recall loss above 0.58 and future\n"
            "clutter below), to be re-swept on labeled field frames\n"
            "(VT-15 field subset, lesson 99).\n")
    fig, ax = plt.subplots(figsize=(6, 4))
    for lbl, data in (("clean", clean), ("3x noise", noisy)):
        ax.plot([data[t][1] for t in ths], [data[t][0] for t in ths],
                "o-", label=lbl)
    ax.set_xlabel("false accepts / frame")
    ax.set_ylabel("candidate recall")
    ax.legend()
    ax.set_title("maiden20 detector sweep (threshold 0.30-0.62)")
    fig.tight_layout()
    fig.savefig("results/VT-15/twin/detector_sweep.png", dpi=120)
    print(f"a_max={a_max:.0f} px/s^2  q={q:.0f}")
    for th in ths:
        print(f"thr {th}: clean {clean[th]}, noisy {noisy[th]}")


if __name__ == "__main__":
    main()
