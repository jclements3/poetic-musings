"""maiden20: Kalman2D unit tests — statics, ramps, whiteness, gating."""

import numpy as np

from maiden.track.kalman2d import Kalman2D

DT = 1.0 / 30.0
RNG = np.random.default_rng(20260821)


def _run_cv(kf, z0, vel, n, sigma, rng):
    """Feed a noisy constant-velocity target; return per-step NIS."""
    kf.start(z0)
    nis = []
    truth = np.asarray(z0, dtype=float)
    for _ in range(n):
        truth = truth + np.asarray(vel) * DT
        kf.predict()
        nis.append(kf.update(truth + rng.normal(0, sigma, 2)))
    return np.array(nis)


def test_static_target_converges():
    kf = Kalman2D(DT, q=10.0, sigma_px=1.0)
    _run_cv(kf, (100.0, 50.0), (0.0, 0.0), 200, 1.0, RNG)
    u, v = kf.uv
    assert abs(u - 100.0) < 1.0 and abs(v - 50.0) < 1.0
    assert abs(kf.x[2]) < 2.0 and abs(kf.x[3]) < 2.0
    assert kf.P[0, 0] < 1.0        # position variance well under R after 200


def test_ramp_tracked_without_lag_bias():
    kf = Kalman2D(DT, q=100.0, sigma_px=1.0)
    _run_cv(kf, (0.0, 0.0), (90.0, -30.0), 300, 1.0, RNG)
    assert abs(kf.x[2] - 90.0) < 5.0 and abs(kf.x[3] + 30.0) < 5.0


def test_innovation_whiteness_nis_chi2():
    """On a matched model the NIS is chi^2 with 2 dof: mean ~2.

    95% band for the mean of 600 draws of chi2_2 is ~2 +/- 0.23; we take
    3 sigma. A fat-tailed NIS here would mean Q lies about maneuvers —
    lesson 11 Explore 1's gate autopsy in miniature.
    """
    kf = Kalman2D(DT, q=50.0, sigma_px=1.5)
    nis = _run_cv(kf, (10.0, 10.0), (60.0, 20.0), 620, 1.5, RNG)[20:]
    assert abs(nis.mean() - 2.0) < 3.0 * np.sqrt(4.0 / len(nis))
    assert np.quantile(nis, 0.99) < 12.0   # chi2_2 99% = 9.21, slack for finite n


def test_missed_update_inflates_p_and_regates():
    """Coasting grows P as q*t^3/3, so a fixed-offset reacquisition's
    Mahalanobis falls monotonically until it gates back in — the property
    that carries a track through the sun-crossing dip (lesson 11)."""
    kf = Kalman2D(DT, q=100.0, sigma_px=1.0)
    _run_cv(kf, (0.0, 0.0), (60.0, 0.0), 100, 1.0, RNG)
    p_before = kf.P[0, 0]
    m_before = kf.mahalanobis((kf.uv[0] + 8.0, kf.uv[1]))
    m_prev, m_last = m_before, m_before
    for _ in range(45):                    # 1.5 s coast: predict only
        kf.predict()
        m_last = kf.mahalanobis((kf.uv[0] + 8.0, kf.uv[1]))
        assert m_last <= m_prev + 1e-9
        m_prev = m_last
    assert kf.P[0, 0] > 50.0 * p_before
    assert m_before > 9.21 > m_last        # rejected then, gates in now


def test_gate_rejects_wild_measurement_when_confident():
    kf = Kalman2D(DT, q=10.0, sigma_px=1.0)
    _run_cv(kf, (0.0, 0.0), (30.0, 10.0), 200, 1.0, RNG)
    z = (kf.uv[0] + 25.0, kf.uv[1] - 25.0)
    assert kf.mahalanobis(z) > 9.21
