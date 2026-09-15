# Panel — orders (2026-09-15)

Quality BOM (switches, diodes, pots) is in `DESIGN.md`; this file is the **tooling**
order the panel depends on and the print-consumables line.

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
