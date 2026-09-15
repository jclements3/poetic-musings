# Erand49 — orders (2026-09-15)

Staged per the PLAN standing rule **buy late**: 1 ADC eval before 13 · 5 IR pairs
before 98 · rib only after the micrometer bore check · strings last. Design facts:
`DESIGN.md` (gateware, gates), `frame-spec.md` (members), `string-specs.md` (band),
`sensor-stations.csv` (49 stations, 3.2 mm bores, 60° pair, per-station yaw).
Ledger: personal (P). Program estimate ~$1,200 (fpga-development-plan.md row 6).
Brain board: `../Oracle/ORDERS.md` (ULX3S 85F, backordered for the 2026-10-02 batch);
printer for caps, sensor mounts and jigs: `../Panel/ORDERS.md`.

## Timing

E is Phase 6 (after P and O), and the rib is the long-lead item, so:

1. **Now:** the bore gauge (Stage 0) — cheap, and it gates the rib.
2. **When the ULX3S lands (Oct):** Stage 1 kit; gate 1 runs on the bench against the
   box with the eval module on a PMOD header — no harp frame needed.
3. **At P start, after the bore check:** order the frame stock and rib (PERT rule) so
   welding overlaps the Panel build.
4. **Only after gate 1 passes:** Stage 2 electronics (13 ADCs, 98 pairs, carrier PCB)
   (LVDS repeaters for the ADC daisy-chain included).
5. **Strings last**, once the frame is welded and the tuners are in.

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

## Where to buy

| Item | Link | Note |
|---|---|---|
| ADS131M08EVM | https://www.ti.com/tool/ADS131M08EVM · https://www.mouser.com/c/?q=ADS131M08EVM | TI direct is usually cheapest; the ADS131M08 ICs for Stage 2 from the same sources |
| IR pairs, 3 mm 940 nm (TSAL4400 + BPV10NF or equivalent) | https://www.mouser.com/c/?q=TSAL4400 · https://www.mouser.com/c/?q=BPV10NF | Vishay; buy 108 for Stage 2 (98 + spares) |
| OPA2380-class TIA opamps | https://www.mouser.com/c/?q=OPA2380 | 2 for Stage 1, ~50 for the carrier |
| 6061-T6 channel, tube, flat bar, plate | https://www.onlinemetals.com · https://www.mcmaster.com | per `frame-spec.md` sections; cut lengths to the CAD |
| Ø12 × 2 mm 6061 tube, M6 × 0.75 lead screw stock, slider nuts | https://www.mcmaster.com | ER-008 tuners, 49 + spares |
| Shoulder bolts, crush sleeves, M8 hardware, heat-set inserts | https://www.mcmaster.com | ER-005/006/007 |
| Harp strings (Erard band) | https://www.harpsetc.com · https://www.vermontharps.com | order by the `string-specs.md` table (nylon treble, wound bass); ask for a pedal-harp gauge set A0–G7 |
| EtherCON RJ45 + cable | https://www.mouser.com/c/?q=NE8FDP | Neutrik; matches the rear HARP port |
| Rigid column case | — | golf travel case or hard tube case, sized to the frame CAD |

## Decided — no harp-side board (one FPGA rule, 2026-09-15)

The 13 ADCs daisy-chain over SPI with LVDS repeaters through the EtherCON cable; the
box does detection + KS. Gate 1 runs the eval module on the real cable length to
measure the noise floor. Add to Stage 2: LVDS driver/receiver pair (SN65LVDS31/32-
class) ×2, ~$10.
