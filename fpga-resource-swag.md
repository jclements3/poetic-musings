# FPGA resource SWAG — how much FPGA does the PM device need?

Rough order-of-magnitude estimate (2026-08-31) to size the One Box FPGA, prompted by
the ledger showing the ULX3S 85F order was **canceled** — so the board is an open
decision, not an owned asset. Numbers are SWAG-grade: ±50% on LUTs, better on BRAM
(memory is arithmetic), DSP counts assume time-multiplexing wherever the sample rate
allows.

Owned today: Alchitry Cu (iCE40 HX8K — 7.7k LUT, 32× 4Kb BRAM, no DSP) and the
Doppler UP5K board. The HX8K is spoken for (Santa Glide) and **cannot drive the V0
display anyway**: 1920×480@60 needs a ~74 MHz pixel clock → ~370 Mbps TMDS DDR lanes,
beyond iCE40 I/O; ECP5 ODDR handles it. So the box needs an ECP5 regardless.

## Per-module SWAG (ECP5 4-input LUTs, BRAM bytes, 18×18 DSP slices)

| Module family | LUT | BRAM | DSP | Notes |
|---|---|---|---|---|
| H2 Forth SoC (CPU, UART+FIFO, timer, IRQ, reg bus) | 3k | 16–32 KB | 1 | J1-class core is tiny; RAM dominates |
| Video: 1920×480 text/VT100 + overlay + TMDS | 3k | 16 KB | 0 | char buf 7 KB + font ROM + line buffers |
| VL-1 synth (pulse osc ×10, ADSSR, rhythm ROM, sequencer, mixer) | 4k | 8 KB | 4 | audio-rate, heavily time-muxed |
| Theremin (freq counters, NCO, CIC/FIR, vibrato, ΣΔ DAC) | 3k | 4 KB | 6 | already passing on ECP5 |
| Erand49 harp: 49 KS waveguides + allpass | 4k | ~80 KB | 8 | delay lines ≈ 96k·Σ(1/f) ≈ 20k samples × 24 bit; 49 strings @96 kHz = 4.7 M updates/s → one pipelined engine at 100 MHz (~21 cyc/string) or two for slack |
| Erand49 detect: 98-ch mux, DC HPF, CORDIC mag, CA-CFAR | 3k | 8 KB | 4 | one CORDIC engine time-shared |
| 512-pt FFT (shared: spectrum view, SDR waterfall) | 3k | 8 KB | 4 | one instance, arbitered |
| CW keyer/decoder (Goertzel) | 1k | 2 KB | 2 | |
| IRIG-B gen/decode + GPS PPS DPLL + 10 MHz | 1.5k | 1 KB | 0 | counters |
| SDR DDC (NCO, I/Q mix, CIC, FIR comp) @ AD9226 65 MSPS | 4k | 16 KB | 12 | the DSP-hungry one; FIR time-share limited at 65 MHz |
| Network (RMII MAC, UDP, Ch.10 framing) | 3k | 16 KB | 0 | plus SDRAM for elasticity |
| Imaging (DVP capture, trigger, run-length blob labeller, ≤32 per-ball centroids) | 3.5k | 12 KB | 2 | snooker: label line buffer + equivalence table + 32 accumulator sets (Σxw, Σyw, Σw, bbox, count); 2 pixel-rate multiplies; end-of-frame sequential divides; frame store in SDRAM, not BRAM |
| M Motion radar (SPI ADC front end, CIC, CFAR, velocity records) | 4k | 8 KB | 6 | snooker cue-ball speed; FFT is the shared instance above; Ch.10 record mux lives in Network |
| Glue: SPI/SD, I²S/TDM, event UART, debounce, PLL/reset, capture/trigger tooling | 3k | 16 KB | 0 | |

## Scenarios

| Scenario | LUT | BRAM | DSP |
|---|---|---|---|
| Biggest single mode (Panel: H2 + video + synth + theremin voice + harp playback + FFT + keyer) | ~22k | ~150 KB | ~25 |
| "Everything resident" one-bitstream demo (add SDR + net + IRIG) | ~32k | ~190 KB | ~37 |
| Snooker mode bitstream (H2 + video + net + imaging + Motion radar + FFT + IRIG) | ~21k | ~95 KB | ~15 |
| + 50% margin for beginner-Clash inference inefficiency and routing at speed | **~48k** | **~285 KB** | **~55** |

Clock domains to plan for: 100 MHz system, ~74 MHz pixel, 65 MHz ADC, 25/50 MHz RMII,
audio 96 kHz — CDC/async-FIFO library blocks are load-bearing, not optional.
32 MB SDRAM required (imaging frames, capture tooling, Ch.10 buffering).

## Fit

| Part | LUT | BRAM | DSP | Verdict |
|---|---|---|---|---|
| iCE40 HX8K (owned) | 7.7k | 16 KB | 0 | retired to bench spare 2026-09-15 (Santa Glide moved into the box); can't do V0 video. |
| ECP5-25F | 24k | 126 KB | 28 | Fits nothing beyond the single Panel mode, no margin. No. |
| ECP5-45F | 44k | 243 KB | 72 | Fits per-mode bitstreams with care; "everything resident" + margin is tight on LUT/BRAM. The gamble option, saves ~$60–80. |
| **ECP5-85F (ULX3S)** | **84k** | **468 KB** | **156** | ~2.5× the margined worst case. Room to write naive Clash first and optimize never. **Re-order this.** |

**SWAG verdict: the canceled ULX3S 85F was the right board.** The 85F's headroom is
what lets a learning-Clash codebase stay naive (fold-style structures, generous
bit-widths) without ever hitting the wall; the 45F would make resource-tuning a
recurring tax on every lesson. Re-order the ULX3S 85F (~$315) — it goes back on the
open-spend list next to the TFT kit.

## What this implies for the Clash library (next step)

Shared blocks, roughly in dependency order — each used by ≥2 letters:

1. Infrastructure: PLL/reset wrappers, register bus, CDC (sync, pulse, async FIFO),
   debounce, BRAM/SDRAM wrappers
2. Comms: UART+FIFO, SPI (SD, ADC), I²S/TDM, event-frame codec
3. Numerics: NCO + phase-inc tables, CIC, FIR, CORDIC (mag/angle), Goertzel,
   512-pt FFT, CA-CFAR, ΣΔ/PWM DAC
4. Timing: ms/us tick, IRIG-B codec, PPS DPLL, timestamped event queue
5. Audio: ADSSR envelope, KS waveguide + allpass fractional delay, mixer
6. Video: timing generator, text/VT100 renderer, overlay compositor, TMDS
7. App-specific on top (H2 SoC integration, synth, harp, DDC, MAC/UDP, centroid, CFAR chain)
