# MAIDEN: Prototype Build Course

A self-paced build course that takes the MAIDEN document set (docs/D0–D9)
from paper to the **Prototype milestone**: three Ch. 10-recording ground
stations, an airborne 6-DOF truth logger, and the full Python processing
pipeline — ingest, tracker, fusion EKF, maneuver recognition, scoring,
report — proven against a digital twin and ready for the validation
campaign.

The course has two layers:

- **Sprint cards** — `maiden00.md` is the index/backlog; `maiden01.md` …
  `maiden67.md` are sprint-sized tasks, each one desk sitting or one
  bench/field session, with a checkbox task list and a verifiable
  definition of done. This is the working path: open the next card, do it,
  check it off.
- **Lessons** — `lesson00.md` … `lesson24.md` and `lesson99.md` are the
  textbook layer: the concepts, math, and design reasoning each sprint
  card's *Read first* line points into. Sprints say *do*; lessons say
  *how and why*.

This is the successor to the theremin course
(`../theremin/course/`). That course taught you HDL, the open FPGA
toolchain, and CW-radar intuition. This one spends those skills: the FPGA
Doppler DSP in lesson 17 is the theremin's signal chain grown up, and the
whole project runs under the systems-engineering discipline the theremin
course only gestured at.

## Prerequisites

- Theremin course lessons 00–14 complete (lesson 99 strongly recommended
  before the hardware lessons here). You know VHDL-2008, GHDL/Yosys/nextpnr,
  self-checking testbenches, and what a mixer, NCO, CIC, and CFAR are.
- Python 3.11+, comfortable with NumPy and pytest.
- The MAIDEN document set read once through in D0's order: D1 → D3 → D5,
  then D2 → D4 → D6. The lessons cite these constantly and never restate a
  requirement — requirements live in D2 only.

## How to take the class

Work the sprint cards in `maiden00.md`'s backlog order; each card's *Read
first* line tells you which lesson section to read before starting. The
notes below describe the lesson layer.

1. Read lessons in numeric order. Each lesson header carries a track tag:
   **[desk]** runs on any machine with Python; **[bench]** needs the
   electronics bench and parts from the shopping list in lesson 16;
   **[field]** needs RCRC. Desk lessons never block on hardware — that is
   the SEMP's twin-first strategy, on purpose.
2. For each lesson: work in the repo (lesson 00 creates it), build what the
   **Build** section describes, and run the **Verify** section's checks.
   This is a *guided-build* course, not a copy-paste course: reference
   formulas, interfaces, and key excerpts are given; you write the modules.
   The pinned interfaces in `CURRICULUM.md` are the contract — match them
   exactly or later lessons won't integrate.
3. Do the **Explore** exercises. Several of them feed discoveries back into
   the document set (D2's TBDs are closed by lessons, not by fiat).
4. The **Checkpoint** section tells you exactly what must be working —
   phrased as verifiable facts — before the next lesson.

**Honesty rule.** Unlike the theremin course, expected outputs here are not
pre-captured: too much depends on your hardware, your survey, your sky.
Verify sections tell you what to measure and what range is acceptable
(usually a VT pass criterion from D7). Hardware-dependent results are
marked *observe on bench* and never faked. When you capture a result, log
it under `results/VT-nn/` — that directory structure is D8's evidence
trail.

## Syllabus

| Lesson | Track | Title | You build | Doc trace |
|---|---|---|---|---|
| 00 | desk | Orientation & the Repo | git repo, Python env, CI skeleton | D5 §CM |
| 01 | desk | The Field Frame | `maiden.geo` LLA→ENU, station poses | GS-004, IF-4 |
| 02 | desk | IRIG-106 Chapter 10 | packet reader/writer core | SYS-005, IF-1 |
| 03 | desk | TMATS | station template + parser | IF-2, GS-004/005 |
| 04 | desk | Time | RTC→UTC decoder, sync plan | SYS-006, VT-02 |
| 05 | desk | The State-Vector Interface | `StateSample`, `Event`, adapters | SW-001, IF-4 |
| 06 | desk | Digital Twin I: Flight Model | scripted Sportsman truth | SW-004 |
| 07 | desk | Digital Twin II: Sensors & Files | synthetic az/el + v_r → real .ch10 | SW-004, VT-17 |
| 08 | desk | Ingest | Ch. 10/TMATS → StateSamples | SW-001, VT-14 |
| 09 | desk/bench | Camera Geometry & Calibration | intrinsics pipeline, px→az/el | GS-005, VT-07 |
| 10 | desk | Video Tracker I: Candidates | sky model, motion proposals | SW-002 |
| 11 | desk | Video Tracker II: Tracks | detector + 2D Kalman → az/el/conf | SW-002, VT-15 |
| 12 | desk | Fusion I: The EKF | 6-state filter, az/el updates, init | SYS-001/002 |
| 13 | desk | Fusion II: Velocity & Dropouts | v_r updates, gating, covariance | SYS-003/004 |
| 14 | desk | maiden.validate | residuals, metrics, the gate | D7 §2, VT-10/11/12 |
| 15 | desk | CI & the HIL Harness | regression gate on every commit | SW-005, VT-18 |
| 16 | bench | Radar Front End | horn, LNA/AAF, module bring-up | GS-003, VT-04/05 |
| 17 | bench | FPGA Doppler DSP | CIC → FFT → CFAR → v_r | GS-002, VT-04 |
| 18 | bench | Station Time Source | PPS → IRIG-B generator, stamping | SYS-006, VT-02 |
| 19 | bench | The Ch. 10 Recorder | SBC recorder, all channels | SYS-005, VT-01/03 |
| 20 | bench/field | Station 1 → Station 3 | integrated station, cal/survey drill | GS-001–007, VT-06 |
| 21 | bench | Airborne Truth Logger | H743 log-only build, mount | AB-001/003, VT-08/13 |
| 22 | desk | Log → Ch. 10 Converter | native log parsers, time channel | AB-002, VT-09 |
| 23 | desk | Maneuvers & Scoring | segmentation, classifier, rubric | SW-003, SYS-007, VT-16/20 |
| 24 | desk | Report, Approach, Field Rules | one-page PDF, glideslope, flags | SYS-009/010/011 |
| 99 | field | The Validation Campaign | ≥10 flights, the gate, the demo | D7 §3, D8 |

(Lesson numbers 25–98 are intentionally unused; 99 is the reserved capstone
tag, same convention as the theremin course.)

## Suggested pacing

Lessons 00–15 are the software track and need nothing you don't already
own; the SEMP schedules them Aug–Nov. Order the lesson-16 parts when you
start lesson 06 — the twin will keep you busy through the shipping delay.
Lessons 16–22 are the hardware track (Oct–Dec, bench). Lessons 23–24 close
the pipeline (Nov–Dec). Lesson 99 is the Nov–Dec campaign plus the Feb
demo. Desk lessons average 2–4 sittings; bench lessons are gated by solder
and sky, not by reading time.

## Files

- `maiden00.md` — sprint index and backlog (start here).
- `maiden01.md` … `maiden67.md` — the sprint cards.
- `CURRICULUM.md` — the design contract this course was built against:
  lesson format, pinned module interfaces, honesty rules.
- `lesson00.md` … `lesson24.md`, `lesson99.md` — the textbook layer.
- Your work lives in the MAIDEN repo that sprint 01 creates, not in
  `course/` — this directory is course material only.
