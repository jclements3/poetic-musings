"""maiden12: twin .ch10 emission behind the pinned CLI (lesson 07)."""

import collections

import numpy as np
from chapter10 import C10

from maiden import timebase as tb
from maiden.ch10 import payloads as pl
from maiden.ch10 import read_packets
from maiden.twin.writer import RTC_SKEW, SUN_OUTAGE_B, write_session


def _counts(path):
    c = collections.Counter()
    for p in C10(str(path)):
        c[(p.channel_id, p.data_type)] += 1
    return c


def test_session_files_referee(tmp_path):
    """PyChapter10 (independent reader) sees the IF-1 channels."""
    paths = write_session(tmp_path, seed=1)
    for name in "ABC":
        c = _counts(paths[name])
        assert c[(0, 0x01)] == 1          # TMATS, exactly once
        assert c[(1, 0x11)] > 50          # 1 Hz time over the sequence
        assert c[(4, 0x09)] > 1000        # RADAR_V at 50 Hz
        assert c[(5, 0x30)] > 500         # TRACKER at 30 Hz
        assert c[(6, 0x30)] > 50          # STATUS at 1 Hz
    ct = _counts(paths["TRUTH"])
    assert ct[(3, 0x09)] > 500            # GNSS-shaped 10 Hz
    assert ct[(4, 0x09)] > 5000           # ATT 100 Hz


def test_outage_and_drift_present(tmp_path):
    paths = write_session(tmp_path, seed=1)
    a = _counts(paths["A"])[(5, 0x30)]
    b = _counts(paths["B"])[(5, 0x30)]
    # B lost ~ the sun-outage window of tracker messages relative to A
    lost = (SUN_OUTAGE_B[1] - SUN_OUTAGE_B[0]) * 30.0
    assert a - b > 0.6 * lost
    # injected per-station drift is recovered by the TimeDecoder
    for name in "ABC":
        dec = tb.decoder_from_file(paths[name])
        assert abs(abs(dec.drift_ppm) - abs(RTC_SKEW[name][1])) < 2.0


def test_payload_round_trip(tmp_path):
    paths = write_session(tmp_path, seed=1)
    saw_tracker = saw_radar = False
    for pkt in read_packets(paths["A"]):
        if pkt.channel == 5:
            tr = pl.unpack_tracker(pkt.body)
            assert -180.0 <= tr.az_deg <= 180.0 and 0.5 <= tr.conf <= 1.0
            saw_tracker = True
        elif pkt.channel == 4:
            rv = pl.unpack_radar_v(pkt.body)
            assert -60.0 < rv.v_r < 60.0
            saw_radar = True
    assert saw_tracker and saw_radar


def test_determinism_and_npz(tmp_path):
    p1 = write_session(tmp_path / "s1", seed=5)
    p2 = write_session(tmp_path / "s2", seed=5)
    assert (p1["npz"].read_bytes() == p2["npz"].read_bytes())
    assert (p1["A"].read_bytes() == p2["A"].read_bytes())
    z = np.load(p1["npz"], allow_pickle=False)
    for key in ("t", "pos_enu", "vel_enu", "att_rpy", "event_t",
                "event_kind", "epoch_utc", "sync_event_utc", "seed"):
        assert key in z, key
    assert float(z["sync_event_utc"]) > float(z["epoch_utc"])


def test_imperfect_differs(tmp_path):
    p1 = write_session(tmp_path / "i0", seed=5)
    p2 = write_session(tmp_path / "i1", seed=5, imperfect=True)
    z1, z2 = np.load(p1["npz"]), np.load(p2["npz"])
    rms = np.sqrt(np.mean((z1["pos_enu"] - z2["pos_enu"]) ** 2))
    assert rms > 1.0
