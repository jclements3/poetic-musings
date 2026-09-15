# PERT/CPM — personal FPGA program (C → I → O → T → P → E)

Updated 2026-08-31 to the POETIC lettering and current decisions (Santa Glide is C;
O absorbs old F+D; E is the harp with the welded frame; keys are MX2A switches, not
a keybed). Unit: weekends; expected = (o + 4m + p)/6. Policy stays serial, so the
critical path is the chain by construction; CPM is for spotting where purchases can
hide lead times.

Phase 0 (toolchain, both firmwares compiling, eForth image booting in the C
simulator) completed 2026-08-31 at ~zero weekend cost — done on desktop time.

## Task network

```
C1 ch0 bench ─► C2 8 drivers + wind coils ─► C3 tube, slug, dwell tune
                                                     │
I1 IRIG-B gen on ULX3S ─► I2 scope/decoder verify    │  (I needs no C output; serial rule only)
        │
        └─► O1 eForth ok on USB serial ─► O2 GPDI text on TFT ─► O3 SD blocks ─► O4 GPIO/ADC words ─► O5 keyer/decoder
                                                                                        │
T1 oscillator hw ─► T2 antenna cal (existing bitstream)  ◄──────────────────────────────┘
        │
        ▼
P1 switch matrix (59× MX2A + diodes) ─► P2 voice engine ─► P3 sequencer/rhythm ─► P4 overlay + block re-measure ─► P5 theremin voice ─► P6 case
                                                                                                            │
        E2 synthetic-string tests ◄── run inside P after P2 (pure HDL)                                      │
        E3 KS from keys           ◄── run inside P after P2                                                 ▼
                       E1 one string + one ADC ─► E0 frame fab (weld, plates, stations) ─► E4 rib + strings ─► E5 98 sensors ─► E6 integrate
```

## Durations and float

| Task | o / m / p | E | Float | Notes |
|---|---|---|---|---|
| C1 | 1/1/2 | 1.2 | 0 | channel 0 at 12 V/CC, slug snap test |
| C2 | 1/2/3 | 2.0 | 0 | 7 more drivers; wind 8× 200T coils |
| C3 | 1/2/4 | 2.2 | 0 | tube mount, dwell-table tuning |
| I1 | 1/1/2 | 1.2 | 0 | IRIG-B frames, free-running |
| I2 | 1/1/1 | 1.0 | 0 | scope/decoder check |
| O1 | 1/1/2 | 1.2 | 0 | Clash sim boot already in progress on desktop |
| O2 | 2/2/4 | 2.3 | 0 | 1920×480 TMDS timing closure |
| O3 | 1/1/2 | 1.2 | 0 | |
| O4 | 1/1/1 | 1.0 | 0 | |
| O5 | 1/1/2 | 1.2 | 0 | keyer/decoder peripheral |
| T1 | 1/1/2 | 1.2 | 0 | parts ordered |
| T2 | 1/2/3 | 2.0 | 0 | existing bitstream, cal only |
| P1 | 1/2/3 | 2.0 | 0 | 59 switches + 1N4148 matrix soldering |
| P2 | 2/2/4 | 2.3 | 0 | |
| P3 | 1/2/3 | 2.0 | 0 | |
| P4 | 1/1/2 | 1.2 | 0 | |
| P5 | 1/1/2 | 1.2 | 0 | |
| P6 | 2/2/4 | 2.3 | 0 | case; last, R6 |
| E2 | 1/1/1 | 1.0 | 2–5 | inside P after P2 |
| E3 | 1/1/2 | 1.2 | 2–5 | inside P after P2 |
| E1 | 1/2/3 | 2.0 | 0 | one ADC eval, one string, sensor-point A/B (R11) |
| E0 | 2/3/5 | 3.2 | 0 | midrib/pillar weld, plates, legs — per frame.step/ER-001..006 |
| E4 | 3/4/6 | 4.2 | 0 | rib CNC + strings, lead-time driven, R5 |
| E5 | 2/3/5 | 3.2 | 0 | station PCBs per sensor-stations.csv |
| E6 | 2/2/4 | 2.3 | 0 | |

