"""Field frame: WGS-84 LLA -> ECEF -> local ENU (D4 IF-4).

Origin of the field frame is Station A's survey mark; axes are geodetic
East-North-Up. Station survey headings live in Pose, not in the frame.
"""
from dataclasses import dataclass

import numpy as np

WGS84_A = 6378137.0
WGS84_F = 1.0 / 298.257223563
WGS84_E2 = WGS84_F * (2.0 - WGS84_F)


def ecef_from_lla(lla) -> np.ndarray:
    """(lat_deg, lon_deg, alt_m) -> ECEF [X, Y, Z] meters."""
    lat, lon, h = np.radians(lla[0]), np.radians(lla[1]), lla[2]
    sin_lat, cos_lat = np.sin(lat), np.cos(lat)
    n = WGS84_A / np.sqrt(1.0 - WGS84_E2 * sin_lat**2)
    return np.array([
        (n + h) * cos_lat * np.cos(lon),
        (n + h) * cos_lat * np.sin(lon),
        (n * (1.0 - WGS84_E2) + h) * sin_lat,
    ])


def enu_from_lla(origin_lla, lla) -> np.ndarray:
    """Exact ENU meters of `lla` relative to `origin_lla`."""
    lat0, lon0 = np.radians(origin_lla[0]), np.radians(origin_lla[1])
    d = ecef_from_lla(lla) - ecef_from_lla(origin_lla)
    sin_p, cos_p = np.sin(lat0), np.cos(lat0)
    sin_l, cos_l = np.sin(lon0), np.cos(lon0)
    rot = np.array([
        [-sin_l,          cos_l,          0.0],
        [-sin_p * cos_l, -sin_p * sin_l,  cos_p],
        [ cos_p * cos_l,  cos_p * sin_l,  sin_p],
    ])
    return rot @ d


@dataclass(frozen=True)
class Pose:
    """A station's surveyed pose in the field frame (D4 IF-2 survey group)."""
    pos_enu: tuple          # (E, N, U) meters
    heading_deg: float      # sighting-rail azimuth, true north = 0, CW +
    boresight_el_deg: float = 0.0
