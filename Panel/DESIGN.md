# Panel — Phase 5 design (the control surface takes physical form)

Role (clarified 2026-09-15): the Panel is the **control surface** for the Clash library —
keys, sliders, buttons and display are generic inputs and a scope for every mode. The
Casio VL-1 was the visual inspiration for the flat-key look; VL-1 synthesis is one mode
among six, not the goal, and VL-1 A/B accuracy is no longer a gate.

**Root framing (`../PROGRAM.md`):** Panel is not a spoke. With Oracle it *is* the root:
Panel is the body, Oracle the brains. Every spoke plugs its special hardware into
this body — the theremin and UHF antenna studs on the end plates, the AD9226 board and
antenna relay at the rear, the GPS and PA can rear-right, the RMII PHY, the harp and
sleigh link connectors, and the strobe/trigger lines to the snooker camera — and every
spoke shows its output on V0 and takes its knobs from S0–S4 and the keys. The library
components Panel itself exercises: `PM.Matrix`, `PM.Zones`, `PM.RegFile`, `PM.Spi`
(slider ADC), the `PM.Synth`/`PM.Audio` set in VL-1 synth mode, and the `pm-video`
console. The six S3 zones are P·O·E·T·I·C; the MUSING spokes (M, U, S, I, N, G) are
entered from the O-mode script menu (`../LAYOUT.html` mode table), so the slider
never needs more than six detents. In `../CLASH-LIBRARY-MAP.md` § Module list, P
contributes the ✓ matrix scanner, slider zone decoder, register file, ΣΔ DAC, mixer,
note table, pulse oscillator and ADSSR, and owns the ○ Audio entries — LFOs, rhythm
ROM + percussion, event sequencer — and the ○ overlay framebuffer (Control and
display). Fabrication and the printer order: § Fabrication below and `ORDERS.md`.

Phase 5 of PLAN.md: build the 3D-printed 49-key panel and case, mount the display and
sliders, wire the matrix, and bring the control surface up against Oracle so every
library block has a key, a slider and a screen. This doc consolidates the decisions scattered across PLAN.md,
fpga-development-plan.md (Panel quality BOM), LAYOUT.html, README.html/gen.py,
HANDOFF.md and Oracle/eforth-pm.md — **Phase 5 should start from this file alone.**
Prereqs O and T. Physical reference: `vl1-reference-photo.png` in this directory
(the real 1981 Casio VL-1 the flat-key look is derived from — visual reference only).

First act of Phase 5 (before any printing): **micrometer bore check, then order the
harp rib** — E's long-lead item rides on P's start (PERT rule).

## Panel — per README.html (regenerate with gen.py)

`../README.html` is the panel map; `../gen.py` regenerates it and
`vl1-49key-panel-layout.png` (cairosvg; note PROGRAM.md's
`LD_LIBRARY_PATH=$HOME/miniconda3/lib` toolchain caveat). Face ≈ **504 × 150 mm**:

- **Keys A0–G7**: 49 keys C2–C6 (29 white + 20 black), flat button caps set in a
  printed keyboard graphic, as on the VL-1. Key ID = gold pedal-harp string label
  (A0–G7). Two-layer ASCII legends: base on the cap, SHIFT above (SHIFT = held
  One Key Play L / P8); DEL = backspace — the keybed doubles as Oracle's keyboard.
- **Buttons P0–P9**: P0 RESET (re-inits current mode, trapped in Forth — not a CPU
  reset) … P7, plus double-size P8/P9 One Key Play as on the VL-1.
- **Sliders S0–S4** (top right): S0 volume, S1 rhythm/melody balance (continuous);
  S2 octave LOW·MID·HIGH, S3 MODE **P·O·E·T·I·C**, S4 OFF·CAL·PLAY·REC (zoned).
- **V0**: 8.8" 1920×480 bar TFT + HDMI driver, bought as a matched kit; **verify the
  active area against the datasheet before cutting** the 55 mm display band.

## Keys and matrix

- **Cherry MX2A Silent Red** switches (decided 2026-08-31), 59 used (49 + P0–P9) on
  identical **14×14 mm plate cutouts, 16 mm pitch** (MX housing limit; chosen over
  13 mm mini pitch). Soldered, **no hot-swap sockets** — a socket is one more contact
  to fail mid-demo; spares live in the lid pocket and any spare fits any position.
- **8×8 matrix, one 1N4148 per switch** (full N-key rollover): 59 switches fold into
  one scan, one 16-wire ribbon (8 rows + 8 cols) to ULX3S GPIO — the only front-back
  crossing besides the speaker pair (LAYOUT plan view).
