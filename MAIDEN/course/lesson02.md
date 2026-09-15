# Lesson 02 — IRIG-106 Chapter 10 [desk]

*Where we are.* You have a repo and a coordinate frame. Now the container:
every byte MAIDEN records — video, radar IF, velocities, tracker messages,
status, time — travels in IRIG-106 Chapter 10 files (SYS-005), one file per
station per session, packets interleaved by time (D4 IF-1). Before the twin
can write these files (lesson 07) or the recorder produce them on hardware
(lesson 19), you need to understand the packet format cold and own a
minimal reader/writer. Ch. 10 looks bureaucratic until you notice it solves
the exact problem that kills hobby multi-sensor rigs: one container, one
timebase, self-describing.

## Objectives

- Draw the Ch. 10 packet header from memory: sync, channel ID, lengths,
  sequence, data type, 48-bit RTC, checksum.
- Implement `maiden/ch10/` with a packet writer covering the four data
  types in D4's IF-1 table (0x01, 0x11, 0x09, 0x30) and a reader.
- Round-trip a file through PyChapter10 as an independent check.
- Know precisely which parts of the standard this project scopes out.

## Concepts

### The packet

A Ch. 10 file is nothing but a stream of packets. Every packet begins with
a 24-byte header, little-endian throughout:

```
offset size  field
 0      2    sync pattern        0xEB25
 2      2    channel ID          which sensor stream (IF-1: 0..6)
 4      4    packet length       header + body + trailer, bytes (mult. of 4)
 8      4    data length         payload bytes (excl. header, secondary
                                 header, filler, data checksum)
12      1    data type version   0x06 (RCC 106-13 era) is fine here
13      1    sequence number     per-channel, wraps at 256
14      1    packet flags        bit0..1: data checksum type; bit7:
                                 secondary header present (we never set it)
15      1    data type           0x01 TMATS / 0x11 time / 0x09 PCM /
                                 0x30 message / 0x40 video ...
16      6    RTC                 48-bit free-running 10 MHz counter
22      2    header checksum     16-bit sum of the 11 preceding 16-bit words
```

The body is data-type-specific and almost always starts with a
**channel-specific data word (CSDW)** — 4 bytes of per-type flags. After
the body: optional filler to a 4-byte boundary, then a data checksum whose
presence/width the packet flags declare (we use the 16-bit variant, flags
bits = 0b10).

Two invariants matter more than any field: (1) the **RTC** in every header
is the same free-running 10 MHz counter for the whole file, so packets
from different channels interleave on a common axis even before you know
what time it is; (2) the **time packet** (type 0x11) is what maps that
counter to real time — lesson 04's whole subject.

### The file

Rules MAIDEN inherits from the standard and enforces (VT-01 checks them):

- First packet is the TMATS setup record (type 0x01, channel 0) — the file
  describes itself before any data appears.
- Packets appear in nondecreasing RTC order across the whole file.
- Per-channel sequence numbers increment without gaps (drop detection).

### What we scope out — said once, honestly

Real Ch. 10 has: secondary headers with absolute time, intra-packet time
stamps (IPTS) per message/frame, 32-bit checksum variants, data type
versions per RCC release, recording/root index packets for fast seeking,
and a dozen data formats (1553, ARINC, analog, Ethernet...). MAIDEN uses
none of the indexing, always omits secondary headers, uses IPTS only where
the format requires them (video and message types — lessons 07/19 add
them per type), and reads/writes only types 0x01, 0x11, 0x09, 0x30, 0x40.
If a third-party tool writes files our reader chokes on, the reader is
wrong; if our writer produces files `i106stat` or PyChapter10 chokes on,
our writer is wrong. That asymmetry is the discipline.

### Tooling

```bash
pip install pychapter10
```

PyChapter10 is the pure-Python reference reader; `irig106lib` (C, with
`i106stat` and `idmptmat` utilities) is the ecosystem's workhorse and what
VT-01 names. Install irig106lib when you reach lesson 19; PyChapter10
suffices for the desk lessons. Our own `maiden.ch10` exists because the
twin must *write* packets exactly to spec, and writing is where you learn
a format.

## Doc Trace

- **SYS-005** — implemented incrementally from here through lesson 19;
  formally verified by VT-01 on the bench.
