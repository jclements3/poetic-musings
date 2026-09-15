"""Twin session writer: truth + sensor streams -> real .ch10 files. SW-004.

What the twin honestly is NOT: it writes tracker *outputs* (Ch 5
messages) and radar *velocity outputs* (Ch 4 PCM). It does not synthesize
Ch 2 video or Ch 3 raw radar IF, so it exercises everything downstream of
the tracker and the Doppler DSP and nothing inside them. Lessons 10-11
grow a frame renderer to test the tracker; lesson 17 tests the DSP on the
bench. A twin that quietly claimed to validate those would be the most
expensive lie in the project (lesson 07).

Default layout (D1 site / D3 Figure 2; placeholder until the Phase 0
survey): A at the field origin looking into the box, B 75 m along the
flight line aimed at the same aerial volume, C near the threshold.
Per-station RTC drift is tens of ppm so lesson 04's TimeDecoder has
something real to untangle.
"""
from pathlib import Path

import numpy as np
import yaml

from maiden import timebase as tb
from maiden.ch10 import payloads as pl
from maiden.ch10.writer import Ch10Writer
from maiden.geo import Pose
from maiden.tmats import Station, render_station
from maiden.twin import sensors
from maiden.twin.model import Imperfections, sportsman

RTC_HZ = 10_000_000
# Truth epoch (deterministic; never wall clock): 14 Nov 2026 = DOY 318,
# 14:32:00 UTC — the D4 example session. utc = day*86400 + seconds-of-day.
EPOCH_DAY, EPOCH_H, EPOCH_M = 318, 14, 32
EPOCH_UTC = EPOCH_DAY * 86_400.0 + EPOCH_H * 3600.0 + EPOCH_M * 60.0
STAMP = "20261114_1432"
# Per-station RTC imperfection: (start offset s, drift ppm). No shared
# perfect clock — three stations agreeing exactly would hide field bugs.
RTC_SKEW = {"A": (3.2, +12.0), "B": (7.9, -27.0), "C": (1.4, +8.0)}
# Scripted Station B sun-crossing outage (seconds into the sequence).
SUN_OUTAGE_B = (38.0, 42.0)
SYNC_EVENT_T = 0.5   # "clap" — lesson 14's alignment tripwire


def _flat_lla(origin_lla, enu):
    """Small-offset ENU -> LLA (twin fidelity; survey supersedes)."""
    lat0, lon0, alt0 = origin_lla
    lat = lat0 + enu[1] / 111_320.0
    lon = lon0 + enu[0] / (111_320.0 * np.cos(np.radians(lat0)))
    # plain floats: repr(np.float64) is not a TMATS value (VT-14 caught this)
    return (float(lat), float(lon), float(alt0 + enu[2]))


def default_poses(field_yaml="config/field/rcrc.yaml"):
    """A/B/C Poses for the default layout, derived from rcrc.yaml's A."""
    with open(field_yaml) as f:
        cfg = yaml.safe_load(f)
    a = cfg["stations"]["A"]
    hdg = float(a["heading_deg"])
    box_r = float(cfg["pattern_box"]["center_range_m"])
    h = np.radians(hdg)
    box = box_r * np.array([np.sin(h), np.cos(h), 0.0])  # box center, ENU
    box[2] = 60.0                                        # mid-box altitude
    perp = np.array([np.cos(h), -np.sin(h), 0.0])        # along flight line

    def aimed(pos):
        d = box - pos
        return float(np.degrees(np.arctan2(d[0], d[1])))

    pa = Pose((0.0, 0.0, 0.0), hdg, float(a["boresight_el_deg"]))
    pb_pos = 75.0 * perp
    pc_pos = -110.0 * perp
    pb = Pose(tuple(pb_pos), aimed(pb_pos), 8.0)
    pc = Pose(tuple(pc_pos), aimed(pc_pos), 8.0)
    return {"A": pa, "B": pb, "C": pc}, cfg


