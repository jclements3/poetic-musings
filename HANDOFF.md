# Handoff — VL-1 / POETIC MUSING session (mobile, 2026-08-29)

## Decisions
- Program name: POETIC (personal) + MUSING (IRAD). Six letters each.
  - POETIC: Piano VL-49 · Oracle console (Forth H2, bar TFT, SD, CW keyer/decoder) · Erand49 harp · Theremin · IRIG clock · Coil launcher/catcher
  - MUSING: MAIDEN (incl. unit integration, solver) · UHF beacon (GPS-disciplined CW/WSPR, personal ledger, ham) · SDR (direct-sampling HF on theremin antennas, AD9226-class ADC) · Imaging (camera capture, timestamp, centroid) · Network (RMII/MAC/UDP/Ch.10) · GPS (station clock copies)
- Serial build rule, finish before start: C → I → O → T → P → E (updated on desktop 2026-08-31; was C → T → O → P → E). U/S after E if funding delayed.
- Piano box is the platform demo (One Box). Not a MAIDEN dependency.
- Display: 8.8" 1920x480 bar TFT over ULX3S GPDI; 55 mm band; verify active area before cutting.
- Keyboard: 49 keys C2–C6, gold harp labels A0–G7 one per key, two-layer ASCII (SHIFT = One Key Play L). ~~Buy a used 49-key MIDI controller keybed, not membrane.~~ Superseded 2026-08-31: VL-1-authentic flat buttons — MX-class switches under 3D-printed white/black caps set in a printed keyboard graphic.
- H2 forth-cpu (howerj) as control plane; port to Clash as Lessons 12–14; black-box VHDL first.
- Harp interface: I2S 24/96 harp-master, 3 Mbaud 8-byte event frames, harp does pluck detect (CORDIC mag + CA-CFAR), KS at 96 kHz with allpass fractional delay.
- One ULX3S ECP5-85F for everything personal; second board optional spare.

## Corrections made this session
- Snooker home rig uses a 12 V coil launcher (magnet wire, IRLZ44N, 1N5408, 8xAA, XB2 button); elastic is snubbers only. The elastic draw-stop/solenoid design is the MAIDEN tabletop testbed, a different rig. Receipts in project files are the coil-rig BOM.
- Still to buy for C: AAs, 8–10 mm ID rigid coil-form tube.

## PERT/CPM outcomes
- Cut C4 (FPGA pulse timing before Forth) — phone slow-mo until O exists.
- Buy 1 ADC eval + 5 IR pairs before 13 ADCs/98 pairs (harp gate 1 = one string).
- Order harp rib at start of P after micrometer bore check.
- Case last; TFT+HDMI driver as matched kit.

## Files
- README.html (was vl1-49key-panel-layout.html) — panel map (gen.py regenerates, incl. the PNG)
- vl1-panel-layout.html — original VL-1 panel map
- vl1-clash-module-tree.md — 36 modules, MAIDEN overlaps starred
- fpga-venn.png/.svg, fpga-venn4.png/.svg — 3- and 4-set overlap (venn4.py regenerates; built ✓ / planned ○)
- fpga-development-plan.md — ordered plan with gates (POETIC + MUSING letters, C → I → O → T → P → E)
- fpga-pert-cpm.md — risks R1–R10, purchase timing
- one-box-overview.html — single-page overview (POETIC + MUSING naming)

## Open items for desktop
- ~~Update overview/plan to POETIC + MUSING letters and C-first order.~~ Done 2026-08-31 (Oracle naming, C → I → O → T → P → E, P = 3D-printed keyboard with Oracle as UI brains).
- Add antennas + THEREMIN/SDR mode to panel drawing when P starts.
- Imaging weak points: global-shutter sensor, external trigger, FOV/range study — put in Sep Basic Plan.
- Metrology reference for I: used GS-101B or Thunderbolt-class GPSDO.
