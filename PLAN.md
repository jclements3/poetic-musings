# PLAN — incremental build of the PM device

The end state: **one portable controller** — the 3D-printed 49-key Panel with the
Oracle Forth console as its brains on a single ULX3S ECP5-85F — that boots to a mode
menu and can demonstrate every spoke of the Clash library on demand. Every phase below ends
with a **working demo someone can watch**, so there is always something to show the
grandkids, and nothing is started until the previous demo passes its gate
(finish-before-start rule).

Scope/cost/difficulty per project: `fpga-development-plan.md`. This file is the
execution order and the demo that closes each phase. The deliverable each phase leaves
behind is a set of measured Clash modules — `CLASH-LIBRARY-MAP.md` § Module list tracks
them by family (✓ verified · ◐ VHDL awaiting port · ○ to write); each directory's
`DESIGN.md` names which entries that phase moves. Everything lives in one unified repo
(github.com/jclements3/poetic-musings, since 2026-09-15).

Milestones: **Basic Plan Sep 2026 · Prototype Dec 2026 · Field Demo Feb 2027.**
December critical path: Phases 0–2, then 3, 7, 8, 12a. Everything else has slack.

---

## Phase 0 — Foundations (now)

Toolchain and repo hygiene; no hardware.

1. Install GHC 9.x + Clash 1.8 (cabal) on the desktop.
2. `Coil/SleighGlide/firmware/SleighGlide.hs`: first compile (`clash --verilog`), fix
   type errors, simulate in `clashi` — confirm `gates` walks 0→7→0 with the dwell table.
3. `Oracle/clash-h2/`: `cabal build`, run the smoke test (`0xA5` on `oLeds`).
4. Sep Basic Plan inputs due: Imaging sensor/trigger/FOV study; metrology pick for I
   (used GS-101B or Thunderbolt-class GPSDO).

**Gate: MET 2026-08-31.** Both firmwares compile (GHC 9.6.7 / Clash 1.8.5): clash-h2
passes its smoke test (0xA5 on oLeds) and generates `h2.v`; SleighGlide generates
`sleigh_glide.v`. The real eForth image (3334 words, metacompiled from upstream
forth-cpu with plain gcc — no gforth) boots in the reference C simulator
(`2 3 + . → 5`) and is installed as `Oracle/clash-h2/h2.bin` — and the same image
**boots end-to-end in Clash simulation** (`cabal test h2-boot`: banner + arithmetic
in ~15.4M cycles / ~60 s wall; functional UART model; zero semantic core fixes
needed vs h2.vhd). The Clash port of the H2 is proven against real software.
**Repo hygiene closed 2026-09-15:** one self-contained repo — `MAIDEN/` (library
source archive) and `Theremin/` absorbed as plain directories, nested histories
archived outside the tree, private material and build outputs ignored by rule; every
root/spoke directory carries a `DESIGN.md`; Panel and Erand49 carry `ORDERS.md`.

## Phase 1 — C · Sleigh Glide 🛷 (first demo, driven from the box)

Per `Coil/DESIGN.md` Rev D (decided 2026-09-15: the ULX3S is the only FPGA board).
The coil FSM, pacer and watchdog move into the box as `PM.Sleigh`; the driver board
at the tube gets its 8 gate signals over a 10-wire ribbon from the rear SLEIGH
connector; the Cu is retired. Rev B/C sims (FSM walk 0→7→0, pacer rates, watchdog)
carry over. Before the board arrives: wind 8 coils (200 T, 24 AWG), build the 8
driver channels, test each with a bench 3.3 V gate source at 12 V / CC 2 A. When it
lands: `PM.Sleigh` in the bitstream, slug in, all dwells 400 ms → tune `runDuty`,
then the dwell table live from the Forth prompt (`dwell!`), then voltage.

**Demo:** flip the switch; the sleigh glides house A→B→A over the snow village, pauses at
each house, parks when switched off; theremin pitch sets the speed. The Christmas
deliverable — needs the box present.
**Teaches:** Moore FSMs, PWM, MOSFET drive, magnetics.

