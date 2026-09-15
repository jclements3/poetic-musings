"""IF-4: the state-vector interface. Change only by revising D4."""
from dataclasses import dataclass, field

import numpy as np

STATIONS = ("A", "B", "C")
SOURCES = STATIONS + ("FUSED", "TRUTH")


@dataclass
class StateSample:
    t_utc:   float                 # seconds, from IRIG-B / GPS
    source:  str                   # "A" | "B" | "C" | "FUSED" | "TRUTH"
    az_deg:  float | None = None   # station-frame azimuth (stations);
    # convention: az clockwise from true north, el above local horizontal
    # (pinned in lesson 09; maiden.camera and twin.sensors agree to 1e-6 deg)
    el_deg:  float | None = None
    conf:    float | None = None   # tracker confidence 0-1
    v_r:     float | None = None   # radial velocity m/s (stations)
    pos_enu: tuple | None = None   # E,N,U metres in field frame (FUSED, TRUTH)
    vel_enu: tuple | None = None
    att_rpy: tuple | None = None   # roll, pitch, yaw deg (TRUTH; FUSED if estimable)
    cov:     np.ndarray | None = None  # 6x6 for FUSED


@dataclass
class Event:
    t_utc: float
    kind:  str                     # "TAKEOFF" | "TOUCHDOWN" | "MANEUVER_START" | ...
    data:  dict = field(default_factory=dict)


def validate(s: StateSample) -> None:
    """Raise ValueError on any IF-4 violation. Cheap; call it in adapters."""
    if s.source not in SOURCES:
        raise ValueError(f"unknown source {s.source!r}")
    if s.source in STATIONS:
        if s.pos_enu is not None or s.cov is not None:
            raise ValueError("station samples carry angles, not state")
        if s.az_deg is None and s.v_r is None:
            raise ValueError("station sample with no measurement")
        if s.conf is not None and not 0.0 <= s.conf <= 1.0:
            raise ValueError("conf out of [0,1]")
    else:
        if s.pos_enu is None or s.vel_enu is None:
            raise ValueError(f"{s.source} sample must carry pos+vel")
        if s.source == "FUSED" and s.cov is not None and s.cov.shape != (6, 6):
            raise ValueError("FUSED cov must be 6x6")
        if s.source == "TRUTH" and s.cov is not None:
            raise ValueError("truth publishes no covariance")
