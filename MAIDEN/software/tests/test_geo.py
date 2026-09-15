"""Known-answer tests for the field frame (lesson 01 / maiden02)."""
from pathlib import Path

import numpy as np
import yaml

from maiden.geo import WGS84_A, WGS84_E2, Pose, enu_from_lla

ORIGIN = (34.6851710, -86.5922440, 183.2)  # Station A survey mark


def _n_radius(lat_deg: float) -> float:
    sin_lat = np.sin(np.radians(lat_deg))
    return WGS84_A / np.sqrt(1.0 - WGS84_E2 * sin_lat**2)


def _flat_earth(origin, lla) -> np.ndarray:
    """Small-displacement approximation used as the intuition oracle."""
    lat0 = np.radians(origin[0])
    n = _n_radius(origin[0])
    # Meridional radius of curvature for the North axis.
    m = WGS84_A * (1.0 - WGS84_E2) / (1.0 - WGS84_E2 * np.sin(lat0) ** 2) ** 1.5
    de = np.radians(lla[1] - origin[1]) * (n + origin[2]) * np.cos(lat0)
    dn = np.radians(lla[0] - origin[0]) * (m + origin[2])
    # First-order meridian-convergence cross-term: cos(lat) shrinks as the
    # point moves north, so a fixed dlon spans less East up there.
    de = de * (1.0 - dn * np.tan(lat0) / (n + origin[2]))
    # Up must include the curvature sag d^2/2R (~6 mm at 270 m) or the
    # 5 mm agreement claim fails on Up alone at the box edge.
    d2 = de * de + dn * dn
    du = (lla[2] - origin[2]) - d2 / (2.0 * WGS84_A)
    return np.array([de, dn, du])


def test_known_answer_one_degree_longitude():
    """1 deg of longitude at RCRC latitude, oracle computed from formula."""
    d_lon = 0.001
    point = (ORIGIN[0], ORIGIN[1] + d_lon, ORIGIN[2])
    oracle_e = (
        np.radians(d_lon)
        * (_n_radius(ORIGIN[0]) + ORIGIN[2])
        * np.cos(np.radians(ORIGIN[0]))
    )
    enu = enu_from_lla(ORIGIN, point)
    assert abs(enu[0] - oracle_e) < 0.02
    assert abs(enu[1]) < 0.02  # tiny meridian convergence only
    assert abs(enu[2]) < 0.02
    # The full degree, scaled, lands near the lesson's quoted ~91,671 m —
    # which is itself rounded/approximate (the exact (N+h)cosphi value is
    # ~91,639 m), so this deserves a loose tolerance, per the lesson's own
    # warning about rounded oracles.
    assert abs(oracle_e * 1000.0 - 91671.0) < 50.0


def test_flat_earth_agreement_within_300m():
    rng = np.random.default_rng(1)
    for _ in range(200):
        # "within 300 m of the origin" = a 300 m radius disc, not a box.
        r = 300.0 * np.sqrt(rng.uniform())
        theta = rng.uniform(0.0, 2.0 * np.pi)
        de, dn = r * np.cos(theta), r * np.sin(theta)
        dh = rng.uniform(-50.0, 50.0)
        lat = ORIGIN[0] + dn / 111132.0
        lon = ORIGIN[1] + de / (
            (_n_radius(ORIGIN[0]) + ORIGIN[2])
            * np.cos(np.radians(ORIGIN[0]))
            * np.pi
            / 180.0
        ) / 1.0
        point = (lat, lon, ORIGIN[2] + dh)
        exact = enu_from_lla(ORIGIN, point)
        approx = _flat_earth(ORIGIN, point)
        assert np.all(np.abs(exact - approx) < 5e-3)


def test_origin_and_symmetry():
    assert np.all(np.abs(enu_from_lla(ORIGIN, ORIGIN)) < 1e-9)
    point = (ORIGIN[0] + 100.0 / 111132.0, ORIGIN[1], ORIGIN[2])
    fwd = enu_from_lla(ORIGIN, point)
    rev = enu_from_lla(point, ORIGIN)
    # Swapping origin/point negates E and N to first order (curvature
    # residual over 100 m stays under 1 mm).
    assert np.all(np.abs(fwd[:2] + rev[:2]) < 1e-3)


def test_rcrc_yaml_parses_with_station_a_values():
    cfg = yaml.safe_load(
        (Path(__file__).parents[2] / "config/field/rcrc.yaml").read_text()
    )
    a = cfg["stations"]["A"]
    assert a["lla"] == [34.6851710, -86.5922440, 183.2]
    assert a["heading_deg"] == 12.4
    assert cfg["stations"]["B"]["lla"] is None
    assert cfg["stations"]["C"]["lla"] is None
    pose = Pose(tuple(enu_from_lla(ORIGIN, a["lla"])), a["heading_deg"],
                a["boresight_el_deg"])
    assert pose.heading_deg == 12.4
