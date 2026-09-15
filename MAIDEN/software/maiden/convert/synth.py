"""SYNTHETIC ArduPilot DataFlash .bin fixture writer — TEST INFRASTRUCTURE.

No real H743 bench log exists until maiden47 (bench). This module writes
a byte-level DataFlash file (FMT self-description + GPS/IMU/BARO/ATT
messages) that pymavlink's DFReader genuinely parses, so the converter
can be developed and regression-tested today. It is labeled synthetic
everywhere it appears; VT-09's real pass runs on the bench log and this
file never substitutes for it.

Trajectory: a level circle over RCRC at pattern-ish speed, plus a
deterministic TimeUS drift (+25 ppm) and millisecond GMS quantization so
the TimeUS->UTC fit has something honest to do.
"""

import struct

import numpy as np

HEAD = b"\xa3\x95"
FMT_ID = 0x80
GPS_ID, IMU_ID, BARO_ID, ATT_ID = 1, 2, 3, 4

_FMT_PAYLOAD = struct.Struct("<BB4s16s64s")

# name, id, fmt-chars, columns   ('L' = int32 degrees*1e7 per DataFlash)
_DEFS = [
    ("GPS", GPS_ID, "QHILLffff", "TimeUS,GWk,GMS,Lat,Lng,Alt,VN,VE,VD"),
    ("IMU", IMU_ID, "Qffffff", "TimeUS,AccX,AccY,AccZ,GyrX,GyrY,GyrZ"),
    ("BARO", BARO_ID, "Qf", "TimeUS,Alt"),
    ("ATT", ATT_ID, "Qfff", "TimeUS,Roll,Pitch,Yaw"),
]

_SIZES = {"Q": 8, "I": 4, "H": 2, "B": 1, "L": 4, "f": 4}
_STRUCT = {"Q": "Q", "I": "I", "H": "H", "B": "B", "L": "i", "f": "f"}

GPS_EPOCH_UNIX = 315_964_800.0
LEAP_SECONDS = 18.0


def _msg_len(fmt_chars: str) -> int:
    return 3 + sum(_SIZES[c] for c in fmt_chars)


def _fmt_msg(name, mid, fmt_chars, cols) -> bytes:
    return (HEAD + bytes([FMT_ID]) +
            _FMT_PAYLOAD.pack(mid, _msg_len(fmt_chars), name.encode(),
                              fmt_chars.encode(), cols.encode()))


def write_synthetic_bin(path, *, duration_s=20.0, utc0=1_800_000_000.0,
                        drift_ppm=25.0, seed=7):
    """Write the fixture; returns a dict of the exact arrays written."""
    rng = np.random.default_rng(seed)
    scale = 1.0 + drift_ppm * 1e-6
    boot_us0 = 90_000_000                       # 90 s after boot

    def timeus(t_utc):
        return round(boot_us0 + (t_utc - utc0) * 1e6 * scale)

    # circle over RCRC: center 150 m N of Station A, r=100 m, 25 m/s
    lat0, lon0, alt0 = 34.6851710, -86.5922440, 183.2
    omega = 25.0 / 100.0
    msgs = []
    truth = {"gps": [], "imu": [], "baro": [], "att": []}

    n_gps = int(duration_s * 10)
    for i in range(n_gps):
        t = utc0 + i * 0.1
        th = omega * (t - utc0)
        n_m = 150.0 + 100.0 * np.cos(th)
        e_m = 100.0 * np.sin(th)
        lat = lat0 + (n_m / 111_132.0)
        lon = lon0 + (e_m / (111_320.0 * np.cos(np.radians(lat0))))
        alt = alt0 + 60.0
        vn = -100.0 * omega * np.sin(th)
        ve = 100.0 * omega * np.cos(th)
        vd = 0.0
        gps_s = t + LEAP_SECONDS - GPS_EPOCH_UNIX
        gwk = int(gps_s // 604_800)
        gms = round((gps_s - gwk * 604_800) * 1000)  # ms quantization
        tus = timeus(t)
        row = (tus, gwk, gms, round(lat * 1e7), round(lon * 1e7),
               alt, vn, ve, vd)
        msgs.append((tus, GPS_ID, "QHILLffff", row))
        truth["gps"].append((tus, gwk, gms, lat, lon, alt, vn, ve, vd))

    for i in range(int(duration_s * 100)):
        t = utc0 + i * 0.01
        tus = timeus(t)
        acc = (0.0, 0.0, -9.81 + 0.05 * rng.standard_normal())
        gyr = (0.0, 0.0, omega)
        row = (tus, *acc, *gyr)
        msgs.append((tus, IMU_ID, "Qffffff", row))
        truth["imu"].append(row)

    for i in range(int(duration_s * 10)):
        t = utc0 + i * 0.1
        tus = timeus(t)
        row = (tus, alt0 + 60.0 + 0.2 * rng.standard_normal())
        msgs.append((tus, BARO_ID, "Qf", row))
        truth["baro"].append(row)

    for i in range(int(duration_s * 25)):
        t = utc0 + i * 0.04
        th = omega * (t - utc0)
        tus = timeus(t)
        yaw = (np.degrees(th) + 90.0) % 360.0
        row = (tus, 20.0, 0.0, yaw)               # 20 deg bank circle
        msgs.append((tus, ATT_ID, "Qfff", row))
        truth["att"].append(row)

    msgs.sort(key=lambda m: m[0])
    with open(path, "wb") as f:
        f.writelines(_fmt_msg(name, mid, fmt_chars, cols) for name, mid, fmt_chars, cols in _DEFS)
        for _tus, mid, fmt_chars, row in msgs:
            body = struct.pack("<" + "".join(_STRUCT[c] for c in fmt_chars),
                               *row)
            f.write(HEAD + bytes([mid]) + body)

    return {k: np.array(v, float) for k, v in truth.items()} | {
        "utc0": utc0, "drift_ppm": drift_ppm}
