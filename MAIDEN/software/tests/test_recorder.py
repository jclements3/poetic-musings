"""maiden40: recorder core — rings, framing, merge writer, demux.

The recorder package lives in firmware/ (it runs on the station SBC),
so the repo root's firmware/ dir joins sys.path here.
"""
import struct
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "firmware"))

from recorder import protocol as proto
from recorder.record import main as record_main
from recorder.record import second_frames, station_tmats
from recorder.rings import Ring
from recorder.sources import (
    CameraSource,
    FpgaSource,
    StatusSource,
)
from recorder.writer import RecorderWriter, default_rings

from maiden import ingest
from maiden import timebase as tb
from maiden.ch10 import payloads as pl
from maiden.ch10 import read_packets

# --- rings (written first, per the card) -------------------------------

class TestRing:
    def test_fifo_and_head_rtc(self):
        r = Ring("t", 4)
        for i in range(3):
            assert r.push(100 + i, i)
        assert r.head_rtc() == 100
        assert r.pop() == (100, 0)
        assert r.head_rtc() == 101
        assert len(r) == 2

    def test_overflow_drops_newest_and_counts(self):
        r = Ring("t", 2)
        assert r.push(1, "a") and r.push(2, "b")
        assert not r.push(3, "c")          # newest discarded
        assert r.drops == 1
        assert [r.pop()[1], r.pop()[1]] == ["a", "b"]  # old data intact

    def test_high_water(self):
        r = Ring("t", 8)
        for i in range(5):
            r.push(i, i)
        r.pop()
        assert r.high_water == 5


# --- UART framing ------------------------------------------------------

class TestFraming:
    def test_round_trip_all_types(self):
        frames = [
            (proto.DOPPLER_V, proto.encode_doppler(True, -12.34, 77, 900, 45)),
            (proto.TIME_MARK, proto.encode_time_mark(123456789, 233, 52215)),
            (proto.STROBE_STAMP, proto.encode_strobe(42, 7, False)),
            (proto.PPS_STATUS, proto.encode_pps_status(-15, True)),
        ]
        stream = b"".join(proto.pack_frame(t, i, p)
                          for i, (t, p) in enumerate(frames))
        parser = proto.FrameParser()
        out = parser.feed(stream)
        assert [t for t, _, _ in out] == [t for t, _ in frames]
        det, v_r, fbin, _peak, _noise, snr = proto.decode_doppler(out[0][2])
        assert det and abs(v_r + 12.34) < 0.005 and fbin == 77
        assert snr == pytest.approx(26.02, abs=0.05)   # 20*log10(900/45)
        rtc, day, secs = proto.decode_time_mark(out[1][2])
        assert (rtc, day, secs) == (123456789, 233, 52215)
        off, locked, hold, seen = proto.decode_pps_status(out[3][2])
        assert (off, locked, hold, seen) == (-15, True, False, True)

    def test_checksum_corruption_rejected_and_resync(self):
        good = proto.pack_frame(proto.DOPPLER_V, 0,
                                proto.encode_doppler(True, 1.0, 5, 100, 10))
        bad = bytearray(proto.pack_frame(
            proto.DOPPLER_V, 1, proto.encode_doppler(True, 2.0, 6, 100, 10)))
        bad[4] ^= 0xFF
        tail = proto.pack_frame(proto.DOPPLER_V, 2,
                                proto.encode_doppler(True, 3.0, 7, 100, 10))
        parser = proto.FrameParser()
        out = parser.feed(good + bytes(bad) + tail)
        assert len(out) == 2
        assert parser.bad_frames >= 1
        assert parser.seq_gaps == 1      # seq 0 -> 2

    def test_split_feed(self):
        frame = proto.pack_frame(proto.STROBE_STAMP, 0,
                                 proto.encode_strobe(99, 1))
        parser = proto.FrameParser()
        assert parser.feed(frame[:5]) == []
        out = parser.feed(frame[5:])
        assert len(out) == 1 and proto.decode_strobe(out[0][2])[0] == 99


# --- merge writer with fake sources ------------------------------------

def _bench_session(tmp_path, ring_sizes=None):
    """Drive the full fake path deterministically: pre-load every ring
    with the writer parked, then start+stop so the drain rule writes the
    whole session. No thread races; overflow behavior is exact."""
    rings = default_rings()
    rings[1] = Ring("ch1", 16)
    rings[4] = Ring("ch4", 400)          # fits the 5 s x 50 Hz pre-load
    rings[6] = Ring("ch6", 16)
    if ring_sizes:
        for ch, n in ring_sizes.items():
            rings[ch] = Ring(f"ch{ch}", n)
    out = tmp_path / "STATION_A_test.ch10"
    writer = RecorderWriter(out, station_tmats("A"), rings)
    clk = {"t": 0.0}
    fpga = FpgaSource(port=None, ch1=rings[1], ch4=rings[4],
                      clock=lambda: clk["t"])
    status = StatusSource(fpga, rings[6], writer.total_drops)
    for s in range(5):
        frames = list(second_frames(s))
        clk["t"] = float(s)
        fpga.handle(frames[0])
        for k, frame in enumerate(frames[1:]):
            clk["t"] = s + (k + 1) * 0.02
            fpga.handle(frame)
        status.emit(s * 10_000_000 + 5_000_000, 13.2, 41.0, 80)
    writer.start()
    writer.stop()                        # drain everything, then close
    return out, writer, fpga


