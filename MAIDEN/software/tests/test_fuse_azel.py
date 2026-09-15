"""maiden22: EKF core — Jacobians vs finite differences, init, wrap."""

import numpy as np
import pytest

from maiden.fuse import (
    Ekf,
    EkfConfig,
    azel_to_unit,
    h_azel,
    jac_azel,
    jac_vr,
)
from maiden.geo import Pose
from maiden.twin.sensors import vr_from_state

RNG = np.random.default_rng(20260821)


def _random_pose(rng):
    return Pose((float(rng.uniform(-100, 100)), float(rng.uniform(-100, 100)),
                 float(rng.uniform(-5, 5))),
                float(rng.uniform(0, 360)))


def _random_state(rng, pose):
    # keep the target well off the station (rho > 20 m) so J is well-scaled
    az, el = rng.uniform(-np.pi, np.pi), rng.uniform(-0.4, 1.2)
    rng_m = rng.uniform(30, 300)
    p = (np.asarray(pose.pos_enu)
         + rng_m * np.array([np.cos(el) * np.sin(az),
                             np.cos(el) * np.cos(az), np.sin(el)]))
    v = rng.normal(0, 20, 3)
    return np.concatenate([p, v])


def test_jacobian_azel():
    """Analytic H vs central finite differences, 1e-6 relative. Mandatory."""
    eps = 1e-4
    for _ in range(50):
        pose = _random_pose(RNG)
        x = _random_state(RNG, pose)
        h_an = jac_azel(x[:3], pose)
        h_fd = np.zeros((2, 6))
        for j in range(3):
            dp = np.zeros(3)
            dp[j] = eps
            hi = h_azel(x[:3] + dp, pose)
            lo = h_azel(x[:3] - dp, pose)
            d = hi - lo
            d[0] = (d[0] + np.pi) % (2 * np.pi) - np.pi
            h_fd[:, j] = d / (2 * eps)
        scale = np.abs(h_an).max()
        assert np.allclose(h_an, h_fd, atol=1e-6 * max(scale, 1.0)), (
            f"azel Jacobian mismatch:\n{h_an}\nvs FD\n{h_fd}")
        assert np.allclose(h_an[:, 3:], 0.0)  # h depends on position only


def test_jacobian_vr_position_block():
    """maiden24's mandatory FD check — the position block is the point."""
    eps = 1e-4
    for _ in range(50):
        pose = _random_pose(RNG)
        x = _random_state(RNG, pose)
        h_an = jac_vr(x, pose)
        h_fd = np.zeros((1, 6))
        for j in range(6):
            dx = np.zeros(6)
            dx[j] = eps
            hi = vr_from_state((x + dx)[:3].reshape(1, 3),
                               (x + dx)[3:].reshape(1, 3), pose)[0]
            lo = vr_from_state((x - dx)[:3].reshape(1, 3),
                               (x - dx)[3:].reshape(1, 3), pose)[0]
            h_fd[0, j] = (hi - lo) / (2 * eps)
        assert np.allclose(h_an, h_fd, atol=1e-6 * max(1.0, np.abs(h_an).max()))
        # the "term everyone forgets" is genuinely nonzero for crossing targets
    x = np.array([100.0, 100.0, 30.0, 0.0, 30.0, 0.0])
    pose = Pose((0.0, 0.0, 0.0), 0.0)
    assert np.abs(jac_vr(x, pose)[0, :3]).max() > 1e-3


def test_azel_unit_roundtrip():
    for _ in range(20):
        pose = _random_pose(RNG)
        x = _random_state(RNG, pose)
        az, el = np.degrees(h_azel(x[:3], pose))
        u = azel_to_unit(az, el, pose)
        d = x[:3] - np.asarray(pose.pos_enu)
        assert np.allclose(u, d / np.linalg.norm(d), atol=1e-12)


def test_init_two_ray_zero_noise():
    pa = Pose((0.0, 0.0, 0.0), 12.4)
    pb = Pose((73.0, -17.0, 0.5), 350.0)
    target = np.array([40.0, 148.0, 55.0])
    ekf = Ekf()
    za = np.degrees(h_azel(target, pa))
    zb = np.degrees(h_azel(target, pb))
    assert ekf.init_two_ray(za, zb, pa, pb, t=0.0)
    assert np.allclose(ekf.state[:3], target, atol=1e-9)
    assert np.allclose(ekf.state[3:], 0.0)
    assert ekf.cov.shape == (6, 6)


def test_init_two_ray_noise_matches_d3():
    """0.5 mrad at R~150 m, B=75 m -> error of order sigma_range ~ 0.15 m."""
    pa = Pose((0.0, 0.0, 0.0), 0.0)
    pb = Pose((75.0, 0.0, 0.0), 0.0)
    target = np.array([20.0, 150.0, 50.0])
    sig = np.degrees(0.5e-3)
    rng = np.random.default_rng(7)
    errs = []
    for _ in range(500):
        ekf = Ekf()
        za = np.degrees(h_azel(target, pa)) + rng.normal(0, sig, 2)
        zb = np.degrees(h_azel(target, pb)) + rng.normal(0, sig, 2)
        assert ekf.init_two_ray(za, zb, pa, pb, t=0.0)
        errs.append(np.linalg.norm(ekf.state[:3] - target))
    rms = float(np.sqrt(np.mean(np.square(errs))))
    # D3: sigma_range ~ R^2 sigma_theta / B = 0.15 m; full 3D error a bit
    # larger (cross-range + el). "Of order" = within [0.05, 0.75] m.
    assert 0.05 < rms < 0.75, rms


def test_init_parallel_rays_guarded():
    pa = Pose((0.0, 0.0, 0.0), 0.0)
    pb = Pose((75.0, 0.0, 0.0), 0.0)
    # target on the baseline extension: rays (nearly) parallel from A and B
    target = np.array([5000.0, 0.0, 0.0])
    ekf = Ekf()
    za = np.degrees(h_azel(target, pa))
    zb = np.degrees(h_azel(target, pb))
    assert not ekf.init_two_ray(za, zb, pa, pb, t=0.0)
    assert ekf.x is None


def test_az_innovation_wrap():
    """A predicted az of +179 deg vs measured -179 deg is a 2-deg error,
    not 358. Without the wrap this update launches the state; with it the
    correction stays small."""
    pose = Pose((0.0, 0.0, 0.0), 0.0)
    ekf = Ekf(EkfConfig())
    # target almost due south (az ~ +-180)
    p = np.array([-1.0, -200.0, 30.0])      # az just past -180 side
    ekf.x = np.concatenate([p, np.zeros(3)])
    ekf.p = np.diag([1.0] * 3 + [1.0] * 3)
    ekf.t = 0.0
    z = np.degrees(h_azel(np.array([1.0, -200.0, 30.0]), pose))  # +180 side
    assert ekf.update_azel(z, pose, gated=False)
    # correction must be ~2 m sideways, not a teleport
    assert np.linalg.norm(ekf.x[:3] - p) < 5.0


def test_predict_shapes_and_growth():
    ekf = Ekf()
    ekf.x = np.zeros(6)
    ekf.p = np.eye(6)
    ekf.t = 0.0
    ekf.predict(0.1)
    assert ekf.x.shape == (6,) and ekf.p.shape == (6, 6)
    assert np.trace(ekf.p) > 6.0            # Q grew it
    with pytest.raises(ValueError):
        ekf.predict(0.0)
