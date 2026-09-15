# maiden03 — Ch. 10 packets: read [desk]

**Sprint goal.** Own the Chapter 10 packet format cold: packet primitives
plus a validating reader that walks any MAIDEN-scope `.ch10` file and
reports violations by offset.

**Depends on.** maiden01.

**Read first.** lesson02.md §Concepts (*The packet*, *The file*, *What we
scope out — said once, honestly*, *Tooling*).

## Tasks

- [x] `pip install pychapter10` (add to dev extras in pyproject).
- [x] Create `software/maiden/ch10/` with `__init__.py` and `packet.py` —
      complete file in lesson 02 §Build: sync constant, the five data-type
      constants (0x01/0x11/0x09/0x30/0x40), the 24-byte header struct,
      `header_checksum`, `data_checksum`, `pack_rtc`.
- [x] Memorize-and-draw drill: sketch the 24-byte header (offset, size,
      field) from memory; check against lesson 02's table until you can.
- [x] Write `software/maiden/ch10/reader.py`: yield
      `(channel, dtype, rtc, body)` tuples; validate sync, both checksums,
      nondecreasing RTC, per-channel sequence continuity, TMATS-first;
      raise `Ch10Error` carrying the file offset on any violation
      (~50 lines, yours).
- [x] Test the reader against hand-built byte fixtures: construct valid
      packets in the test with `struct` + `packet.py` helpers (the writer
      arrives in maiden04), plus corrupted variants (bad sync, bad
      checksum, backward RTC) asserting `Ch10Error` with the right offset.

## Done when

- `pytest software/tests/test_ch10.py` passes the reader-side tests
  (valid fixture parses; each corruption raises with a correct offset).
- You can narrate a hex dump of a packet header byte-by-byte
  (`25 eb`, channel, lengths, type…) without the table in front of you.
- You can list the three file-level invariants VT-01 will check and the
  scoped-out Ch. 10 features (secondary headers, indexing, non-MAIDEN
  types).

## Doc trace

SYS-005 (container discipline; formally verified by VT-01 at maiden42) ·
D4 IF-1 (channel/type table the reader enforces) · D3 §Key architecture
decisions ("one container, one timebase").
