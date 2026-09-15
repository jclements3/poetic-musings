"""maiden24: three-radials demo + chi-square gating.

The U^-1 vr demo is documentation-as-test of D3's argument: three radial
velocities resolve the full velocity vector from a single epoch, no
differencing of positions. (Card names it test_three_radials.py; kept in
the test_fuse* family per the sprint's file scope.)
"""

import numpy as np

from maiden.fuse import CHI2_GATE, Ekf, h_azel
from maiden.geo import Pose
from maiden.twin.model import sportsman
from maiden.twin.sensors import SIGMA_VR, vr_from_state
from maiden.twin.writer import default_poses


def test_three_radials_recover_velocity():
    """One epoch, U from the true unit vectors — D3's argument, with a
    discovery the course keeps: the twin's default layout places A, B, C
    COLLINEAR along the flight line, so every u_i lies in the plane
    spanned by the station line and the target. U is exactly rank 2:
    radials alone resolve only the two in-plane velocity components, and
    the out-of-plane component must come from the az/el updates — which
    is precisely how the EKF blends them. D3's "three radials -> 3D
    velocity" implicitly requires a non-collinear C (the real Station C
    sits at the runway threshold, off the A-B line; survey note for
    lesson 99 / maiden59).
    """
    truth = sportsman(seed=3)
    poses, _ = default_poses()
    rng = np.random.default_rng(11)
    i = len(truth.t) // 3            # mid-sequence epoch, in-maneuver
    p, v = truth.pos_enu[i], truth.vel_enu[i]

    u_rows, vr = [], []
    for name in ("A", "B", "C"):
        pose = poses[name]
        d = p - np.asarray(pose.pos_enu)
        u_rows.append(d / np.linalg.norm(d))
        vr.append(vr_from_state(p.reshape(1, 3), v.reshape(1, 3), pose)[0]
                  + rng.normal(0.0, SIGMA_VR))
    u = np.vstack(u_rows)

    # the discovery, pinned: collinear stations => rank-2 U
    assert np.linalg.matrix_rank(u, tol=1e-9) == 2

    # minimum-norm least squares recovers the in-plane components
    v_hat = np.linalg.lstsq(u, np.array(vr), rcond=None)[0]
    sa = np.asarray(poses["A"].pos_enu)
    line = np.asarray(poses["B"].pos_enu) - sa
    normal = np.cross(line, p - sa)
    normal /= np.linalg.norm(normal)
    v_in = v - (v @ normal) * normal          # truth, out-of-plane removed
    v_hat_in = v_hat - (v_hat @ normal) * normal
    assert np.linalg.norm(v_hat_in - v_in) < 20.0 * SIGMA_VR, (
        f"in-plane |dv|={np.linalg.norm(v_hat_in - v_in):.3f}")
    # no position differencing anywhere above: one epoch in, velocity out.


def test_three_radials_full_rank_with_offset_c():
    """Move C off the station line (the real threshold geometry) and D3's
    claim holds exactly: full 3D velocity from one epoch."""
    truth = sportsman(seed=3)
    poses, _ = default_poses()
    c = np.asarray(poses["C"].pos_enu) + np.array([0.0, 60.0, 0.0])
    poses = {"A": poses["A"], "B": poses["B"],
             "C": Pose(tuple(c), poses["C"].heading_deg)}
    rng = np.random.default_rng(11)
    i = len(truth.t) // 3
    p, v = truth.pos_enu[i], truth.vel_enu[i]
    u_rows, vr = [], []
    for name in ("A", "B", "C"):
        pose = poses[name]
        d = p - np.asarray(pose.pos_enu)
        u_rows.append(d / np.linalg.norm(d))
        vr.append(vr_from_state(p.reshape(1, 3), v.reshape(1, 3), pose)[0]
                  + rng.normal(0.0, SIGMA_VR))
    u = np.vstack(u_rows)
    kappa = np.linalg.cond(u)
    v_hat = np.linalg.solve(u, np.array(vr))
    assert np.linalg.norm(v_hat - v) < 5.0 * kappa * SIGMA_VR, (
        f"|dv|={np.linalg.norm(v_hat - v):.3f}, cond(U)={kappa:.1f}")


def test_conditioning_degrades_when_rays_align():
    """All u_i nearly parallel -> U nearly singular (the far-target case)."""
    p_far = np.array([0.0, 5000.0, 100.0])
    poses, _ = default_poses()
    u = np.vstack([
        (p_far - np.asarray(poses[n].pos_enu))
        / np.linalg.norm(p_far - np.asarray(poses[n].pos_enu))
        for n in ("A", "B", "C")])
    p_near = np.array([0.0, 150.0, 60.0])
    u_near = np.vstack([
        (p_near - np.asarray(poses[n].pos_enu))
        / np.linalg.norm(p_near - np.asarray(poses[n].pos_enu))
        for n in ("A", "B", "C")])
    assert np.linalg.cond(u) > 20.0 * np.linalg.cond(u_near)


def test_gate_constants_and_rejection():
    assert CHI2_GATE == {1: 10.83, 2: 13.82}
    pose = Pose((0.0, 0.0, 0.0), 0.0)
    ekf = Ekf()
    p = np.array([20.0, 150.0, 50.0])
    ekf.x = np.concatenate([p, np.zeros(3)])
    ekf.p = np.diag([0.25] * 3 + [100.0] * 3)
    ekf.t = 0.0
    # consistent measurement: applied
    z = np.degrees(h_azel(p, pose))
    assert ekf.update_azel(z, pose)
    # 30-sigma az outlier: gated, state untouched
    x_before = ekf.x.copy()
    z_out = z + np.array([np.degrees(30 * 0.5e-3), 0.0])
    assert not ekf.update_azel(z_out, pose)
    assert np.allclose(ekf.x, x_before)
    # v_r outlier likewise
    assert ekf.update_vr(float(np.zeros(1)[0]), pose)  # v=0, consistent
    x_before = ekf.x.copy()
    assert not ekf.update_vr(40.0, pose)               # ~270 sigma
    assert np.allclose(ekf.x, x_before)