Expected chain: C 5.4 + I 2.2 + O 6.9 + T 3.2 + P 11.0 + E 14.9 ≈ **44 weekends**
(~11 months of weekends); σ ≈ 3.5, 90% ≈ 48. The growth from the old 31 is scope,
not slippage: Santa Glide bring-up, IRIG, the keyer, and the harp frame are now real
tasks instead of asterisks.

## Exposures

**R1 — retired.** C4 (FPGA pulse timing before Forth) was cut; Santa Glide's Rev B is
open-loop by design and already compiles to Verilog.

**R2 — O2 before O1 is a false gate.** If the TFT arrives before eForth talks over USB
serial, resist debugging both at once. Hold O2 until O1 prints `ok`.

**R3 — Bad purchase: clone key switches.** The decision is Cherry MX2A Silent Red from
an authorized distributor (Mouser/DigiKey). Marketplace "Cherry" lots are the
counterfeit risk; clone packs have the sticking/inconsistency this build exists to avoid.

**R4 — Bad purchase: 13 ADCs and a carrier PCB before E1.** One ADS131M08 eval and
5 IR pairs first; the 13-chip carrier and the other 93 pairs only after one string passes.

**R5 — E4 lead time is the real critical path in E.** Rib CNC and strings are vendor
weeks. Place the rib order at the *start* of P (after micrometer bore check). A purchase,
not work — doesn't violate serial. Hides ~4 weeks.

**R6 — Case before panel verification is rework.** Don't cut the 55 mm display band
until the TFT active area is measured. P6 stays last.

**R7 — Bar TFT + driver mismatch.** Matched kit with 1920×480 EDID (link below).

**R8 — Purchases with no consumer yet.** UP5K spares, RMII PHY, GPS module, GPSDO:
work-ledger parts; they have no consumer until G/N/M. Leave them. (The Alchitry Cu is
bought and spoken for — it *is* Santa Glide.)

**R9 — Wasted effort: a second theremin bitstream.** T2 uses the existing ECP5 port
unchanged; it gets refactored onto the register bus once, in P5.

**R10 — Wasted effort: harp DSP without hardware.** E2/E3 are pure-HDL and run inside
P after P2, making E1 a hardware-only gate.

**R11 — Sensor PCBs before Gate 1.** `sensor-stations.csv` is a design input, not an
order form. E1's one-string rig carries a slide-adjustable sensor mount; the optical
fraction (currently the DXF's 0.056·L) is confirmed on the bench before any 49-station
PCB is fabbed.

## Purchase timing

| Buy | When | Why |
|---|---|---|
| AAs, coil form tube | now | C1 |
| Bar TFT + HDMI driver kit — VSDISPLAY HSD088IPW1-A00 + VS-HSD088 controller, https://www.amazon.com/dp/B09C31P7FV | during I | arrives for O2 |
| 70× Cherry MX2A Silent Red, 70× 1N4148 (onsemi/Vishay), 7× Bourns PTA4543 + knobs | during O | arrives for P1 |
| Frame metal: RT 4"×2.5"×3/16" + Ø2"×3/16" 6061 tube + plate stock | during P | arrives for E0 |
| 1× ADS131M08 eval, 5× IR pairs | during P | arrives for E1 |
| CNC rib order (post-micrometer) | start of P | 4-week lead hidden |
| String set (per string-specs.md, 49 rows) | after E1 | bores confirmed on one string |
| 13× ADC + carrier PCB, 93 IR pairs, station PCBs | after E1 passes | only then known-good |

## Net effect

The old plan's savings (C4 cut, E2/E3 inside P, rib lead hidden) are all retained.
The chain is honest at ~44 weekends because the scope is now the whole instrument —
frame, stations, keyer, clock — with every at-risk purchase still gated behind a
one-unit proof.
