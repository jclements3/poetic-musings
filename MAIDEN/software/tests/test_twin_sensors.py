"""maiden11: forward sensor models (lesson 07)."""

import numpy as np

from maiden.geo import Pose
from maiden.twin import sensors
from maiden.twin.model import sportsman


def _static_truth(pos, vel, dur=10.0, hz=100.0):
    from maiden.twin.model import Truth

    t = np.arange(0.0, dur, 1.0 / hz)
    p = np.asarray(pos) + np.outer(t, np.asarray(vel))
    v = np.tile(np.asarray(vel, float), (len(t), 1))
    return Truth(t, p, v, np.zeros((len(t), 3)))


def test_boresight_spot_check():
    """Target dead on A's boresight, receding at 10 m/s, zero noise."""
    pose = Pose((0.0, 0.0, 0.0), heading_deg=12.4, boresight_el_deg=8.0)
    h, e = np.radians(12.4), np.radians(8.0)
    u = np.array([np.sin(h) * np.cos(e), np.cos(h) * np.cos(e), np.sin(e)])
    truth = _static_truth(150.0 * u, 10.0 * u)

    old_th, old_vr = sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR
    sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR = 0.0, 0.0
    try:
        s = sensors.observe(truth, pose, rng=np.random.default_rng(0),
                            dropout_p=0.0)
    finally:
        sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR = old_th, old_vr

    assert np.allclose(s.tracker[:, 1], 0.0, atol=1e-9)      # az = 0
    assert np.allclose(s.tracker[:, 2], 8.0, atol=1e-9)      # el = boresight
    assert np.allclose(s.radar[:, 1], 10.0, atol=1e-9)       # +10 receding


def test_noise_matches_declared_sigma():
    """Sample std within [0.7, 1.3]x of the named constants."""
    pose = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
    truth = sportsman(seed=3)
    rng = np.random.default_rng(7)
    noisy = sensors.observe(truth, pose, rng=rng, dropout_p=0.0)

    old_th, old_vr = sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR
    sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR = 0.0, 0.0
    try:
        clean = sensors.observe(truth, pose,
                                rng=np.random.default_rng(7), dropout_p=0.0)
    finally:
        sensors.SIGMA_THETA_RAD, sensors.SIGMA_VR = old_th, old_vr

    az_err = np.radians(noisy.tracker[:, 1] - clean.tracker[:, 1])
    vr_err = noisy.radar[:, 1] - clean.radar[:, 1]
    assert 0.7 * sensors.SIGMA_THETA_RAD < az_err.std() \
        < 1.3 * sensors.SIGMA_THETA_RAD
    assert 0.7 * sensors.SIGMA_VR < vr_err.std() < 1.3 * sensors.SIGMA_VR
    # conf bounded and tied to SNR (higher SNR -> higher conf)
    assert noisy.tracker[:, 3].min() >= 0.5
    assert noisy.tracker[:, 3].max() <= 1.0


def test_dropouts_and_outage_visible():
    pose = Pose((75.0, 0.0, 0.0), 350.0, 8.0)
    truth = sportsman(seed=3)
    dur = truth.t[-1] - truth.t[0]
    full = sensors.observe(truth, pose, rng=np.random.default_rng(1),
                           dropout_p=0.0)
    gappy = sensors.observe(truth, pose, rng=np.random.default_rng(1),
                            dropout_p=0.05, outage=(30.0, 34.0))
    n_full, n_gappy = len(full.tracker), len(gappy.tracker)
    # expected loss: 5% Bernoulli + 4 s x 30 Hz outage
    expected = n_full * 0.95 - 4.0 * sensors.TRACKER_HZ
    assert abs(n_gappy - expected) < 0.02 * n_full
    # outage window truly dark in the tracker stream
    tt = gappy.tracker[:, 0]
    assert not np.any((tt >= 30.0) & (tt <= 34.0))
    # radar unaffected by the (camera) outage: only Bernoulli loss
    assert len(gappy.radar) > 0.9 * dur * sensors.RADAR_HZ * 0.95


def test_streams_unaligned():
    """Tracker, radar, and truth grids must not coincide (lesson 07)."""
    pose = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
    truth = sportsman(seed=0)
    s = sensors.observe(truth, pose, rng=np.random.default_rng(0),
                        dropout_p=0.0)
    common = set(np.round(s.tracker[:, 0], 9)) & set(np.round(truth.t, 9))
    assert not common
    common_r = set(np.round(s.radar[:, 0], 9)) & set(np.round(truth.t, 9))
    assert not common_r
