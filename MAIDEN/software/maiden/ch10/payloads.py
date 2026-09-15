"""Payload struct layouts for MAIDEN's IF-1 channels — single definition.

Three users share these (D4 IF-1): the twin's writer (lesson 07), the
station recorder (lesson 19), and ingest (lesson 08). Field meanings come
from the D4 channel table; sizes are pinned here and nowhere else.

TRUTH files reuse channel numbers 3/4 with different *names* in their
TMATS (GNSS/ATT instead of RADAR_IF/RADAR_V) — the Ch. 10 data *types*
still match the writer's IF-1 channel/type map. Ingest must dispatch on
the TMATS DSI name, not the channel number alone.
"""
import struct
from typing import NamedTuple

# Ch 4 · RADAR_V · PCM (D4: "v_r float32 m/s, SNR dB, peak bin")
_RADAR_V = struct.Struct("<ffI")
# Ch 5 · TRACKER · message (D4: "az, el (deg, float32), conf (0-1), bbox px")
_TRACKER = struct.Struct("<fffHHHH")
# Ch 6 · STATUS · message (D4: "battery V, temp degC, PPS lock, disk free")
_STATUS = struct.Struct("<ffBBH")
# TRUTH Ch 3 · GNSS-shaped: field-frame pos ENU + vel ENU (float32 x 6)
_TRUTH_GNSS = struct.Struct("<6f")
# TRUTH Ch 4 · ATT: roll, pitch, yaw degrees (float32 x 3)
_TRUTH_ATT = struct.Struct("<3f")


class RadarV(NamedTuple):
    v_r: float
    snr_db: float
    peak_bin: int


class Tracker(NamedTuple):
    az_deg: float
    el_deg: float
    conf: float
    bbox: tuple  # (x, y, w, h) pixels


class Status(NamedTuple):
    battery_v: float
    temp_c: float
    pps_lock: bool
    disk_free_pct: int


def pack_radar_v(v_r: float, snr_db: float, peak_bin: int = 0) -> bytes:
    return _RADAR_V.pack(v_r, snr_db, peak_bin)


def unpack_radar_v(body: bytes) -> RadarV:
    v, s, b = _RADAR_V.unpack(body)
    return RadarV(v, s, b)


def pack_tracker(az_deg, el_deg, conf, bbox=(0, 0, 0, 0)) -> bytes:
    return _TRACKER.pack(az_deg, el_deg, conf, *bbox)


def unpack_tracker(body: bytes) -> Tracker:
    az, el, conf, *bbox = _TRACKER.unpack(body)
    return Tracker(az, el, conf, tuple(bbox))


def pack_status(battery_v, temp_c, pps_lock, disk_free_pct) -> bytes:
    return _STATUS.pack(battery_v, temp_c, int(pps_lock), disk_free_pct, 0)


def unpack_status(body: bytes) -> Status:
    bv, tc, lock, disk, _pad = _STATUS.unpack(body)
    return Status(bv, tc, bool(lock), disk)


def pack_truth_gnss(pos_enu, vel_enu) -> bytes:
    return _TRUTH_GNSS.pack(*pos_enu, *vel_enu)


def unpack_truth_gnss(body: bytes):
    v = _TRUTH_GNSS.unpack(body)
    return v[:3], v[3:]


def pack_truth_att(rpy) -> bytes:
    return _TRUTH_ATT.pack(*rpy)


def unpack_truth_att(body: bytes):
    return _TRUTH_ATT.unpack(body)
