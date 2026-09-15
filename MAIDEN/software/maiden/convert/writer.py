"""AirborneRecords + Airframe -> one aircraft .ch10 (lesson 22).

Channel plan (constrained by maiden.ch10.writer's strict IF-1 pairs):

  Ch 0  TMATS   0x01  aircraft descriptor (AIRFRAME/LOGGER attributes)
  Ch 1  TIME    0x11  1 Hz BCD time packets from GPS-disciplined UTC
  Ch 3  GNSS    0x09  payloads.pack_truth_gnss: field-frame ENU pos+vel
                      (float32 x 6) at GPS rate — what maiden.ingest's
                      Aircraft path loads as TRUTH StateSamples
  Ch 4  ATT     0x09  payloads.pack_truth_att: EKF roll/pitch/yaw deg
  Ch 5  GPS_LLA 0x30  raw provenance: <QddffffHI> TimeUS, lat, lon (f64
                      deg), alt, vn, ve, vd (f32; NED m/s), GWk, GMS —
                      lossless round-trip source; ingest skips it
  Ch 6  IMU_BARO 0x30 tagged records: u8 tag (0=IMU, 1=BARO) + u64
                      TimeUS + (6f acc/gyr | 1f alt). ingest skips Ch 6
                      by design; convert.read_back() consumes it.

The same byte layouts are echoed into the TMATS comment group
(C\\MAIDEN\\CONVERT\\*) so the file describes itself forever.

RTC is synthesized at 10 MHz from UTC (rtc = (utc - utc0 + 1 s) * 1e7):
RTC is file-internal currency and the Ch 1 packets define its exchange
rate, exactly as on the stations (SYS-006 airborne clause).

The ENU field frame does NOT belong to the aircraft (lesson 22): the
origin comes in from the session's ground set (or rcrc.yaml Station A by
default) and is recorded in TMATS as C\\MAIDEN\\CONVERT\\ORIGIN_LLA.
"""

import struct
import time
from dataclasses import dataclass

import numpy as np

from maiden.ch10 import payloads as pl
from maiden.ch10.writer import Ch10Writer
from maiden.geo import enu_from_lla
from maiden.timebase import encode_time_payload
from maiden.tmats import Station, render_station

RTC_HZ = 10_000_000
GPS_LLA = struct.Struct("<QddffffHI")
IMU_REC = struct.Struct("<BQ6f")
BARO_REC = struct.Struct("<BQf")


@dataclass
class Airframe:
    name: str
    logger_serial: str
    mass_g: float | None
    mount_xyz_mm: tuple | None

    @classmethod
    def from_yaml(cls, path):
        import yaml

        with open(path) as f:
            d = yaml.safe_load(f)
        m = d.get("mount_xyz_mm")
        return cls(name=d["name"], logger_serial=d["logger_serial"],
                   mass_g=d.get("mass_g"),
                   mount_xyz_mm=tuple(m) if m else None)


def _aircraft_tmats(af: Airframe, origin_lla) -> str:
    st = Station(
        station_id=f"AIRCRAFT_{af.name}", serial=af.logger_serial,
        lat=None, lon=None, alt_m=None, hdg_deg=None, cam=None, radar=None,
        channels=[(0, "TMATS", "COM"), (1, "TIME", "TIM"),
                  (3, "GNSS", "PCM"), (4, "ATT", "PCM"),
                  (5, "GPS_LLA", "MSG"), (6, "IMU_BARO", "MSG")],
    )
    extra = [
        f"C\\MAIDEN\\AIRFRAME\\NAME:{af.name};",
        f"C\\MAIDEN\\LOGGER\\SERIAL:{af.logger_serial};",
        "C\\MAIDEN\\LOGGER\\ATT_SOURCE:ARDUPILOT_EKF;",
    ]
    if af.mass_g is not None:
        extra.insert(2, f"C\\MAIDEN\\LOGGER\\MASS_G:{af.mass_g};")
    if af.mount_xyz_mm is not None:
        x, y, z = af.mount_xyz_mm
        extra.append(f"C\\MAIDEN\\LOGGER\\MOUNT_XYZ_MM:{x},{y},{z};")
    extra.append("C\\MAIDEN\\CONVERT\\ORIGIN_LLA:"
                 f"{origin_lla[0]:.7f},{origin_lla[1]:.7f},{origin_lla[2]:.1f};")
    extra.append("C\\MAIDEN\\CONVERT\\GPS_LLA_FMT:<QddffffHI>;")
    extra.append("C\\MAIDEN\\CONVERT\\IMU_REC_FMT:<BQ6f>;")
    extra.append("C\\MAIDEN\\CONVERT\\BARO_REC_FMT:<BQf>;")
    return render_station(st) + "\n".join(extra) + "\n"


