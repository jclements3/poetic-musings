"""Repro: emit.py must produce STATION-FRAME az (the ecosystem contract:
twin.writer writes station-frame, ingest decodes verbatim, fuse adds
heading back). px_to_azel returns TRUE az, so a nonzero heading biases
every emitted sample by the survey heading."""
import numpy as np

from maiden.camera import CameraModel, azel_to_px
from maiden.geo import Pose
from maiden.track.emit import to_state_samples
from maiden.track.tracker import TrackOut, TrackState
from maiden.twin.sensors import station_azel


def test_emitted_az_is_station_frame():
    model = CameraModel(fx=831.5, fy=831.5, cx=480.0, cy=270.0)
    pose = Pose(pos_enu=(0.0, 0.0, 0.0), heading_deg=30.0,
                boresight_el_deg=8.0)
    # target dead on the boresight, 150 m out
    az_true, el_true = 30.0, 8.0
    u, v = azel_to_px(model, pose, az_true, el_true)
    # twin/fusion contract: station-frame az of this target is 0
    p = 150.0 * np.array([np.sin(np.radians(az_true)) * np.cos(np.radians(el_true)),
                          np.cos(np.radians(az_true)) * np.cos(np.radians(el_true)),
                          np.sin(np.radians(el_true))])
    az_sf, _el_sf = station_azel(p.reshape(1, 3), pose)
    assert abs(az_sf[0]) < 1e-6
    tr = TrackOut(1, float(u), float(v), 0.9, TrackState.CONFIRMED)
    (s,) = to_state_samples([tr], 0.0, model, pose, "A")
    # the sample must carry station-frame az (== 0), not true az (== 30)
    assert abs(s.az_deg - az_sf[0]) < 1e-3, \
        f"emitted az {s.az_deg:.3f} deg vs station-frame {az_sf[0]:.3f}"
