"""Regressions from the adversarial data-path review (post-maiden57).

Each test pins a confirmed bug fix:
  1. reader: packet_len=0 header looped forever (yield + off+=0).
  2. reader: oversized data_len silently served trailer/next-packet bytes.
  3. timebase: BCD Hmn digit had 3 bits; ms >= 800 corrupted the seconds
     field (layout now nibble-aligned per RCC 106 Time F1).
  4. timebase: midnight unwrap kept a sticky +86 400 when the source's
     day field incremented one packet late.
  5. convert: day-of-year used a 365-day-year formula (off by the
     accumulated leap days -> airborne/station absolute misalignment).
"""
import calendar
import struct
from itertools import islice, pairwise

import pytest

from maiden import timebase as tb
from maiden.ch10 import Ch10Error, read_packets
from maiden.ch10 import packet as pk

TMATS = "G\\PN:MAIDEN;\nG\\DSI\\N:1;  G\\DSI-1:STATION_A;\n"


def _raw_packet(channel, dtype, rtc, body, packet_len=None, data_len=None,
                flags=0x00, seq=0):
    if data_len is None:
        data_len = len(body)
    if packet_len is None:
        packet_len = 24 + len(body)
    hdr22 = struct.pack("<HHIIBBBB6s", pk.SYNC, channel, packet_len,
                        data_len, 0x06, seq, flags, dtype, pk.pack_rtc(rtc))
    return hdr22 + struct.pack("<H", pk.header_checksum(hdr22)) + body


def _tmats_first():
    return _raw_packet(0, pk.T_TMATS, 0, TMATS.encode())


def test_reader_rejects_zero_packet_len(tmp_path):
    p = tmp_path / "z.ch10"
    p.write_bytes(_tmats_first()
                  + _raw_packet(1, pk.T_TIME, 10, b"", packet_len=0))
    with pytest.raises(Ch10Error, match="nonsense lengths"):
        list(islice(read_packets(p), 10))


def test_reader_rejects_data_len_overrun(tmp_path):
    p = tmp_path / "o.ch10"
    body = b"ABCD"
    evil = _raw_packet(5, pk.T_MSG, 10, body, data_len=40,
                       packet_len=24 + len(body))
    p.write_bytes(_tmats_first() + evil)
    with pytest.raises(Ch10Error, match="nonsense lengths"):
        list(read_packets(p))


def test_ingest_walker_rejects_data_len_into_trailer(tmp_path):
    """walk_packets: data_len may not reach the 2-byte checksum trailer."""
    from maiden.ingest import IngestError, walk_packets

    body = b"ABCD"
    evil = _raw_packet(5, pk.T_MSG, 10, body, data_len=len(body) + 1,
                       packet_len=24 + len(body) + 2, flags=0x02)
    p = tmp_path / "t.ch10"
    p.write_bytes(_tmats_first() + evil)
    with pytest.raises(IngestError, match="nonsense lengths"):
        list(walk_packets(p))


@pytest.mark.parametrize("ms", [0, 10, 700, 800, 990])
def test_bcd_ms_full_digit_range(ms):
    day, sod = tb.decode_time_payload(
        tb.encode_time_payload(233, 14, 30, 5, ms=ms))
    assert day == 233
    assert sod == pytest.approx(14 * 3600 + 30 * 60 + 5 + ms / 1000.0,
                                abs=1e-6)


def test_unwrap_survives_late_day_increment():
    """Day field catching up one packet after the seconds wrapped must
    not leave a permanent +86 400 in the stream."""
    seq = [(233, 86398), (233, 86399), (233, 0), (234, 1), (234, 2)]
    pairs = []
    for i, (day, sod) in enumerate(seq):
        h, rem = divmod(sod, 3600)
        m, s = divmod(rem, 60)
        pairs.append((i * 10_000_000, tb.encode_time_payload(day, h, m, s)))
    dec = tb.decoder_from_packets(pairs)
    utcs = [p.utc for p in dec.points]
    deltas = [b - a for a, b in pairwise(utcs)]
    assert all(abs(d - 1.0) < 0.5 for d in deltas), deltas
    assert abs(dec.drift_ppm) < 1.0


def test_unwrap_still_handles_constant_day_source():
    """A source that never increments its day field still unwraps."""
    seq = [(233, 86398), (233, 86399), (233, 0), (233, 1)]
    pairs = []
    for i, (day, sod) in enumerate(seq):
        h, rem = divmod(sod, 3600)
        m, s = divmod(rem, 60)
        pairs.append((i * 10_000_000, tb.encode_time_payload(day, h, m, s)))
    dec = tb.decoder_from_packets(pairs)
    utcs = [p.utc for p in dec.points]
    deltas = [b - a for a, b in pairwise(utcs)]
    assert all(abs(d - 1.0) < 0.5 for d in deltas), deltas


def test_convert_time_channel_carries_true_day_of_year(tmp_path):
    """Aircraft Ch 1 day must be the real UTC DOY (stations carry true
    DOY from IRIG-B; a mismatch breaks SYS-006's no-manual-offset)."""
    from maiden.convert import Airframe, get_adapter, write_aircraft_ch10
    from maiden.convert.synth import write_synthetic_bin

    # 2026-08-21 14:30:00 UTC = DOY 233
    utc0 = calendar.timegm((2026, 8, 21, 14, 30, 0, 0, 0, 0))
    src = tmp_path / "synth.bin"
    write_synthetic_bin(src, utc0=float(utc0), duration_s=5.0)
    rec = get_adapter(src).read(src)
    af = Airframe(name="TEST", logger_serial="T-1", mass_g=None,
                  mount_xyz_mm=None)
    out = tmp_path / "AIRCRAFT_TEST.ch10"
    write_aircraft_ch10(rec, af, out, (34.685171, -86.592244, 183.2))

    days = [tb.decode_time_payload(b)[0]
            for _ch, dt, _rtc, b in _walk(out) if dt == 0x11]
    assert days and all(d == 233 for d in days), days


def _walk(path):
    from maiden.ingest import walk_packets

    yield from walk_packets(path)
