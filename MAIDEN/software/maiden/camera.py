"""Pixel -> direction geometry for MAIDEN stations (lesson 09).

THE PINNED ANGLE CONVENTION (cited by state.py, twin.sensors, the EKF):

- ``az_deg`` — azimuth of a ray, **clockwise from true north**, in the
  station's local ENU frame: ``az = atan2(E, N)`` (degrees).
- ``el_deg`` — elevation above the local horizontal: ``el = asin(U)``
  for a unit ray (degrees).

Camera frame: X right, Y down, Z out the lens.  With heading 0 and
boresight elevation 0 the camera looks true north, so X_cam -> E,
Y_cam -> -U, Z_cam -> N.  The full chain is

    ray_enu = R_U(heading) . R_E(boresight_el) . P . ray_cam

with P the fixed permutation above; heading rotates clockwise from
north (E' = E cos h + N sin h), boresight elevation tips the optical
axis up.  Distortion (Brown k1, k2) applies in *normalized* image
coordinates, before the fx/cx scaling — see lesson 09 for why the
order matters and what its violation looks like.
"""

from dataclasses import dataclass

import numpy as np


def _rot_enu(pose):
    """3x3 matrix taking camera-frame vectors to ENU (columns = axes)."""
    h = np.radians(pose.heading_deg)
    e = np.radians(pose.boresight_el_deg)
    # P: cam (x, y, z) -> ENU (x, -y up, z north) => columns of P
    perm = np.array([[1.0, 0.0, 0.0],
                     [0.0, 0.0, 1.0],
                     [0.0, -1.0, 0.0]])
    r_e = np.array([[1.0, 0.0, 0.0],
                    [0.0, np.cos(e), -np.sin(e)],
                    [0.0, np.sin(e), np.cos(e)]])
    r_u = np.array([[np.cos(h), np.sin(h), 0.0],
                    [-np.sin(h), np.cos(h), 0.0],
                    [0.0, 0.0, 1.0]])
    return r_u @ r_e @ perm


@dataclass(frozen=True)
class CameraModel:
    fx: float
    fy: float
    cx: float
    cy: float
    k1: float = 0.0
    k2: float = 0.0

    @classmethod
    def from_tmats(cls, cam_attrs) -> "CameraModel":
        """Build from a TMATS C\\MAIDEN\\CAM attribute dict (IF-2 names,
        lowercased by maiden.tmats.parse_station)."""
        a = {k.lower(): v for k, v in dict(cam_attrs).items()}
        return cls(fx=float(a["fx"]), fy=float(a["fy"]),
                   cx=float(a["cx"]), cy=float(a["cy"]),
                   k1=float(a.get("k1") or 0.0), k2=float(a.get("k2") or 0.0))

    def _distort(self, x, y):
        r2 = x * x + y * y
        f = 1.0 + self.k1 * r2 + self.k2 * r2 * r2
        return x * f, y * f

    def undistort(self, u, v):
        """Pixel -> normalized coords with distortion removed
        (3 fixed-point iterations; adequate at k1 ~ -0.1)."""
        xd = (np.asarray(u, dtype=float) - self.cx) / self.fx
        yd = (np.asarray(v, dtype=float) - self.cy) / self.fy
        x, y = xd, yd
        for _ in range(3):
            r2 = x * x + y * y
            f = 1.0 + self.k1 * r2 + self.k2 * r2 * r2
            x, y = xd / f, yd / f
        return x, y

    def px_to_ray_cam(self, u, v) -> np.ndarray:
        """Unit ray(s) in the camera frame (X right, Y down, Z out).
        Shape (..., 3)."""
        x, y = self.undistort(u, v)
        ray = np.stack(np.broadcast_arrays(x, y, np.ones_like(x)), axis=-1)
        return ray / np.linalg.norm(ray, axis=-1, keepdims=True)


def px_to_azel(model: CameraModel, pose, u, v):
    """Pixel(s) -> (az_deg, el_deg) per THE convention (module docstring)."""
    ray = model.px_to_ray_cam(u, v) @ _rot_enu(pose).T
    az = np.degrees(np.arctan2(ray[..., 0], ray[..., 1]))
    el = np.degrees(np.arcsin(np.clip(ray[..., 2], -1.0, 1.0)))
    return az, el


def azel_to_px(model: CameraModel, pose, az_deg, el_deg):
    """(az, el) -> pixel(s); None (scalar) / NaN (array) behind the camera."""
    az = np.radians(np.asarray(az_deg, dtype=float))
    el = np.radians(np.asarray(el_deg, dtype=float))
    ray_enu = np.stack(np.broadcast_arrays(
        np.cos(el) * np.sin(az), np.cos(el) * np.cos(az), np.sin(el)),
        axis=-1)
    ray_cam = ray_enu @ _rot_enu(pose)          # R.T applied row-wise
    z = ray_cam[..., 2]
    scalar = np.ndim(z) == 0
    if scalar and z <= 0:
        return None
    with np.errstate(divide="ignore", invalid="ignore"):
        x = np.where(z > 0, ray_cam[..., 0] / z, np.nan)
        y = np.where(z > 0, ray_cam[..., 1] / z, np.nan)
    xd, yd = model._distort(x, y)
    u = model.fx * xd + model.cx
    v = model.fy * yd + model.cy
    if scalar:
        return float(u), float(v)
    return u, v
