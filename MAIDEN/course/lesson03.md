# Lesson 03 — TMATS [desk]

*Where we are.* Your Ch. 10 writer insists on a TMATS packet first and so
far you've fed it placeholder text. TMATS — the Telemetry Attributes
Transfer Standard, IRIG-106 Chapter 9 — is that first packet's payload: a
plain-text description of everything in the file. For MAIDEN it carries
more than channel bookkeeping: the survey position, camera intrinsics, and
radar boresight ride in it (D4 IF-2), which makes every `.ch10` file
self-contained — hand someone the file and they can reconstruct geometry
without your notebook. This lesson writes the station template verbatim
from the ICD and the parser/generator pair the whole pipeline uses.

## Objectives

- Read and write TMATS attribute syntax: `KEY:VALUE;` lines, G/R groups,
  comment attributes.
- Create `config/tmats/station.tmt` matching D4 IF-2 exactly.
- Build `maiden/tmats.py`: template → `Station` descriptor, descriptor →
  template, round-trip stable.
- Start the malformed-input hardening that VT-14 will hold you to: the
  parser never crashes, it degrades.

## Concepts

### The syntax

TMATS is a sequence of `CODE:VALUE;` attributes, whitespace and newlines
insignificant outside values, `--` comments to end of line (a common
extension; RCC files in the wild use them and so does D4's example).
Attribute codes are structured: a group letter, a backslash, a name, and
optional dash-indices tying rows together:

```
G\PN:MAIDEN;                     -- G group: general, program name
G\DSI\N:1;                       -- number of data sources
G\DSI-1:STATION_A;               -- data source #1's name
G\106:23;                        -- RCC 106 revision
R-1\ID:STATION_A;                -- R group: recorder #1
R-1\N:7;                         -- it has 7 channels
R-1\TK1-2:1;                     -- channel row 2: track/channel number 1
R-1\DSI-2:TIME;                  -- ...named TIME
R-1\CDT-2:TIM;                   -- ...channel data type TIM
```

The pattern to internalize: `R-1\TK1-2` means *recorder 1, attribute TK1,
row 2*. Rows are how a flat key-value format expresses tables. A parser
that treats codes as opaque strings and only splits on `\` and `-` handles
all of it.

### MAIDEN's attributes

D4 IF-2's design decision, worth restating because it's clever: standard
Ch. 9 groups describe the channels so *any* Ch. 10 tool parses the file,
while MAIDEN-specific survey/calibration values ride in **comment-group
attributes** under a `C\MAIDEN\...` namespace. Foreign tools skip them;
ours require them. The full set (values are the ICD's worked example —
Station A's survey):

```
C\MAIDEN\SURVEY\LAT, LON, ALT_M, HDG_DEG
C\MAIDEN\CAM\FX, FY, CX, CY, K1, K2
C\MAIDEN\RADAR\MODULE, F_GHZ, BORESIGHT_AZ, BORESIGHT_EL
```

These are exactly the numbers `maiden.geo.Pose` (lesson 01) and the camera
model (lesson 09) need — TMATS is how they travel from the field into the
pipeline. Change the survey, re-render the TMATS; never edit a `.ch10` in
place (D5 data rules).

### Parser posture

Two consumers, two postures. The *generator* is strict: it emits the
template byte-for-byte deterministic so files diff cleanly across
sessions. The *parser* is defensive: field-recorded files pass through SD
cards, USB adapters, and your own future bugs. VT-14's clause "no crash on
malformed TMATS" begins here: unknown attributes are collected, not
rejected; missing MAIDEN attributes yield a descriptor with explicit
`None`s and a warnings list; truncated/garbage input returns errors as
values, not exceptions. The rule of thumb: `parse()` raises only on
programmer error, never on data.

## Doc Trace

- **D4 IF-2** — the template this lesson reproduces verbatim; any future
  change to it is an ICD revision (D5 change control), and the repo copy
  in `config/tmats/` is the controlled artifact the ICD points at.
- **GS-004 / GS-005** — survey and calibration values enter the data path
  here; their accuracy is verified by VT-06/VT-07 later, their *transport*
  is verified by this lesson's round-trip tests.
- **SW-001** — ingest (lesson 08) builds its `Station` descriptors from
  this parser; VT-14's malformed-TMATS fuzz clause lands on this module.

## Build

**File: config/tmats/station.tmt** — transcribe from D4 IF-2 exactly: the
`G\` block (PN, DSI, 106), the `R-1\` block (ID, RID, N:7, and the seven
TK1/DSI/CDT rows for TMATS, TIME, VIDEO, RADAR_IF, RADAR_V, TRACKER,
STATUS with their TFMT/TSRC/VTF extras), and the twelve `C\MAIDEN\`
attributes. Keep the ICD's comment lines. This file is Station A's; the
generator parameterizes it for B and C.

**File: software/maiden/tmats.py** — *skeleton*:

```python
"""TMATS (IRIG-106 Ch. 9 subset) parse + generate per D4 IF-2."""
from dataclasses import dataclass, field


@dataclass
class Station:
    station_id: str                 # R-1\ID
    serial: str | None              # R-1\RID
    lat: float | None               # C\MAIDEN\SURVEY\LAT
    lon: float | None
    alt_m: float | None
    hdg_deg: float | None
    cam: dict | None                # fx, fy, cx, cy, k1, k2
    radar: dict | None              # module, f_ghz, boresight_az, boresight_el
    channels: list = field(default_factory=list)   # (num, name, cdt) rows
    raw: dict = field(default_factory=dict)        # every attribute, verbatim
    warnings: list = field(default_factory=list)


def parse_attributes(text: str) -> dict:
    # strip '--' comments; split on ';'; each piece splits on FIRST ':'
    # only (values may contain colons); keep insertion order; collect
    # syntactically broken pieces into a '__errors__' list instead of
    # raising.
    ...


def parse_station(text: str) -> Station:
    # build Station from parse_attributes(); every missing MAIDEN
    # attribute -> None + a warning string; channel rows gathered by
    # scanning R-1\TK1-n / DSI-n / CDT-n triples.
    ...


def render_station(st: Station) -> str:
    # deterministic: fixed attribute order (the template's), fixed float
    # formatting (repr of the stored value, not %-rounding -- survey
    # precision is data, not presentation).
    ...
```

**File: software/tests/test_tmats.py** — four tests:

1. *Template parses:* `parse_station(open("config/tmats/station.tmt"))`
   yields `station_id == "STATION_A"`, `lat == 34.6851710`,
   `hdg_deg == 12.4`, `cam["fx"] == 1820.4`,
   `radar["module"] == "CDM324"`, 7 channel rows, empty warnings.
2. *Round-trip:* `render_station(parse_station(text))` re-parses to an
   equal descriptor; the MAIDEN attribute values are byte-identical
   between renders (deterministic formatting).
3. *Degradation:* delete the `C\MAIDEN\SURVEY\HDG_DEG` line — parse
   succeeds, `hdg_deg is None`, one warning naming the attribute.
4. *Fuzz:* feed 200 mutations (random byte deletions/insertions/
   truncations of the template, seeded RNG) — `parse_station` never
   raises. Cheap now; VT-14 formalizes it in lesson 08's suite.

Wire the lesson-02 writer to this: replace the placeholder in
`write_tmats` tests with the rendered template, and confirm PyChapter10
still reads the file and its TMATS body decodes as ASCII.

## Verify

- `pytest software/tests/test_tmats.py` passes, fuzz test included.
- `diff <(python -c "from maiden.tmats import *; print(render_station(parse_station(open('config/tmats/station.tmt').read())), end='')") config/tmats/station.tmt`
  — decide: either it's empty (renderer preserves comments) or you
  document that comments are generator-side only and the template is the
  commented reference. Pick one and write it in the module docstring;
  ambiguity here becomes a diff-noise tax on every future session.
- Lesson-02 round-trip test still green with real TMATS payload.
- Commit: `tmats: station template per D4 IF-2, parser/generator`.

## Explore

1. **Break a foreign tool politely.** Strip all `C\MAIDEN\` attributes and
   run the file through PyChapter10's TMATS handling — it should be
   indifferent. That indifference is the design: verify it, then note in
   the ICD margin (a comment in station.tmt) that the namespace is
   load-bearing for MAIDEN only.
2. **Serial-number discipline.** D5 CM assigns MAIDEN-STA-001…003 and
   versioned calibration per serial. Extend `render_station` to take the
   serial and station letter as parameters and generate B/C variants.
   Where should per-serial calibration files live? Propose the
   `config/` layout in a README — lesson 20 will hold you to it.
3. **What's NOT in the template.** The aircraft TMATS (D4 IF-3: airframe,
   logger serial, mass, mount) shares syntax but not schema. List which
   `Station` fields an `Aircraft` descriptor replaces — lesson 22 builds
   it, and a shared `parse_attributes` core is the payoff of today's
   split.

## Checkpoint

- `config/tmats/station.tmt` matches D4 IF-2, and lesson 02's writer now
  emits it as the real first packet.
- `maiden.tmats.parse_station` / `render_station` round-trip the template;
  missing attributes degrade to `None` + warning; 200-case fuzz never
  raises.
- You can parse `R-1\TK1-4:3;` aloud — group, recorder index, attribute,
  row, value — without notes.
