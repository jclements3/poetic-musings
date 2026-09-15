# Erand49 — orders (2026-09-15)

Staged per the PLAN standing rule **buy late**: 1 ADC eval before 13 · 5 IR pairs
before 98 · rib only after the micrometer bore check · strings last. Design facts:
`DESIGN.md` (gateware, gates), `frame-spec.md` (members), `string-specs.md` (band),
`sensor-stations.csv` (49 stations, 3.2 mm bores, 60° pair, per-station yaw).
Ledger: personal (P). Program estimate ~$1,200 (fpga-development-plan.md row 6).

## Stage 0 — before anything (P start)

| Item | Qty | Spec / note | Est. |
|---|---|---|---|
| Micrometer / bore gauge, 3–13 mm | 1 | the **bore check** that gates the rib order (PERT rule) | ~$40 |
| 3D-printed sensor-mount and cap coupons | — | on the Panel printer (`../Panel/ORDERS.md`) | filament |

## Stage 1 — Gate 1 kit (one string, ~$150)

| Item | Qty | Spec / note | Est. |
|---|---|---|---|
| **ADS131M08 evaluation module** (TI ADS131M08EVM) | 1 | 8-ch 24-bit simultaneous-sampling SPI ADC — the production part, so gate-1 firmware carries over | ~$100 |
| IR emitter/photodiode pairs, 3 mm, 940 nm | 5 pairs (+5 spare) | e.g. Vishay TSAL4400 / BPV10NF or TSSP-class pairs; 3.2 mm bore fit | ~$10 |
| Bench string + tuner | 1 | one mid-band string (c4-class, `string-specs.md` row ~24) on a scrap-wood jig with one axle-tube tuner | ~$15 |
| Transimpedance front end, proto | 2 ch | opamp (OPA2380-class), 1 MΩ feedback, 100 nF; PCB later | ~$10 |
| Cable to the box HARP port | 1 | EtherCON RJ45 + 3 Mbaud link + 5 V (LAYOUT rear panel) | ~$15 |

**Pass gate 1 (`DESIGN.md` §Verification 2) before Stage 2.**

## Stage 2 — full instrument (~$1,000)

| Item | Qty | Spec / note | Est. |
|---|---|---|---|
| ADS131M08 (IC) | 13 (+1) | 104 channels for 98 photodiodes | ~$130 |
| Carrier PCB, 4-layer | 2 | 13 ADCs + TIAs + SPI fan-out, fits inside the open midrib channel | ~$80 |
| IR pairs, 3 mm | 98 (+10) | same part as gate 1 | ~$60 |
| **Harp-side FPGA board** | 1 | see *Open item* below | TBD |
| Frame stock, 6061-T6: C-channel 2.5 × 4 × 3/16 in ×1.9 m · round tube 2 in OD × 3/16 ×2.1 m · flat bar 1 × 1/8 in ×1.2 m · plate for two neck plates | — | per `frame-spec.md`; order after the bore check | ~$250 |
| Axle-tube tuners (ER-008) | 49 | Ø12 × 2 mm 6061 tube, M6 × 0.75 lead screw, slider nut, steel nut insert, press cap; 3 mm ball-end T-handle | ~$120 |
| Shoulder bolts, crush sleeves, M8 hardware, wing bolts | — | ER-005 / ER-006 / ER-007 | ~$30 |
| Welding | — | one welded joint (ER-004) + neck seams; local shop or TIG time | ~$100 |
| **Strings** | 49 (+7) | Erard band per `string-specs.md`: nylon g7–~c4, wound bass to a0 | ~$200 |
| Rigid column travel case | 1 | strings stay tensioned (LAYOUT travel table) | ~$80 |

## Open item — the harp-side board vs the "two boards only" rule

`DESIGN.md` puts detection + KS on a board **in the harp** (98 analog channels never
leave the frame), but PLAN's standing rule is *two boards only* (ULX3S in the box, Cu
in Santa Glide). Decide at Stage 2, not before:

- **A — third board in the harp** (ULX3S-12F or an ECP5 PMOD-class board, ~$60–100):
  cleanest signal integrity; amends the rule to "two boards *in the box demo*".
- **B — no harp FPGA:** 13 ADCs daisy-chained over one SPI/LVDS run through the
  EtherCON cable to the box; the box does detection + KS. Keeps the rule; ~1.5 m of
  SPI at the ADC clock needs LVDS repeaters and eats box GPIO.

Recommendation: A, decided when gate 1 shows the real cable length and noise floor.
