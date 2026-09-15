# Lesson 05 — The State-Vector Interface [desk]

*Where we are.* You can now read Chapter 10 packets, describe their
producers in TMATS, and resolve any RTC to UTC. The next dozen lessons
build modules that *consume* measurements: trackers, the EKF, maneuver
recognition, scoring. If each of those knew about packet formats, every new
sensor or log format would ripple through the whole pipeline. D4's answer
is IF-4: one in-software interface, the `StateSample`, that everything
above ingest consumes and nothing below it escapes. This lesson implements
it verbatim, builds the adapter registry that funnels every source into
it, and pins its invariants down with property tests — the cheapest
insurance this project will ever buy.

## Objectives

- Implement `StateSample` and `Event` exactly as D4 IF-4 defines them.
- Explain the adapter pattern here in one sentence: new sensors are
  adapters that emit `StateSample`; consumers never change.
- Encode the field-presence rules by source kind and enforce them.
- Build a registry so adapters self-describe and ingest can dispatch.
- Write property tests that will run against every future adapter.

## Concepts

### Why one interface, and why this one

The pipeline has five producers already planned — three stations, the
airborne logger, the twin — and D4 IF-3 lists five *more* native airborne
formats. The consumers (fusion, maneuver, scoring, validate) must not know
or care which of these produced a measurement. IF-4 is the waist of the
hourglass: many formats below, many algorithms above, one type in the
middle. When lesson 22 adds the PX4 `.ulg` parser, or Phase 2 adds a phone
video, the diff touches one adapter file and zero consumers. That is the
whole argument, and it is strong enough that D4 makes the interface a
controlled item: *change it only by revising the ICD.*

### Reading the dataclass like an ICD

Every field is `| None` except `t_utc` and `source`, and the Nones are
systematic, not sloppy:

- **Station samples** (`source` ∈ "A"/"B"/"C") are *angle-and-rate*
  measurements: `az_deg`, `el_deg`, `conf` from the tracker, `v_r` from
  the radar. They have no position — a single station cannot know one.
- **FUSED samples** are the EKF's output: `pos_enu`, `vel_enu`, the 6×6
  `cov`, and `att_rpy` only if estimable. No az/el — that information has
  been consumed.
- **TRUTH samples** (airborne logger or twin) carry `pos_enu`, `vel_enu`,
  `att_rpy`; no covariance is published for truth.

The field frame is lesson 01's: ENU, origin at Station A's survey mark,
defined once in TMATS. `t_utc` comes from lesson 04's decoder — by the
time a `StateSample` exists, time is already resolved; no RTC leaks above
the waist.

`Event` is deliberately loose (`kind` string + `data` dict): takeoff,
touchdown, maneuver boundaries, field-rule crossings, clap marks. Typed
richness can come later; the loose form is what lets lesson 06's twin emit
training labels years before lesson 23's classifier exists.

## Doc Trace

- **Implements:** the data half of SW-001 (the reading half is lesson 08).
- **Governed by:** D4 IF-4, verbatim — field names, types, and meanings
  are contractual; this lesson's code must match the ICD or the ICD must
  be revised, never a silent third option.
- **Verified by:** VT-14 ("every adapter emits valid StateSample") — the
  property tests you write today are VT-14's engine; lesson 08 and lesson
  22 plug their adapters into them unchanged.
- **Feeds:** literally everything above ingest.

## Build

### `software/maiden/state.py`

Complete file. The dataclasses are D4's text made executable; the
validation is this lesson's addition:

