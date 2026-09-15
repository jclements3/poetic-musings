"""maiden19: candidate pipeline unit tests + clean-sky twin end-to-end."""

import numpy as np

from maiden.camera import CameraModel
from maiden.geo import Pose
from maiden.track.candidates import SkyModel, link_coherence, propose
from maiden.track.metrics import Report
from maiden.twin.model import sportsman
from maiden.twin.render import RenderConfig, render_session

RNG = np.random.default_rng(20260821)


def _flat_frames(n, h=90, w=160, level=128.0, noise=2.0):
    return [np.clip(level + RNG.normal(0, noise, (h, w)), 0, 255)
            .astype(np.uint8) for _ in range(n)]


def _fit_sky(frames, **kw):
    sky = SkyModel(**kw)
    for f in frames:
        sky.update(f)
    assert sky.ready
    return sky


def test_known_blob_is_proposed():
    sky = _fit_sky(_flat_frames(30, ), n=9, stride=1)
    img = _flat_frames(1)[0].astype(np.float32)
    img[40:46, 70:78] -= 90.0          # dark 6x8 target
    cands = propose(sky.residual(img), sky.sigma)
    assert len(cands) == 1
    c = cands[0]
    assert abs(c.u - 73.5) < 1.5 and abs(c.v - 42.5) < 1.5
    assert c.area >= 30 and c.contrast > 5


def test_sub_min_area_blob_is_not():
    sky = _fit_sky(_flat_frames(30), n=9, stride=1)
    img = _flat_frames(1)[0].astype(np.float32)
    img[40, 70] -= 90.0                # single-pixel spike
    assert propose(sky.residual(img), sky.sigma) == []


def test_sigma_adapts_to_doubled_noise():
    lo = _fit_sky(_flat_frames(30, noise=2.0), n=9, stride=1)
    hi = _fit_sky(_flat_frames(30, noise=4.0), n=9, stride=1)
    assert hi.sigma.mean() > 1.6 * lo.sigma.mean()
    # a bump that clears the low-noise threshold hides in the high-noise sky
    img_lo = _flat_frames(1, noise=2.0)[0].astype(np.float32)
    img_hi = _flat_frames(1, noise=4.0)[0].astype(np.float32)
    for img in (img_lo, img_hi):
        img[40:45, 70:75] -= 12.0
    assert len(propose(lo.residual(img_lo), lo.sigma)) == 1
    assert len(propose(hi.residual(img_hi), hi.sigma)) == 0


def test_coherence_linking():
    sky = _fit_sky(_flat_frames(30), n=9, stride=1)
    imgs = []
    for k in range(2):
        img = _flat_frames(1)[0].astype(np.float32)
        img[40:45, 70 + 5 * k:75 + 5 * k] -= 90.0
        imgs.append(img)
    prev = propose(sky.residual(imgs[0]), sky.sigma)
    cur = link_coherence(prev, propose(sky.residual(imgs[1]), sky.sigma))
    assert cur[0].coherence is not None and abs(cur[0].coherence - 5.0) < 1.5


def test_clean_sky_twin_recall():
    """End-to-end: clean-sky recall >= 0.95 at >= 6 px (SW-002 floor).

    Half resolution (intrinsics scaled with it) keeps the >= 6 px bin
    populated: at quarter-res the whole flight sits below 6 rendered px.
    The evaluated window (frames 450-740) brackets the first pass of the
    target through this camera's FOV; earlier frames only warm the sky
    model. ~30 s — the suite's heaviest test, and its core CV evidence.
    """
    model = CameraModel(fx=1663 / 2, fy=1663 / 2, cx=480.0, cy=270.0)
    pose = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
    cfg = RenderConfig(width=960, height=540, noise_sigma=0.01)
    truth = sportsman()
    sky = SkyModel(n=25, stride=3)
    rep = Report()
    prev = []
    for i, (t, img, label) in enumerate(
            render_session(truth, "A", model, pose, cfg)):
        if i < 440:
            continue
        if i >= 740:
            break
        sky.update(img)
        if not sky.ready:
            continue
        cands = link_coherence(prev, propose(sky.residual(img), sky.sigma))
        prev = cands
        rep.add(t, label, cands)
    rec = rep.recall_by_bin()
    assert rec[">=6px"] is not None and rec[">=6px"] >= 0.95
    assert rep.false_per_frame() < 1.0
