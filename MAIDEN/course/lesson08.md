# Lesson 08 — Ingest [desk]

*Where we are.* You can write a Ch. 10 file (lesson 02), describe it with
TMATS (lesson 03), resolve its clocks (lesson 04), and — as of lesson 07 —
the twin manufactures complete three-station sessions plus airborne truth.
What you cannot yet do is read any of it back into the types the rest of
the pipeline speaks. This lesson builds `maiden.ingest`: the one place in
MAIDEN where file formats are allowed to exist. Above this line, everything
is `StateSample`s; below it, everything is packets. That asymmetry is the
whole point of IF-4.

## Objectives

- Implement `maiden.ingest.load(path) -> Iterator[StateSample]` as a
  streaming generator — constant memory, no whole-file loads.
- Parse the TMATS packet into a `Station` or `Aircraft` descriptor and
  attach it to the stream's metadata.
- Decode channels 1, 4, 5, and 6 into time-resolved samples using the
  lesson-04 `TimeDecoder`; leave Ch 2 video and Ch 3 raw I/Q as
  addressable-but-not-decoded (the tracker and DSP replay tools want them
  later, not now).
- Round-trip the lesson-07 twin session: ingested az/el and v_r must agree
  with pre-noise twin truth to within the noise the twin injected.
- Survive garbage: fuzzed TMATS and truncated files raise clean errors or
  end the stream — never crash, never emit a nonsense sample.

## Concepts

### Ingest is an adapter boundary, not a library wrapper

D6 says "PyChapter10 / irig106lib wrapper," and you will use PyChapter10
for packet walking, but the design center is the boundary: `load()` yields
`StateSample`s and nothing else. When lesson 22's converter meets ArduPilot
logs, and when some future MAIDEN meets a sensor you haven't imagined, they
become new adapters that emit the same type. Downstream code (fusion,
scoring, validate) must be unable to tell which file format a sample came
from. Any field that would leak the format is a design bug.

The shape is a three-layer stack:

```
  load(path)
    ├── PacketWalker      yields (channel_id, data_type, rtc, payload)
    │                     from PyChapter10; tolerant of truncation
    ├── TimeDecoder       lesson 04: Ch 1 packets → rtc→UTC mapping
    └── ChannelDecoders   per-channel payload → StateSample fields
```

Two passes are tempting (first find all time packets, then decode), but a
streaming single pass is required: field sessions are multi-gigabyte, and
lesson 19's recorder guarantees a time packet before any data that needs
it (TMATS first, time early and periodic — IF-1). So: feed Ch 1 packets to
the `TimeDecoder` as they arrive; any data packet whose RTC precedes the
first time packet goes to a small hold-back queue, flushed once the decoder
is primed. Bound the queue; if it overflows, the file violates IF-1 and
you raise `IngestError` saying so.

### The two payloads you decode today

**Ch 4 RADAR_V** (PCM, 50 Hz): minor frame = `v_r` float32 m/s, `snr_db`
float32, `peak_bin` uint16, pad uint16 — 12 bytes, little-endian. This
struct is *defined here and used by lesson 19's recorder and lesson 17's
DSP output formatter* — write it once in `maiden/ch10/payloads.py` and
import it everywhere. A sample with `snr_db` below threshold still gets
emitted (with its low SNR); deciding what to trust is fusion's job.

**Ch 5 TRACKER** (message, per frame): `az` float32 deg, `el` float32 deg,
`conf` float32 0–1, `bbox` = 4 × uint16 px — 20 bytes, little-endian. Same
rule: the struct lives in `payloads.py`; lesson 11 writes it, you read it.

Ch 6 STATUS decodes into `Event`s (kind `"STATUS"`, data = battery V,
temp, PPS lock, disk free) rather than `StateSample`s — it is bookkeeping,
and lesson 14's sync audit will want the PPS-lock timeline.

### Malformed input is a requirement, not an edge case

VT-14's pass criterion has two clauses: every adapter emits valid
`StateSample`s, and *no crash on malformed TMATS*. Treat the second as a
first-class behavior: a fuzzer will hand your TMATS parser byte soup, and
the correct responses are (a) a clean `TmatsError` with a useful message,
or (b) a successfully parsed subset with the damage reported — never a
traceback from three libraries down. The same discipline applies to
truncated files: a session that ends mid-packet (station battery died —
GS-007 exists for a reason) must yield every complete sample and then stop.

## Doc Trace

- **SW-001** is this lesson: Ch. 10/TMATS in, source-independent
  state-vector stream out. The interface is D4 IF-4 verbatim (lesson 05's
  dataclasses); the file layout is IF-1; the descriptors come from IF-2.
- **VT-14** verifies it: adapter validity tests plus the TMATS fuzz, run
  in CI. This lesson writes those tests; lesson 15 wires them into the
  gate. Log the first passing run to `results/VT-14/`.
- The hold-back rule above depends on the recorder honoring IF-1 packet
  ordering — note the cross-reference in `firmware/`'s lesson-19 notes
  when you get there.

## Build

**`software/maiden/ch10/payloads.py`** — complete, and short. Two
`struct.Struct` definitions (`RADAR_V = struct.Struct("<ffHxx")`,
`TRACKER = struct.Struct("<fff4H")`), pack/unpack helpers, and the
docstring stating these are IF-1 payload contracts shared by ingest, the
recorder, and the twin. Refactor lesson 07's twin writer to import from
here instead of its private copies — one definition, three users.

