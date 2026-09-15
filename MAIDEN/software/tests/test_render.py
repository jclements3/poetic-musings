"""maiden18: twin renderer — pixel-size law, labels, sun, gradient."""

import numpy as np

from maiden.camera import CameraModel, azel_to_px
from maiden.geo import Pose
from maiden.twin.model import sportsman
from maiden.twin.render import RenderConfig, render_session, target_size_px

M60 = CameraModel(fx=1663.0, fy=1663.0, cx=960.0, cy=540.0)
# quarter-resolution model for fast renders: intrinsics scale with pixels
M60Q = CameraModel(fx=1663.0 / 4, fy=1663.0 / 4, cx=240.0, cy=135.0)
POSE = Pose(pos_enu=(0.0, 0.0, 0.0), heading_deg=0.0, boresight_el_deg=0.0)
SMALL = RenderConfig(width=480, height=270, noise_sigma=0.0)


class _StaticTruth:
    """Truth stub: target parked at one point for a few frames."""

    def __init__(self, pos, n=5):
        self.t = np.linspace(0.0, (n - 1) / 30.0, n)
        self.pos_enu = np.tile(np.asarray(pos, float), (n, 1))
        self.vel_enu = np.zeros((n, 3))
        self.att_rpy = np.zeros((n, 3))


def test_size_law_three_ranges():
    # lesson 10's table: 60 deg lens, 1.5 m span
    assert abs(target_size_px(M60, 150.0) - 16.63) < 0.1
    assert abs(target_size_px(M60, 300.0) - 8.3) < 0.1
    assert abs(target_size_px(M60, 415.0) - 6.0) < 0.1


def test_labels_match_projection_and_blob_is_dark():
    pos = (10.0, 150.0, 40.0)
    frames = list(render_session(_StaticTruth(pos), "A", M60Q, POSE, SMALL))
    assert len(frames) >= 3
    _t, img, label = frames[1]
    assert label is not None
    u, v, size = label
    az = np.degrees(np.arctan2(pos[0], pos[1]))
    el = np.degrees(np.arctan2(pos[2], np.hypot(pos[0], pos[1])))
    ue, ve = azel_to_px(M60Q, POSE, az, el)
    assert abs(u - ue) < 1e-6 and abs(v - ve) < 1e-6
    r = np.linalg.norm(pos)
    assert abs(size - target_size_px(M60Q, r)) < 1e-6
    iu, iv = round(u), round(v)
    if 0 <= iu < SMALL.width and 0 <= iv < SMALL.height:
        assert img[iv, iu] < 0.6 * img[iv, min(iu + 60, SMALL.width - 1)]


def test_sky_gradient_monotonic():
    frames = list(render_session(_StaticTruth((0, 5000, 10)), "A", M60Q, POSE,
                                 SMALL))
    img = frames[0][1].astype(float)
    col = img[:, 10]
    assert col[-1] > col[0]                       # brighter at horizon
    assert np.all(np.diff(col) >= -1)             # monotonic within jpeg-free render


def test_sun_saturates():
    cfg = RenderConfig(width=480, height=270, noise_sigma=0.0,
                       sun_azel=(5.0, 10.0), sun_radius_px=12)
    frames = list(render_session(_StaticTruth((-50, 150, 40)), "A", M60Q, POSE,
                                 cfg))
    img = frames[0][1]
    su, sv = azel_to_px(M60Q, POSE, 5.0, 10.0)
    assert img[int(sv), int(su)] == 255


def test_full_sportsman_labels_cover_scored_window():
    # D1's pattern box spans +/-60 deg of the centerline; a 60 deg lens
    # covers +/-30. One fixed camera therefore sees only the central part
    # of the box; full coverage is the three-station union's job (D3).
    # Assert the honest single-camera number so a regression is visible.
    from maiden.twin.writer import default_poses

    truth = sportsman()
    ev = {e.kind: e.t_utc for e in truth.events}
    t0, t1 = ev["SCORED_START"], ev["SCORED_END"]
    poses, _ = default_poses()
    cfg = RenderConfig(width=480, height=270, noise_sigma=0.0)
    n_frames = n_labeled = 0
    for t, _, label in render_session(truth, "A", M60Q, poses["A"], cfg):
        if t0 <= t <= t1:
            n_frames += 1
            n_labeled += label is not None
    assert n_frames > 1000
    assert n_labeled / n_frames > 0.3