def write_aircraft_ch10(rec, airframe: Airframe, out_path, origin_lla):
    """Write the aircraft .ch10; returns (path, stats dict)."""
    utc0 = float(rec.gps_t[0])

    def rtc_of(utc):
        return round((utc - utc0 + 1.0) * RTC_HZ)

    pkts = []
    # Ch 1: 1 Hz time packets spanning the log
    t_first = int(np.floor(min(rec.gps_t[0], rec.imu_t[0] if len(rec.imu_t)
                               else rec.gps_t[0])))
    t_last = int(np.ceil(rec.gps_t[-1]))
    for s in range(t_first, t_last + 1):
        # True UTC day-of-year: the naive (s % 365-day-year) formula was
        # off by the accumulated leap days (14 by 2026), which would
        # misalign airborne vs station absolute time by days and defeat
        # SYS-006's no-manual-offset requirement. Found by adversarial
        # review; stations carry true DOY from IRIG-B, so must we.
        g = time.gmtime(s)
        pkts.append((rtc_of(float(s)), 1, 0x11,
                     encode_time_payload(g.tm_yday, g.tm_hour, g.tm_min,
                                         g.tm_sec)))
    # Ch 3 GNSS (ENU) + Ch 5 GPS_LLA (raw provenance), per GPS fix
    for i in range(len(rec.gps_t)):
        lla = (float(rec.lat[i]), float(rec.lon[i]), float(rec.alt[i]))
        pos = enu_from_lla(origin_lla, lla)
        vel = (float(rec.ve[i]), float(rec.vn[i]), -float(rec.vd[i]))  # NED->ENU
        pkts.append((rtc_of(rec.gps_t[i]), 3, 0x09,
                     pl.pack_truth_gnss(tuple(pos), vel)))
        pkts.append((rtc_of(rec.gps_t[i]), 5, 0x30,
                     GPS_LLA.pack(int(rec.gps_timeus[i]), lla[0], lla[1],
                                  lla[2], float(rec.vn[i]), float(rec.ve[i]),
                                  float(rec.vd[i]), int(rec.gwk[i]),
                                  int(rec.gms[i]))))
    # Ch 4 ATT
    for i in range(len(rec.att_t)):
        pkts.append((rtc_of(rec.att_t[i]), 4, 0x09,
                     pl.pack_truth_att(tuple(rec.rpy[i]))))
    # Ch 6 IMU + BARO tagged records
    for i in range(len(rec.imu_t)):
        pkts.append((rtc_of(rec.imu_t[i]), 6, 0x30,
                     IMU_REC.pack(0, int(rec.imu_timeus[i]),
                                  *rec.acc[i], *rec.gyr[i])))
    for i in range(len(rec.baro_t)):
        pkts.append((rtc_of(rec.baro_t[i]), 6, 0x30,
                     BARO_REC.pack(1, int(rec.baro_timeus[i]),
                                   float(rec.baro_alt[i]))))

    pkts.sort(key=lambda p: p[0])
    w = Ch10Writer(out_path)
    w.write_tmats(max(0, pkts[0][0] - 1),
                  _aircraft_tmats(airframe, origin_lla))
    for rtc, ch, dt, body in pkts:
        w.write_packet(channel=ch, dtype=dt, rtc=rtc, body=body)
    w.close()
    stats = dict(rec.counts())
    stats["fit_resid_rms_s"] = rec.fit[4]
    stats["time_packets"] = t_last - t_first + 1
    return out_path, stats


def read_back(path):
    """Provenance reader for the round-trip test: Ch 5 / Ch 6 records."""
    from maiden.ingest import walk_packets

    gps, imu, baro = [], [], []
    for channel, dtype, _rtc, body in walk_packets(path):
        if channel == 5 and dtype == 0x30:
            gps.append(GPS_LLA.unpack(body))
        elif channel == 6 and dtype == 0x30:
            if body[0] == 0:
                imu.append(IMU_REC.unpack(body))
            else:
                baro.append(BARO_REC.unpack(body))
    return gps, imu, baro
