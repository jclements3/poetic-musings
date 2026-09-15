# ORDERS — master purchase tracker and ledger split

One row per purchase decision across the program. Detail, links and timing live in
the per-directory files: `Oracle/ORDERS.md` · `Panel/ORDERS.md` · `Erand49/ORDERS.md`;
Santa Glide's receipts are screenshots in `Coil/SantaGlide/orders/`. Update the
**Status** column here when something is ordered or arrives; keep receipts, amounts
paid and reimbursement paperwork **out of this public repo** (`LEDGER.md` and
`receipts/` are git-ignored by rule).

Status: `plan` → `backorder` → `ordered` → `received` → `installed`. Ledger: **P**
personal · **W** work · **H** ham (personal). Estimates are budget figures, not prices paid.

## Root

| # | Item | Letter | Ledger | Est. | Status | Trigger / note |
|---|---|---|---|---|---|---|
| R1 | ULX3S ECP5-85F v3.1.x (Mouser CS-ULX3S-03) | O | P | $150–200 | **backorder** — batch 2026-10-02 | earlier order cancelled; do not downgrade |
| R2 | 8.8" 1920×480 bar TFT + HDMI driver, matched kit | O/P | P | $60 | plan | verify active area before cutting the band |
| R3 | microSD ×2, 5 V supply / USB bank, ribbons, PMOD breakouts | O | P | $55 | plan | with the board |
| R4 | Bambu Lab P1S (+AMS optional) | P | P | $550–800 | plan — **order now** | shared tooling: harp caps, village parts, driver case |
| R5 | ASA/PETG filament ×2, PEI plate, inserts, dowels, 20×3 bar, 14 mm reamer | P | P | ~$90 | plan | with the printer |
| R6 | Cherry MX2A Silent Red ×70, 1N4148 ×70 | P | P | ~$75 | plan | after the print coupon passes |
| R7 | Bourns PTA4543-2015CPB103 ×7 + knobs | P | P | ~$25 | plan | with R6 |

## POETIC spokes

| # | Item | Letter | Ledger | Est. | Status | Trigger / note |
|---|---|---|---|---|---|---|
| E0 | Bore gauge 3–13 mm | E | P | $40 | plan — now | gates the rib order |
| E1 | Gate-1 kit: ADS131M08EVM, 10 IR pairs, bench string + tuner, TIA proto, EtherCON cable | E | P | ~$150 | plan | when R1 lands |
| E2 | Frame stock 6061 (channel, tube, bar, plate) + rib | E | P | ~$250 | plan | at P start, after E0 |
| E3 | 13× ADS131M08 + carrier PCB, 108 IR pairs, tuners ×49, hardware, welding | E | P | ~$520 | plan | only after gate 1 passes |
| E4 | Strings ×56 (Erard band), travel case | E | P | ~$280 | plan | last |
| E5 | Harp-side board (ULX3S 12F/25F) — *open item* | E | P | ~$100 | plan | decided after gate 1 |
| T1 | Theremin LC oscillator parts | T | P | $0 | **received** | ordered pre-program |
| I1 | IRIG-B: none (scope on hand) | I | P | $0 | — | GPSDO reference comes under G |
| C1 | Santa Glide: Cu, coils, MOSFETs, diodes, tube, buttons, bench supply | C | P | sunk | **received** | `Coil/SantaGlide/orders/` |
| C2 | Still to buy: AAs, 8–10 mm ID rigid coil-form tube | C | P | ~$20 | plan | HANDOFF 08-29 |

## MUSING spokes

| # | Item | Letter | Ledger | Est. | Status | Trigger / note |
|---|---|---|---|---|---|---|
| M1 | CDM324-class 24 GHz Doppler module + SPI ADC | M | W | ~$60 | plan | after G |
| U1 | Whip + SMA bulkhead, PA can, 20 m filter | U | H | TBD | plan | after G |
| S1 | AD9226-class ADC board + antenna relay, JFET buffer | S | W | ~$30 | plan | after T |
| I2 | OV9281 global-shutter module + lens + overhead clamp mount | Imaging | W | TBD (study) | plan | after Sep FOV study, N, G |
| N1 | RMII PHY PMOD | N | W | ~$25 | plan | after O |
| G1 | u-blox module with PPS | G | W | ~$30 | plan | after O |
| G2 | GPSDO metrology reference (used GS-101B / Thunderbolt-class) | G | W | ~$100–150 | plan | verification only |

## Totals (estimates)

| Ledger | Planned | Notes |
|---|---|---|
| P personal | ~$2,600 | of which harp ~$1,340, printer ~$550–800, board + display ~$260 |
| W work | ~$300 + camera/lens | spoke hardware only; work never buys the box |
| H ham | TBD | UHF PA and antenna |

Rules carried from PLAN.md: buy late (1 eval before 13, 5 pairs before 98, rib after
the bore check, case last, TFT as a matched kit); ledgers never commingle.
