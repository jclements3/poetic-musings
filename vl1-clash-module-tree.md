# VL-49 — Clash module tree

Target: ULX3S ECP5-85F. `*` = module reused by or feeding MAIDEN station FPGA. `**` = reused verbatim from existing theremin/MAIDEN library.

```
Top
├── Clocks
│   ├── PLL 25 MHz → 100 MHz sys, 148.5 MHz pixel        *
│   └── Reset sync                                        **
│
├── Control plane — H2 Forth SoC                          *
│   ├── H2 core (16-bit J1 derivative)                    *   station bring-up console
│   ├── Program BRAM 16 K × 16 (eForth image)             *
│   ├── Data/return stacks                                *
│   ├── IRQ controller                                    *
│   ├── Timer (tempo, rhythm tick, sequencer clock)       *   IRIG-B-slaved tick on station
│   ├── UART 115200 + FIFO                                **  Ch.10 recorder link
│   ├── Memory-mapped register bus 0x4000..                *   CFAR/threshold registers
│   └── LFSR (noise, seed)                                **
│
├── Panel I/O
│   ├── Key matrix scanner 8×8 (49 keys + 10 buttons)     *   station button/status panel
│   ├── Debounce + edge detect                            **
│   ├── ASCII layer decoder (base/SHIFT → key code)
│   ├── Slide-switch decoder S0/S1/S2 (3/6/4 pos)
│   └── ADC reader P0/P1 (SPI, 2 ch)                      **  same block as harp/MAIDEN ADC
│
├── Voice engine (memory-mapped peripheral)
│   ├── Note → phase-increment table (C1–C7, 73 entries)  *   NCO test-tone gen for radar
│   ├── Pulse-pattern oscillator (10 patterns, 1-bit)
│   ├── Electro pitch-mod (tempo-clocked square)
│   ├── ADSSR envelope, 11-level stepped, shared-step     *   pulse shaping / gating
│   ├── Vibrato LFO, constant-slope depth
│   ├── Tremolo LFO
│   ├── Patch register (8 × BCD digit → fields)           *   packed config word decode
│   └── Fixed-point gain multiply                         **
│
├── Rhythm engine
│   ├── Pattern ROM (10 patterns × 16 steps)              *   BRAM table pattern (twiddles)
│   ├── Percussion voices (noise burst + decaying pulse)  *   LFSR + envelope, shared
│   └── Step sequencer, tempo-locked
│
├── Melody sequencer
│   ├── 100-entry note/duration RAM                       *   timestamped event buffer
│   ├── REC/PLAY/One-Key-Play state machine
│   └── Balance mixer (melody × rhythm, 2-ch fixed-point) **  I/Q channel scaling
│
├── Audio out
│   ├── ΣΔ/PWM DAC 1-bit                                  **
│   └── (external RC LP, speaker amp)
│
└── Display — 1920×480 over GPDI
    ├── Video timing generator 1920×480                   *   station status/scope view
    ├── Text-mode framebuffer 240×30, 8×16 font           *   ported from H2 vga.vhd
    ├── VT100 subset (cursor, clear, scroll)              *
    ├── Overlay framebuffer (envelope/spectrum strip)     *   live FFT/CFAR plot
    ├── 512-pt FFT tap for spectrum overlay               **  MAIDEN FFT block
    └── TMDS encoder + DDR serializer                     *
```

## Module count

| Group | Modules | New | Reused (* / **) |
|---|---|---|---|
| Clocks | 2 | 0 | 2 |
| Control plane | 8 | 0 | 8 |
| Panel I/O | 5 | 3 | 2 |
| Voice engine | 8 | 5 | 3 |
| Rhythm engine | 3 | 1 | 2 |
| Melody sequencer | 3 | 2 | 1 |
| Audio out | 1 | 0 | 1 |
| Display | 6 | 0 | 6 |
| **Total** | **36** | **11** | **25** |

25 of 36 modules carry over to or from MAIDEN. The 11 new ones are the VL-1-specific instrument logic — all small, none timing-critical.

## Build order

1. Clocks + H2 SoC + UART: Forth prompt over USB serial. Gate: `ok` echo.
2. Key matrix + ASCII decoder: Forth prompt from the panel. Gate: type `1 2 + .` on keys.
3. Voice engine + DAC: `90099914 patch!` from the prompt. Gate: each PM.Synth block driven from keys, area re-measured on ECP5; SyntherJack traces as a reference, not a gate.
4. Sequencer + rhythm. Gate: Da Da Da.
5. GPDI text mode. Gate: prompt on the bar TFT. Unplug USB serial.
6. Overlay + FFT strip. Gate: live envelope + spectrum during play.

Each gate is one variable. Steps 1, 5, 6 are the MAIDEN station console deliverables in disguise.

## Lesson mapping

| Lesson | Module |
|---|---|
| 03–04 | Key matrix scanner, debounce |
| 05 | Pulse-pattern oscillator |
| 06 | ADSSR envelope (state machine) |
| 07 | Patch register / BCD decode |
| 08 | Sequencer RAM + state machine |
| 09 | Rhythm ROM + percussion |
| 10 | Video timing + text framebuffer |
| 11 | TMDS/GPDI |
| 12–14 | H2 core rewrite in Clash |

## Resource estimate (ECP5-85F)

H2 SoC ~1.5 k LUT + 4 BRAM; voice/rhythm/sequencer ~1 k LUT + 2 BRAM; display text+overlay ~1.5 k LUT + 8 BRAM (1920×480 overlay at 1 bpp = 115 KB → use a 480×120 strip, 7 KB); FFT tap reuses MAIDEN block ~3 k LUT + 4 BRAM. Total ~7 k LUT / 18 BRAM of 84 k / 208. Confirm with `synth_ecp5` per BOM Note A before quoting.
