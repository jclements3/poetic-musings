# maiden38 — IRIG-B generator [desk]

**Sprint goal.** `irigb_gen` and `strobe_latch` simulate green — the
station emits a decodable IRIG-B DCLS frame aligned to PPS and latches
camera-strobe timestamps into a FIFO.

**Depends on.** maiden37 (RTC + pps_stb contract).

**Read first.** lesson18.md § "IRIG-B on the wire" (the 2/5/8 ms symbol
table and the 100-cell frame layout — you will implement it bit-for-bit),
§ "Stamping frames", § Build 2–4.

## Tasks

- [x] Implement `irigb_gen.vhd` to the pinned entity (rtc, pps_stb,
      tod_set/tod_secs/tod_day load, irigb out, frame_stb at P_r):
      TOD counter incrementing at top of second (PPS-aligned when locked,
      RTC-derived in holdover); 100-state cell sequencer at 10 ms =
      100,000 RTC counts; frame-vector builder function (BCD encode,
      units-digit first, + 17-bit straight-binary seconds LSB-first;
      zeros in the control-function cells — legal); pulse-width shaper
      for the 2/5/8 ms symbols; P_r leading edge on the top of second.
- [x] Implement `strobe_latch.vhd`: async strobe → 2-FF sync → edge →
      push `(rtc, seq)` into a 16-deep FIFO with a read port for the
      recorder link; sticky overflow bit surfaced for Ch 6 — dropped
      stamps must be loud.
- [x] Extend `timebase_tb.vhd` with a *decoder procedure you write
      yourself* (encoder and decoder by the same hand find each other's
      bugs): decode the emitted waveform back to TOD.
- [x] TB case, frame: decoded TOD matches the loaded value; P_r edge
      within 1 RTC count of the PPS edge; SYS-006-tagged.
- [x] TB case, holdover continuity: frames keep coming with the crystal
      cadence, no TOD discontinuity on PPS return.
- [x] TB case, strobe: 30 Hz strobe with jitter → FIFO stamps monotonic,
      count matches strobes, no overflow; 17-strobe burst → sticky
      overflow bit sets.
- [ ] Frame the strobe/status records the recorder will drain per
      `firmware/recorder/PROTOCOL.md` (shared tagged-record UART framing
      with maiden35's doppler records); add the timebase record types to
      that file.

## Done when

- `make sim` green across all lesson 18 TB cases (nominal, offset,
  holdover, frame decode, strobe), every assert SYS-006-tagged.
- Your own decoder procedure round-trips the frame: symbol widths,
  double-8 ms frame mark, BCD digits, and SBS field all verified in sim.
- `firmware/recorder/PROTOCOL.md` lists the timebase record types
  alongside the doppler ones.

## Doc trace

SYS-006, D6 §IRIG-B time source, D4 §Time (IRIG-B + frame stamping),
IF-1 Ch 1/Ch 6 producers, D5 risk R3; feeds VT-02 and maiden40.

---
**Execution notes (2026-08-21, sim run on VALKYRIE):** `make sim` green —
frame decode (independent TB decoder), P_r/PPS alignment, holdover
continuity, strobe FIFO + sticky overflow all pass (15/15 SYS-006 cases).
Two findings: (1) lesson 18 erratum — its frame sketch puts SBS contiguous
at cells 80–97 with P9 at 99, contradicting its own "P on every 10th
cell"; implemented the real RCC layout (P9 at 89, SBS split 80–88/90–97,
P0 at 99), noted in irigb_gen.vhd's header. (2) [resolved] The PROTOCOL.md merge is done — types 0x10-0x12 live in firmware/recorder/PROTOCOL.md (RECORDS.md retired). Original note: the PROTOCOL.md task is
NOT ticked: maiden35 ran concurrently and owns that file's creation, so
the timebase record types are documented in firmware/timebase/RECORDS.md
pending a one-commit merge into PROTOCOL.md.
