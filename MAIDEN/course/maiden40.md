# maiden40 — Recorder Core [desk]

**Sprint goal.** Build the SBC recorder's skeleton — rings, min-RTC merge
writer, CLI, and the written UART protocol — so the bench sprints only add
real sources to a tested core.

**Depends on.** maiden04 (Ch. 10 writer core), maiden05 (TMATS builder);
maiden34–38 helpful for the UART record framing but not blocking — the
protocol doc can lead the firmware.

**Read first.** Lesson 19: *One file, seven channels, one ordering rule*,
*The rate budget*, *Threads, rings, and the never-drop discipline*, and the
Build section.

**Tasks**

- [x] Do the rate-budget arithmetic yourself before coding (target ≈
      1.2 MB/s aggregate; write your numbers into a comment in
      `writer.py`) and size each ring for ≥ 2 s at channel rate.
- [x] Create `firmware/recorder/rings.py` — bounded deque with per-channel
      drop counter, newest-item discard on overflow — with its own pytest,
      written first.
- [x] Create `firmware/recorder/writer.py` — the min-RTC merge loop over
      `maiden.ch10.writer` (lesson 19's skeleton), TMATS packet first,
      fsync every N MB.
- [x] Create `firmware/recorder/sources.py` with the three capture-thread
      classes (`FpgaSource`, `CameraSource`, `StatusSource`) as stubs that
      can be driven by a fake source in tests; real I/O lands in maiden41–42.
- [x] Create `firmware/recorder/record.py` — CLI per lesson 19
      (`python -m recorder --station A --out STATION_A_….ch10`) with clean
      SIGINT shutdown that flushes all rings.
- [x] Extend `firmware/recorder/PROTOCOL.md` (created in maiden35, timebase
      records added in maiden38) with the recorder's side of the contract:
      the Ch 4 / Ch 5 / Ch 6 payload layouts you had to invent. If you
      reached this card before maiden35, create the file here and maiden35
      will extend it — either order works; one file owns the framing.
- [x] Add a pytest that drives fake sources with out-of-order-arrival,
      in-order-RTC data and asserts the output file is nondecreasing in RTC
      and TMATS-first (parse it back with `maiden.ingest`).

**Done when**

- `pytest` green on `rings.py` and the fake-source merge test; the merged
  file loads in PyChapter10 and `maiden ingest --summary` without error.
- A ring forced to overflow in a test increments its drop counter and the
  counter value appears in the generated Ch 6 status payload.
- `PROTOCOL.md` is committed and cited from both the Python and the VHDL
  source headers.

**Doc trace.** SYS-005, GS-001 (timestamping half); D4 IF-1/IF-2; D6
"Ch. 10 recorder". Bench verification (VT-01/VT-03) is maiden42.

---

**Execution notes (maiden40, desk).** All seven tasks done; 14 tests in
`software/tests/test_recorder.py`, ruff clean. Verified end to end:
`python -m recorder --station A --out ... --selftest 5` writes a file
that PyChapter10 loads (261 packets, channels 0/1/4/6), the strict
reader validates, and `maiden ingest --summary` reads back (250 radar
samples, 5 status events, zero drops). Decisions of record: (1) the
drop-counter rides in the STATUS payload's reserved pad halfword —
PROTOCOL.md documents it; surfacing in `payloads.unpack_status`/ingest
is a flagged one-line D4 fold-back. (2) DOPPLER_V records carry no RTC;
recorder extrapolates from TIME_MARK (~1-2 ms worst case) — PROTOCOL.md
notes the maiden41 candidate fix. (3) Late items are clamped forward
and counted (`late_clamped`), never dropped or fatal. (4) Torn-file
salvage policy = ingest's truncation tolerance + 8 MB fsync cadence.
Real serial/camera I/O and VT-01/VT-03 remain bench work (maiden41-42).
