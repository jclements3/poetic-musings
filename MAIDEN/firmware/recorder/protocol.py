"""Python side of the station UART record framing.

Wire format: firmware/recorder/PROTOCOL.md — the single owner of the
framing (0xA5 sync / type / seq / fixed payload / two's-complement
checksum) and of every record layout. The VHDL producers cite the same
file (firmware/doppler/rtl/doppler_core.vhd, firmware/timebase/rtl/*).

This module packs frames (for tests and fake sources) and parses byte
streams with the documented resync rule: on a bad checksum, advance one
byte and rescan for sync; count SEQ gaps per type, never die on them.
"""
import math
import struct

SYNC = 0xA5

DOPPLER_V = 0x01
STATION_STATUS = 0x04
PPS_STATUS = 0x10
TIME_MARK = 0x11
STROBE_STAMP = 0x12

PAYLOAD_SIZE = {
    DOPPLER_V: 9,
    STATION_STATUS: 12,
    PPS_STATUS: 4,
    TIME_MARK: 10,
    STROBE_STAMP: 9,
}


def pack_frame(rtype: int, seq: int, payload: bytes) -> bytes:
    if len(payload) != PAYLOAD_SIZE[rtype]:
        raise ValueError(
            f"type 0x{rtype:02x} payload must be {PAYLOAD_SIZE[rtype]} B")
    head = bytes([SYNC, rtype, seq & 0xFF]) + payload
    cksum = (-sum(head)) & 0xFF
    return head + bytes([cksum])


class FrameParser:
    """Feed raw bytes, get validated (type, seq, payload) records out."""

    def __init__(self):
        self._buf = bytearray()
        self._last_seq: dict[int, int] = {}
        self.seq_gaps = 0
        self.bad_frames = 0

    def feed(self, data: bytes):
        self._buf.extend(data)
        out = []
        while True:
            # scan to the next sync byte
            i = self._buf.find(bytes([SYNC]))
            if i < 0:
                self._buf.clear()
                break
            del self._buf[:i]
            if len(self._buf) < 4:
                break
            rtype = self._buf[1]
            size = PAYLOAD_SIZE.get(rtype)
            if size is None:
                self.bad_frames += 1
                del self._buf[:1]
                continue
            total = 3 + size + 1
            if len(self._buf) < total:
                break
            frame = bytes(self._buf[:total])
            if sum(frame) & 0xFF != 0:
                self.bad_frames += 1
                del self._buf[:1]      # resync: slide one byte
                continue
            seq = frame[2]
            last = self._last_seq.get(rtype)
            if last is not None and (last + 1) & 0xFF != seq:
                self.seq_gaps += 1
            self._last_seq[rtype] = seq
            out.append((rtype, seq, frame[3:-1]))
            del self._buf[:total]
        return out


# --- record decoders (layouts per PROTOCOL.md) -------------------------

def decode_doppler(payload: bytes):
    """0x01 -> (det_valid, v_r m/s, bin, peak, noise, snr_db)."""
    flags, v_cm, fbin, peak, noise = struct.unpack("<BhHHH", payload)
    det = bool(flags & 1)
    snr = 20.0 * math.log10(peak / noise) if det and peak and noise else 0.0
    return det, v_cm / 100.0, fbin, peak, noise, snr


def decode_time_mark(payload: bytes):
    """0x11 -> (pps_rtc, day_of_year, seconds_of_day)."""
    pps_rtc = int.from_bytes(payload[0:6], "little")
    packed = struct.unpack("<I", payload[6:10])[0]
    secs = packed & 0x1FFFF          # bits 0-16
    day = (packed >> 17) & 0x1FF     # bits 17-25
    return pps_rtc, day, secs


def encode_time_mark(pps_rtc: int, day: int, secs: int) -> bytes:
    packed = (secs & 0x1FFFF) | ((day & 0x1FF) << 17)
    return pps_rtc.to_bytes(6, "little") + struct.pack("<I", packed)


def decode_strobe(payload: bytes):
    """0x12 -> (rtc, seq, fifo_overflow)."""
    rtc = int.from_bytes(payload[0:6], "little")
    seq, flags = struct.unpack("<HB", payload[6:9])
    return rtc, seq, bool(flags & 1)


def encode_strobe(rtc: int, seq: int, overflow: bool = False) -> bytes:
    return rtc.to_bytes(6, "little") + struct.pack("<HB", seq, int(overflow))


def decode_pps_status(payload: bytes):
    """0x10 -> (offset_counts signed, locked, holdover, pps_seen)."""
    raw = int.from_bytes(payload[0:3], "little")
    if raw & 0x800000:               # sign-extend s20-in-3-bytes
        raw -= 1 << 24
    flags = payload[3]
    return raw, bool(flags & 1), bool(flags & 2), bool(flags & 4)


def encode_pps_status(offset: int, locked: bool, holdover: bool = False,
                      pps_seen: bool = True) -> bytes:
    flags = int(locked) | (int(holdover) << 1) | (int(pps_seen) << 2)
    return (offset & 0xFFFFFF).to_bytes(3, "little") + bytes([flags])


def encode_doppler(det: bool, v_r: float, fbin: int, peak: int,
                   noise: int) -> bytes:
    return struct.pack("<BhHHH", int(det), round(v_r * 100), fbin,
                       peak, noise)
