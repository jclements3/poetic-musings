# maiden49 — .bin → Ch. 10 [desk]

**Sprint goal.** Build `maiden/convert/`: the ArduPilot DataFlash adapter
in full, the `LogAdapter` registry with the four IF-3 stubs, and the
writer that turns airborne records into a station-grade `.ch10` with a
GPS-disciplined time channel.

**Depends on.** maiden04 (Ch. 10 writer), maiden05 (TMATS generator),
maiden06 (TimeDecoder conventions). A DataFlash `.bin` with GPS lock to
develop against — maiden47's bench log if it exists yet, otherwise any
downloaded ArduPilot sample log (swap in your own before maiden50).

**Read first.** lesson22.md — *Two clocks in every log*, *Why the output
is Ch. 10 and not "just arrays"*, *The adapter registry*, and the Build
section.

**Tasks**

- [x] `software/maiden/convert/adapters.py`: `LogAdapter` protocol,
      `AirborneRecords` dataclass (per-stream arrays: `gps`, `imu`,
      `baro`, `att`, all UTC-stamped), `get_adapter(path)` dispatching on
      suffix.
- [x] Stubs for `.ulg`, `.bbl`, `.ubx`, EdgeTX `.csv`, each raising
      `NotImplementedError` with its D4 IF-3 row quoted in the docstring.
- [x] `convert/ardupilot.py`: iterate messages with
      `pymavlink.DFReader_binary`; collect GPS (incl. `GWk`/`GMS`), IMU,
      BARO, ATT streams with `TimeUS`.
- [x] Least-squares `TimeUS → UTC` fit over all GPS fixes (reject
      `GWk == 0`); apply the leap-second correction as a loudly-commented
      constant (or from the log if the firmware provides it); stamp all
      streams through the fit.
- [x] `convert/writer.py`: `AirborneRecords` + `Airframe` descriptor →
      one `.ch10` — TMATS packet first (with
      `C\MAIDEN\AIRFRAME\...` / `C\MAIDEN\LOGGER\...` fields incl.
      `ATT_SOURCE:ARDUPILOT_EKF`), Ch 1 time packets at 1 Hz from UTC,
      PCM channels for GPS/IMU/BARO/ATT with payload structs documented
      in both the module docstring and the TMATS comment group.
- [x] `config/airframes/<name>.yaml`: airframe name, logger serial,
      installed mass (VT-13 weigh-in when available), mount offset.
- [x] `maiden convert LOG --airframe ... --out DIR` CLI printing per-stream
      message counts and the fit residual (RMS) of the time regression.

**Done when**

- `maiden convert` produces a `.ch10` from the development log;
  PyChapter10 opens it; TMATS parses with airframe, serial, mass, and
  mount offset present.
- The time-fit residual is printed and recorded; the first Ch 1 time
  packet's UTC equals the first GPS fix's UTC (leap correction included)
  to the millisecond.
- The registry dispatches by suffix; all four stubs raise with their
  IF-3 rows cited.

**Doc trace.** AB-002; D4 IF-3 (parser table, TMATS content); SYS-006
airborne clause. Verified fully in maiden50 (VT-09).

---

**Execution notes (maiden49, desk).** All tasks done. Development log is
a SYNTHETIC DataFlash fixture (`maiden.convert.synth`, byte-level FMT +
messages, genuinely parsed by pymavlink DFReader) — no real H743 log
exists until maiden47, so VT-09's real pass is still open (maiden50
bench); 9 tests in `software/tests/test_convert.py` pin behavior:
adapter counts, TimeUS→UTC fit (recovers the injected +25 ppm within
2 ppm, residual < 1.5 ms from GMS quantization), leap constant (18 s,
loud comment), lossless Ch 5/Ch 6 provenance round-trip, first time
packet vs first GPS fix to the millisecond, ingest loads the file as
TRUTH StateSamples (Aircraft descriptor, ENU via the session origin),
registry dispatch + 4 IF-3 stubs. Channel plan deviation from the
lesson sketch, forced by the writer's strict IF-1 pairs: GNSS(ENU)→Ch3
PCM, ATT→Ch4 PCM (what ingest loads), raw GPS_LLA→Ch5 MSG and tagged
IMU/BARO→Ch6 MSG (provenance streams read by convert.read_back; ingest
skips them by design). Byte layouts echoed in TMATS C\MAIDEN\CONVERT
attributes. `--origin-lla` defaults from rcrc.yaml field_origin.