**`software/maiden/ingest.py`** — the module (skeleton):

```python
@dataclass
class Station:
    id: str                      # "A" | "B" | "C", from TMATS DSI
    serial: str                  # R-1\RID
    survey_lla: tuple[float, float, float]
    heading_deg: float
    cam: CameraAttrs | None      # FX FY CX CY K1 K2, if present
    radar: RadarAttrs | None     # MODULE F_GHZ BORESIGHT_AZ/EL

@dataclass
class Aircraft:
    tail: str
    logger_serial: str
    mass_g: float | None

def describe(path) -> Station | Aircraft:
    """Parse only the TMATS packet (first packet, IF-1) and return the
    descriptor. Cheap; used by session tooling to inventory a directory."""

def load(path, *, channels=None) -> Iterator[StateSample]:
    """Stream StateSamples in file order. channels=None decodes the
    default set {1, 4, 5, 6}; pass e.g. {5} to skip radar."""

def events(path) -> Iterator[Event]:
    """Ch 6 STATUS (and later: recorder-marked events)."""
```

Build order that stays runnable at every step:

1. `PacketWalker` over PyChapter10, yielding raw packet tuples; unit-test
   against a twin station file (packet count, channel ids seen).
2. `describe()`: reuse lesson 03's TMATS parser; map the `C\MAIDEN\*`
   attributes into the descriptor dataclasses. The `source` letter comes
   from `G\DSI-1` (`STATION_A` → `"A"`).
3. Time: instantiate `TimeDecoder`, feed Ch 1, implement the hold-back
   queue (a `collections.deque`, cap ~2 s of packets).
4. Ch 5 → `StateSample(t_utc=…, source=station.id, az_deg=…, el_deg=…,
   conf=…)`, other fields `None`. Ch 4 → samples carrying only `v_r`
   (and stash `snr_db` in… nowhere: IF-4 has no SNR field. See Explore 3.)
5. Ch 6 → `Event`s in `events()`.

Every sample passes lesson 05's `StateSample.validate()` before being
yielded; a decoder that produces an invalid sample is a bug you want at
ingest, not inside the EKF.

**`software/tests/test_ingest.py`** — the VT-14 suite:

- *Round-trip:* run the twin (fixed `--seed`), ingest station A, join
  ingested az/el to `truth.npz` pre-noise values by timestamp; assert the
  residual standard deviation is within [0.7×, 1.3×] of the σ the twin
  injected (0.5 mrad-class angles, lesson 07's Doppler σ for v_r), and
  the residual mean is ~0 (no sign or unit slips — the classic bug this
  catches is degrees/radians in exactly one place).
- *Ordering:* `t_utc` is non-decreasing per source.
- *Fuzz:* `hypothesis` (or a seeded byte-mangler) corrupts the TMATS
  payload 500 ways; assert `describe()` either raises `TmatsError` or
  returns a descriptor — no other exception type escapes.
- *Truncation:* chop a twin file at ten random byte offsets; `load()`
  yields only complete samples and terminates cleanly.

## Verify

- `pytest software/tests/test_ingest.py -v` — all green. This is VT-14's
  desk half; copy the pytest summary and the fuzz-case count into
  `results/VT-14/` with the git hash.
- `python -m maiden.ingest data/twin/STATION_A_*.ch10 --summary` (write
  the tiny `__main__` — it prints sample counts per channel, time span,
  and the descriptor). Check the counts against what lesson 07's twin
  reported writing: tracker samples ≈ frames rendered, radar samples ≈
  50 × duration. A mismatch of more than the twin's declared dropout rate
  means the walker or the hold-back queue is eating packets.
- Memory: ingest a twin session under `/usr/bin/time -v` and confirm max
  RSS stays flat if you double the session length (regenerate the twin
  with a longer script). Streaming means *streaming*.

## Explore

1. **Kill the hold-back queue.** Reorder a copy of a twin file so a data
   packet precedes the first time packet by more than the queue bound.
   Confirm you get the IF-1-violation `IngestError`, then decide: should
   real field sessions fail hard here, or degrade per D4's clap-fallback
   sync path? Write your answer as a comment in `ingest.py` — lesson 14
   will hold you to it.
2. **Foreign file.** Feed `load()` a Ch. 10 file from the wild (the
   irig106.org sample files) — one that has channels MAIDEN never
   defined. The right behavior: describe() fails informatively (no
   `C\MAIDEN` attributes), load() with explicit `channels=` still walks
   packets. How close is your code to that today?
3. **The SNR gap.** Ch 4 carries `snr_db` but IF-4's `StateSample` has no
   field for it, so fusion cannot weight radar samples by SNR. That is an
   interface change: per D5 change control, draft the one-line addition
   to D4 IF-4 (and lesson 05's dataclass) as a commit touching both, or
   write down why fusion shouldn't see SNR. Either is defensible;
   undocumented loss of information is not.

## Checkpoint

- `pytest software/tests/test_ingest.py` passes, including fuzz and
  truncation cases; evidence logged in `results/VT-14/`.
- `describe()` returns a correct `Station` for all three twin stations
  and a correct `Aircraft` for the truth file.
- Round-trip residuals vs. twin pre-noise truth are zero-mean and match
  the injected σ for both az/el and v_r.
- `payloads.py` is the single definition of the Ch 4 / Ch 5 structs, and
  the twin imports it (no private copies remain).
- You have written (or consciously declined, in writing) the D4 IF-4
  SNR-field change from Explore 3.
