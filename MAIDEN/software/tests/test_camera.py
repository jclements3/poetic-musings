"""maiden16: camera model round-trips, convention anchors, TMATS loop."""

import numpy as np
import pytest

from maiden.camera import CameraModel, azel_to_px, px_to_azel
from maiden.geo import Pose
from maiden.tmats import parse_station

TEMPLATE = "config/tmats/station.tmt"

M0 = CameraModel(fx=1663.0, fy=1663.0, cx=960.0, cy=540.0)
MD = CameraModel(fx=1663.0, fy=1663.0, cx=960.0, cy=540.0, k1=-0.112, k2=0.041)
POSE = Pose(pos_enu=(0.0, 0.0, 0.0), heading_deg=0.0, boresight_el_deg=0.0)


def _grid(model, pose, n=7, span=20.0):
    az0, el0 = pose.heading_deg, pose.boresight_el_deg
    az = az0 + np.linspace(-span, span, n)
    el = el0 + np.linspace(-span / 2, span / 2, n)
    return np.meshgrid(az, el)


@pytest.mark.parametrize("model,tol_deg", [(M0, 1e-6), (MD, 1e-3)])
def test_round_trip(model, tol_deg):
    az, el = _grid(model, POSE)
    u, v = azel_to_px(model, POSE, az, el)
    az2, el2 = px_to_azel(model, POSE, u, v)
    assert np.nanmax(np.abs(az2 - az)) < tol_deg
    assert np.nanmax(np.abs(el2 - el)) < tol_deg


def test_convention_anchor_north():
    az, el = px_to_azel(M0, POSE, M0.cx, M0.cy)
    assert abs(float(az)) < 1e-9 and abs(float(el)) < 1e-9


def test_convention_anchor_east():
    pose = Pose(pos_enu=(0.0, 0.0, 0.0), heading_deg=90.0, boresight_el_deg=0.0)
    az, el = px_to_azel(M0, pose, M0.cx, M0.cy)
    assert abs(float(az) - 90.0) < 1e-9 and abs(float(el)) < 1e-9


def test_boresight_el_anchor():
    pose = Pose(pos_enu=(0.0, 0.0, 0.0), heading_deg=0.0, boresight_el_deg=8.0)
    az, el = px_to_azel(M0, pose, M0.cx, M0.cy)
    assert abs(float(az)) < 1e-9 and abs(float(el) - 8.0) < 1e-9


def test_behind_camera_is_none():
    assert azel_to_px(M0, POSE, 180.0, 0.0) is None
    u, v = azel_to_px(M0, POSE, np.array([0.0, 180.0]), np.array([0.0, 0.0]))
    assert np.isfinite(u[0]) and np.isnan(u[1]) and np.isnan(v[1])


def test_tmats_loop():
    with open(TEMPLATE) as f:
        st = parse_station(f.read())
    m = CameraModel.from_tmats(st.cam)
    assert (m.fx, m.fy, m.cx, m.cy) == (1820.4, 1819.9, 960.2, 541.7)
    assert (m.k1, m.k2) == (-0.112, 0.041)
