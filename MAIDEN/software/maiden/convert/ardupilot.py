"""ArduPilot DataFlash .bin adapter (the real one, per lesson 22).

Two clocks in every log: TimeUS (microseconds since boot, drifting
crystal) on every message, and GWk/GMS (absolute GPS time) on GPS
messages only. A least-squares line utc = a*(TimeUS-t0) + b + u0 over
all locked GPS fixes transfers the absolute clock onto the relative one;
every IMU/BARO/ATT sample is then stamped through the fit. Fit is
demeaned about the first point for the same float64-conditioning reason
as maiden.timebase (lesson 04 erratum).

GPS time -> UTC needs the leap-second correction, pinned loudly below.
"""

import numpy as np

from .adapters import AirborneRecords

# GPS epoch 1980-01-06T00:00:00 UTC as a Unix timestamp.
GPS_EPOCH_UNIX = 315_964_800.0

# LEAP SECONDS (GPS - UTC). 18 s since 2017-01-01 and still 18 as of the
# current IERS bulletin. If this is wrong, truth is wrong by 18 m at
# pattern speeds -- VT-02's clap check exists to catch exactly this.
# ArduPilot logs do not reliably carry the field, so it is a constant.
LEAP_SECONDS = 18.0


def gps_to_utc(gwk, gms) -> float:
    """GPS week/ms-of-week -> UTC seconds (Unix epoch)."""
    return GPS_EPOCH_UNIX + float(gwk) * 604_800.0 + float(gms) * 1e-3 \
        - LEAP_SECONDS


class ArduPilotBin:
    suffixes = (".bin", ".BIN")

    def read(self, path) -> AirborneRecords:
        from pymavlink import DFReader

        log = DFReader.DFReader_binary(str(path))
        gps, imu, baro, att = [], [], [], []
        while True:
            m = log.recv_msg()
            if m is None:
                break
            t = m.get_type()
            if t == "GPS":
                gps.append((m.TimeUS, m.GWk, m.GMS, m.Lat, m.Lng, m.Alt,
                            m.VN, m.VE, m.VD))
            elif t == "IMU":
                imu.append((m.TimeUS, m.AccX, m.AccY, m.AccZ,
                            m.GyrX, m.GyrY, m.GyrZ))
            elif t == "BARO":
                baro.append((m.TimeUS, m.Alt))
            elif t == "ATT":
                att.append((m.TimeUS, m.Roll, m.Pitch, m.Yaw))
        if not gps:
            raise ValueError(f"{path}: no GPS messages — cannot fit UTC")
        g = np.array(gps, float)
        locked = g[:, 1] > 0                      # reject GWk == 0: no lock
        if locked.sum() < 2:
            raise ValueError(f"{path}: fewer than two locked GPS fixes")
        g = g[locked]

        timeus = g[:, 0]
        utc = np.array([gps_to_utc(w, ms) for w, ms in zip(g[:, 1], g[:, 2])])
        t0, u0 = timeus[0], utc[0]
        a, b = np.polyfit(timeus - t0, utc - u0, 1)
        resid = a * (timeus - t0) + b + u0 - utc
        resid_rms = float(np.sqrt(np.mean(resid ** 2)))

        def stamp(tus):
            tus = np.asarray(tus, float)
            return a * (tus - t0) + b + u0

        imu_a = np.array(imu, float) if imu else np.zeros((0, 7))
        baro_a = np.array(baro, float) if baro else np.zeros((0, 2))
        att_a = np.array(att, float) if att else np.zeros((0, 4))

        # DFReader applies the 'L' multiplier (1e-7 deg) itself when the
        # value is int-scaled; guard for raw-int variants.
        lat, lon = g[:, 3], g[:, 4]
        if np.abs(lat).max(initial=0.0) > 360.0:
            lat, lon = lat * 1e-7, lon * 1e-7

        return AirborneRecords(
            gps_t=stamp(timeus), lat=lat, lon=lon, alt=g[:, 5],
            vn=g[:, 6], ve=g[:, 7], vd=g[:, 8],
            gwk=g[:, 1].astype(np.uint16), gms=g[:, 2].astype(np.uint32),
            gps_timeus=timeus.astype(np.uint64),
            imu_t=stamp(imu_a[:, 0]), acc=imu_a[:, 1:4], gyr=imu_a[:, 4:7],
            imu_timeus=imu_a[:, 0].astype(np.uint64),
            baro_t=stamp(baro_a[:, 0]), baro_alt=baro_a[:, 1],
            baro_timeus=baro_a[:, 0].astype(np.uint64),
            att_t=stamp(att_a[:, 0]), rpy=att_a[:, 1:4],
            att_timeus=att_a[:, 0].astype(np.uint64),
            fit=(float(a), float(b), float(t0), float(u0), resid_rms),
        )
