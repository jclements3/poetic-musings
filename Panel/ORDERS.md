# Panel — orders (2026-09-15)

Quality BOM (switches, diodes, pots) is in `DESIGN.md`; this file is the **tooling**
order the panel depends on, the print-consumables line, and where to buy. The brain
board is in `../Oracle/ORDERS.md` (ULX3S 85F, backordered for the 2026-10-02 batch).

## Timing

Panel is Phase 5 (after O and T), but nothing here waits for the board:

1. **Now:** order the printer and one spool; print the 3 × 2-key coupon and a cap set
   as soon as it arrives (§ Fabrication step 6 in `DESIGN.md`).
2. **With the coupon passing:** order the 70 switches, 70 diodes and 7 pots — the
   plate segments print while they ship.
3. **When the ULX3S lands (Oct):** the matrix ribbon and slider board go on the bench
   against it, case still unprinted (Phase 5 gates are electrical).
4. **Case last** (PERT rule), TFT + HDMI driver as a matched kit (`../Oracle/ORDERS.md`).

## 3D printer — recommendation

The panel face is 504 × 150 mm, printed in PETG or ASA as a segmented plate
(`DESIGN.md` § Fabrication). Requirements, in priority order:

1. **Enclosed** — ASA needs it; PETG benefits (fewer warped key wells).
2. **Bed ≥ 250 mm in X** so three segments cover 504 mm with margin.
3. **Reliable first-layer / textured plate** — the panel prints face down.
4. **Multi-colour is optional** (cap legends can be done by filament swap).

| Option | Bed (mm) | Segments | Enclosed | Approx. | Verdict |
|---|---|---|---|---|---|
| **Bambu Lab P1S** | 256 × 256 × 256 | 3 | yes | ~$550–600 (P1S Combo w/ AMS ~$800) | **Recommended.** Fast, enclosed, textured PEI plate, ASA-capable, big community of MX-keyboard prints. AMS optional for two-colour caps. |
| Bambu Lab X1C | 256 × 256 × 256 | 3 | yes | ~$1,100 | Same footprint as P1S with lidar/first-layer inspection; not worth the delta for this panel. |
| Prusa MK4S + enclosure | 250 × 210 × 220 | 3 | with kit | ~$1,000 | Excellent, but the enclosure is extra and Y is 210 mm — fine for the 150 mm panel, tight for the case wedge. |
| Prusa XL (1 head) | 360 × 360 × 360 | **2** | optional | ~$2,000+ | Two segments and the case in one go; only if a bigger printer is wanted anyway. |
| Creality K2 Plus / K1 Max | 350 × 350 × 350 | **2** | yes | ~$900–1,300 | Two-segment option at a lower price; less consistent than Prusa/Bambu. |

**Order: Bambu Lab P1S** (add the AMS Combo only if two-colour cap legends are
wanted). Three segments of ~168 mm each fit the 256 mm bed with the joint tongues.

## Where to buy

| Item | Link | Note |
|---|---|---|
| **Bambu Lab P1S** | https://us.store.bambulab.com/products/p1s | direct is cheapest; P1S Combo adds the AMS. Micro Center stocks it in-store if one is near. |
| ASA / PETG filament | https://us.store.bambulab.com/collections/asa · https://us.store.bambulab.com/collections/petg | any name brand works (Polymaker, Prusament); Bambu spools are RFID-recognised by the AMS |
| Cherry MX2A Silent Red, 70 | https://www.mouser.com/c/?q=MX2A%20silent%20red · https://www.digikey.com/en/products/filter/keyboard-switches/ (search MX2A) | authorized channel only — no clone packs (`DESIGN.md` reliability rule) |
| 1N4148, 70 | https://www.mouser.com/c/?q=1N4148 | onsemi or Vishay |
| Bourns PTA4543-2015CPB103, 7 + knobs | https://www.mouser.com/c/?q=PTA4543-2015CPB103 | 45 mm travel, 10 k linear |
| M3 heat-set inserts, dowels, 20 × 3 mm aluminium bar, 14 mm reamer | McMaster-Carr (https://www.mcmaster.com) | one order, next-day in the US |

## Consumables

| Item | Qty | Note |
|---|---|---|
| ASA filament, 1 kg (or PETG if printing open) | 2 spools | panel ≈ 350 g, caps/knobs ≈ 120 g, case ≈ 800 g |
| Textured PEI plate | 1 | if not supplied |
| M3 heat-set inserts + M3 × 6 screws | 30 | segment splices, board standoffs |
| 20 × 3 mm aluminium flat bar | 300 mm | two splice bars per joint |
| 3 mm dowel pins | 8 | segment alignment |
| 14 mm reamer or square file | 1 | switch cutouts to size |

Ledger: personal (P). Printer is shared tooling — Erand49 caps, Santa Glide village
parts and the Coil driver-board case print on it too.
