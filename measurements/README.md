# Measurements — ECP5-85F area and Fmax

Numbers from `yosys synth_ecp5` + `nextpnr-ecp5 --85k --package CABGA381`, no pin
constraints, Fmax against a 100 MHz target unless noted. Per-run detail and caveats:
`2026-09-15-area-A.md`, `2026-09-15-area-B.md`, `2026-09-15-snooker-fit.md`.
Generated HDL and logs live in session scratch, not here (except `Oracle/pm-top/logs/`).

## Consolidated table (2026-09-15)

| Block (top) | LUT4 | FF | BRAM | DSP | Fmax MHz | Domain / note |
|---|---|---|---|---|---|---|
| H2 core (`h2`, no RAM/UART) | 1076 | 47 | 0 | 0 | 68.7 | 25 MHz bus |
| PM.RegFile (incl. Zones+Matrix) | 1463 | 724 | 0 | 6 | 58.0 | 25 MHz bus; `kIx` map fold is the path |
| PM.Matrix | 1231 | 604 | 0 | 0 | 60.2 | same path |
| PM.Zones | 139 | 46 | 0 | 6 | 114 | |
| PM.Adc | 96 | 101 | 0 | 0 | 200 | |
| PM.Spi | 79 | 38 | 0 | 0 | 179 | |
| PM.HarpLink (UART+frame) | 538 | 194 | 0 | 1 | 156 | |
| PM.SleighSpeed | 96 | 68 | 0 | 0 | 225 | retired link |
| PM.Sleigh | 281 | 248 | 0 | 0 | 132 | |
| PM.Gps | 232 | 105 | 0 | 1 | 48.7 | 25 MHz domain |
| PM.Keyer | 379 | 99 | 0 | 5 | 54.9 | 25 MHz domain |
| IRIG-B (`irigb`) | 370 | 117 | 0 | 5 | 37.6 | 25 MHz domain |
| PM.Wspr | 190 | 46 | 0 | 2 | 130 | |
| PM.Net beacon TX | 408 | 113 | 0 | 0 | 132 | RMII 50 MHz |
| PM.NetRx | 267 | 139 | 0 | 0 | — | yosys only (fit run) |
| Video console + timing | 126 | 83 | 5 | 2 | 84.5 | 66.7 MHz pixel |
| PM.Synth voice | 469 | 59 | 0 | 1 | 117 | ×10 voices ≈ 4.7k |
| PM.Lfo | 92 | 32 | 0 | 1 | 152 | |
| PM.Rhythm | 341 | 128 | 0 | 0 | 161 | |
| PM.Seq | 292 | 74 | 1 | 0 | 99.3 | |
| PM.Audio (DAC+NCO+mixer) | 464 | 44 | 0 | 0 | 52.4 | audio rate |
| PM.I2s | 157 | 120 | 0 | 0 | 126 | |
| PM.Ks bank ×4 | 545 | 405 | 8 | 3 | 26.3 | audio rate; needs 2 pipeline stages for 100 MHz |
| PM.Ks bank ×49 (Erard) | 1987–2021 | 904 | 44 | 3 | 23.9–25.5 | 5× headroom at 96 kHz×49 |
| PM.Goertzel | 413 | 133 | 0 | 16 | 22.5 | audio rate; unpipelined products |
| PM.AmDemod | 727 | 743 | 0 | 0 | 81.5 | |
| PM.Ddc (R=512) | 2428 | 1678 | 0 | 18 | 80.2 | ≥ 65 MSPS ✓ |
| FFT512 (R2SDF) | 2976 | 486 | 3 | 34 | — | fit run; 4 mults/stage |
| CA-CFAR | 96 | 246 | 0 | 2 | — | fit run |
| PM.Dvp | 47 | 36 | 0 | 0 | 142 | |
| **PM.Blob (before fix)** | **34910** | 4001 | 1 | 0 | timeout | Vec 32 Acc in registers |
| **PM.Blob (after fix)** | **3498** | 821 | 1 (+56 DPR16X4) | 0 | — | acc table in RAM; nextpnr pending |
| PM.PpsDiscipline | 240 | 156 | 0 | 0 | — | fit run |
| PM.StrobeLatch | 2712 | 1057 | 0 | 0 | — | fit run; 16×48-bit Vec FIFO in registers → move to BRAM |

Not yet measured: PM.Dpll, PM.Sdram, PM.UdpTx, PM.Records, PM.Video.Overlay/Tmds
standalone, H2.System SoC.

## Snooker-mode fit (pre blob-fix)

Flat top of every Snooker-row block: 29.9k LUT4 + 2.3k CCU2C (nextpnr 36.2k/83.6k
TRELLIS_COMB = 43 %), 13.0k FF, 44 DP16KD (99 KB), 61 DSP (39 %). Versus SWAG row
21k / 95 KB / 15 DSP. With the blob fix (−31k LUT4 standalone) expect ≈ 8–10k LUT4.
DSP is the real overshoot: FFT 34 + DDC 18. Timing at placement stage failed the 25 MHz
sys and 66.7 MHz pixel constraints; router cut at 25 min — rerun after the blob fix.

## Follow-ups (ordered)

1. Re-run the snooker fit with the fixed blob; get a routed Fmax and critical path.
2. StrobeLatch FIFO → blockRam (2.7k LUT4 → ~100).
3. Pipeline KS string update (2 stages), Goertzel products, PM.Audio cone; register the
   `kIx` map fold in Matrix/RegFile if the bus ever leaves 25 MHz.
4. FFT: share multipliers across stages or accept 34 DSP (156 available).
5. Measure the unmeasured six; add `-fexpose-all-unfoldings -fno-worker-wrapper` to
   pm-time/pm-vision cabal ghc-options so tops can compile against installed libs.
6. Toolchain: one Clash netlist generation at a time on this 7 GB box; strip the
   all-zero RAM init literal before yosys on large BRAM designs.
