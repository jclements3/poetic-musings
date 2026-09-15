"""maiden56 — approach analytics, rehearsed against twin truth (VT-22).

The shipped rcrc.yaml runway is PLACEHOLDER_PENDING_SURVEY and does not
lie on the twin's scripted path, so these tests build a fixture runway
ON the twin's approach (threshold at the script's endpoint) — rehearsing
the estimation math; the real geometry arrives with the survey.
"""

import subprocess
import sys

import numpy as np
import pytest

from maiden.approach import approach_metrics, final_leg_mask
from maiden.fuse import fuse_session

SEED = 404


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    d = tmp_path_factory.mktemp("twin") / "s404"
    subprocess.run([sys.executable, "-m", "maiden.twin", "--out", str(d),
                    "--seed", str(SEED), "--imperfect"], check=True)
    (fused, _stats), stations = fuse_session(d)
    truth = np.load(d / "truth.npz", allow_pickle=True)
    return d, fused, stations, truth


def _truth_approach(truth):
    """Scripted approach window from truth arrays: the contiguous final
    stretch of monotone descent ending at the script's last sample."""
    t = truth["t"] + float(truth["epoch_utc"])
    pos = truth["pos_enu"]
    vel = truth["vel_enu"]
    vU = vel[:, 2]
    i = len(t) - 1
    while i > 0 and vU[i - 1] <= 0.05:
        i -= 1
    return t[i:], pos[i:], vel[i:]


def _fixture_field(truth):
    _tt, tp, tv = _truth_approach(truth)
    heading = float(np.degrees(np.arctan2(tv[-1, 0], tv[-1, 1])))
    return {
        "runway": {
            "status": "TEST_FIXTURE_ON_TWIN_PATH",
            "heading_deg": heading,
            "ground_height_m": 0.0,
            "threshold_enu": [float(tp[-1, 0]), float(tp[-1, 1])],
            "target_enu": [float(tp[-1, 0]) + 30.0, float(tp[-1, 1])],
        }
    }


def test_final_leg_found(session):
    _d, fused, _stations, truth = session
    fld = _fixture_field(truth)
    t = np.array([s.t_utc for s in fused])
    pos = np.array([s.pos_enu for s in fused])
    vel = np.array([s.vel_enu for s in fused])
    m = final_leg_mask(t, pos, vel, fld["runway"])
    assert m.sum() > 200                       # multi-second leg at 50 Hz
    tt, _, _ = _truth_approach(truth)
    assert abs(t[m][-1] - tt[-1]) < 2.0        # ends where the script ends


def test_glideslope_matches_script(session):
    _d, fused, _stations, truth = session
    fld = _fixture_field(truth)
    ap = approach_metrics(fused, [], fld)
    assert ap is not None
    # scripted glideslope from the truth arrays over the SAME window the
    # estimator chose — this compares estimation quality, not window
    # choice (the twin's cosine-blended altitude profile is nonlinear,
    # so different windows legitimately fit different mean slopes)
    tt, tp, _tv = _truth_approach(truth)
    w = (tt >= ap.final_leg[0]) & (tt <= ap.final_leg[1])
    thr = np.asarray(fld["runway"]["threshold_enu"])
    dd = np.linalg.norm(tp[w, :2] - thr, axis=1)
    slope = np.polyfit(dd, tp[w, 2], 1)[0]
    gs_script = np.degrees(np.arctan(slope))
    assert ap.glideslope_deg == pytest.approx(gs_script, abs=0.5)
    assert 0 < ap.glideslope_se_deg < 0.5      # a band, and a sane one
    assert ap.glideslope_deg > 0               # descending toward threshold


def test_threshold_speed_within_1mps_of_truth(session):
    """The VT-22 number, rehearsed (binding test is the campaign)."""
    _d, fused, _stations, truth = session
    fld = _fixture_field(truth)
    ap = approach_metrics(fused, [], fld)
    tt, _tp, tv = _truth_approach(truth)
    # truth speed at the time the estimate was taken
    ap.final_leg[1] if ap.threshold_speed_mps else None
    speeds = np.linalg.norm(tv, axis=1)
    v_truth = float(np.interp(ap.touchdown_t if ap.touchdown_t else tt[-1],
                              tt, speeds))
    assert abs(ap.threshold_speed_mps - v_truth) <= 1.0


def test_c_radar_crosscheck(session):
    d, fused, stations, truth = session
    from maiden.ingest import load
    c_samples = [s for s in load(next(d.glob("STATION_C_*.ch10")))]
    fld = _fixture_field(truth)
    ap = approach_metrics(fused, [], fld, c_samples=c_samples,
                          c_pose=stations["C"])
    # cross-check present and inside the same 1 m/s envelope, OR honestly
    # refused for oblique geometry (twin C aims at the box, not the
    # fixture threshold; both outcomes are legitimate)
    if ap.threshold_speed_c_mps is not None:
        assert abs(ap.crosscheck_delta_mps) <= 1.0
    else:
        assert any("oblique" in n or "cross-check" in n for n in ap.notes)


def test_touchdown_extrapolated_and_scattered(session):
    _d, fused, _stations, truth = session
    fld = _fixture_field(truth)
    ap = approach_metrics(fused, [], fld)
    # twin script ends airborne at ~5 m: the detector must say so
    assert ap.touchdown_extrapolated
    assert ap.touchdown_enu is not None
    _tt, tp, _ = _truth_approach(truth)
    # extrapolated point lands within ~40 m of the script's endpoint,
    # further along the same track
    assert np.hypot(ap.touchdown_enu[0] - tp[-1, 0],
                    ap.touchdown_enu[1] - tp[-1, 1]) < 40.0
    assert len(ap.scatter_enu) == 1


def test_no_landing_returns_none(session):
    _d, fused, _stations, truth = session
    fld = _fixture_field(truth)
    tt, _, _ = _truth_approach(truth)
    early = [s for s in fused if s.t_utc < tt[0] - 5.0]
    assert approach_metrics(early, [], fld) is None
