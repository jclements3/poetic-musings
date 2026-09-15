"""Minimal Ch. 10 writer: TMATS-first, RTC-ordered, IF-1 types only."""
import struct

from . import packet as pk

_ALLOWED = {0: pk.T_TMATS, 1: pk.T_TIME, 2: pk.T_VIDEO,
            3: pk.T_PCM, 4: pk.T_PCM, 5: pk.T_MSG, 6: pk.T_MSG}


class Ch10Writer:
    def __init__(self, path):
        self._f = open(path, "wb")  # noqa: SIM115 — writer owns the handle until close()
        self._seq = {}          # channel -> next sequence number
        self._last_rtc = -1
        self._wrote_tmats = False

    def write_packet(self, channel: int, dtype: int, rtc: int,
                     body: bytes) -> None:
        if _ALLOWED.get(channel) != dtype:
            raise ValueError(
                f"channel {channel} / dtype 0x{dtype:02x} not in D4 IF-1")
        if not self._wrote_tmats and dtype != pk.T_TMATS:
            raise ValueError("first packet must be TMATS (channel 0)")
        if rtc < self._last_rtc:
            raise ValueError(
                f"RTC not nondecreasing: {rtc} < {self._last_rtc}")

        # Padding arithmetic: packet_len = 24 (header) + len(body)
        # + filler + 2 (16-bit data checksum) must be a multiple of 4,
        # so filler = (-(len(body) + 2)) % 4 == (2 - len(body)) % 4.
        # The data checksum covers body + filler; data_len counts only
        # the payload (body), excluding filler and checksum.
        filler = (2 - len(body)) % 4
        padded = body + b"\x00" * filler
        packet_len = 24 + len(padded) + 2

        seq = self._seq.get(channel, 0)
        # flags 0b10: 16-bit data checksum present; no secondary header
        hdr22 = struct.pack(
            "<HHIIBBBB6s", pk.SYNC, channel, packet_len, len(body),
            0x06, seq, 0x02, dtype, pk.pack_rtc(rtc))
        hdr = hdr22 + struct.pack("<H", pk.header_checksum(hdr22))

        self._f.write(hdr)
        self._f.write(padded)
        self._f.write(struct.pack("<H", pk.data_checksum(padded)))

        self._seq[channel] = (seq + 1) & 0xFF
        self._last_rtc = rtc
        if dtype == pk.T_TMATS:
            self._wrote_tmats = True

    def write_tmats(self, rtc: int, tmats_text: str) -> None:
        # CSDW for computer-generated F1: 4 bytes, 0 is acceptable here
        body = struct.pack("<I", 0) + tmats_text.encode("ascii")
        self.write_packet(0, pk.T_TMATS, rtc, body)

    def close(self):
        self._f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
