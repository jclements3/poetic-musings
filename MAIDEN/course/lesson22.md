# Lesson 22 — Log → Ch. 10 Converter [desk]

*Where we are.* Lesson 21 left a flight controller on the bench logging
GNSS, IMU, and baro to an SD card in ArduPilot DataFlash format. That log
is truth — but nothing downstream reads DataFlash. D4 IF-3's answer is to
convert every native airborne format into the same Ch. 10 container the
stations write, so the whole pipeline from ingest up never learns what a
`.bin` file is. This lesson builds `maiden/convert/`: the ArduPilot parser
in full, the adapter registry that will hold the others, and the time
discipline that lets an airborne file align with three station files
without a manual offset.

## Objectives

- Parse an ArduPilot DataFlash `.bin` with pymavlink and extract GPS, IMU,
  BARO, and ATT message streams with their native timestamps.
- Build the boot-time→UTC mapping from GPS week/ms and apply it to every
  message, then emit Ch 1 time packets from GPS time.
- Write an aircraft `.ch10` (TMATS + time + PCM channels) using the
  lesson 02 writer, with a TMATS record naming airframe, logger serial,
  mass, and mount offset.
- Register the remaining IF-3 parsers as contracted stubs behind one
  adapter interface.
- Pass VT-09: lossless round-trip of values and GPS-aligned times.

## Concepts

### Two clocks in every log

A DataFlash log stamps every message with `TimeUS` — microseconds since
autopilot boot. That clock starts at an arbitrary wall time and drifts like
any crystal. The GPS messages additionally carry `GWk` (GPS week number)
and `GMS` (milliseconds into the week) — absolute GPS time, good to
nanoseconds at the receiver. The entire conversion problem is transferring
the absolute clock onto the relative one:

```
  GPS msgs:   TimeUS ────────► GWk/GMS ──► UTC        (sparse, ~10 Hz)
  IMU msgs:   TimeUS ────?                             (dense, 100+ Hz)

  fit:  utc(TimeUS) = a·TimeUS + b   (least squares over all GPS fixes)
```

A linear fit over the whole log absorbs crystal drift (ppm-level, so a
single flight is comfortably linear) and smooths receiver jitter. Every
IMU, BARO, and ATT sample then gets a UTC stamp through the fit. GPS time
itself needs one correction to become UTC: the leap-second offset (18 s as
of the current bulletin — read it from the log's `GPS` message if the
firmware provides `GPAA`/leap fields, else pin it as a converter constant
with a loud comment). Get this wrong and your truth is 18 m of position
error at pattern speeds; VT-02's clap check exists to catch exactly this
class of mistake.

### Why the output is Ch. 10 and not "just arrays"

The converter could hand fusion a NumPy file. It deliberately doesn't: by
emitting the same container the stations write — TMATS first, Ch 1 time
packets, PCM data channels — the airborne file flows through the same
ingest (lesson 08), the same RTC→UTC decoder (lesson 04), and the same
provenance discipline (raw file + TMATS describes itself forever). The RTC
in the airborne file is synthesized (a 10 MHz counter derived from UTC),
which is fine: RTC is a file-internal currency; the Ch 1 packets define
its exchange rate, exactly as on the stations. That is the SYS-006 clause
this lesson implements — air and ground share one timebase because both
files resolve to GPS-disciplined UTC, with no hand alignment.

