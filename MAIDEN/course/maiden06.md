# maiden06 — TimeDecoder [desk]

**Sprint goal.** Turn Ch 1 time packets into a drift-aware, gap-aware
RTC→UTC function — the resolution step every downstream module calls.

**Depends on.** maiden04 (reader for the file-walking function).

**Read first.** lesson04.md §Concepts (*Why timing is a first-class
requirement*, *The timebase chain*) and §Build.

## Tasks

- [x] Write `software/maiden/timebase.py` — complete file in lesson 04
      §Build: `TimePoint`, `TimeDecoder` with least-squares `fit()`,
      `to_utc()`, `drift_ppm`, `gaps()`, `healthy()`.
- [x] Write the file-walking function (yours): walk a `.ch10` via the
      maiden03 reader, decode each Ch 1 payload's BCD day/h/m/s to
      seconds, return a fitted `TimeDecoder`. Handle the two traps the
      lesson names: BCD ≠ binary, and midnight rollover (unwrap +86400).
- [x] Write `software/tests/test_timebase.py` — the four lesson-04 cases:
      exact recovery (≤1 µs mid-span, drift ≈ 0), 20 ppm drift recovered
      within 0.1 ppm with ≤100 µs error over 300 s (and the
      naive-offset-would-be-6 ms comparison made executable), gap
      detection with `healthy() == False`, BCD + midnight-crossing stream
      → monotonic UTC.
- [x] Explore 3 (recommended): one hour-off corrupted time packet;
      add the fit → drop >3σ residuals → refit outlier pass with a test.
- [ ] Commit: `timebase: RTC->UTC from Ch 1 time packets`.

## Done when

- `pytest software/tests/test_timebase.py` green on all four cases.
- You can state from memory why SYS-006 says 5 ms and not 50 ms
  (5 ms × 30 m/s = 0.15 m — matched to the triangulation noise floor,
  per lesson 04's unpacking of D3).

## Doc trace

SYS-006 (ground-software half; hardware half lands at maiden37–39) ·
D4 §Time and synchronization, IF-1 Ch 1 · feeds `maiden.ingest`
(maiden14) and `maiden.validate` step 1 (maiden26) · VT-02 procedure is
the next sprint.
