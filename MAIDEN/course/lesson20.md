# Lesson 20 — Station 1 → Station 3 [bench/field]

*Where we are.* Every subsystem of a ground station now exists and has
passed its own bench test: radar chain (16–17), time source (18), recorder
(19), and the camera/calibration toolkit from lesson 09. This lesson turns
the pile on your bench into **MAIDEN-STA-001** — powered, cased, on a
tripod, surveyed, calibrated, and recording — then replicates it into
-002 and -003. It also closes the loop the software track has been waiting
for since lesson 15: the first *real* HIL dataset, recorded by real
hardware, replayed by CI on every commit from now on.

## Objectives

- Design and wire the station power tree from one 4S LiFePO₄ pack and
  verify the GS-007 endurance budget with measured draws (VT-31).
- Assemble Station 1: case, tripod, leveling head, sighting rail; assign
  serial MAIDEN-STA-001 and create its per-serial calibration files under
  `config/` per D5 configuration management.
- Execute the full D6 survey & calibration procedure for real and retire
  VT-06 and VT-07 with field evidence.
- Record the HIL dataset and wire it into lesson 15's CI harness.
- Replicate to Stations 2 and 3 from a written build checklist.

## Concepts

### The power tree

One battery, two rails, every load measured:

```
 4S LiFePO₄ 10 Ah (12.8 V nom, ~128 Wh)
   ├── fuse (blade, sized after measurement)
   ├── buck 12 V ──── camera (if 12 V model), LNA rail
   └── buck 5 V  ──── SBC, FPGA board, GNSS, radar module
                       └── INA219 shunt → Ch 6 battery telemetry
```

Budget math, with placeholder draws you will replace by measurement: SBC
~6 W, camera ~2 W, FPGA board ~1 W, radar + LNA ~0.5 W, GNSS ~0.2 W ≈
**10 W**. 128 Wh at 80 % usable and 90 % converter efficiency → ~9 h —
GS-007's 3 h with 3× margin *if the estimates hold*. They never quite do:
the Pi's transient draw during video encode, the camera's power at full
frame rate, and buck converter efficiency at light load are the usual
liars. Measure the integrated station at the shunt, not the datasheet.

Margin is not waste here — cold weather (a February demo, per D1) takes a
real bite out of LiFePO₄ capacity, and D5's risk R8 says one person is
deploying three of these; a battery that always lasts the session is one
less thing on the field checklist.

### Serials and per-serial calibration — CM for hardware

D5's rule: each station has a serial recorded in its TMATS, and
calibration files are versioned per serial. Concretely:

```
config/
├── stations/
│   ├── MAIDEN-STA-001/
│   │   ├── station.yaml      # serial, camera model+lens, radar module
│   │   ├── intrinsics.yaml   # lesson 09 output: fx fy cx cy k1 k2, date
│   │   └── boresight.yaml    # radar az/el offsets from rail, date
│   ├── MAIDEN-STA-002/ …
│   └── MAIDEN-STA-003/ …
```

The recorder (lesson 19) builds its TMATS from these files; the survey
values (position, heading) are per-*session* and entered at deploy, not
per-serial. This split matters: intrinsics survive a drive to the field;
heading does not survive picking up the tripod. Getting this wrong is
exactly risk R4 — survey/calibration sloppiness swamping fusion — and the
file layout is the mitigation you can enforce with a schema check in CI.

### The survey & calibration procedure, for real this time

You have rehearsed the pieces (lesson 09 checkerboards, lesson 16
reflector walks). Now run the D6 procedure end to end, as one drill,
because the 15-minute deploy requirement (GS-006, tested at VT-30 in
lesson 99) is won or lost in how these steps chain:

1. Set tripod; level; mark the ground point.
2. 5-minute GNSS average at the mark → position.
3. Sight a surveyed far landmark through the rail → heading; verify
   against a second landmark (the two must agree within GS-004's 0.2° —
   if they don't, your first landmark coordinate is wrong, and you just
   learned why the procedure demands two).
4. 12-pose checkerboard → intrinsics; reprojection ≤ 0.5 px or redo.
5. Corner reflector walked across the beam → boresight peak at rail
   heading.

The error budget from D3 is the reason for the fuss: σ_range ≈ R²·σ_θ/B
means at 150 m a 0.2° heading error moves the target ~0.5 m — half of
SYS-002's entire budget, spent before the EKF sees a single measurement.

### The HIL dataset

Lesson 15 left a TODO in the CI matrix: `data/HIL/` did not exist. Today
it does. A good HIL recording for CI is *boring on purpose*: bench
Station 1, radar viewing a box fan (steady, known-ish Doppler), camera
viewing a monitor looping twin-rendered frames or a swinging pendulum,
5 minutes, everything locked. CI doesn't need an interesting scene; it
needs a *stable* one, so that a regression in ingest, tracking, or the
Doppler DSP shows up as a diff against pinned metrics rather than as
noise.

## Doc Trace

