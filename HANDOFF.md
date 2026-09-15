# Handoff — POETIC MUSINGS

Two sessions, newest first. The 2026-09-15 section supersedes the 2026-08-29 one
wherever they disagree; the older section is kept as the record of how the letters
were chosen.

---

# 2026-09-15 desktop session — reorientation to a Clash library on a Panel+Oracle root

## Decisions
- **The deliverable is a Clash FPGA signal-processing library.** The box is the
  demonstrator / test fixture, not the product. `CLASH-LIBRARY-MAP.md` maps every
  hardware part to the block it exercises; `LIBRARY.md` is the catalogue.
- **Root + spokes replaces POETIC/MUSING as structure.** Root = **Panel** (body: keys,
  sliders, TFT, speaker, case, antenna studs) + **Oracle** (brains: H2 Forth, 0x40xx
  bus, SD, console). Ten spokes each add one piece of hardware to the root and depend
  only on the root. POETIC / MUSING survive as group labels and as the ledger split
  (bookkeeping only). Tree in `PROGRAM.md` reads P O E T I C / M U S I N G.
- **Piano → Panel.** The VL-1 was the visual inspiration, not the goal. VL-1 synthesis
  is one mode; VL-1 A/B accuracy is no longer a gate. Phase 5 gates are now about
  matrix events, flicker-free zones, the console + spectrum strip, and every
  `PM.Synth`/`PM.Audio` block driven from the keys and re-measured on ECP5.
- **Oracle is the runtime, not a demo.** It owns the CPU, bus, storage and console;
  the keyer/decoder blocks belong to U (housed in `Oracle/pm-keyer` because the bus
  lives there).
- **MAIDEN as a program is gone from this repo.** `MAIDEN/` stays as the *library
  source archive* (measured `Maiden.{Cic,Fir,Cordic,Cfar}`, theremin port, doppler
  and timebase VHDL). The 3-station fusion program is out of scope. **M = Motion
  radar** (the Doppler front end on the root). Imaging keeps letter **I**.
- **Snooker ball tracking is the I + M demo.** Overhead OV9281 (640×400, 200 fps)
  gives per-ball centroids, IRIG-stamped, over N; 24 GHz Doppler gives cue-ball
  departure speed. Gate: gap-free track at 200 fps (I); radar speed within 5 % of
  the camera speed, timestamps aligned (M). The snow village / Sleigh Glide sits on
  the same 5×10 ft table — a known-trajectory calibration target.
- **Build rule:** root first — **O → P → T** (T is the regression gate) — then any
  spoke as its hardware arrives. Funding sets timing, not dependency.
- **Every directory has a `DESIGN.md` in one shape** (plan summary · spoke/root
  framing · signal path · registers/Forth · verification gates · out of scope):
  Panel, Oracle, Erand49, Theremin (in its sub-repo), IRIG, Coil, GPS, SDR, UHF,
  Network, Imaging. `MAIDEN/…` paths inside them mean "archive", not a dependency.

- **One FPGA board — the ULX3S — is the only FPGA in PM** (later on 09-15). The sleigh
  Glide's FSM moves into the box (`PM.Sleigh`, Rev D), gates over a 10-wire ribbon
  to the driver board at the tube; the Alchitry Cu is retired to bench spare. The
  harp gets no board of its own: 13 ADCs daisy-chain over the EtherCON link.
- **Sleigh project renamed "Sleigh Glide"** (`Coil/SleighGlide/`, `SleighGlide.hs`,
  `sleigh_glide.pcf`; the slug is "the sleigh"). Git history was rewritten with
  `filter-branch` and **force-pushed** so no commit message carries the old name;
  reflog expired and gc'd locally. Any other clone must `git fetch && git reset --hard
  origin/main`.
- **Purchases:** ULX3S 85F backordered at Mouser for the 2026-10-02 batch
  (`Oracle/ORDERS.md`); printer recommendation Bambu Lab P1S (`Panel/ORDERS.md`);
  master tracker `ORDERS.md` with the P/W/H ledger split; `STATUS.md` is the one-page
  state, updated each session.

## Doc changes this session (all committed on `main`, nothing pushed)
PROGRAM.md (rewritten) · CLASH-LIBRARY-MAP.md (new: map, module list, status) ·
STATUS.md (new) · ORDERS.md (new) + Oracle/Panel/Erand49 ORDERS.md · PLAN.md ·
fpga-development-plan.md · fpga-resource-swag.md · LIBRARY.md · one-box-overview.html
· LAYOUT.html · README.html/gen.py · vl1-clash-module-tree.md · fpga-pert-cpm.md ·
a DESIGN.md in every root/spoke directory · Coil/DESIGN.md rewritten for Rev D.
Repo unified (MAIDEN/, Theremin/ absorbed) and pushed to
github.com/jclements3/poetic-musings; history rewritten for the rename.

## Open items
- ~~No git remote~~ — pushed to github.com/jclements3/poetic-musings (public); the old
  standalone theremin and MAIDEN repos are stale copies to archive.
- Migrate the measured Clash blocks out of `MAIDEN/…` into a top-level `lib/` so the
  archive can eventually go; `Oracle/pm-*` packages are the interim home.
- Move `Oracle/pm-keyer` under `UHF/` when cabal paths are next touched.
- Write `PM.Sleigh` (bus-side port of `SleighGlide.hs`, 0x4050 group) — first new
  block needed when the board lands; wind coils and build the driver channels before.
- M and S register groups are unassigned until their phase starts (0x4060 Imaging is
  provisional).
- Panel silk still VL-1-flavoured; mode-neutral layer decision in `Panel/DESIGN.md`.
- fpga-venn diagrams and `vl1-clash-module-tree.md` still count modules by the old
  three-way split; regenerate when the `lib/` migration lands.

---

# 2026-08-29 mobile session (historical — letters, panel, PERT)

## Decisions
- Program name: POETIC (personal) + MUSING (work ledger). Six letters each.
  - POETIC: Panel (VL-49 surface) · Oracle console (Forth H2, bar TFT, SD, CW keyer/decoder) · Erand49 harp · Theremin · IRIG clock · Coil launcher/catcher
  - MUSING: MAIDEN (incl. unit integration, solver) · UHF beacon (GPS-disciplined CW/WSPR, personal ledger, ham) · SDR (direct-sampling HF on theremin antennas, AD9226-class ADC) · Imaging (camera capture, timestamp, centroid) · Network (RMII/MAC/UDP/Ch.10) · GPS (station clock copies)
- ~~Serial build rule, finish before start: C → I → O → T → P → E~~ Superseded 2026-09-15: root first O → P → T, then spokes as hardware arrives.
- Panel box is the platform demo (One Box). Not a MAIDEN dependency.
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
- ~~Update overview/plan to POETIC + MUSING letters and C-first order.~~ Done 2026-08-31; restructured again 2026-09-15 (see above).
- Add antennas + THEREMIN/SDR mode to panel drawing when P starts.
- Imaging weak points: global-shutter sensor, external trigger, FOV/range study — put in Sep Basic Plan. *(2026-09-15: target fixed as the snooker table; numbers in `Imaging/DESIGN.md`.)*
- Metrology reference for I: used GS-101B or Thunderbolt-class GPSDO.