- Gateware scans free-running with **10 ms debounce** (Sleigh Glide's value), tolerant
  of slow release; Forth pops press/release *events* from the 0x4024 FIFO
  (eforth-pm.md) — it never scans rows. No velocity sensing — period-correct (the
  VL-1 had none); velocity expression is Erand49's job.

## Sliders and the mode selector

**Bourns PTA4543-2015CPB103** (45 mm travel, 10 k linear, Bourns knobs), 5 used in
identical 45 mm slots. S0/S1 read as raw ADC (0x4022); S2–S4 are digitized and
**zone-compared in gateware with hysteresis** — a slider parked on a boundary can
never flicker between modes during a demo. Forth reads clean zone numbers from
iPanel (0x4020), never raw counts. Mode changes additionally require a **1 s dwell**
(kernel dispatch loop, eforth-pm.md boot flow step 5): any further zone change
restarts the timer, banner on V0 during the handoff, teardown word (mute, tx-off,
seq stop) before `mode-go` — a bumped slider never yanks a demo. Silk: continuous
scale under S0/S1, printed detent zones under S2–S4.

## Quality BOM (copied from fpga-development-plan.md, decided 2026-08-31)

Reliability rule: authorized distributors and name brands only — no clone switch
packs, no generic pots. Nothing may stick or misbehave in front of the grandkids.
Uniformity rule: one switch type, one pot type, one cutout each; variation lives only
in printed caps, knobs, and silk.

| Part | Qty | Spec / brand | Source | Est. |
|---|---|---|---|---|
| Key switches | 70 (59 used + spares) | **Cherry MX2A Silent Red** (100M actuations, factory lube, quiet, authorized channel; Kailh BOX considered and passed over) | Mouser/DigiKey | ~$70 |
| Matrix diodes | 70 | 1N4148, onsemi or Vishay (name brand only) | Mouser | ~$5 |
| Slide pots S0–S4 | 7 (5 used + 2 spares) | Bourns PTA4543-2015CPB103, 45 mm travel, 10 k linear; Bourns knobs | Mouser/DigiKey | ~$25 |
| Panel + key caps + slider knobs | — | 3D-printed, **PETG or ASA (not PLA)** — PLA creeps under finger heat/pressure; a warped key well is a sticking key. 16 mm pitch, body ≈ 504 mm, 14×14 mm cutouts | own printer | filament |
| Solder, wire, misc | — | switches soldered, no hot-swap sockets; spares in the lid pocket | on hand | ~$5 |

Total ≈ **$130**. (one-box-overview.html still shows a stale "$150 membrane matrix"
row — the membrane keybed was superseded 2026-08-31 per HANDOFF.md.)

## Case

**PETG/ASA wedge** per LAYOUT board-layout notes: 504 × 150 mm footprint, **~40 mm
tall at the front edge, ~70 mm at the rear**. Inside (LAYOUT plan view): ULX3S 85F
center under the display band, USB/microSD facing rear cutouts; power board (OR-diode
+ 4 polyfuses) rear-left; battery bay (USB bank ≤150×70×25 mm, underside quarter-turn
door) left of the ULX3S so the weight centers; audio amp + underside speaker at the
loop end; oscillator boards at both antenna ends; UHF PA can and GPS at the rear-right.
All inter-board runs along the rear wall. Antenna studs in shallow counterbores so
packed ends are flush; rods/whip clip inside the lid. Case prints **last** (PERT rule)
— panel first, case once the boards are placed for real.

## Fabrication — how the panel gets made (added 2026-09-15)

The face is **504 × 150 mm**; no hobby bed prints that in one piece, so the panel is a
**segmented plate** on a printer chosen in `ORDERS.md` (recommended: 256 mm-class
enclosed CoreXY → three segments; a 350 mm-class bed → two). Order of work:

1. **Decide the silk** (next section) — it changes the top surface and the cap set.
2. **Geometry from the panel map, not by hand.** `../gen.py` owns every key, slider,
   button and display position. Add an export of the cut layer (SVG/DXF, 1:1 mm):
   59 × **14.0 × 14.0 mm** switch cutouts at **16 mm pitch**, five **45 mm** slider
   slots, the **55 mm** display band (verify the TFT active area against the
   datasheet before cutting), P0–P9 button wells, antenna-stud counterbores at the
   ends. Extrude in CAD: 3 mm plate, 2 mm perimeter lip, 1.5 mm ribs under the key
   rows so a 500 mm span does not oil-can.
3. **Segment on key-pitch boundaries.** Joints fall *between* switch cutouts, never
   through one; each segment carries whole hardware groups (the slider board and the
   display band each stay inside one segment; the 8×8 ribbon exits from one segment).
   Three segments ≈ 168 mm each. Joint: printed tongue-and-groove along the seam +
   two alignment dowels + M3 heat-set inserts underneath with a 20 × 3 mm aluminium
   splice bar across each joint (the splice is what makes three prints feel like one
   panel). Seam lands under a black key row where the silk can hide it.
4. **Material and settings.** **PETG or ASA, never PLA** (finger heat + clamp load
   creep a key well into a sticking key). ASA in an enclosure; PETG open is fine.
   0.4 mm nozzle, 0.2 mm layers, 5 perimeters, 40 % gyroid, print the plate **face
   down on a textured/smooth sheet** for the top finish. Cutouts modelled **0.2 mm
   undersize** and reamed to 14.0 mm so MX2A housings snap tight without rattle.
5. **Caps, knobs, overlays** as separate small jobs in the same material: 29 white +
   20 black key caps, P0–P9 caps (P8/P9 double width), 5 slider knobs (or Bourns
   knobs per the BOM), plus 10 % spares. Two-colour legends via a filament swap at
   the cap top layer, or engraved 0.4 mm and paint-filled.
6. **Coupon first.** Print one 3 × 2-key coupon with a slider slot in the chosen
   material: cap fit, switch snap, slot clearance, flatness after a night on the
   bench. Only then slice the segments (~6–8 h each).
7. **Assembly.** Press switches into the plate (no hot-swap sockets — soldered),
   one 1N4148 per switch, rows/columns, 16-wire ribbon to the ULX3S GPIO; slider
   pots in the slots; splice the segments; bring the plate up on the bench against
   the ULX3S **before the case exists** — every Phase 5 gate is electrical.
8. **Case last** (PERT rule): same segment split, PETG/ASA wedge 40 → 70 mm, once
   the boards are placed for real.

## Open design task — panel silk (decide before printing)

The panel IDs are already mode-neutral (A0–G7, S0–S4, P0–P9, ASCII layers) but the
decorative legends (voice names, rhythm names MARCH…BEGUINE, calculator keys) are
VL-1-specific, and VL-1 emulation is *one mode among many* (PROGRAM.md open item).

- **Option A — mode-neutral silk**: print only the neutral layer; every mode's
  legends live on V0. Cleanest object; loses the 1981 charm and makes P mode harder
  to drive eyes-up.
- **Option B — VL-1 overlays**: neutral base silk + snap-on printed overlay strips
  (rhythm row, button row, calculator digits) per mode. Authentic in P mode, honest
  everywhere else; overlays are one more thing to lose.

**Recommendation: B, minimally** — permanent silk carries the neutral layer plus the
few VL-1 legends that are functionally load-bearing in P mode (rhythm names under the
white keys, button captions), styled after `vl1-reference-photo.png`; everything else
(voice tables, spoke demo scripts, band plans) is V0's job, and a single snap-in strip above
the keys is the escape hatch if another mode ever needs its own printed legend. The
box *is* a VL-1 derivative — the silk may say so, as long as no mode *requires*
reading another mode's labels.

## VL-1 synth engine (gateware; Forth drives it via 0x402E)

Per the one-box-overview letters table and PLAN: **pulse-pattern oscillators** (the
VL-1's timbre trick), 5 voices + the programmable **ADSSR slot** (8-digit BCD patch
register — `90099914 patch!`), LFOs (vibrato/tremolo per patch digit), **rhythm ROM**
with the 10 patterns (MARCH · WALTZ · 4-BEAT · SWING · ROCK-1 · ROCK-2 · BOSSA ·
SAMBA · RHUMBA · BEGUINE) + percussion, **100-note sequencer** (notes stored to card
REC blocks), **One Key Play** (P8/P9), tempo, octave (S2), mixer with theremin-as-
voice-source select, and **calculator mode** (matrix digits → V0). Real-time synthesis
is entirely gateware; sequencing, patches, tempo state, and the calculator are Forth
(`PIANO` vocabulary: `voice! patch! rhythm! tempo! note-on/off seq-rec seq-play okp
calc` — eforth-pm.md §2). SWAG budget: ~4k LUT / 8 KB / 4 DSP, time-muxed.

## Phase 5 gate (fpga-development-plan.md row 5 + PLAN.md)

1. 59 switches deliver clean press/release events at 0x4024 (PM.Matrix); ASCII layer types into Forth.
2. S0/S1 read as ADC (PM.Spi); S2–S4 zones never flicker on a boundary; S3 mode change dwells 1 s and hands off with teardown (PM.Zones, PM.RegFile).
3. V0 shows the Forth console plus a live envelope/spectrum strip (pm-video + Fft tap).
4. Keys drive every PM.Synth / PM.Audio block — note table, pulse oscillator, ADSSR, mixer, ΣΔ DAC — and each is re-measured on ECP5 after integration.
5. Synth mode plays the VL-1 patches (`90099914 patch!`) and the sequencer; sound-alike is a nice-to-have, not a gate.
6. Antennas + theremin source select — theremin plays as a Panel voice.

**Demo: this is PM device v1** — a playable instrument/computer; every prior phase
runs inside one object. Write the per-mode demo-day cue card (what to say, what to
show, how to reset) as part of closing the phase.
