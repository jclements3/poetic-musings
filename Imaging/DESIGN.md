# Imaging — Phase 11 design (I·MUSING · triggered, timestamped centroid camera)

PLAN.md Phase 11: global-shutter sensor per the Sep study; external trigger; IRIG
timestamp; centroid extraction; stream over N. Prereqs N, G. Gate/demo: wave
something in front of the camera, watch timestamped centroids stream. Cost TBD —
**the Sep Basic Plan study comes first** (fpga-development-plan #11).

## Sep study inputs (restated from HANDOFF.md, due Sep Basic Plan)

The declared weak points: **global-shutter sensor choice, external trigger, FOV/range
study.** Concretely, the study must produce: (1) a sensor+interface pick the FPGA can
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
      ─► threshold (register, hysteresis) ─► centroid accumulator per frame:
             Σx·w, Σy·w, Σw, bbox, pixel count   (running sums — no frame buffer
      ─► SDRAM frame store (debug/still readout   needed for the centroid itself)
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
- **Centroid:** single-pass running sums at pixel rate; divide happens once per
  frame (sequential shift-subtract divider, or in Forth for bring-up). Sub-pixel
  from the weighted sums. Az/el conversion via intrinsics lives in software
  (tabletop plan: checkerboard calibration ≤0.5 px reprojection) — fabric ships
  pixel coordinates.
- **Record type:** extend `MAIDEN/firmware/recorder/PROTOCOL.md`'s table (it is the
  single owner — the new row is proposed there when this letter starts): 0x20
  CENTROID, per frame: rtc u48, seq u16, cx_q4 u16, cy_q4 u16, sum_w u16, flags u8
  (≈16 B payload). Pairs with 0x12 STROBE_STAMP; mirrors D4's Ch 5 TRACKER channel
  (az, el, conf, bbox per frame) one calibration step downstream.

## Register block (eforth-pm.md conventions, provisional 0x4060 group)

| addr | write | read |
|---|---|---|
| 0x4060 | oImgCtrl — capture en, trigger mode (slave/master), test pattern | iImgStat — frame valid, FIFO overflow (sticky), sensor PLL locked |
| 0x4062 | oImgTrig — trigger rate divider (frames per PPS), manual fire | iImgSeq — frame seq |
| 0x4064 | oImgThresh — threshold + hysteresis | iImgCx / iImgCy (autoinc pair, latched per frame) |
| 0x4066 | oImgExp — exposure/gain (SCCB/I²C shim to sensor) | iImgSum — Σw (detection confidence proxy) |

Forth: `img-go` `trig!` `thresh!` `cent@ ( -- cy cx )` `.cent` — bring-up is typing
at the O console with a still readout from SDRAM before N is ever involved.

## Verification (the gate)

1. **Sim:** DVP stimulus from PNG-derived vectors; centroid property-tested against
   a NumPy golden model (MAIDEN golden-model discipline); strobe_latch TB reused.
2. **Bench:** LED point source on the mat — centroid noise floor (target: sub-pixel
   σ per the study's FOV table); trigger phase vs PPS on the scope; IRIG timestamp
   consistency: (centroid rtc) − (TIME_MARK mapping) drift-free over 10 min.
3. **Demo:** wave a target; laptop plots timestamped centroids live over N,
   zero STROBE_STAMP overflows. Evidence to `Imaging/results/`.

## Out of scope

Video compression/H.264 (SBC path owns it), multi-camera fusion (M Phase 12b),
lens/mount mechanics beyond the study, MIPI D-PHY unless the study forces it
(prefer DVP; a MIPI-only pick costs a deserializer and a lane of risk).
