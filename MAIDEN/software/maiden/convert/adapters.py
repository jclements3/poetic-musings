"""Airborne log adapters (D4 IF-3): one real parser, four honest stubs.

IF-3 lists five native formats. We own one airframe and it runs
ArduPilot, so `ardupilot.py` is fully built and the rest raise
`NotImplementedError` with their IF-3 rows quoted — adding PX4 support
later is a new file, not a refactor (lesson 22 §The adapter registry).

`AirborneRecords` is the common currency: per-stream numpy arrays, all
UTC-stamped through the log's own TimeUS→UTC fit. The Ch. 10 writer half
(`writer.py`) consumes only this type.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np


@dataclass
class AirborneRecords:
    """Per-stream arrays from one airborne log. All times are UTC seconds.

    gps columns:  t_utc, lat (deg), lon (deg), alt (m AMSL),
                  vn, ve, vd (m/s, NED), timeus (raw autopilot clock)
    imu columns:  t_utc, acc (n,3) m/s^2, gyr (n,3) rad/s, timeus
    baro columns: t_utc, alt (m), timeus
    att columns:  t_utc, rpy (n,3) deg  [autopilot EKF attitude —
                  ATT_SOURCE:ARDUPILOT_EKF, not a raw sensor], timeus
    fit:          (a, b, t0, u0, resid_rms_s) of utc = a*(TimeUS-t0)+b+u0
    """

    gps_t: np.ndarray
    lat: np.ndarray
    lon: np.ndarray
    alt: np.ndarray
    vn: np.ndarray
    ve: np.ndarray
    vd: np.ndarray
    gwk: np.ndarray
    gms: np.ndarray
    gps_timeus: np.ndarray
    imu_t: np.ndarray
    acc: np.ndarray
    gyr: np.ndarray
    imu_timeus: np.ndarray
    baro_t: np.ndarray
    baro_alt: np.ndarray
    baro_timeus: np.ndarray
    att_t: np.ndarray
    rpy: np.ndarray
    att_timeus: np.ndarray
    fit: tuple = field(default=())

    def counts(self) -> dict:
        return {"GPS": len(self.gps_t), "IMU": len(self.imu_t),
                "BARO": len(self.baro_t), "ATT": len(self.att_t)}


class LogAdapter(Protocol):
    suffixes: tuple[str, ...]

    def read(self, path: Path) -> AirborneRecords: ...


class _Stub:
    """Base for not-yet-implemented IF-3 adapters."""

    suffixes: tuple[str, ...] = ()
    row = ""

    def read(self, path):
        raise NotImplementedError(
            f"{type(self).__name__}: not implemented. D4 IF-3 row: {self.row}")


class Px4Ulog(_Stub):
    """D4 IF-3: 'PX4 .ulg | pyulog | vehicle_gps_position | same | —'."""

    suffixes = (".ulg",)
    row = "PX4 .ulg | pyulog | vehicle_gps_position | GPS/IMU/BARO/ATT"


class BetaflightBbl(_Stub):
    """D4 IF-3: 'Betaflight Blackbox .bbl | orangebox | GPS frames if
    present | IMU, GPS | No baro on many boards; attitude derived'."""

    suffixes = (".bbl",)
    row = ("Betaflight Blackbox .bbl | orangebox | GPS frames if present | "
           "IMU, GPS | no baro on many boards; attitude derived")


class UbloxUbx(_Stub):
    """D4 IF-3: 'u-blox .ubx | pyubx2 | NAV-PVT iTOW | GPS only |
    Standalone GNSS logger option'."""

    suffixes = (".ubx",)
    row = "u-blox .ubx | pyubx2 | NAV-PVT iTOW | GPS only"


class EdgeTxCsv(_Stub):
    """D4 IF-3: 'EdgeTX telemetry .csv | built-in | TX clock (offset by
    clap) | GPS, baro (low rate) | Fallback only'."""

    suffixes = (".csv",)
    row = ("EdgeTX telemetry .csv | built-in | TX clock (offset by clap) | "
           "GPS, baro (low rate) | fallback only")


def get_adapter(path) -> LogAdapter:
    """Dispatch on suffix, case-insensitive. ArduPilot .bin is the one
    fully-built adapter (lesson 22); everything else is a stub."""
    from . import ardupilot

    suffix = Path(path).suffix.lower()
    table: dict[str, LogAdapter] = {".bin": ardupilot.ArduPilotBin()}
    for stub in (Px4Ulog(), BetaflightBbl(), UbloxUbx(), EdgeTxCsv()):
        for s in stub.suffixes:
            table[s] = stub
    try:
        return table[suffix]
    except KeyError:
        raise ValueError(
            f"no IF-3 adapter for suffix {suffix!r} "
            f"(known: {sorted(table)})") from None