```python
"""IF-4: the state-vector interface. Change only by revising D4."""
from dataclasses import dataclass, field
import numpy as np

STATIONS = ("A", "B", "C")
SOURCES = STATIONS + ("FUSED", "TRUTH")

@dataclass
class StateSample:
    t_utc:   float                 # seconds, from IRIG-B / GPS
    source:  str                   # "A" | "B" | "C" | "FUSED" | "TRUTH"
    az_deg:  float | None = None   # station-frame azimuth (stations)
    el_deg:  float | None = None
    conf:    float | None = None   # tracker confidence 0-1
    v_r:     float | None = None   # radial velocity m/s (stations)
    pos_enu: tuple | None = None   # E,N,U metres in field frame (FUSED, TRUTH)
    vel_enu: tuple | None = None
    att_rpy: tuple | None = None   # roll, pitch, yaw deg (TRUTH; FUSED if estimable)
    cov:     np.ndarray | None = None  # 6x6 for FUSED

@dataclass
class Event:
    t_utc: float
    kind:  str                     # "TAKEOFF" | "TOUCHDOWN" | "MANEUVER_START" | ...
    data:  dict = field(default_factory=dict)


def validate(s: StateSample) -> None:
    """Raise ValueError on any IF-4 violation. Cheap; call it in adapters."""
    if s.source not in SOURCES:
        raise ValueError(f"unknown source {s.source!r}")
    if s.source in STATIONS:
        if s.pos_enu is not None or s.cov is not None:
            raise ValueError("station samples carry angles, not state")
        if s.az_deg is None and s.v_r is None:
            raise ValueError("station sample with no measurement")
        if s.conf is not None and not 0.0 <= s.conf <= 1.0:
            raise ValueError("conf out of [0,1]")
    else:
        if s.pos_enu is None or s.vel_enu is None:
            raise ValueError(f"{s.source} sample must carry pos+vel")
        if s.source == "FUSED" and s.cov is not None and s.cov.shape != (6, 6):
            raise ValueError("FUSED cov must be 6x6")
        if s.source == "TRUTH" and s.cov is not None:
            raise ValueError("truth publishes no covariance")
```

Note what `validate` does *not* enforce: it never requires `cov` on FUSED
(early EKF bring-up emits without it) and never requires `att_rpy`. Encode
the ICD, not your hopes.

### `software/maiden/adapters.py`

The registry — adapters register themselves against a source description
and ingest (lesson 08) dispatches by it. Skeleton; the body is yours:

```python
"""Adapter registry: everything below IF-4 registers here.  [skeleton]"""
_REGISTRY: dict[str, callable] = {}

def adapter(kind: str):
    """Decorator: @adapter("ch10.station"), @adapter("ardupilot.bin"), ..."""
    ...

def get(kind: str):
    """Return the adapter callable or raise a KeyError naming known kinds."""
    ...
```

An adapter's contract, documented in the module docstring: it is a
callable taking a source path plus its descriptor (Station/Aircraft, from
TMATS) and yielding `StateSample`s in nondecreasing `t_utc`, each passing
`validate`. Write the contract down; the tests below enforce it.

## Verify

`software/tests/test_state.py`, in three layers:

- **Example-based:** a legal sample of each source kind passes `validate`;
  each rule above has one failing counter-example asserting `ValueError`.
- **Property-based** (use `hypothesis` if you like it, or a seeded random
  generator if you don't): generate random samples with fields drawn per
  source kind; assert `validate` accepts exactly the legal combinations.
- **The adapter contract test, written once, reused forever:**

```python
def check_adapter_stream(samples):
    """Every adapter test in lessons 08 and 22 calls this. VT-14's core."""
    last = {}
    for s in samples:
        validate(s)
        assert s.t_utc >= last.get(s.source, -np.inf), "t_utc regressed"
        last[s.source] = s.t_utc
```

Put `check_adapter_stream` somewhere importable by tests
(`software/tests/conftest.py` is fine). `pytest software/tests` must pass.

## Explore

1. **Serialization.** Fusion runs will want to save/load sample streams
   without re-ingesting. Add `to_npz` / `from_npz` round-trip helpers for
   a list of samples and a test proving round-trip equality. Decide — and
   document in a docstring — how `None` survives the trip.
2. **Frozen or not?** Make `StateSample` `frozen=True` and see what
   breaks. Decide whether mutability is a convenience or a bug farm here,
   and record the decision as a comment citing where samples get built.
3. **A hostile adapter.** Write a deliberately buggy generator (emits one
   out-of-order sample among 1000) and confirm `check_adapter_stream`
   catches it. This is the lesson-08 fuzz test in embryo.

## Checkpoint

- `software/maiden/state.py` matches D4 IF-4 field-for-field; any
  deviation you chose is instead a committed revision to D4.
- `validate` enforces the source-kind presence rules; tests cover accept
  and reject paths for every rule.
- `check_adapter_stream` exists, is importable from tests, and catches
  ordering and validity violations.
- `pytest software/tests` is green.