def _time_packets(t0, t1, rtc_of):
    """1 Hz Ch 1 packets at integer sequence seconds."""
    out = []
    for s in range(int(np.floor(t0)), int(np.ceil(t1)) + 1):
        utc = EPOCH_UTC + s
        day = int(utc // 86_400)
        sod = utc - day * 86_400
        hh, rem = divmod(sod, 3600)
        mm, ss = divmod(rem, 60)
        body = tb.encode_time_payload(day, int(hh), int(mm), int(ss))
        out.append((rtc_of(s), 1, 0x11, body))
    return out


def _station_file(path, name, pose, streams, t_span, origin_lla, cam):
    off, ppm = RTC_SKEW[name]

    def rtc_of(t):
        return round((off + t) * RTC_HZ * (1.0 + ppm * 1e-6))

    lat, lon, alt = _flat_lla(origin_lla, np.asarray(pose.pos_enu))
    st = Station(
        station_id=f"STATION_{name}", serial=f"MAIDEN-STA-00{ord(name)-64}",
        lat=lat, lon=lon, alt_m=alt, hdg_deg=pose.heading_deg,
        cam=cam,
        radar={"module": "CDM324", "f_ghz": 24.125,
               "boresight_az": 0.0, "boresight_el": pose.boresight_el_deg},
        channels=[(0, "TMATS", "COM"), (1, "TIME", "TIM"),
                  (4, "RADAR_V", "PCM"), (5, "TRACKER", "MSG"),
                  (6, "STATUS", "MSG")],
    )
    pkts = _time_packets(*t_span, rtc_of)
    for t, az, el, conf in streams.tracker:
        pkts.append((rtc_of(t), 5, 0x30, pl.pack_tracker(az, el, conf)))
    for t, v_r, snr in streams.radar:
        pkts.append((rtc_of(t), 4, 0x09, pl.pack_radar_v(v_r, snr)))
    for s in range(int(t_span[0]), int(t_span[1]) + 1):
        pkts.append((rtc_of(s + 0.05), 6, 0x30,
                     pl.pack_status(13.2, 25.0, True, 80)))
    pkts.sort(key=lambda p: p[0])
    w = Ch10Writer(path)
    w.write_tmats(max(0, pkts[0][0] - 1), render_station(st))
    for rtc, ch, dt, body in pkts:
        w.write_packet(channel=ch, dtype=dt, rtc=rtc, body=body)
    w.close()


def _truth_file(path, truth):
    def rtc_of(t):
        return round(t * RTC_HZ)    # GPS-disciplined: no drift

    st = Station(
        station_id="TRUTH", serial="MAIDEN-AB-001",
        lat=None, lon=None, alt_m=None, hdg_deg=None, cam=None, radar=None,
        channels=[(0, "TMATS", "COM"), (1, "TIME", "TIM"),
                  (3, "GNSS", "PCM"), (4, "ATT", "PCM")],
    )
    pkts = _time_packets(truth.t[0], truth.t[-1], rtc_of)
    for i in range(0, len(truth.t), 10):          # 10 Hz GNSS-shaped
        pkts.append((rtc_of(truth.t[i]), 3, 0x09,
                     pl.pack_truth_gnss(truth.pos_enu[i], truth.vel_enu[i])))
    for i in range(len(truth.t)):                 # 100 Hz ATT
        pkts.append((rtc_of(truth.t[i]), 4, 0x09,
                     pl.pack_truth_att(truth.att_rpy[i])))
    pkts.sort(key=lambda p: p[0])
    w = Ch10Writer(path)
    w.write_tmats(max(0, pkts[0][0] - 1), render_station(st))
    for rtc, ch, dt, body in pkts:
        w.write_packet(channel=ch, dtype=dt, rtc=rtc, body=body)
    w.close()


def write_session(out_dir, seed: int = 0, imperfect: bool = False) -> dict:
    """Write STATION_A/B/C + TRUTH .ch10 files and truth.npz. Returns paths."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    imp = Imperfections()
    if imperfect:
        imp = Imperfections(
            loop_ovality=float(rng.uniform(0.05, 0.2)),
            roll_drift_deg=float(rng.uniform(-8.0, 8.0)),
            alt_mismatch_m=float(rng.uniform(-6.0, 6.0)),
            center_offset_m=float(rng.uniform(-10.0, 10.0)),
        )
    truth = sportsman(imp, seed=seed)
    poses, cfg = default_poses()
    cam = {"fx": 1820.4, "fy": 1819.9, "cx": 960.2, "cy": 541.7,
           "k1": -0.112, "k2": 0.041}
    origin_lla = tuple(cfg["field_origin"]["lla"])
    t_span = (truth.t[0], truth.t[-1])

    paths = {}
    for name, pose in poses.items():
        streams = sensors.observe(
            truth, pose, rng=np.random.default_rng(seed * 1000 + ord(name)),
            outage=SUN_OUTAGE_B if name == "B" else None)
        p = out / f"STATION_{name}_{STAMP}.ch10"
        _station_file(p, name, pose, streams, t_span, origin_lla, cam)
        paths[name] = p

    paths["TRUTH"] = out / f"TRUTH_{STAMP}.ch10"
    _truth_file(paths["TRUTH"], truth)

    npz = out / "truth.npz"
    np.savez(
        npz, t=truth.t, pos_enu=truth.pos_enu, vel_enu=truth.vel_enu,
        att_rpy=truth.att_rpy,
        event_t=np.array([e.t_utc for e in truth.events]),
        event_kind=np.array([e.kind for e in truth.events]),
        epoch_utc=EPOCH_UTC, sync_event_utc=EPOCH_UTC + SYNC_EVENT_T,
        seed=seed,
    )
    paths["npz"] = npz
    return paths
