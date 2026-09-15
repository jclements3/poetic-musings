# MAIDEN Prototype Build Course — Curriculum Contract

The design authority for the lessons in this directory. Lesson authors and
reviewers: follow this exactly. Students: this is the syllabus contract; the
lessons are `lesson00.md` … `lesson24.md` and `lesson99.md`.

**Course goal.** Starting from the released Basic Plan document set
(docs/D0–D9, Rev 0.1) and the skills taught by the theremin course, build
the MAIDEN Prototype: three Ch. 10-recording ground stations, an airborne
6-DOF truth logger with converter, and the complete processing pipeline
(ingest → tracker → fusion → maneuver recognition → scoring → report),
exercised end-to-end against a digital twin, with CI replaying twin and HIL
data on every commit. Exit state = D5 SEMP's Prototype milestone entry
criteria for the validation campaign.

**Student profile.** Senior systems engineer; the theremin course graduate:
writes VHDL-2008 with self-checking requirement-tagged testbenches, runs
the pinned OSS CAD Suite flow, understands NCO/mixing/CIC/FFT/CFAR at the
block level. Strong Python. New to: estimation theory in anger (EKF),
computer vision, IRIG-106. Explain those from first principles; never
condescend on the rest.

**Document discipline.** Requirements are cited by ID (SYS-002, GS-003…)
and defined only in D2. Tests are cited by ID (VT-10…) and defined only in
D7. Interfaces come from D4; design intent from D6; schedule and CM rules
from D5. A lesson that needs to change any of these says so explicitly and
directs the student to revise the document — the docs are living artifacts
and the course treats doc revision as part of the build (D5 change
control: requirement change = commit touching D2 + affected D6/D7 rows).

## Lesson format (mandatory template)

Each lesson uses exactly these sections, in order:

1. `# Lesson XX — <Title> [track]` where track ∈ desk / bench / field,
   then a one-paragraph *Where we are* orienting the student in the build
   arc and naming what exists after the previous lesson.
2. `## Objectives` — 3–6 bullets, checkable.
3. `## Concepts` — the teaching. First principles for new material
   (estimation, vision, IRIG-106); working-engineer level for the rest.
   ASCII diagrams where they help.
4. `## Doc Trace` — the explicit map from this lesson's work to the
   document set: which D-doc sections govern it, which requirement IDs it
   implements, which VT tests will verify it, and any TBD it closes.
   Every lesson has one. This is the course's recurring thread, as the
   radar connection was the theremin course's.
5. `## Build` — what to make. Interfaces and key formulas are given
   verbatim and are contractual; module internals are guided prose plus
   excerpts. File paths are repo paths (`software/maiden/...`). If a
   lesson provides a complete file, it is complete and pasteable; if it
   provides a skeleton, it is labeled *skeleton*.
6. `## Verify` — how to know it works: commands, what to measure, and the
   acceptance range (the VT pass criterion where one applies). Software
   checks are pytest tests the student writes and keeps. Hardware results
   are marked **observe on bench** and logged to `results/VT-nn/`;
   NO fabricated outputs anywhere in the course.
7. `## Explore` — 2–4 exercises extending or stress-testing the build. At
   least one per lesson probes a design decision from D6 (including the
   ones that turn out to be wrong — see "Design friction" below).
