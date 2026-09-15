# Oracle — orders (2026-09-15)

The root's brain board and what plugs into it. Panel hardware (switches, pots,
printer) is in `../Panel/ORDERS.md`; spoke hardware in each spoke's file.
Ledger: personal (P).

## The FPGA board — ULX3S ECP5-85F

Designer: Radiona (radiona.org/ulx3s). Buy from Mouser (Radiona brand) or Crowd
Supply; Mouser is faster in the US. **Check stock on the 85F before ordering — the
earlier order was cancelled for lack of stock; wait rather than downgrade.**

| Option | Choice | Why |
|---|---|---|
| FPGA | **LFE5U-85F** (not 12F/25F/45F) | margined worst case ≈ 48k LUT / 285 KB / 55 DSP (`../fpga-resource-swag.md`); 85F is ~2.5× that. 45F is a gamble on LUT/BRAM. |
| Board revision | **v3.1.x** | GPDI (HDMI-compatible) for the 1920×480 TFT, 32 MB SDRAM, microSD, USB serial/JTAG, two 26-pin GPIO headers (56 I/O) |
| ESP32 module | leave off | not used by the plan |
| Price | ~$150–200 | one board runs every mode; a second is an optional spare |

What it covers without add-ons: Oracle (H2, UART, SD), the TFT over GPDI, Imaging's
frame store and Network's elastic buffer in SDRAM, and all spoke I/O through the
headers (16-wire matrix ribbon, slider ADC, RMII PHY PMOD, AD9226 board, camera DVP
ribbon, sleigh link, harp EtherCON breakout).

The Alchitry Cu already owned stays on Santa Glide (standalone); it is not a fallback
for the box — the HX8K has no video and 16 KB of BRAM.

## With the board

| Item | Qty | Note | Est. |
|---|---|---|---|
| 8.8" 1920×480 bar TFT + HDMI driver board, **matched kit** | 1 | verify the active area against the datasheet before cutting the 55 mm display band | ~$60 |
| microSD, 8–32 GB, name brand | 2 | one demo card + one known-good clone (LAYOUT travel table) | ~$15 |
| USB-C cable + 5 V / 3 A supply or USB power bank ≤150×70×25 mm | 1 + 1 | nothing above 5 V inside the box | ~$25 |
| 2× 26-pin IDC ribbon + PMOD breakouts | — | matrix ribbon, PHY PMOD, ADC boards | ~$15 |
| Level/protection: 3.3 V-only I/O — series resistors on every off-board line | — | LAYOUT rear-panel rule | ~$5 |

Toolchain is free: Yosys + nextpnr-ecp5 + Clash 1.8.5 / GHC 9.6.7 (already installed
for Phase 0); the same flow that built the Cu bitstream.
