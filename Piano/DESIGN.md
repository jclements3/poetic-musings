# Piano — Phase 5 design (the PM device takes physical form)

Phase 5 of PLAN.md: build the 3D-printed 49-key panel and case, mount the display and
sliders, wire the matrix, and bring up the VL-1 synth engine with Oracle as the brains
behind the UI. This doc consolidates the decisions scattered across PLAN.md,
fpga-development-plan.md (Piano quality BOM), LAYOUT.html, README.html/gen.py,
HANDOFF.md and Oracle/eforth-pm.md — **Phase 5 should start from this file alone.**
Prereqs O and T. Physical reference: `vl1-reference-photo.png` in this directory
(the real 1981 Casio VL-1 the panel is derived from — the A/B target for the gate).

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
- Gateware scans free-running with **10 ms debounce** (Santa Glide's value), tolerant
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
(voice tables, IRAD scripts, band plans) is V0's job, and a single snap-in strip above
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

1. 49 keys scan (events clean at 0x4024, ASCII layer types into Forth).
2. `90099914 patch!` plays; voices and rhythms select from the panel.
3. Da Da Da on One Key Play; 100-note sequencer records and replays from card.
4. Calculator sub-mode works.
5. **A/B against the real VL-1** (`vl1-reference-photo.png` unit).
6. Antennas + theremin source select — theremin plays as a Piano voice.

**Demo: this is PM device v1** — a playable instrument/computer; every prior phase
runs inside one object. Write the per-mode demo-day cue card (what to say, what to
show, how to reset) as part of closing the phase.