8. `## Checkpoint` — bullet list of verifiable facts that must hold before
   the next lesson ("`pytest software/tests/test_geo.py` passes", "twin
   .ch10 loads in PyChapter10 with 7 channels").

Tone: direct, technical, occasionally wry. No marketing language.

**Design friction rule.** Where the D6 design has a real problem (e.g., the
CIC ↓8 decimation vs. 24 GHz Doppler bandwidth in lesson 17), the lesson
does not silently fix it: it walks the student into discovering it, then
has them revise the document per D5 change control. Finding these is a
feature of the course, not an erratum.

## The repo (created in lesson 00)

```
maiden/                      (this repo, git-initialized in lesson 00)
├── docs/                    D0–D9 (already present)
├── course/                  this course (material only; no student work)
├── software/
│   ├── maiden/              the Python package
│   │   ├── geo.py           L01   field frame, LLA→ENU, poses
│   │   ├── ch10/            L02   packet reader/writer core
│   │   ├── tmats.py         L03   parser + generator
│   │   ├── timebase.py      L04   RTC→UTC, sync checks
│   │   ├── state.py         L05   StateSample, Event, adapter registry
│   │   ├── twin/            L06–07 flight model, sensor models, writer
│   │   ├── ingest.py        L08   files → StateSample stream
│   │   ├── camera.py        L09   intrinsics, px→az/el
│   │   ├── track/           L10–11 candidates, tracker
│   │   ├── fuse.py          L12–13 EKF
│   │   ├── validate.py      L14   residuals, metrics, gate
│   │   ├── convert/         L22   native airborne logs → Ch. 10
│   │   ├── maneuver.py      L23   segmentation + recognition
│   │   ├── score.py         L23   rubric + calibration layer
│   │   └── report.py        L24   PDF, approach panel, field rules
│   └── tests/               pytest; grows every lesson
├── firmware/                L17–18 FPGA: doppler DSP, IRIG-B (VHDL)
├── hardware/                L16, 20, 21: CAD, schematics, BOM
├── config/
│   ├── tmats/station.tmt    L03   the IF-2 template
│   └── field/rcrc.yaml      L01   survey points, rule polygons
├── data/                    raw sessions by date; never modified
└── results/                 VT-nn evidence; feeds D8
```

Conventions: Python 3.11+, NumPy-first, dataclasses over dicts, pytest,
ruff. VHDL per the theremin house style (numeric_std only, synchronous
active-high resets, 2-FF synchronizers on every async input,
requirement-tagged testbench asserts — here the tags are VT/requirement
IDs, e.g. `GS-002 FAIL: ...`).

## Pinned interfaces

These are contractual across lessons. Generics/defaults may be extended,
never renamed or retyped.

- **Field frame** (L01): ENU, origin = Station A survey mark, N along
  survey north. `maiden.geo.enu_from_lla(origin_lla, lla) -> np.ndarray`
  and `Pose(pos_enu, heading_deg, boresight_el_deg)` for stations.
- **StateSample / Event** (L05): exactly the D4 IF-4 dataclasses,
  fields and meanings verbatim from the ICD. Everything above ingest
  consumes these and nothing else.
- **Twin CLI** (L07): `maiden twin --out DIR [--seed N] [--imperfect]`
  writes `STATION_{A,B,C}_*.ch10` + `TRUTH_*.ch10` + `truth.npz`.
- **Ingest** (L08): `maiden.ingest.load(path) -> Iterator[StateSample]`;
  TMATS → `Station | Aircraft` descriptor objects.
- **Tracker** (L11): per-station, per-frame → `az_deg, el_deg, conf`
  emitted as StateSamples (`source` = station id).
- **EKF** (L12–13): state x = [E N U vE vN vU]ᵀ; publishes FUSED
  StateSamples with 6×6 covariance. Measurement models: az/el (nonlinear,
  station pose from TMATS) and v_r = v·û(station→target).
- **Validate** (L14): `maiden validate --session DIR` → per-flight and
  per-maneuver metrics table + gate verdict, JSON + markdown, in D8's
  table schema.
- **FPGA Doppler DSP** (L17): 16-bit 48 kS/s I/Q in → CIC decimate →
  512-pt FFT (50 Hz update) → CA-CFAR → v_r float (m/s, signed) + SNR +
  peak bin out UART/SPI; raw I/Q passes through. Decimation factor is
  decided in-lesson (D6 says ↓8; the lesson audits that).
- **IRIG-B source** (L18): GNSS PPS in → IRIG-B DCLS out + 10 MHz RTC;
  camera strobe GPIO latches RTC per frame.
- **Recorder** (L19): channel map exactly IF-1 (Ch 0–6, types per D4
  table); TMATS packet first; packets interleaved by RTC.
- **Converter** (L22): parsers per D4 IF-3 table; ArduPilot `.bin` via
  pymavlink is the baseline; emits the same channel/time discipline as
  stations.

## Verification thread

Every VT test from D7 that can be exercised before the field campaign is
assigned to a lesson (see the syllabus table in README.md). The course
maintains the D5 rule: raw evidence lands in `results/VT-nn/`, committed
with the code that produced it; D8's "Other verification results" table is
filled as lessons complete, not retroactively. Lesson 99 runs the
remaining field-only tests and the campaign gate.
