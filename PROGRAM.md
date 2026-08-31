# POETIC MUSINGS — program index

**Mission:** one portable controller (the One Box, ULX3S ECP5-85F behind the 3D-printed
49-key Piano panel with Oracle as the brains) that JC can carry anywhere to demonstrate,
and teach the grandkids with, a family of FPGA projects: Santa's sleigh gliding a tube,
harp optical sensors making MIDI sounds, a Forth computer playing games, a music
synthesizer, a theremin, a CW transceiver, an SDR, and radar+camera fusion feeding an
AI data stream (4 cameras + 2 radars) on the IRAD side.

Build rule: serial, finish before start. **C → I → O → T → P → E**, then IRAD
**G → N → U → S → I → M** interleaved as funding allows. Details and gates:
`fpga-development-plan.md`. Single-page overview: `one-box-overview.html`.
Panel map: `README.html` (regenerate with `gen.py`).

## POETIC (personal)

| L | Directory | Project | Status |
|---|---|---|---|
| P | `Piano/` | 3D-printed 49-key VL-1-derivative keyboard; Oracle is the brains behind its UI | Panel map done (`README.html`); keybed purchase pending |
| O | `Oracle/` | Console: H2 Forth CPU, 8.8" bar TFT, SD, CW keyer/decoder | `Oracle/clash-h2/` compiles + smoke-tests; Verilog generated; real eForth image boots in the C sim AND in Clash simulation (`cabal test h2-boot`); PM capability spec in `Oracle/eforth-pm.md` |
| E | `Erand49/` | Harp: 98 IR optical sensors → pluck detect → KS synthesis → MIDI/I²S | designed: `Erand49/LAYOUT.html` (string band, ER-001..006), `frame_cad.py` → `frame.step` CAD master, string/frame specs, sensor-stations.csv; gate 1 = one string, one ADC eval |
| T | `Theremin/` | D-Lev-derived theremin; antennas double as SDR input | full repo copied 2026-08-31 from `../theremin` (git history intact) |
| I | `IRIG/` | IRIG-B timecode clock; free-running until G disciplines it | empty — next after C |
| C | `Coil/` | Santa Glide: sleigh slug in 10 ft tube, 8-coil linear reluctance motor, Alchitry Cu | `Coil/SantaGlide/` — design done, parts ordered, Rev B compiles to `santa_glide.v` |

## MUSING (IRAD)

| L | Directory | Project | Status |
|---|---|---|---|
| M | `MAIDEN/` | Tabletop testbed, unit integration, solver; fusion of 4 cameras + 2 radars into an AI data stream; Ch.10/TMATS | full repo copied 2026-08-31 from `../maiden` (white paper, range BOM, lessons, firmware, finance) |
| U | `UHF/` | GPS-disciplined CW/WSPR beacon (ham — personal ledger) | empty |
| S | `SDR/` | Direct-sampling HF on the theremin antennas, AD9226-class ADC | empty |
| I | `Imaging/` | Global-shutter capture, external trigger, IRIG timestamp, centroid | empty — sensor/FOV study due Sep Basic Plan |
| N | `Network/` | RMII PHY, MAC, UDP, Ch.10 transport | empty |
| G | `GPS/` | PPS DPLL, 10 MHz, station clock copies; disciplines IRIG | empty |

## Root files

- `PROGRAM.md` — this index
- `PLAN.md` — phased execution plan: each phase ends in a demo, culminating in the PM device
- `HANDOFF.md` — 2026-08-29 mobile session handoff (decisions, corrections, PERT outcomes)
- `fpga-development-plan.md` — ordered plan with difficulty/cost/gates and legacy letter map
- `fpga-pert-cpm.md` — risks R1–R10, purchase timing
- `one-box-overview.html` — single-page program overview with embedded panel SVG
- `README.html` + `gen.py` — 49-key panel map and its generator
- `vl1-panel-layout.html` — original VL-1 panel map (reference)
- `vl1-49key-panel-layout.png` — current render (gen.py emits it via cairosvg)
- `vl1-clash-module-tree.md` — 36 Clash modules, MAIDEN overlaps starred
- `fpga-venn*.svg/.png`, `venn4.py` — 3- and 4-set component-overlap diagrams

## Notes / open items

- Panel IDs are generic (keys A0–G7 = pedal-harp labels, S0–S4 sliders, P0–P9 buttons,
  V0 display), but the silk legends (voices, rhythms, calculator keys) are still tied to
  the 1981 Casio VL-1. As the box becomes a multi-demo controller, the legends need a
  mode-neutral layer (or per-demo overlays) — VL-1 emulation is one mode among many.
- Two boards total: ULX3S ECP5-85F for everything in the box; Alchitry Cu runs Santa
  Glide standalone.
- `MAIDEN/` and `Theremin/` keep their own `.git` repos (tracked as gitlinks from this
  repo). Their `.venv`s were not copied — recreate locally if needed.
- `MAIDEN/theremin/` is an older embedded copy predating the top-level `Theremin/` repo.
- Phase 0 gate met 2026-08-31: both firmwares compile (GHC 9.6.7/Clash 1.8.5),
  smoke test passes, Verilog generated, real eForth image boots in the C simulator.
  Toolchain note: some Python tools need `LD_LIBRARY_PATH=$HOME/miniconda3/lib`.