- **Implements:** GS-006/GS-007 in hardware form (their *demonstrations*
  VT-30 and the 3-attempt deploy drill are lesson 99's); completes the
  physical side of GS-001–GS-005.
- **Governed by:** D6 "Ground station" (power, enclosure, survey &
  calibration procedure), D5 configuration management (serials, per-serial
  calibration), D5 §HIL (the CI merge point), D3 Figure 2 (why survey
  accuracy dominates).
- **Verifies:** VT-06 (survey repeatability), VT-07 (intrinsics — now on
  the real station cameras), VT-31 (battery endurance).
- **Risks retired or reduced:** R4 (procedure now written, drilled, and
  schema-checked), R8 (pre-wired cases and the build checklist are the
  quick-deploy groundwork).

## Build

1. **Power.** Wire the tree above on the bench with the shunt in place;
   measure every rail at idle and while recording; size the fuse at 2×
   measured peak. Log the draws in `hardware/stations/power-budget.md` —
   real numbers, dated.
2. **Case and tripod.** Weatherproof case, glands for antenna/camera/GNSS;
   surveyor tripod with leveling head; sighting rail along the camera
   boresight. Photograph the layout before closing the lid — the photo
   goes in the build checklist.
3. **Serial and config.** Create `config/stations/MAIDEN-STA-001/` and
   point the recorder's TMATS builder at it. Add a pytest that validates
   every station directory against a schema (required keys, dated
   calibrations) — R4's cheap insurance.
4. **Drill the procedure.** Run the 5-step survey & calibration in the
   yard or field. Time each step (baseline for GS-006, no pass/fail yet).
5. **HIL dataset.** Record the 5-minute bench session; place under
   `data/HIL/2026….../`; extend lesson 15's CI job to replay it and pin
   the metrics that must not regress (track count, v_r distribution
   bounds, ingest sample counts).
6. **Replicate ×3.** Write `hardware/stations/BUILD-CHECKLIST.md` while
   building -002 (you always discover the checklist's gaps on unit two).
   Station B gets the 35° lens per D6 — its `station.yaml` and intrinsics
   differ; nothing else should. Calibrate each serial independently;
   never copy another station's intrinsics file, and make the schema
   check reject two stations whose intrinsics are byte-identical.

## Verify

**VT-06 — survey accuracy.** Survey the same mark on two different days;
compare positions and headings (and against an RTK reference if the F9P
base from lesson 21's decision is available). Pass = ≤ 0.1 m, ≤ 0.2°.
**Observe on field**; log both surveys and the deltas to `results/VT-06/`.

**VT-07 — camera intrinsics.** Lesson 09's hold-out check, rerun on each
real station camera in its case (the window glass is now in the optical
path — that's the point). Pass = ≤ 0.5 px on hold-out poses, all three
serials. **Observe on bench**; log per-serial reports to `results/VT-07/`.

**VT-31 — battery endurance.** Full-load recording until the 5 V rail
sags or 4 h elapses, Ch 6 telemetry as the log. Pass = ≥ 3 h. **Observe on
bench** (outdoors if you can arrange a cold day — note the temperature in
the evidence). Log the discharge curve to `results/VT-31/`.

**CI.** The HIL replay job runs green on the next push, and a deliberately
broken ingest branch turns it red.

## Explore

1. **Deploy-time dress rehearsal.** Run the full solo deploy of all three
   stations in the yard, stopwatch running, no pass/fail pressure. Where
   did the time go? Feed the top two time sinks back into the checklist —
   VT-30 in lesson 99 will thank you.
2. **Thermal soak.** Closed case, sun or heat lamp, full load, 1 h: plot
   SoC temperature from Ch 6. Does the Pi throttle? If yes, that's a vent
   or a heatsink now, not a mystery dropout in November.
3. **Survey sensitivity.** Deliberately mis-enter heading by 0.5° in a
   twin run (lesson 07 lets you perturb a station pose): how far does
   fused position move at 150 m? Compare with D3's R²·σ_θ/B prediction.
   Pin the result in `docs/` margin notes — it is the number you'll quote
   whenever you're tempted to rush step 3 in the field.
4. **Design friction, small:** D6 says the survey heading is entered "on
   the station keypad or host app" — neither exists. Decide (host app CLI
   is the cheap answer), build the entry path into the recorder's session
   setup, and update D6 and D9's workflow step 2 to match what you built.

## Checkpoint

- Three cased, powered stations with serials MAIDEN-STA-001…003;
  `config/stations/` populated, schema-checked by pytest, and feeding
  each recorder's TMATS.
- Measured power budget committed; VT-31 evidence in `results/VT-31/`
  shows ≥ 3 h.
- VT-06 and VT-07 evidence in `results/`, all pass criteria met on real
  hardware.
- `data/HIL/` exists; CI replays it with pinned metrics and fails on an
  injected regression.
- `hardware/stations/BUILD-CHECKLIST.md` is complete enough that future-you
  could build station 4 without this lesson open.
- D8's rows for VT-06, VT-07, VT-31 are filled.