## Phase 2 — I · IRIG clock ⏱

IRIG-B generator on the ULX3S: 1 s frame counter, BCD time fields, 10 ms bit cells,
DC-level and modulated outputs. Free-running on the board crystal (disciplined later,
Phase 7). **Implemented and sim-verified 2026-08-31** (`IRIG/clash/`: 8-frame testbench
covering cell widths, markers, rollovers, set latch, AM carrier — cross-checked
bit-for-bit against MAIDEN's decoder-verified irigb_gen.vhd; Verilog generated,
elaborates in yosys). Remaining for the gate: scope/decoder verification on the bench
(needs the ULX3S).

**Demo:** a clock that emits real range timecode; decode it and show the time moving.
**Teaches:** counters, framing, serialization — the second rep of Phase 1's skills.

## Phase 3 — O · Oracle 🖥 (the box gets its brains)

1. H2 as black-box VHDL first: eForth `ok` prompt over USB serial; `1 2 + .` → 3.
2. Bar TFT: verify active area against datasheet **before cutting anything**; GPDI
   text/VT100; prompt on glass, laptop unplugged.
3. SD block read (block 1 loads); GPIO/ADC words; timer/IRQ.
4. CW keyer/decoder peripheral — keyer sends, decoder prints to screen.
5. Clash port of H2 (`Oracle/clash-h2/`) replaces the VHDL as Lessons 12–14.

**Demo:** a self-contained Forth computer — type on it, compute, load a game from SD,
key CW and watch it decode. *(Desktop 2026-08-31: the whole ladder is pre-proven in
simulation — eForth boots, personal card greets and `1 load`s, IRIG clock live and
settable, keyer/decoder round-trips CW, text console renders pixel-exact — the bench
work is wiring real pins to already-tested gateware.)*
**Teaches:** soft CPUs, Forth, memory-mapped I/O, video timing.

## Phase 4 — T · Theremin 🎵

Bench the LC oscillator hardware; the Clash port already passes. Pitch + volume from
the antennas through the speaker; envelope/spectrum view on Oracle. From here on the
theremin suite runs as the regression target for every library change.

**Demo:** play music from thin air; watch the pitch track on the display.
**Teaches:** mixed-signal, frequency counting, NCOs, DSP basics.

## Phase 5 — P · Panel 🎛 (the control surface takes physical form)

Micrometer bore check, then order the harp rib (long lead — see PERT). Keys are
VL-1-authentic flat buttons: 59 MX-class switches (49 keys + P0–P9) under 3D-printed
white/black caps set in a printed keyboard graphic; print the panel per `README.html`;
mount bar TFT and sliders S0–S4; wire the 8×8 matrix (one 1N4148 per switch). Synth mode exercises PM.Synth / PM.Audio
(NCO, pulse oscillator, ADSSR, mixer, ΣΔ DAC) from the keys; VL-1 voices are the
test patches, not an accuracy target.

Design task before printing: mode-neutral silk legends — VL-1 emulation is one mode of
the PM device, not its identity (see PROGRAM.md open items).

**Demo:** *this is PM device v1* — the control surface drives every library block:
keys as ASCII into Forth, keys as notes through PM.Synth, sliders switching modes with no
flicker, envelope/spectrum live on V0, theremin as a voice source.
**Teaches:** integration — every prior phase is running inside one object.

## Phase 6 — E · Erand49 🪕

Gate 1 first, cheap: **one string, one ADC eval, 5 IR pairs** — pluck detected
(CORDIC mag + CA-CFAR), shown on Oracle, sounds a KS voice. Only then buy the
13 ADCs / 98 IR pairs. Gate 2: 49 strings, harp-master I²S 24/96 into the box,
3 Mbaud event frames, playable.

**Demo:** pluck real strings, optical sensors catch it, the box sings; harp drives
the Panel synth over MIDI-style events.
**Teaches:** detection theory, physical modeling synthesis, multi-channel ADC.

---

## Remaining spokes — any order once the root (O, P) and T are up

Each adds one piece of hardware to Panel+Oracle. Funding sets timing, not dependency.

