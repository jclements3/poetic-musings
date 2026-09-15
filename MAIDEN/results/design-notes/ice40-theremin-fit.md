# iCE40 fit check — theremin_top (27 Aug 2026)

Question: which candidate iCE40 boards can host the theremin build?
Method per BOM Note A: `yosys synth_ice40` + `nextpnr-ice40` on the laptop,
no hardware assumed. Same Clash-generated Verilog as the ECP5 flow
(`make pnr-ice40 ICE_DEV=... ICE_PKG=...`, new Makefile targets). ECP5
reference: 1,816 LUT4 / 452 FF / 2 DP16KD, Fmax 86.7 MHz.

## Remapping findings

- The two 512-deep DelayDiffFilter buffers remapped cleanly:
  **6x SB_RAM40_4K total (3 EBR each)** — exactly the 4Kbit slicing
  predicted. No ECP5-specific primitives were emitted or rejected;
  Clash's generated Verilog is architecture-neutral.
- iCE40 has no distributed RAM, so the IIR state banks and the
  quarter-wave sine ROM land in fabric (part of the LC growth vs ECP5:
  2,432 LC vs 1,816 LUT4).

## Measured results (48 MHz constraint)

| Board        | Device/pkg    | LC used/avail (%) | EBR   | Fmax (routed) | 48 MHz | Notes |
|--------------|---------------|-------------------|-------|---------------|--------|-------|
| Alchitry Cu V2 | HX8K/cb132  | 2,432/7,680 (31%) | 6/32  | 55.6 MHz      | PASS   | package confirmed available in nextpnr |
| HX8K breakout  | HX8K/ct256  | 2,432/7,680 (31%) | 6/32  | 56.8 MHz      | PASS   | already owned (BOM #8) |
| iCESugar       | UP5K/sg48   | 2,432/5,280 (46%) | 6/30  | 21.65 MHz     | FAIL   | passes cleanly at a 21 MHz constraint |
| iCEstick       | HX1K/tq144  | 2,432/1,280 (190%)| 6/16  | —             | FAIL   | does not place: control confirmed |

## UP5K resolution at its real clock

Period resolution scales 1/f_clk from 0.055 cent at 75 MHz:
at 21 MHz, resolution ≈ 0.055 x 75/21 = **0.20 cent** — still ~25x below
the ~5-cent audibility threshold. The UP5K hosts the theremin fine at a
21 MHz (or PLL'd 24 MHz-class) clock; it fails only the arbitrary 48 MHz
bar, not the instrument's requirement.

## Verdict

Any HX8K board hosts the theremin with 3x headroom and >55 MHz timing;
the UP5K works at a reduced clock with inaudible resolution cost; the
HX1K cannot fit it at all.

**Buy recommendation (revised 27 Aug): Alchitry Cu V2.** The HX8K
breakout listed as owned could not be located; if it stays lost, the
Alchitry Cu V2 is the measured replacement (HX8K/cb132: 31% LC, 6 EBR,
55.6 MHz PASS, onboard USB programming). The ULX3S order was canceled;
the MAIDEN-class ECP5 decision is deferred to maiden36.
