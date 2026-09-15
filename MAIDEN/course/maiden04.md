# maiden04 — Ch. 10 packets: write [desk]

**Sprint goal.** Complete `maiden.ch10` with a spec-honest writer and prove
the pair with a PyChapter10-refereed round-trip.

**Depends on.** maiden03.

**Read first.** lesson02.md §Build (the `writer.py` skeleton and its
numbered fill-in holes) and re-skim §The file for the invariants the
writer must *enforce*, not just obey.

## Tasks

- [x] Write `software/maiden/ch10/writer.py` from the lesson 02 skeleton:
      `Ch10Writer.write_packet` enforcing IF-1 channel/type pairs,
      TMATS-first, RTC monotonicity; filler-pad to 4-byte alignment with
      the 16-bit data checksum (work out the padding arithmetic and leave
      the comment the skeleton demands); `write_tmats` with the
      computer-generated F1 CSDW.
- [x] Finish `software/tests/test_ch10.py` with the three lesson-02
      tests: (1) write TMATS + 2 time + 1 PCM, read back with *your*
      maiden03 reader; (2) same file through PyChapter10 — 4 packets,
      channel IDs and types match; (3) violations raise (PCM before
      TMATS, backward RTC, corrupted checksum byte).
- [x] `xxd file | head -2` on a generated file; narrate the header bytes
      aloud.
- [x] Explore 1: single-bit corruption script; document (docstring) which
      of your reader vs PyChapter10 is stricter and why.
- [x] Commit: `ch10: packet core, writer/reader for IF-1 types`.

## Done when

- `pytest software/tests/test_ch10.py` fully green — PyChapter10
  round-trip included (your writer agreeing with your reader alone proves
  nothing; the foreign parser is the referee).
- The writer *refuses* a channel/type pair not in D4 IF-1's table.
- A generated file's first packet is TMATS on channel 0 and every
  packet's RTC is nondecreasing — verified by test, not by intention.

## Doc trace

SYS-005 · D4 IF-1 (allowed channel/type pairs; the writer is its
enforcement point) · feeds the twin (maiden12), the converter (maiden49),
and the recorder (maiden40); VT-01 verifies the hardware end at maiden42.
