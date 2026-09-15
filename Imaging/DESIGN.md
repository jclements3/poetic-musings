# Imaging — Phase 11 design (I·MUSING · snooker table, part 1: where the balls are)

PLAN.md Phase 11: overhead OV9281 global-shutter camera on the snooker table; external
trigger; IRIG timestamp; per-ball centroid extraction in gateware; stream over N.
Prereqs N, G. **Gate:** roll one ball — a continuous, IRIG-stamped centroid track
arrives over N with no frame gaps at 200 fps. **Demo:** roll balls; V0 draws each
ball's path live. Part 2 is M (Motion radar): cue-ball departure speed, checked
against this letter's camera-derived speed within 5 %. Cost: OV9281 module + lens +
overhead mount, TBD after **the Sep Basic Plan study** (fpga-development-plan #11).

**Spoke framing (`../PROGRAM.md`):** Imaging adds the overhead OV9281 camera and its
strobe/trigger line to the Panel+Oracle root. In `../CLASH-LIBRARY-MAP.md` § Module
list it owns the largest block of ○ work in the library — DVP camera capture and the
run-length blob labeller with per-ball centroids (I/O and links) — plus the ◐ async
strobe timestamp latch (Timing, port from `strobe_latch.vhd`), and it consumes N's
transmitter and I/G's clock. The `MAIDEN/…` paths below are the library source
archive, a plain directory in this unified repo since 2026-09-15; its harvested camera
decisions stand, its USB3→SBC video path does not apply here.

## Snooker geometry (sets the study's numbers)

| Quantity | Value | Consequence |
|---|---|---|
| Table playing area | 12 ft × 6 ft (3569 × 1778 mm) | one overhead camera, 2:1 aspect matches 640×400 sensor turned landscape |
| Ball diameter | 52.5 mm | ≈ 9 px across the full table at 640 px wide — enough for a centroid, not for colour |
| Shot speed | up to ~8 m/s on a break | at 200 fps: 40 mm/frame, under one diameter — tracks stay continuous |
| Mount height for full-table FOV | ~2.5 m with a ~75° lens (study confirms) | 5.6 mm/px; sub-pixel centroid → ~1 mm |
| Balls in play | up to 22 | per-frame record must carry *many* centroids, not one |
| Lighting | overhead, green baize | mono threshold separates balls from cloth; cue/player occlusion expected |

## Sep study inputs (restated from HANDOFF.md, due Sep Basic Plan)

The declared weak points: **global-shutter sensor choice, external trigger, FOV/range
study** — now with the snooker table as the fixed target: full-table FOV from one
overhead mount, 200 fps sustained, ball-sized blobs. Concretely, the study must produce: (1) a sensor+interface pick the FPGA can
capture natively; (2) proof of hardware trigger/strobe (both directions — see below);
(3) FOV vs range vs centroid error against MAIDEN's error law σ ≈ R²·σθ/B
(tabletop-range-BOM-plan §2.2: 0.2 mrad sub-pixel centroid → 0.2 mm at 1.5 m; same
equation gives 0.15 m at 150 m).

## Camera decisions harvested from MAIDEN

- **Tabletop pick** (`MAIDEN/tabletop-range-BOM-plan.md`): OV9281 module, 640×400
  @ 210 fps mono, global shutter, ~$35 — with the reason of record: *rolling shutter
  skews ~13 cm at Mach-5 scale, more than the whole model; global shutter is the one
  non-negotiable part.* The OV9281 die also comes on MIPI/DVP breakouts, making it
  the leading candidate for FPGA-native capture here.
- **Station pick** (`MAIDEN/hardware/BOM.md` #4 + Note B): 1080p30 global-shutter
  USB3 machine-vision camera + lens, 3× (60°/35°/60° fields per D6), ~$450, model
  TBD at order time; hard requirements: global shutter AND hardware strobe output
  confirmed in the datasheet, C/CS mount, "do not cheap out."
- **Timestamp mechanism** (D4 ICD, SYS-006): camera strobe → FPGA latches RTC;
  worst-case 2-clk synchronizer latency (200 ns at 10 MHz) against a 5 ms budget.

**Two capture paths, both PM-legitimate:** MAIDEN stations keep USB3→SBC H.264 into
Ch 2 (that path stays theirs). *This letter* builds the FPGA-native path the SWAG
sizes (DVP capture + trigger + centroid: ~2k LUT, 8 KB line buffers, 2 DSP, frames
in SDRAM) — the box does detection in fabric and ships coordinates, not video.

## Architecture

```
 trigger in (G's PPS/IRIG-derived rate, or manual) ─► exposure trigger ─► sensor
 sensor DVP (PCLK/HREF/VSYNC + D[7:0], own clock domain) ─► capture CDC FIFO
      ─► threshold (register, hysteresis) ─► run-length blob labeller (one line
             buffer, up to 32 blobs/frame) ─► per-blob accumulators:
             Σx·w, Σy·w, Σw, bbox, pixel count   (running sums — no frame buffer
      ─► SDRAM frame store (debug/still readout   needed for the centroids)
          via O console — bring-up tooling)
 strobe/exposure-active ─► strobe_latch (MAIDEN/firmware/timebase/rtl/strobe_latch.vhd,
      reused verbatim: 2-FF sync, (rtc,seq) 16-deep FIFO, sticky loud overflow)
 centroid + (rtc,seq) pair ─► CENTROID record ─► N's record mux ─► UDP/Ch.10
```

- **Trigger, both directions:** slave mode (FPGA fires the sensor's trigger pin at a
  programmed rate phase-locked to G's PPS — frames land at known IRIG times) is
  primary; master mode (sensor free-runs, FPGA stamps its strobe) is the fallback
  and is exactly MAIDEN's Ch 2 mechanism. The Sep study confirms the pick supports
  slave trigger; STROBE_STAMP semantics (seq counts every frame including dropped
  stamps) carry over unchanged.
- **Centroid, per ball:** single-pass run-length labelling with one line buffer
  (blobs merge across rows by overlap; ball-sized min/max area rejects the cue tip
  and glare); running sums per blob; divides happen at end of frame (sequential
  shift-subtract divider, or in Forth for bring-up). Ball identity across frames is
  nearest-neighbour association in software (40 mm/frame max step vs 52.5 mm
  spacing minimum) — fabric ships unlabelled centroids. Sub-pixel
  from the weighted sums. Az/el conversion via intrinsics lives in software
  (tabletop plan: checkerboard calibration ≤0.5 px reprojection) — fabric ships
  pixel coordinates.
- **Record type:** extend `MAIDEN/firmware/recorder/PROTOCOL.md`'s table (it is the
  single owner — the new row is proposed there when this letter starts): 0x20
  CENTROID, one per blob per frame: rtc u48, seq u16, blob u8, cx_q4 u16, cy_q4 u16,
  sum_w u16, flags u8 (≈17 B payload; ≤32 records per frame, 200 fps → ≤ 110 KB/s). Pairs with 0x12 STROBE_STAMP; mirrors D4's Ch 5 TRACKER channel
  (az, el, conf, bbox per frame) one calibration step downstream.

## Register block (eforth-pm.md conventions, provisional 0x4060 group)

| addr | write | read |
|---|---|---|
| 0x4060 | oImgCtrl — capture en, trigger mode (slave/master), test pattern | iImgStat — frame valid, FIFO overflow (sticky), sensor PLL locked |
| 0x4062 | oImgTrig — trigger rate divider (frames per PPS), manual fire | iImgSeq — frame seq |
| 0x4064 | oImgThresh — threshold + hysteresis, min/max blob area | iImgCx / iImgCy (autoinc pair, per blob; iImgN = blobs this frame) |
| 0x4066 | oImgExp — exposure/gain (SCCB/I²C shim to sensor) | iImgSum — Σw (detection confidence proxy) |

Forth: `img-go` `trig!` `thresh!` `cent@ ( -- cy cx )` `.cent` — bring-up is typing
at the O console with a still readout from SDRAM before N is ever involved.

## Verification (the gate)

1. **Sim:** DVP stimulus from PNG-derived vectors; centroid property-tested against
   a NumPy golden model (MAIDEN golden-model discipline); strobe_latch TB reused.
2. **Bench:** one stationary ball on the baize — centroid noise floor (target: sub-
   pixel σ per the study's FOV table); trigger phase vs PPS on the scope; IRIG
   timestamp consistency: (centroid rtc) − (TIME_MARK mapping) drift-free over 10 min.
3. **Gate:** roll one ball the length of the table — a gap-free track at 200 fps
   over N, zero STROBE_STAMP overflows; speed from Δcentroid/Δt is the reference M's
   radar must match within 5 %.
4. **Demo:** roll several balls; V0 draws each path live. Evidence to
   `Imaging/results/`.

## Out of scope

Ball colour identification (mono sensor at 9 px/ball — needs a colour sensor or an
SBC classifier pass), ball spin, video compression/H.264, multi-camera fusion,
lens/mount mechanics beyond the study, MIPI D-PHY unless the study forces it
(prefer DVP; a MIPI-only pick costs a deserializer and a lane of risk).
