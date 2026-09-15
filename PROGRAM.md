# POETIC MUSINGS — program index

**Mission:** build up a measured, sim-verified **Clash FPGA signal-processing library**,
demonstrated on one portable box. The box has two roots and everything else hangs off
them:

- **Panel** — the body: 49 keys, 5 sliders, 10 buttons, 8.8" bar TFT, speaker, case,
  antenna studs. Physical only.
- **Oracle** — the brains: H2 Forth CPU in Clash on the ULX3S ECP5-85F, the 0x40xx
  register bus, SD storage, serial and on-screen console. Every library block is
  configured, driven and read back from its prompt.

Each **spoke** below adds one piece of special hardware to the Panel+Oracle root and the
library components that hardware exercises. Spokes do not depend on each other; they
depend only on the root. Hardware-to-component map: `CLASH-LIBRARY-MAP.md`. Block
inventory: `LIBRARY.md`.

```
Panel + Oracle  (ULX3S ECP5-85F · keys · sliders · TFT · Forth · 0x40xx bus)
├── T  Theremin   + pitch rod, volume loop, 2 Colpitts boards        → EdgeSampler, DelayDiff, IIR, NCO, DAC
├── E  Erand49    + 98 IR pairs, 13 ADCs, harp frame                 → SPI ADC, CORDIC, CFAR, KS waveguide, HarpLink
├── I  IRIG       + IRIG-B output, scope                             → DCLS framer, BCD time, TOD set
├── G  GPS        + u-blox PPS/NMEA, 10 MHz out                      → PPS discipline, RTC, NMEA parser, DPLL
├── S  SDR        + AD9226 ADC, antenna relay (reuses T antennas)    → CIC, FIR, DDC, FFT512, AM demod
├── U  UHF        + whip on SMA, PA can                              → Keyer, Morse decoder, Goertzel, WSPR mod, TX interlock
├── N  Network    + RMII PHY                                         → MAC TX/RX, UDP/IPv4, CRC32, Ch.10 framing
├── V  Imaging    + OV9281 global-shutter camera, strobe line        → DVP capture, strobe latch, centroid
├── R  Radar      + Doppler front end (SPI ADC)                      → CIC → FFT → CFAR → velocity records
└── C  Coil       + Santa Glide tube on its own Alchitry Cu          → SleighSpeed link, watchdog, coil pacer
```

## Spokes

| L | Directory | Extra hardware added to the root | Library components exercised | Status |
|---|---|---|---|---|
| **P** | `Panel/` | *root* — keys, sliders, buttons, TFT, speaker, case | Matrix, Zones, RegFile, Spi, Synth, Audio, video console | `Panel/DESIGN.md`; panel map `README.html` |
| **O** | `Oracle/` | *root* — ULX3S, SD, USB serial | H2 SoC, UART, register bus, Cdc, SD block device | boots real eForth in Clash sim; Verilog generated |
| T | `Theremin/` (older VHDL) · `MAIDEN/theremin/clash/` (measured Clash) | antennas + oscillator boards | full theremin suite — **regression gate for every library change** | measured: 1,816 LUT4 |
| E | `Erand49/` | IR sensors, ADCs, harp frame | Cordic, Cfar, KS, HarpLink, I²S | designed; gate 1 = one string |
| I | `IRIG/` | IRIG-B out | DCLS framer | implemented + sim-verified |
| G | `GPS/` | u-blox module | Gps parser ✓, pps_discipline (VHDL), DPLL ○ | `DESIGN.md` |
| S | `SDR/` | AD9226 ADC + relay | Cic, Fir, Fft ✓; DDC wiring ○ | `DESIGN.md` |
| U | `UHF/` | whip, PA | Keyer ✓, WSPR ○ | `DESIGN.md` |
| N | `Network/` | RMII PHY | Net TX ✓, MAC RX ○ | `DESIGN.md` |
| V | `Imaging/` | OV9281 camera | strobe_latch (VHDL), DVP ○ | `DESIGN.md` |
| R | `MAIDEN/firmware/doppler/` | Doppler front end | doppler_core (VHDL), reuses Cic/Fft/Cfar | measured VHDL, sim green |
| C | `Coil/` | Santa Glide tube + Alchitry Cu | SleighSpeed | design done, Rev C rx on Cu |

Build rule: **root first, then spokes as hardware arrives.** O → P, then T (regression
gate), then any spoke in any order. Gates per spoke: `fpga-development-plan.md`.
Execution plan with the demo that closes each phase: `PLAN.md`.

## Root files

- `PROGRAM.md` — this index
- `CLASH-LIBRARY-MAP.md` — every hardware part mapped to the Clash component it demonstrates
- `LIBRARY.md` — shared-block inventory: what exists (measured VHDL/Clash), where, and which spokes consume it
- `PLAN.md` — phased execution plan: each phase ends in a demo
- `HANDOFF.md` — 2026-08-29 mobile session handoff (historical; predates the spoke model)
- `fpga-development-plan.md` — per-spoke difficulty/cost/gates and legacy letter map
- `fpga-pert-cpm.md` — risks R1–R10, purchase timing
- `one-box-overview.html` — single-page overview with embedded panel SVG
- `README.html` + `gen.py` — 49-key panel map and its generator
- `vl1-panel-layout.html` — original VL-1 panel map (visual inspiration only)
- `vl1-49key-panel-layout.png` — current render (gen.py emits it via cairosvg)
- `vl1-clash-module-tree.md` — 36 Clash modules for the root
- `fpga-venn*.svg/.png`, `venn4.py` — component-overlap diagrams

## Notes / open items

- `MAIDEN/` is a **library source archive**, not a spoke: it is the older IRAD testbed
  repo (own `.git`, tracked as a gitlink) where the measured Clash DSP blocks
  (`Maiden.{Cic,Fir,Cordic,Cfar}`, the theremin port, doppler and timebase VHDL) were
  born. Blocks are consumed in place or ported, never edited there. The 3-station
  fusion program that used to be the "M" capstone is out of scope here.
- `Theremin/` also keeps its own `.git`. Their `.venv`s were not copied.
- Panel silk legends are still tied to the 1981 Casio VL-1; they need a mode-neutral
  layer since VL-1 synthesis is one mode among many.
- Two boards total: ULX3S ECP5-85F in the box; Alchitry Cu runs Santa Glide standalone.
- Toolchain: GHC 9.6.7 / Clash 1.8.5; some Python tools need
  `LD_LIBRARY_PATH=$HOME/miniconda3/lib`.
