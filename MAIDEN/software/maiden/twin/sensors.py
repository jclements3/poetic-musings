"""Forward sensor models: truth -> per-station measurements. SW-004.

Geometry per lesson 07 / D3 Figure 2; az/el convention pinned in lesson
09: az clockwise from true north, el above local horizontal. `observe`
returns *station-frame* azimuth (true az minus survey heading), so a
target on the boresight reads az = 0.

The sun-crossing outage silences the TRACKER stream only — sun blinds a
camera; the CW radar does not care.
"""
from dataclasses import dataclass

import numpy as np

from maiden.geo import Pose

# --- noise constants, with provenance (nothing magic) -----------------------
# D3 assumed tracker accuracy (~0.5 px through a 60-deg lens at 1080p;
# lesson 09 derives it). Revisit after VT-15 measures the real tracker.
SIGMA_THETA_RAD = 0.5e-3
# Half of VT-04's bench criterion (|error| <= 0.3 m/s); revisit after
# lesson 17 measures the real Doppler chain.
SIGMA_VR = 0.15                  # m/s
# SNR model for the conf/snr proxies: 20 dB at the 150 m box center,
# falling 20*log10(R/150) — free-space-ish, tuned only for plausibility.
SNR0_DB, SNR_R0_M = 20.0, 150.0
SIGMA_SNR_DB = 2.0
# Per-sample Bernoulli dropout default (D6 "optional drop-outs").
DROPOUT_P = 0.01
TRACKER_HZ, RADAR_HZ = 30.0, 50.0
# Deliberately unaligned stream phases (fractions of a sample period):
# tracker/radar/truth clocks must never coincide (lesson 07 rates rule).
TRACKER_PHASE, RADAR_PHASE = 0.37, 0.61


@dataclass(frozen=True)
class StationStreams:
    """One station's measurement streams (times in truth-sequence seconds)."""

    tracker: np.ndarray   # (M, 4): t, az_deg (station frame), el_deg, conf
    radar: np.ndarray     # (K, 3): t, v_r (m/s, + receding), snr_db


def _wrap_deg(a):
    return (np.asarray(a) + 180.0) % 360.0 - 180.0


def azel_from_pos(p, pose: Pose):
    """True-north az / horizontal el (deg) of point(s) p from a station."""
    d = np.atleast_2d(p) - np.asarray(pose.pos_enu)
    az_true = np.degrees(np.arctan2(d[:, 0], d[:, 1]))     # CW from N
    el = np.degrees(np.arctan2(d[:, 2], np.hypot(d[:, 0], d[:, 1])))
    return az_true, el


def station_azel(p, pose: Pose):
    """Station-frame az (relative to survey heading) and el."""
    az_true, el = azel_from_pos(p, pose)
    return _wrap_deg(az_true - pose.heading_deg), el


def vr_from_state(p, v, pose: Pose):
    """Radial velocity v . u_hat, positive = receding (theremin sign)."""
    d = np.atleast_2d(p) - np.asarray(pose.pos_enu)
    u = d / np.linalg.norm(d, axis=1, keepdims=True)
    return np.sum(np.atleast_2d(v) * u, axis=1)


def _interp(t_out, t_in, arr):
    return np.column_stack([np.interp(t_out, t_in, arr[:, i])
                            for i in range(arr.shape[1])])


def _snr_db(rng, p, pose):
    r = np.linalg.norm(np.atleast_2d(p) - np.asarray(pose.pos_enu), axis=1)
    return (SNR0_DB - 20.0 * np.log10(r / SNR_R0_M)
            + rng.normal(0.0, SIGMA_SNR_DB, r.shape))


def observe(truth, pose: Pose, *, rng, dropout_p: float = DROPOUT_P,
            outage: tuple[float, float] | None = None) -> StationStreams:
    """Project truth through one station's pose into noisy streams.

    `outage` is a (t0, t1) window (seconds) during which the tracker
    stream goes dark — the scripted Station B sun crossing when the twin
    session assembles the default layout (see twin.writer).
    """
    t0, t1 = truth.t[0], truth.t[-1]

    # tracker stream: 30 Hz, phase-offset, station-frame az/el + conf
    tt = np.arange(t0 + TRACKER_PHASE / TRACKER_HZ, t1, 1.0 / TRACKER_HZ)
    pos = _interp(tt, truth.t, truth.pos_enu)
    az, el = station_azel(pos, pose)
    sig_deg = np.degrees(SIGMA_THETA_RAD)
    az = az + rng.normal(0.0, sig_deg, az.shape)
    el = el + rng.normal(0.0, sig_deg, el.shape)
    snr_t = _snr_db(rng, pos, pose)
    # conf in [0.5, 1.0], tied to the SNR proxy (0 dB -> 0.5, 20 dB -> 1.0)
    conf = np.clip(0.5 + 0.025 * snr_t, 0.5, 1.0)
    keep = rng.random(tt.shape) >= dropout_p
    if outage is not None:
        keep &= ~((tt >= outage[0]) & (tt <= outage[1]))
    tracker = np.column_stack([tt, az, el, conf])[keep]

    # radar stream: 50 Hz, different phase, v_r + snr
    tr = np.arange(t0 + RADAR_PHASE / RADAR_HZ, t1, 1.0 / RADAR_HZ)
    pos_r = _interp(tr, truth.t, truth.pos_enu)
    vel_r = _interp(tr, truth.t, truth.vel_enu)
    v_r = vr_from_state(pos_r, vel_r, pose) + rng.normal(0.0, SIGMA_VR,
                                                         tr.shape)
    snr_r = _snr_db(rng, pos_r, pose)
    keep_r = rng.random(tr.shape) >= dropout_p
    radar = np.column_stack([tr, v_r, snr_r])[keep_r]

    return StationStreams(tracker=tracker, radar=radar)