## Phase 7 — G · GPS 🛰

u-blox with PPS; PPS-locked 10 MHz DPLL; discipline the Phase 2 IRIG clock; verify
against the GPSDO metrology reference. Station clock copies become a stock module.

**Demo:** the clock from Phase 2 stops drifting — show holdover vs. locked.

## Phase 8 — N · Network 🌐

RMII PHY, MAC, UDP. Stream ADC samples to a laptop, zero drops over 10 min.
Ch.10 transport framing on top. (Bench capture tooling from Oracle earns its keep here.)

**Demo:** live sensor data from the box onto a laptop screen across the room.

## Phase 9 — U · UHF 📡 (ham — personal ledger)

GPS-disciplined CW + WSPR beacon.

**Demo:** transmit, then pull up wsprnet and show the grandkids their signal was
heard hundreds of miles away.

## Phase 10 — S · SDR 📻

AD9226-class ADC direct-sampling HF on the theremin antennas; DDC (CIC/FIR);
waterfall on Oracle; decode a broadcast or WSPR signal.

**Demo:** the theremin's antennas become a radio receiver — same box, new mode.

## Phase 11 — I · Imaging 📷 (snooker table, part 1: where the balls are)

Global-shutter OV9281 (640×400, 120–210 fps) mounted overhead on the snooker table;
external trigger; IRIG timestamp; centroid extraction in gateware; stream over N.
A 52.5 mm ball is ~9 px across the full 12 ft table — enough for a centroid; at
200 fps an 8 m/s break moves under one ball diameter per frame, so tracks stay
continuous. Colour ID is out of scope (mono sensor); cue/player occlusion is expected.

**Gate:** roll one ball; a continuous, IRIG-stamped centroid track arrives over N with
no frame gaps at 200 fps.
**Demo:** roll balls on the table; V0 draws each ball's path live.

## Phase 12 — M · Motion radar 📡 (snooker table, part 2: how fast the cue ball leaves)

24 GHz Doppler front end (CDM324-class, SPI ADC) aimed down the table; CIC → FFT → CFAR
→ velocity records, IRIG-stamped, plotted on V0, streamed over N. Start with the
measured `MAIDEN/firmware/doppler` VHDL as a black box, port to Clash, re-measure on
ECP5. Radial speed only: a ball crossing the beam reads near zero, and multiple moving
balls give speeds with no ball identity.

**Gate:** strike the cue ball straight at the radar; the velocity trace on V0 matches the
camera-derived speed from Phase 11 within 5 %, timestamps aligned by IRIG.
**Demo:** one shot on the snooker table — camera says where every ball went, radar says
how fast the cue ball left, both on one time-aligned screen. This is the whole MUSING
half exercised on one shot.
**Teaches:** the full detection chain on one screen — the same blocks E used for plucks.

---

## Definition of done — the PM device

- One case: Panel + Oracle, ULX3S inside; Sleigh Glide packs alongside (tube, driver board, ribbon).
- Power on → the **S3 MODE slider selects the demonstration: P · O · E · T · I · C**
  (Panel · Oracle/Forth/games/spoke scripts · Erand49 · Theremin · IRIG clock · CW);
  V0 shows the mode screen, deeper choices via keys.
- Every mode reachable in under a minute, no laptop, no internet.
- A demo-day checklist per mode (what to say, what to show, reset procedure) lives in
  each project directory.

## Standing rules

- Finish before start; a phase closes only when its demo passes in front of a person.
- Theremin suite = regression gate for every shared-library change after Phase 4.
- **One FPGA board only — the ULX3S ECP5-85F** (2026-09-15). Everything else is
  sensors, drivers and ADCs on cables: Sleigh Glide's driver board over a gate ribbon,
  the harp's 13 ADCs daisy-chained over the EtherCON link. No harp-side board.
- Ledgers never commingle (P personal, W work; U is ham/personal). Bookkeeping only;
  it does not shape the build order.
- Buy late: 1 ADC eval before 13; 5 IR pairs before 98; rib only after bore check;
  case last; TFT + HDMI as a matched kit.