- **D4 IF-1** — the channel map and data-type table this module encodes;
  the writer refuses channel/type pairs not in that table.
- **D3 §Key architecture decisions** — "one container, one timebase" is
  the decision this lesson turns into code.

## Build

Create `software/maiden/ch10/` with `__init__.py`, `packet.py`,
`writer.py`, `reader.py`.

**File: software/maiden/ch10/packet.py**

```python
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
```

**File: software/maiden/ch10/writer.py** — *skeleton*; you fill the marked
holes:

```python
"""Minimal Ch. 10 writer: TMATS-first, RTC-ordered, IF-1 types only."""
import struct

from . import packet as pk

_ALLOWED = {0: pk.T_TMATS, 1: pk.T_TIME, 2: pk.T_VIDEO,
            3: pk.T_PCM, 4: pk.T_PCM, 5: pk.T_MSG, 6: pk.T_MSG}


class Ch10Writer:
    def __init__(self, path):
        self._f = open(path, "wb")
        self._seq = {}          # channel -> next sequence number
        self._last_rtc = -1
        self._wrote_tmats = False

    def write_packet(self, channel: int, dtype: int, rtc: int,
                     body: bytes) -> None:
        # 1) enforce: IF-1 channel/type pair, TMATS-first, RTC monotonic
        # 2) filler-pad body to 4-byte boundary (before checksum)
        # 3) packet_len = 24 + len(padded body) + 2-byte data checksum,
        #    itself padded to a multiple of 4 (pad AFTER checksum with
        #    zeros if needed; simplest: pad body so 24+body+2 is % 4 == 2,
        #    then 2 more filler bytes -- work it out and comment it)
        # 4) build 22-byte header prefix, append header_checksum
        # 5) write header, body, data checksum; bump sequence
        ...

    def write_tmats(self, rtc: int, tmats_text: str) -> None:
        # CSDW for computer-generated F1: 4 bytes, 0 is acceptable here
        body = struct.pack("<I", 0) + tmats_text.encode("ascii")
        self.write_packet(0, pk.T_TMATS, rtc, body)

    def close(self):
        self._f.close()
```

**File: software/maiden/ch10/reader.py** — the inverse: yield
`(channel, dtype, rtc, body)` tuples, validating sync, both checksums, RTC
order, and sequence continuity; raise `Ch10Error` with the file offset on
any violation. ~50 lines; write it yourself against `packet.py`.

**File: software/tests/test_ch10.py** — three tests:

1. Write TMATS + two time packets + a PCM packet; read back with
   *your* reader; fields survive.
2. Same file through **PyChapter10** (`from chapter10 import C10`):
   iterate packets, assert 4 packets, channel IDs and data types match.
3. Violations raise: PCM before TMATS; RTC going backward; corrupted
   checksum byte.

## Verify

- All `test_ch10.py` tests pass, including the PyChapter10 round-trip —
  that one is the independent referee; your writer and reader agreeing
  with each other proves nothing.
- Hex-dump the first 32 bytes of a generated file (`xxd file | head -2`)
  and read the header aloud: `25 eb`, channel 0, your lengths, type
  `01`. If you cannot narrate every byte, reread §Concepts.
- Commit: `ch10: packet core, writer/reader for IF-1 types`.

## Explore

1. **Corrupt one bit** in a written file with a script and confirm your
   reader reports the right offset and PyChapter10's behavior on the same
   file. Decide and document (docstring) which of you is stricter.
2. **Time the reader** on a synthetic 100 MB file of PCM packets. The
   validation campaign will produce multi-GB sessions; if pure Python
   reads at <20 MB/s, note it — lesson 08 discusses where irig106lib
   swaps in.
3. **Read D4's video row.** Type 0x40 carries an H.264 transport stream
   with IPTS per frame. Sketch (comments only) what `write_video_frame`
   will need beyond `write_packet` — lesson 07 renders no real video, but
   lesson 19 does.

## Checkpoint

- `maiden.ch10` writes TMATS/time/PCM/message packets that PyChapter10
  parses, and reads them back with full validation.
- `pytest software/tests/test_ch10.py` passes.
- You can list from memory: the three file-level invariants VT-01 will
  check, and the scoped-out features (secondary headers, indexing,
  non-MAIDEN data types).
