"""Twin frame renderer (lesson 10) — ground-truthed imagery for the tracker.

THE MODEL, HONESTLY: gradient sky + Gaussian-blurred dark ellipse for the
airframe + optional saturated sun disc with bloom + per-pixel Gaussian
noise.  That is enough to exercise the candidate/track pipeline with
exact truth labels, and NOT enough to claim field performance — no
clouds, no haze, no birds (Explore adds one), no lens flare, no rolling
shutter.  VT-15's field verdict waits for labeled field frames (D6, D5
risk R1); numbers measured on this imagery are twin rehearsal evidence
and are logged as such.

Video note: the real recorder writes H.264 TS per IF-1 Ch 2.  This desk
machine has no H.264 encoder wired in, so `write_video_file` stores one
JPEG per frame in the Ch 2 packets (dtype 0x40, IPTS = packet RTC) of a
separate VIDEO_<st> file, documented here and in maiden18's card.  The
labels sidecar (labels_<st>.npz) is the contract the tracker consumes.
"""

from collections.abc import Iterator
from dataclasses import dataclass

import cv2
import numpy as np

from maiden.camera import CameraModel, azel_to_px
from maiden.ch10.writer import Ch10Writer
from maiden.twin.sensors import azel_from_pos


@dataclass
class RenderConfig:
    width: int = 1920
    height: int = 1080
    fps: int = 30
    sky_top: float = 0.55
    sky_horizon: float = 0.95     # luminance 0..1, top -> horizon
    noise_sigma: float = 0.01
    sun_azel: tuple | None = None  # (az_deg, el_deg); None = no sun
    sun_radius_px: int = 45
    span_m: float = 1.5
    target_luminance: float = 0.25


def target_size_px(model: CameraModel, range_m: float, span_m: float = 1.5):
    """The one-line answer from lesson 09: fx * span / R, in pixels."""
    return model.fx * span_m / range_m


def _base_sky(cfg: RenderConfig) -> np.ndarray:
    col = np.linspace(cfg.sky_top, cfg.sky_horizon, cfg.height, dtype=np.float32)
    return np.repeat(col[:, None], cfg.width, axis=1) * 255.0


def _draw_sun(img: np.ndarray, u: float, v: float, cfg: RenderConfig):
    mask = np.zeros_like(img)
    cv2.circle(mask, (round(u), round(v)), cfg.sun_radius_px, 255.0, -1)
    bloom = cv2.GaussianBlur(mask, (0, 0), cfg.sun_radius_px * 0.8)
    np.clip(img + mask + 0.8 * bloom, 0, 255, out=img)


def render_session(truth, station: str, model: CameraModel, pose,
                   cfg: RenderConfig | None = None) -> Iterator[tuple]:
    """Yield (t_utc, image uint8 HxW, truth_px) at cfg.fps.

    truth_px is (u, v, size_px) when the target projects inside the
    frame, else None.  t_utc is sequence-relative like twin truth.t.
    """
    cfg = cfg or RenderConfig()
    base = _base_sky(cfg)
    sun_px = None
    if cfg.sun_azel is not None:
        sun_px = azel_to_px(model, pose, *cfg.sun_azel)
    frame_t = np.arange(truth.t[0], truth.t[-1], 1.0 / cfg.fps)
    pos = np.stack([np.interp(frame_t, truth.t, truth.pos_enu[:, i])
                    for i in range(3)], axis=1)
    az, el = azel_from_pos(pos, pose)
    rng_m = np.linalg.norm(pos - np.asarray(pose.pos_enu), axis=1)
    uv = azel_to_px(model, pose, az, el)
    rng_noise = np.random.default_rng(0)
    for k, t in enumerate(frame_t):
        img = base.copy()
        u, v = float(uv[0][k]), float(uv[1][k])
        size = float(target_size_px(model, rng_m[k], cfg.span_m))
        label = None
        if np.isfinite(u) and -size <= u < cfg.width + size \
                and -size <= v < cfg.height + size:
            axes = (max(1, round(size / 2)), max(1, round(size / 4)))
            cv2.ellipse(img, (round(u), round(v)), axes, 0.0,
                        0, 360, cfg.target_luminance * 255.0, -1)
            x0 = max(0, int(u - 3 * size)); x1 = min(cfg.width, int(u + 3 * size))
            y0 = max(0, int(v - 3 * size)); y1 = min(cfg.height, int(v + 3 * size))
            if x1 > x0 and y1 > y0:
                img[y0:y1, x0:x1] = cv2.GaussianBlur(img[y0:y1, x0:x1], (0, 0), 1.0)
            label = (u, v, size)
        # Sun goes on LAST: sensor saturation and bloom wash out whatever
        # sits in front of the disc — that clipping is exactly the R1
        # mechanism (a target crossing the sun loses its contrast).
        if sun_px is not None:
            _draw_sun(img, sun_px[0], sun_px[1], cfg)
        if cfg.noise_sigma > 0:
            img += rng_noise.normal(0.0, cfg.noise_sigma * 255.0, img.shape)
        yield t, np.clip(img, 0, 255).astype(np.uint8), label


def write_video_file(out_dir, station: str, truth, model: CameraModel, pose,
                     cfg: RenderConfig | None = None, jpeg_q: int = 80):
    """Write VIDEO_<st>_*.ch10 (Ch 0 TMATS + Ch 1 time + Ch 2 JPEG frames)
    plus labels_<st>.npz.  Returns (ch10_path, labels_path)."""
    from pathlib import Path

    from maiden.twin import writer as tw

    cfg = cfg or RenderConfig()
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    off, ppm = tw.RTC_SKEW[station]

    def rtc_of(t):
        return round((off + t) * tw.RTC_HZ * (1.0 + ppm * 1e-6))

    path = out / f"VIDEO_{station}_{tw.STAMP}.ch10"
    w = Ch10Writer(path)
    with open("config/tmats/station.tmt") as f:
        w.write_tmats(0, f.read())
    tvec, uvec, vvec, svec = [], [], [], []
    pending = sorted(tw._time_packets(truth.t[0], truth.t[-1], rtc_of),
                     key=lambda p: p[0])
    i = 0
    for t, img, label in render_session(truth, station, model, pose, cfg):
        rtc = rtc_of(t)
        while i < len(pending) and pending[i][0] <= rtc:
            w.write_packet(channel=1, dtype=0x11, rtc=pending[i][0],
                           body=pending[i][3])
            i += 1
        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, jpeg_q])
        assert ok
        w.write_packet(channel=2, dtype=0x40, rtc=rtc, body=buf.tobytes())
        if label is not None:
            tvec.append(t); uvec.append(label[0])
            vvec.append(label[1]); svec.append(label[2])
    w.close()
    labels = out / f"labels_{station}.npz"
    np.savez(labels, t=np.array(tvec), u=np.array(uvec),
             v=np.array(vvec), size_px=np.array(svec))
    return path, labels
