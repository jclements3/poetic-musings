"""Run the tracker over rendered twin video and write a Ch 5 session file.

The desk stand-in for the on-station path (D6: full tracker runs on the
host post-session): frames -> candidates -> StationTracker -> emit ->
STATION-shaped .ch10 (TMATS first, Ch 1 time, Ch 5 TRACKER) that
maiden.ingest reads back — the maiden21 round-trip artifact.
"""

from pathlib import Path

from maiden.camera import CameraModel
from maiden.ch10.writer import Ch10Writer
from maiden.track.candidates import SkyModel, link_coherence, propose
from maiden.track.emit import to_ch5_bodies, to_state_samples
from maiden.track.tracker import StationTracker, TrackerCfg
from maiden.twin import writer as tw
from maiden.twin.render import RenderConfig, render_session


def track_rendered_session(truth, station: str, model: CameraModel, pose,
                           cfg: RenderConfig | None = None,
                           tcfg: TrackerCfg | None = None,
                           frame_range: tuple | None = None):
    """Yield (t, track_outs, label) per frame of a rendered twin session."""
    sky = SkyModel(n=25, stride=3)
    tracker = StationTracker(tcfg)
    prev = []
    for i, (t, img, label) in enumerate(
            render_session(truth, station, model, pose, cfg)):
        if frame_range and not (frame_range[0] <= i < frame_range[1]):
            if frame_range and i >= frame_range[1]:
                break
            continue
        sky.update(img)
        if not sky.ready:
            continue
        cands = link_coherence(prev, propose(sky.residual(img), sky.sigma))
        prev = cands
        yield t, tracker.consume(cands), label


def write_track_session(out_dir, truth, station: str, model: CameraModel,
                        pose, cfg=None, tcfg=None, frame_range=None):
    """Track rendered twin video -> TRACKS_<st>_*.ch10 + emitted samples.

    Returns (path, samples): `samples` are the StateSamples emitted, in
    order, for round-trip comparison against maiden.ingest.load(path).
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    off, ppm = tw.RTC_SKEW[station]

    def rtc_of(t):
        return round((off + t) * tw.RTC_HZ * (1.0 + ppm * 1e-6))

    # The IF-2 template is Station A's record; other stations would need
    # their own survey block (twin.writer builds those inline).
    assert station == "A", "template TMATS is Station A's; extend if needed"
    path = out / f"TRACKS_{station}_{tw.STAMP}.ch10"
    w = Ch10Writer(path)
    with open("config/tmats/station.tmt") as f:
        w.write_tmats(0, f.read())
    samples = []
    pending = None
    for t, outs, _label in track_rendered_session(
            truth, station, model, pose, cfg, tcfg, frame_range):
        if pending is None:
            pending = sorted(tw._time_packets(t, truth.t[-1], rtc_of))
        rtc = rtc_of(t)
        while pending and pending[0][0] <= rtc:
            p = pending.pop(0)
            w.write_packet(channel=1, dtype=0x11, rtc=p[0], body=p[3])
        for s, body in zip(
                to_state_samples(outs, t, model, pose, station),
                to_ch5_bodies(outs, model, pose)):
            w.write_packet(channel=5, dtype=0x30, rtc=rtc, body=body)
            samples.append(s)
    w.close()
    return path, samples
