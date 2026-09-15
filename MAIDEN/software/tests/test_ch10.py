"""maiden03/04: Ch. 10 packet core, reader, writer, PyChapter10 referee."""
import struct

import pytest

from maiden.ch10 import Ch10Error, Ch10Writer, read_packets
from maiden.ch10 import packet as pk


def _hand_packet(channel, dtype, rtc, body, seq=0, corrupt=None):
    """Build one packet by hand (maiden03: no writer yet)."""
    filler = (2 - len(body)) % 4
    padded = body + b"\x00" * filler
    packet_len = 24 + len(padded) + 2
    hdr22 = struct.pack("<HHIIBBBB6s", pk.SYNC, channel, packet_len,
                        len(body), 0x06, seq, 0x02, dtype,
                        pk.pack_rtc(rtc))
    raw = (hdr22 + struct.pack("<H", pk.header_checksum(hdr22))
           + padded + struct.pack("<H", pk.data_checksum(padded)))
    if corrupt == "sync":
        raw = b"\x00\x00" + raw[2:]
    elif corrupt == "checksum":
        raw = raw[:22] + struct.pack("<H", 0xDEAD) + raw[24:]
    return raw


def _tmats_body(text="G\\PN:MAIDEN;"):
    return struct.pack("<I", 0) + text.encode("ascii")


def test_reader_hand_built_fixture(tmp_path):
    p = tmp_path / "a.ch10"
    p.write_bytes(
        _hand_packet(0, pk.T_TMATS, 100, _tmats_body())
        + _hand_packet(1, pk.T_TIME, 200, b"\x01\x02\x03\x04" * 3)
        + _hand_packet(3, pk.T_PCM, 300, b"\xAA" * 10))
    pkts = list(read_packets(p))
    assert [(c, d, r) for c, d, r, _ in pkts] == [
        (0, pk.T_TMATS, 100), (1, pk.T_TIME, 200), (3, pk.T_PCM, 300)]
    assert pkts[2][3] == b"\xAA" * 10  # body survives, filler stripped


@pytest.mark.parametrize("corrupt,msg", [
    ("sync", "bad sync"), ("checksum", "header checksum")])
def test_reader_corruption_offset(tmp_path, corrupt, msg):
    good = _hand_packet(0, pk.T_TMATS, 100, _tmats_body())
    bad = _hand_packet(1, pk.T_TIME, 200, b"\x00" * 12, corrupt=corrupt)
    p = tmp_path / "bad.ch10"
    p.write_bytes(good + bad)
    with pytest.raises(Ch10Error) as ei:
        list(read_packets(p))
    assert ei.value.offset == len(good)  # right offset
    assert msg in str(ei.value)


def test_reader_backward_rtc(tmp_path):
    good = _hand_packet(0, pk.T_TMATS, 500, _tmats_body())
    p = tmp_path / "rtc.ch10"
    p.write_bytes(good + _hand_packet(1, pk.T_TIME, 400, b"\x00" * 12))
    with pytest.raises(Ch10Error) as ei:
        list(read_packets(p))
    assert "RTC decreased" in str(ei.value)
    assert ei.value.offset == len(good)


def _write_session(path, tmats_text="G\\PN:MAIDEN;"):
    w = Ch10Writer(path)
    w.write_tmats(100, tmats_text)
    w.write_packet(1, pk.T_TIME, 200, b"\x11" * 12)
    w.write_packet(1, pk.T_TIME, 300, b"\x22" * 12)
    w.write_packet(3, pk.T_PCM, 400, b"\x33" * 10)
    w.close()


def test_writer_reader_roundtrip(tmp_path):
    p = tmp_path / "s.ch10"
    _write_session(p)
    pkts = list(read_packets(p))
    assert [(c, d, r) for c, d, r, _ in pkts] == [
        (0, pk.T_TMATS, 100), (1, pk.T_TIME, 200),
        (1, pk.T_TIME, 300), (3, pk.T_PCM, 400)]
    assert pkts[0][3][4:] == b"G\\PN:MAIDEN;"  # after 4-byte CSDW


def test_pychapter10_referee(tmp_path):
    p = tmp_path / "ref.ch10"
    _write_session(p)
    from chapter10 import C10
    got = [(pkt.channel_id, pkt.data_type) for pkt in C10(str(p))]
    assert got == [(0, pk.T_TMATS), (1, pk.T_TIME),
                   (1, pk.T_TIME), (3, pk.T_PCM)]


def test_writer_violations(tmp_path):
    w = Ch10Writer(tmp_path / "v1.ch10")
    with pytest.raises(ValueError, match="TMATS"):
        w.write_packet(3, pk.T_PCM, 100, b"\x00" * 4)  # PCM before TMATS
    w.write_tmats(100, "G\\PN:MAIDEN;")
    with pytest.raises(ValueError, match="nondecreasing"):
        w.write_packet(1, pk.T_TIME, 50, b"\x00" * 12)  # backward RTC
    with pytest.raises(ValueError, match="not in D4 IF-1"):
        w.write_packet(2, pk.T_PCM, 200, b"\x00" * 4)  # video ch, PCM type
    w.close()


def test_corruption_strictness(tmp_path):
    """Explore 1: flip one data byte — our reader is stricter than
    PyChapter10 (we verify the data checksum; it parses structure only)."""
    p = tmp_path / "c.ch10"
    _write_session(p)
    raw = bytearray(p.read_bytes())
    raw[-6] ^= 0x01  # a data byte inside the last packet's body
    p.write_bytes(bytes(raw))
    with pytest.raises(Ch10Error, match="data checksum"):
        list(read_packets(p))
    from chapter10 import C10
    assert len(list(C10(str(p)))) == 4  # PyChapter10: indifferent
