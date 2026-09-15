# Snooker-mode fit on the ECP5-85F — 2026-09-15

Design: `Oracle/pm-top` (`PM.TopSnooker`), one copy of every Snooker-row block, four clock domains (25 MHz sys, ~66.7 MHz pixel, 333 MHz TMDS-bit, 50 MHz RMII), 21 in / 10 out ports (btn, ftdi UART, dvp, adc_d, pps, gate_in, sd, matrix, rmii; led, gpdi_dp, irig, sleigh_gate). Flow: store clash 1.8.5 (deps compiled from source, see notes) -> yosys 0.68 `synth_ecp5` -> nextpnr-ecp5 `--85k --package CABGA381 --freq 25`, LPF = clock pin + 4 FREQUENCY constraints. Artefacts: `Oracle/pm-top/logs/`, `Oracle/pm-top/verilog/`.
## Per-block yosys (each block synthesised standalone from its own topEntity; LUT4 / CCU2C / FF / DP16KD / MULT18X18D)

| Block | LUT4 | CCU2C | FF | BRAM | DSP | note |
|---|---|---|---|---|---|---|
| H2 core (`h2`) | 1076 | 46 | 47 | 0 (+32 DPR16X4 stacks) | 0 | program RAM = 2×8K×16 in the top (16 DP16KD) |
| RegFile (zones+matrix) | 1463 | 85 | 724 | 0 | 6 | constant multiplies inferred as DSP |
| UART (HarpLink tx+rx) | 538 | 30 | 194 | 0 | 1 | standalone includes the harp frame layer |
| Video console | 126 | 46 | 83 | 5 | 2 | overlay strip (4 BRAM) + 3 TMDS encoders only in the top |
| Net TX beacon / MAC RX | 408 / 267 | 18 / 30 | 113 / 139 | 0 | 0 | Records path + 2k CDC FIFO only in the top (~5 BRAM) |
| DVP capture | 47 | 20 | 36 | 0 | 0 | |
| **Blob labeller** | **34273** | 205 | 4001 | 1 | 0 | dominates: `Vec 32 Acc` register file + merge/scan/divide mux trees |
| DDC (NCO, 2×CIC r=512, 2×FIR15) | 2428 | 796 | 1678 | 0 | **18** | CIC 2/125/283 each; FIR 0/256/553/8 DSP each |
| FFT512 (R2SDF) | 2976 | 563 | 486 | 3 (+48 DPR16X4) | **34** | 4 real mults per stage, no sharing |
| CA-CFAR | 96 | 55 | 246 | 0 (+10 DPR16X4) | 2 | |
| IRIG-B | 370 | 55 | 117 | 0 | 5 | |
| PPS discipline | 240 | 173 | 156 | 0 | 0 | |
| StrobeLatch | 2712 | 14 | 1057 | 0 | 0 | 16×48-bit `Vec` FIFO in registers, not BRAM |
## Totals (flat top) vs SWAG

| | LUT (TRELLIS_COMB) | FF | BRAM | DSP |
|---|---|---|---|---|
| yosys flat top | 29 898 LUT4 + 2 346 CCU2C | 13 041 | 44 DP16KD = 99 KB | 61 |
| nextpnr utilisation | **36 192 / 83 640 (43%)** | 13 041 (15%) | 44 / 208 (21%) | **61 / 156 (39%)** |
| SWAG Snooker row | 21k | — | 95 KB | 15 |
| SWAG +50% margin | 48k | — | 285 KB | 55 |

LUT is 1.7× the row (inside the margined 48k); BRAM lands on the estimate; DSP is 4× the row and above the margined 55. The flat top is smaller than the sum of the standalone blocks (~46k LUT4) mainly because Blob's area-limit registers are 16-bit in the top (upper bits constant) — Blob is still the single largest consumer.
## nextpnr: timing (placement-stage; the router was cut at the 25-min cap with ~170 of 155 354 arcs left, so no routed Fmax or critical-path report)

clk_25mhz 19.91 MHz (FAIL at 25) · clk_pixel 57.6 MHz (FAIL at 66.7) · clk_rmii 90.8 MHz (PASS at 50) · clk_tmds 301 MHz (FAIL at 333 SDR model). Async-input max delay 15.4 ns. Expect the 25 MHz path to be in Blob (32-way merge/scan) or the 39-bit CIC integrators; not confirmed.
## Stubs / omissions
- No PLL or reset synchronisers: four clock+reset input pairs; TMDS serialiser is a 10:1 SDR shifter at 333 MHz (real design: ODDRX2 at 5×), no LVDS negative pins.
- clash-h2: `h2` core + two `blockRamFilePow2 "h2.bin"` program RAMs + own IO decode (0x4000 UART, 0x4004 LED, 0x4010–0x4094 block regs); `H2.System`'s LED-only top not embedded; UART is pm-lib's HarpLink 8N1 (÷217), not the upstream FIFO UART.
- Second `timingGen` for the overlay (textConsole hides its own); SD = 3 bit-banged GPIO from a held register; DVP pclk edge-sampled in the 25 MHz domain; matrix/zones fed from `adc_d`.
- Radar: DDC from parallel 12-bit `adc_d` (no SPI ADC), FFT enabled by DDC valid, |re|+|im| magnitude, CFAR detect only to a counter/status reg (no velocity record). Records: PPS/TimeMark/StrobeStamp/Centroid → 2k CDC FIFO → `beaconGoAdapter` → beacon (payload not carried). MAC RX only feeds counters.
- Nothing simulated; wiring is plausible only. Library note: installed pm-time/pm-vision libs lack unfoldings (`ppsStep`, `$wdvpT`), so all deps were compiled from source with `-i`; adding `-fexpose-all-unfoldings -fno-worker-wrapper` (as theremin-clash does) would fix this. Clash total 21m40s once it ran (three OOM kills from concurrent sessions; disk was at 100% so tmpfs was used).