class TestMergeWriter:
    def test_file_is_tmats_first_and_rtc_ordered(self, tmp_path):
        out, writer, _ = _bench_session(tmp_path)
        pkts = list(read_packets(out))       # strict reader validates
        assert pkts[0].channel == 0 and pkts[0].dtype == 0x01
        rtcs = [p.rtc for p in pkts]
        assert rtcs == sorted(rtcs)
        chans = {p.channel for p in pkts}
        assert chans == {0, 1, 4, 6}
        assert all(v == 0 for v in writer.stats()["drops"].values())

    def test_ingest_reads_it_back(self, tmp_path):
        out, _, _ = _bench_session(tmp_path)
        desc = ingest.describe(out)
        assert desc.id == "A"
        assert desc.serial == "MAIDEN-STA-001"
        samples = list(ingest.load(out))
        vr = [s for s in samples if s.v_r is not None]
        assert len(vr) >= 200                # 5 s x 50 Hz minus holdback
        events = list(ingest.events(out))
        assert len(events) == 5
        assert all(e.data["pps_lock"] for e in events)
        # summary CLI path
        assert "STATION_A" in ingest.summarize(out)

    def test_time_packets_decode(self, tmp_path):
        out, _, _ = _bench_session(tmp_path)
        dec = tb.decoder_from_file(out)
        assert abs((dec.to_utc(10_000_000) - dec.to_utc(0)) - 1.0) < 1e-6

    def test_overflow_counter_reaches_ch6_payload(self, tmp_path):
        out, writer, _ = _bench_session(tmp_path, ring_sizes={4: 3})
        # cap 3 vs 250 pre-loaded doppler records: exact, deterministic
        assert writer.rings[4].drops == 247
        assert writer.total_drops() > 0
        pkts = [p for p in read_packets(out) if p.channel == 6]
        # last status message carries the saturating drop total in the
        # pad halfword (PROTOCOL.md 0x04 layout)
        total = struct.unpack("<H", pkts[-1].body[10:12])[0]
        assert total == min(writer.total_drops(), 0xFFFF)
        # base struct still parses as the pinned IF-1 STATUS layout
        st = pl.unpack_status(pkts[-1].body)
        assert st.battery_v == pytest.approx(13.2, abs=0.01)

    def test_late_item_clamped_not_fatal(self, tmp_path):
        # A late arrival is only "late" if a later-RTC packet was already
        # written while this ring sat empty — queue-present items get
        # reordered correctly by the merge itself (also asserted here).
        import time as _time
        rings = {1: Ring("ch1", 4), 4: Ring("ch4", 16), 6: Ring("ch6", 4)}
        out = tmp_path / "late.ch10"
        w = RecorderWriter(out, station_tmats("A"), rings)
        rings[1].push(10_000_000, (1, 0x11,
                                   tb.encode_time_payload(233, 12, 0, 1)))
        w.start()
        for _ in range(1000):                 # wait for ch1 to be written
            if w.written >= 1:
                break
            _time.sleep(0.002)
        assert w.written >= 1
        rings[4].push(9_000_000, (4, 0x09, pl.pack_radar_v(1.0, 20.0)))
        w.stop()
        assert w.late_clamped == 1
        pkts = list(read_packets(out))
        assert [p.rtc for p in pkts] == sorted(p.rtc for p in pkts)


class TestCameraAssociation:
    def test_frames_pair_by_index(self, tmp_path):
        rings = default_rings()
        fpga = FpgaSource(port=None, ch1=rings[1], ch4=rings[4])
        cam = CameraSource(fpga, rings[2])
        for i in range(3):
            fpga.handle(proto.pack_frame(
                proto.STROBE_STAMP, i,
                proto.encode_strobe(1000 + 333 * i, i)))
        assert cam.push_frame(b"frame0")
        assert cam.push_frame(b"frame1")
        assert rings[2].head_rtc() == 1000
        # frame arrives before its stamp -> counted, not invented
        cam2 = CameraSource(fpga, rings[2])
        cam2._last_seq = 2
        fpga.strobe_stamps.clear()
        assert not cam2.push_frame(b"early")
        assert cam2.unstamped == 1


class TestCli:
    def test_selftest_writes_valid_file(self, tmp_path, capsys):
        out = tmp_path / "cli.ch10"
        rc = record_main(["--station", "B", "--out", str(out),
                          "--selftest", "3"])
        assert rc == 0
        desc = ingest.describe(out)
        assert desc.id == "B"
        assert "wrote" in capsys.readouterr().out

    def test_without_selftest_refuses_cleanly(self, tmp_path, capsys):
        rc = record_main(["--station", "A",
                          "--out", str(tmp_path / "x.ch10")])
        assert rc == 2
        assert "bench" in capsys.readouterr().err
