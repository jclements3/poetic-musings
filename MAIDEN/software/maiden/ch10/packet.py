"""Ch. 10 packet primitives (RCC 106; subset per D4 IF-1)."""
import struct

SYNC = 0xEB25

# data types used by MAIDEN (D4 IF-1 table)
T_TMATS = 0x01
T_TIME = 0x11
T_PCM = 0x09
T_MSG = 0x30
T_VIDEO = 0x40

_HDR = struct.Struct("<HHIIBBBB6sH")  # 24 bytes


def header_checksum(hdr22: bytes) -> int:
    """16-bit sum of the first 11 little-endian words of the header."""
    return sum(struct.unpack("<11H", hdr22)) & 0xFFFF


def data_checksum(body: bytes) -> int:
    """16-bit sum of body as little-endian words (zero-padded)."""
    if len(body) % 2:
        body = body + b"\x00"
    return sum(struct.unpack(f"<{len(body)//2}H", body)) & 0xFFFF


def pack_rtc(rtc: int) -> bytes:
    return rtc.to_bytes(6, "little")
