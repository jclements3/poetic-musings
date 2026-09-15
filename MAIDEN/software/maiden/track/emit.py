"""Track emission: TrackOut -> StateSamples and Ch 5 packets (maiden21).

One code path, two sinks (lesson 11): the live pipeline consumes
StateSample(t_utc, source=station id, az_deg, el_deg, conf); recorded
sessions carry the identical numbers as payloads.TRACKER messages on
Ch 5, byte-identical to what maiden.ingest already decodes.

COASTED EMISSION — THE DECISION (lesson 11 Explore 2): coasted tracks DO
emit, with conf falling by COAST_DECAY per missed frame, rather than
going silent.  Rationale: fusion (lesson 13) already de-weights by conf
and chi-square-gates wild predictions, so a low-conf coasted sample is
information ("the tracker believes it's near here") while silence is
ambiguous ("no aircraft, or no tracker?").  The flag survives the trip:
coasted samples are exactly those with conf below the last-hit EMA, and
fusion's half of the bargain is its gate.  Revisit with field data if
coasted az/el error proves unusable (lesson 11's K-sweep shows error
grows ~linearly with coast length on twin data).
"""

import numpy as np

from maiden.camera import CameraModel, px_to_azel
from maiden.ch10 import payloads as pl
from maiden.state import StateSample, validate


def _station_azel(model: CameraModel, pose, u, v):
    """px -> STATION-FRAME az/el — the ecosystem contract for station
    samples (twin.writer writes station-frame, ingest decodes verbatim,
    fuse.azel_to_unit adds the heading back).  px_to_azel returns TRUE
    az; forgetting the heading subtraction biased every emitted sample
    by the survey heading (12.4 deg on Station A's template) — caught by
    test_emit_station_frame.py."""
    az_true, el = px_to_azel(model, pose, u, v)
    az = (az_true - pose.heading_deg + 180.0) % 360.0 - 180.0
    return az, el


def to_state_samples(track_outs, t_utc: float, model: CameraModel, pose,
                     station_id: str) -> list[StateSample]:
    out = []
    for tr in track_outs:
        az, el = _station_azel(model, pose, tr.u, tr.v)
        s = StateSample(t_utc=t_utc, source=station_id,
                        az_deg=float(az), el_deg=float(el),
                        conf=float(np.clip(tr.conf, 0.0, 1.0)))
        validate(s)
        out.append(s)
    return out


def to_ch5_bodies(track_outs, model: CameraModel, pose) -> list[bytes]:
    """The same numbers, packed for the recorder's Ch 5 (IF-1)."""
    bodies = []
    for tr in track_outs:
        az, el = _station_azel(model, pose, tr.u, tr.v)
        x, y, w, h = (int(b) for b in tr.bbox)
        bodies.append(pl.pack_tracker(
            float(az), float(el), float(np.clip(tr.conf, 0.0, 1.0)),
            (x, y, w, h)))
    return bodies
