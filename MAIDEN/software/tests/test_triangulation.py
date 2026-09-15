"""maiden13: D3's sigma_range ~ R^2*sigma_theta/B, made executable.

Why the factor-of-~1.5 tolerance: the D3 formula is a small-angle scalar
sketch — two coplanar rays, error purely in the range direction, baseline
exactly perpendicular to the line of sight. The Monte-Carlo below is the
real 3D problem: elevation couples in, the baseline is not exactly
perpendicular at every geometry, and both stations' angular noise (not
one) contributes. Those effects move the constant, not the scaling; the
1/B law is what we pin down.
"""

from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from maiden.geo import Pose
from maiden.twin import sensors

SIGMA_THETA = sensors.SIGMA_THETA_RAD
RESULTS = Path("results/lesson07")


def _ray(az_deg, el_deg):
    az, el = np.radians(az_deg), np.radians(el_deg)
    return np.array([np.sin(az) * np.cos(el),
                     np.cos(az) * np.cos(el),
                     np.sin(el)])


def triangulate(stations, az_el_pairs):
    """Least-squares intersection of rays: min sum |(I-uu^T)(x-s)|^2."""
    a = np.zeros((3, 3))
    b = np.zeros(3)
    for s, (az, el) in zip(stations, az_el_pairs):
        u = _ray(az, el)
        proj = np.eye(3) - np.outer(u, u)
        a += proj
        b += proj @ np.asarray(s)
    return np.linalg.solve(a, b)


def _mc_sigma_range(baseline_m, n=3000, seed=42):
    """Range-direction scatter for a target ~150 m out from the baseline."""
    rng = np.random.default_rng(seed)
    pa = Pose((0.0, 0.0, 0.0), 0.0, 8.0)
    pb = Pose((baseline_m, 0.0, 0.0), 0.0, 8.0)
    target = np.array([baseline_m / 2.0, 148.0, 20.0])
    mid = (np.asarray(pa.pos_enu) + np.asarray(pb.pos_enu)) / 2.0
    range_dir = (target - mid) / np.linalg.norm(target - mid)

    sig = np.degrees(SIGMA_THETA)
    errs = np.empty(n)
    cross = np.empty(n)
    for i in range(n):
        pairs = []
        for pose in (pa, pb):
            az, el = sensors.azel_from_pos(target, pose)
            pairs.append((az[0] + rng.normal(0, sig),
                          el[0] + rng.normal(0, sig)))
        est = triangulate([pa.pos_enu, pb.pos_enu], pairs)
        d = est - target
        errs[i] = d @ range_dir
        cross[i] = np.linalg.norm(d - (d @ range_dir) * range_dir)
    r_eff = np.linalg.norm(target - mid)
    return errs.std(), cross.std(), r_eff


def test_d3_formula_default_geometry():
    """At R~150, B=75: measured sigma_range within 1.5x of R^2*sig/B."""
    meas, cross, r = _mc_sigma_range(75.0)
    pred = r**2 * SIGMA_THETA / 75.0
    assert pred / 1.5 < meas < pred * 1.5, (meas, pred)
    # cross-range markedly smaller than range scatter
    assert cross < 0.8 * meas


def test_one_over_b_scaling_and_figure():
    """B=25 m -> ~0.45 m per D3; sweep and pin the figure in results/."""
    bs = np.array([25.0, 50.0, 75.0, 100.0])
    meas = []
    preds = []
    for b in bs:
        m, _, r = _mc_sigma_range(b)
        meas.append(m)
        preds.append(r**2 * SIGMA_THETA / b)
    meas, preds = np.array(meas), np.array(preds)
    assert preds[0] / 1.5 < meas[0] < preds[0] * 1.5      # ~0.45 m at 25 m
    # 1/B scaling: measured ratio 25 m vs 100 m within 25% of 4x
    assert 3.0 < meas[0] / meas[-1] < 5.0

    RESULTS.mkdir(parents=True, exist_ok=True)
    head = Path(".git/HEAD").read_text().strip()
    ref = Path(".git", head.split()[-1])
    githash = ref.read_text()[:12] if ref.exists() else head[:12]
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.plot(bs, meas, "o-", label="Monte-Carlo (seed 42)")
    ax.plot(bs, preds, "--", label=r"D3: $R^2\sigma_\theta/B$")
    ax.set_xlabel("baseline B (m)")
    ax.set_ylabel(r"$\sigma_{range}$ (m)")
    ax.set_title(f"Why B must be 75 m down the fence  ·  {githash}")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(RESULTS / "sigma_vs_baseline.png", dpi=120)
    plt.close(fig)


def test_time_skew_probe():
    """33 ms bias on B ~ 1 m error at 30 m/s (lesson 04's argument)."""
    pa = Pose((0.0, 0.0, 0.0), 0.0, 8.0)
    pb = Pose((75.0, 0.0, 0.0), 0.0, 8.0)
    v = np.array([30.0, 0.0, 0.0])            # cross-range, worst case
    p0 = np.array([37.5, 148.0, 20.0])
    az_a, el_a = sensors.azel_from_pos(p0, pa)
    p_skew = p0 + v * 0.033                   # B sees the target 33 ms late
    az_b, el_b = sensors.azel_from_pos(p_skew, pb)
    est = triangulate([pa.pos_enu, pb.pos_enu],
                      [(az_a[0], el_a[0]), (az_b[0], el_b[0])])
    err = np.linalg.norm(est - p0)
    assert 0.4 < err < 2.5, err               # ~1 m, same order as GPS