One content note from D4: the `ATT` message is the autopilot EKF's
attitude estimate, not a raw sensor. It is still the best attitude truth
we have (AB-001 doesn't require better), but the TMATS comment group and
the lesson's channel notes say "EKF attitude" so nobody downstream
mistakes it for an independent measurement.

### The adapter registry

IF-3 lists five native formats. Building five parsers today would be
scope theater — you own one airframe and it runs ArduPilot. The honest
structure is one fully-built adapter and four stubs that raise
`NotImplementedError` with the IF-3 row quoted, all behind a common
interface, so adding PX4 support later is a new file, not a refactor:

```python
class LogAdapter(Protocol):
    suffixes: tuple[str, ...]           # e.g. (".bin", ".BIN")
    def read(self, path: Path) -> AirborneRecords: ...
```

`AirborneRecords` is a dataclass of per-stream arrays (`gps`, `imu`,
`baro`, `att`), each column-documented, each stamped in UTC. The writer
half of the converter consumes only `AirborneRecords`, so it is shared by
all adapters.

## Doc Trace

- **AB-002** is this lesson's requirement: GPS-disciplined timestamps,
  convertible to Ch. 10 with IRIG-B time packets. Verified by **VT-09**.
- **D4 IF-3** governs the parser table (formats, libraries, time sources,
  channels produced) and the TMATS content (airframe, logger serial,
  mass, mount position). The converter must match its rows; a new format
  is a revision to IF-3 first, code second.
- **SYS-006**'s airborne clause is satisfied here: the Ch 1 time channel
  built from GPS time is what lets ingest align this file with station
  files automatically.
- Feeds **VT-08** evidence (lesson 21's rate checks run on the converted
  file) and lesson 14's truth side of the residual pipeline.

## Build

`software/maiden/convert/` with:

- `adapters.py` — the `LogAdapter` protocol, `AirborneRecords`, and the
  registry (`get_adapter(path)` dispatching on suffix). Stubs for `.ulg`
  (pyulog), `.bbl` (orangebox), `.ubx` (pyubx2), and EdgeTX `.csv`, each
  citing its IF-3 row and time-source note in the docstring.
- `ardupilot.py` — the real one. `pymavlink.DFReader_binary` iterates
  messages; collect `GPS` (Lat, Lng, Alt, Spd/VZ or VN/VE/VD depending on
  firmware, GWk, GMS, TimeUS), `IMU` (AccX..GyrZ, TimeUS), `BARO` (Alt,
  TimeUS), `ATT` (Roll, Pitch, Yaw, TimeUS). Build the TimeUS→UTC fit
  from the GPS stream (reject fixes with GWk == 0 — no lock yet), apply
  the leap-second correction, stamp all streams.
- `writer.py` — `AirborneRecords` + an `Airframe` descriptor → one
  `.ch10` via `maiden.ch10`: TMATS packet first (template below), Ch 1
  time packets at 1 Hz from UTC, PCM channels GPS/IMU/BARO/ATT with the
  payload structs you pin here (document byte order and units in the
  module docstring *and* the TMATS comment group — they must agree).
- `cli.py` — `maiden convert LOG --airframe config/airframes/kaos.yaml
  --out DIR`. The airframe YAML holds what TMATS needs: name, logger
  serial, installed mass from VT-13's weigh-in, mount offset from the CG.

TMATS additions (extending the IF-2 comment-group pattern):

```
G\PN:MAIDEN;
R-1\ID:AIRCRAFT_KAOS;
C\MAIDEN\AIRFRAME\NAME:KAOS_60;
C\MAIDEN\LOGGER\SERIAL:MAIDEN-LOG-001;
C\MAIDEN\LOGGER\MASS_G:54.0;
C\MAIDEN\LOGGER\MOUNT_XYZ_MM:12,0,-8;
C\MAIDEN\LOGGER\ATT_SOURCE:ARDUPILOT_EKF;
```

Then the ingest side: add an `Aircraft` descriptor branch to lesson 08's
TMATS handling so these files load as `source="TRUTH"` StateSamples with
`pos_enu`/`vel_enu` (through `maiden.geo`, origin from the *session's*
station TMATS — the aircraft file carries LLA truth; the field frame
belongs to the ground set) and `att_rpy` from ATT.

## Verify

VT-09, on lesson 21's bench log (a log with GPS lock — the balcony
capture, not the basement one):

1. `maiden convert BENCH.bin --airframe ... --out results/VT-09/` —
   converter reports message counts per stream and the fit residual of
   the TimeUS→UTC regression (print it; a healthy log fits to well under
   a millisecond RMS — **observe on bench log**, record the number).
2. Round-trip test (`software/tests/test_convert_roundtrip.py`): parse
   the `.bin` directly with pymavlink, read the `.ch10` back through
   `maiden.ingest`, and compare stream by stream: identical sample
   counts, values equal within float32 quantization, timestamps equal
   within the fit residual. Lossless is the VT-09 criterion — a dropped
   or duplicated sample is a fail, not a warning.
3. Time-alignment check: the first Ch 1 time packet's UTC must equal the
   first GPS fix's UTC (leap correction included) to the millisecond.
4. Rate check (VT-08 evidence on the converted file): GPS ≥ 10 Hz,
   IMU ≥ 100 Hz, baro ≥ 10 Hz, no gaps > 2× nominal interval.

Commit the result sheet and the fit residual under `results/VT-09/`.

## Explore

- **Leap-second injection.** Add 1 s to the leap constant and rerun the
  round-trip test. Which check catches it, and what would it have done to
  the lesson 14 residuals if it had shipped? (Work out the position error
  at 30 m/s before you run anything.)
- **The dropout log.** Pull the SD card mid-log (bench, power off) and
  convert the truncated file. Decide and document the converter's policy:
  refuse, or convert with a loud gap warning? D5's data rules ("raw is
  never modified, derived is regenerable") constrain the answer.
- **Second adapter for real.** If you have any `.ubx` from the survey
  receiver, implement the pyubx2 stub (NAV-PVT iTOW → UTC is a
  simpler version of the same two-clock problem). GPS-only per IF-3.

## Checkpoint

- `maiden convert` produces a `.ch10` from the bench log; PyChapter10
  opens it; TMATS parses with airframe, serial, mass, mount offset.
- `pytest software/tests/test_convert_roundtrip.py` passes: lossless
  values, GPS-aligned times, VT-08 rates — evidence in `results/VT-09/`.
- `maiden.ingest.load()` yields TRUTH StateSamples from the converted
  file, in the field frame, with `att_rpy` populated.
- The adapter registry dispatches by suffix; the four stubs raise with
  their IF-3 rows cited.
