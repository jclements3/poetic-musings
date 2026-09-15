"""Validating Ch. 10 reader: yields (channel, dtype, rtc, body) tuples.

Stricter than PyChapter10: this reader verifies both checksums, RTC
order, per-channel sequence continuity, and TMATS-first on every walk
(PyChapter10 parses structure but does not enforce the file-level
invariants; corrupting a checksum byte upsets us and not it — see
test_ch10.py::test_corruption_strictness).
"""
import struct
from typing import NamedTuple

from . import packet as pk

_HDR = struct.Struct("<HHIIBBBB6sH")


class Packet(NamedTuple):
    """One validated packet. Tuple-compatible: (channel, dtype, rtc, body)."""

    channel: int
    dtype: int
    rtc: int
    body: bytes


class Ch10Error(Exception):
    def __init__(self, msg: str, offset: int):
        super().__init__(f"{msg} (at file offset {offset})")
        self.offset = offset


def read_packets(path):
    """Yield (channel, dtype, rtc, body) for every packet, validating."""
    with open(path, "rb") as f:
        data = f.read()
    off = 0
    last_rtc = -1
    seq = {}
    first = True
    while off < len(data):
        if len(data) - off < 24:
            raise Ch10Error("truncated header", off)
        (sync, channel, packet_len, data_len, _ver, seqno, flags,
         dtype, rtc6, hcs) = _HDR.unpack_from(data, off)
        if sync != pk.SYNC:
            raise Ch10Error(f"bad sync 0x{sync:04x}", off)
        if pk.header_checksum(data[off:off + 22]) != hcs:
            raise Ch10Error("header checksum mismatch", off)
        # Length sanity BEFORE trusting either field: packet_len < 24
        # would stall the walk (packet_len == 0 loops forever), and a
        # data_len reaching past the payload region would serve the
        # trailer/next packet's bytes as body.
        trailer = 2 if flags & 0x03 == 0x02 else 0
        if packet_len < 24 + trailer or data_len > packet_len - 24 - trailer:
            raise Ch10Error(
                f"nonsense lengths: packet_len={packet_len} "
                f"data_len={data_len}", off)
        if off + packet_len > len(data):
            raise Ch10Error("truncated packet body", off)
        rtc = int.from_bytes(rtc6, "little")
        if rtc < last_rtc:
            raise Ch10Error(f"RTC decreased {last_rtc} -> {rtc}", off)
        expect = seq.get(channel)
        if expect is not None and seqno != expect:
            raise Ch10Error(
                f"ch {channel} sequence gap: got {seqno}, want {expect}",
                off)
        body = data[off + 24:off + 24 + data_len]
        if flags & 0x03 == 0x02:
            padded = data[off + 24:off + packet_len - 2]
            (dcs,) = struct.unpack_from("<H", data, off + packet_len - 2)
            if pk.data_checksum(padded) != dcs:
                raise Ch10Error("data checksum mismatch", off)
        if first:
            if channel != 0 or dtype != pk.T_TMATS:
                raise Ch10Error("first packet is not TMATS on channel 0",
                                off)
            first = False
        yield Packet(channel, dtype, rtc, body)
        seq[channel] = (seqno + 1) & 0xFF
        last_rtc = rtc
        off += packet_len
