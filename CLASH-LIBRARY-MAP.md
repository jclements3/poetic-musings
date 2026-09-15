# CLASH LIBRARY MAP — the One Box as a Clash signal-processing library build-up

**Reorientation (2026-09-15):** the program is a Clash FPGA signal-processing library.
The root is **Panel + Oracle** (49-key control surface + H2 Forth brains on the ULX3S
ECP5-85F). Each spoke adds one piece of special hardware to that root and exercises the
library components listed here. The box is the test fixture; the library is the
deliverable.

Legend — status: ✓ measured/sim-verified Clash · ◐ measured VHDL, Clash port pending ·
○ planned (SWAG-sized, no artifact). Location per `LIBRARY.md`; register map per
`Oracle/eforth-pm.md`; mode letters per `PROGRAM.md`.

## 1. Panel and human input

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| 49 keys A0–G7 + 10 buttons P0–P9, 8×8 diode matrix, one 16-wire ribbon | Free-running scan, debounce, edge detect, event FIFO, keycode fold | `PM.Matrix` (`Oracle/pm-lib`), 0x4024 | ✓ |
| SHIFT / two-layer ASCII legends | Combinational layer decode, keybed as console keyboard | ASCII layer decoder | ○ |
| Sliders S0/S1 (volume, balance) | SPI mode-0 master, ADC readout | `PM.Spi` (`Oracle/pm-spi`), 0x4022 | ✓ |
| Sliders S2–S4 (octave, MODE P·O·E·T·I·C, OFF·CAL·PLAY·REC) | Zone compare with hysteresis, 1 s dwell single-fire | `PM.Zones` (`Oracle/pm-lib`), 0x4020 | ✓ |
| Panel → Forth handoff | Memory-mapped register file, FIFO-popping reads, command pulses, hardware interlock | `PM.RegFile` (`Oracle/pm-lib`), 0x4020–0x403F | ✓ |

## 2. Control plane

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| USB serial (bring-up) | UART + FIFO, boots eForth | `H2.SystemUart` (`Oracle/clash-h2`) | ✓ |
| ULX3S 85F itself | Soft CPU in Clash: H2/J1 stack machine, BRAM program store, IRQ, timer, reg bus | `Oracle/clash-h2` (black-box VHDL first, Clash port = Lessons 12–14) | ✓ boot / ◐ port |
| microSD | SPI block device, block-0 boot, `1 load` | `PM.Spi` + SD block model in sim | ✓ sim |
| 25 MHz oscillator → sys / pixel / audio clocks | PLL, reset sync, 2-flop sync, pulse sync, Gray async FIFO across non-integer ratios | `PM.Cdc` (`Oracle/pm-lib`) | ✓ |
| Test-only | Hedgehog property tests, cycle-exact equivalence, GHDL elaboration of generated HDL | Lesson 09 method, `MAIDEN/lessons` | ✓ |

## 3. Audio synthesis (Panel, VL-1 synth mode, letter P)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Speaker + RC low-pass | 1-bit ΣΔ DAC, PWM | `PM.Audio` DsmDac, `Theremin.Pwm` | ✓ |
| Keys → pitch | Note → phase-increment table, NCO, quarter-wave sine LUT in BRAM | `PM.Synth` note table, `Theremin.Nco`, `SineLutQuarter` | ✓ |
| VL-1 voices (piano, fantasy, violin, flute, guitar) | 10-pattern 1-bit pulse oscillator, ADSSR envelope FSM, patch BCD decode | `PM.Synth` (`Oracle/pm-synth`) | ✓ osc/ADSSR · ○ patch/LFOs |
| Rhythm section | Pattern ROM, LFSR noise percussion, tempo-locked step sequencer | Rhythm engine | ○ |
| Melody REC/PLAY | 100-entry event RAM, sequencer FSM | Melody sequencer | ○ |
| Balance slider S1 | 4-ch saturating fixed-point mixer | `PM.Audio` mixer | ✓ |

## 4. Optical harp (Erand49, letter E)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| 98 IR pairs, 13 ADCs (gate 1 = one string) | Multi-channel SPI ADC sequencing | `PM.Spi` | ✓ single-ch |
| Pluck detect | CORDIC vectoring magnitude, CA-CFAR threshold (no divide) | `Maiden.Cordic`, `Maiden.Cfar` (`MAIDEN/theremin/clash`) | ✓ |
| String sound | Karplus-Strong waveguide, allpass fractional delay, ADSSR | KS waveguide | ○ |
| Harp ↔ box link | 3 Mbaud 8-byte event frames, A5/checksum framing, resync on corruption | `PM.HarpLink` (`Oracle/pm-lib`), 0x4036 | ✓ |
| I²S 24/96 harp-master | I²S serializer/deserializer | I²S block | ○ |

## 5. Theremin and SDR (letters T, S)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Pitch/volume antennas + LC tanks | Edge sampling, delay-difference filter, N-stage IIR | `Theremin.EdgeSampler`, `DelayDiffFilter`, `IirNStage` (175 LUT4 @ 132 MHz) | ✓ |
| Full theremin path | Sensor → NCO → volume curve → DAC; regression gate for the whole library | `Theremin.SensorTop`, `ThereminTop` (1,816 LUT4 / 452 FF / 2 BRAM) | ✓ |
| Antennas as HF input, AD9226-class ADC | DDC: CIC decimator (type-level ratio), 15-tap FIR droop comp, NCO mixer | `Maiden.Cic`, `Maiden.Fir`, `Theremin.Nco` | ✓ blocks · ○ DDC wiring |
| Spectrum/waterfall on V0 | 512-pt R2SDF streaming FFT | `Theremin.Fft` (4,620 LUT4 / 34 DSP / 3 BRAM) | ✓ |
| AM demod in-box (S gate) | Envelope detector, audio decimation | reuse Cordic + Cic | ○ |

## 6. Radio (Oracle keyer, UHF beacon, letters O, U)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Paddle / key input | CW keyer FSM, runtime WPM | `PM.Keyer` (`Oracle/pm-keyer`) | ✓ |
| Sidetone / received CW | Morse decoder, Goertzel tone detect | `PM.Keyer` decoder ✓ · Goertzel ○ | ✓ / ○ |
| WSPR TX (20 m) | Forth-side symbol encode, gateware tone step, TX-only-in-mode-C hardware interlock | `PM.RegFile` interlock ✓ · WSPR modulator ○ | ✓ / ○ |

## 7. Time and position (letters I, G)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| IRIG-B output / scope check | Bit-for-bit DCLS framer, BCD time fields, live TOD set | `IRIG/clash` (8-frame TB, erratum-fixed) | ✓ |
| GPS module PPS + NMEA | PPS discipline, 48-bit Ch.10-width RTC, holdover watchdog | `pps_discipline.vhd` (MAIDEN timebase) | ◐ |
| GPS NMEA serial | `$GxRMC` parser, checksum gate, leap day-of-year, one strobe per fix | `PM.Gps` (`Oracle/pm-gps`), 0x4040 | ✓ |
| 10 MHz reference out | PPS-locked DPLL | GPS DPLL | ○ |
| Camera strobe input | Async trigger → 2FF → (rtc, seq) FIFO with sticky overflow | `strobe_latch.vhd` | ◐ |

## 8. Display (V0)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| 8.8" 1920×480 bar TFT over GPDI | Video timing generator, pixel-exact text console, IBM-VGA glyph ROM | `Oracle/pm-video` (~200 LUT4, 5 BRAM), 0x4026 | ✓ |
| HDMI connector | TMDS encoder + DDR serializer | TMDS block | ○ |
| Envelope/spectrum strip | Overlay framebuffer fed by FFT tap | Overlay + `Theremin.Fft` | ○ overlay · ✓ FFT |

## 9. Network and Coil spokes (letters N, C)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Sleigh Glide: 8 coils + MOSFET driver board over a 10-wire gate ribbon | Moore FSM + dwell table, virtual-tick pacer, ribbon-sense dead-man, PWM hold/run, theremin-pitch → speed | `PM.Sleigh` (○ — port of `SleighGlide.hs` + `PM.SleighSpeed` mapping onto the bus; FSM/pacer/watchdog sims ✓ carry over) | ◐ |
| RMII PHY / RJ45 | 100BASE-TX dibit stream, CRC32 FCS, IPv4 checksum, 64-byte pad, IFG | `PM.Net` (`Oracle/pm-net`) TX ✓ · MAC RX ○ | ✓ / ○ |
| Ch.10 recorder link (N) | Tagged-record UART framing, TMATS payloads | `MAIDEN/firmware/recorder/PROTOCOL.md` | ◐ (Python + wire spec) |

## 10. Snooker table: Imaging + Motion radar (letters I, M)

One demo, two spokes: the overhead camera says where every ball went, the radar says
how fast the cue ball left, IRIG aligns them on one screen (PLAN.md Phases 11–12).

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Overhead OV9281 global-shutter camera, 640×400 @ 120–210 fps | DVP parallel capture, line/frame sync, external trigger | DVP capture | ○ |
| Camera strobe line | Async trigger → 2FF → (rtc, seq) FIFO with sticky overflow; IRIG-stamped frame | `strobe_latch.vhd` (MAIDEN timebase) | ◐ |
| Balls on green baize (~9 px per 52.5 mm ball) | Threshold + run-length blob, centroid accumulate, one record per ball per frame | centroid | ○ |
| Track stream to laptop | Centroid records in Ch.10 framing over UDP; gate = gap-free track at 200 fps | `PM.Net` + recorder protocol | ✓ TX / ◐ framing |
| CDM324-class 24 GHz Doppler module aimed down the table | SPI ADC front end, I/Q sample path | `PM.Spi`, doppler_top ADC front end | ✓ / ◐ |
| Cue-ball departure (~1.3 kHz Doppler at 8 m/s) | CIC decimate → FFT512 → CA-CFAR → velocity record; radial-only, no ball identity | `Maiden.Cic`, `Theremin.Fft`, `Maiden.Cfar`, `doppler_core.vhd` | ✓ blocks · ◐ chain |
| V0 one-screen view | Ball paths + velocity trace on the overlay strip, timestamps aligned by IRIG; gate = radar speed within 5 % of camera speed | overlay FB + `Theremin.Fft` tap | ○ overlay |

## Status — 2026-09-15 (evening, after the parallel build-out)

| Family | Verified ✓ | Awaiting port ◐ | To write ○ |
|---|---|---|---|
| DSP core | 15 | 1 | 0 |
| Audio and synthesis | 10 | 0 | 0 |
| I/O and links | 14 | 0 | 0 |
| Timing and CDC | 6 | 0 | 2 |
| Control and display | 5 | 0 | 0 |
| **Total** | **50** | **1** | **2** |

- **Verified** = hedgehog/assertion spec green in Clash sim, Verilog generated. Measured
  ECP5 area exists for `ThereminTop`, `Theremin.Fft`, `IirNStage` and the text console;
  every other ✓ still needs an area number after integration (Lesson 11: area is a
  measurement).
- **Awaiting port** = green in sim, needs its box-side port: Doppler chain, Ch.10
  record framing, PPS discipline, strobe timestamp latch (measured VHDL), and the
  Sleigh Glide sequencer (`SleighGlide.hs` → `PM.Sleigh`, one FPGA rule 2026-09-15). Each ports when its spoke
  starts (`LIBRARY.md` porting rule).
- **To write** is down to two shared blocks: the PPS-locked 10 MHz DPLL (G) and the
  SDRAM controller (N elasticity, Imaging frame store). The 2026-09-15 parallel
  build-out (11 agents, one package each) added 16 blocks with 21 new test suites:
  pm-ks, pm-dsp, pm-vision, pm-wspr, pm-time (new) and Lfo/Rhythm/Seq, I2s, NetRx/
  Records, Sleigh, Overlay/Tmds (extended). Python golden models (fpython prelude
  style) for KS, blob centroids and the WSPR encoder.
- **Blockers:** none in gateware. ULX3S 85F on backorder until 2026-10-02
  (`ORDERS.md` R1) — no new area measurements before then. Regression gate (theremin
  suite) is green.
- **Next moves:** `synth_ecp5` area for every ✓ block (no board needed); hedgehog
  property tests + GHDL elaboration for the ported VHDL (porting-rule steps 2–3); a
  variable-length UDP TX so `PM.Records` datagrams reach the wire; KS bank state to
  BRAM before the 49-string synthesis; WSPR encoder cross-check against wsprsim.

Update this table whenever a block changes column; the per-family list below is the
source of the counts.

## Module list — what the effort produces

✓ exists and is sim-verified · ◐ exists as measured VHDL, Clash port pending · ○ to be
written. Roughly 35 ✓, 5 ◐, 15 ○ as of 2026-09-15.

**DSP core**
- ✓ CIC decimator with type-level ratio (`Maiden.Cic`)
- ✓ 15-tap systolic FIR, CIC droop compensator (`Maiden.Fir`)
- ✓ 512-point streaming FFT, R2SDF — 4,620 LUT4 / 34 DSP / 3 BRAM on ECP5 (`Theremin.Fft`)
- ✓ 16-stage pipelined CORDIC, vectoring magnitude/phase (`Maiden.Cordic`)
- ✓ CA-CFAR detector, integer compare, no divide (`Maiden.Cfar`)
- ✓ NCO with quarter-wave sine LUT in BRAM
- ✓ N-stage IIR — 175 LUT4 @ 132 MHz (`Theremin.IirNStage`)
- ✓ Edge sampler, edge-to-pulse-position, sensor period measure, delay-difference filter
- ◐ Doppler chain integration: CIC → FFT → CFAR → velocity records (`doppler_core.vhd`; wiring pattern now in `PM.Ddc`)
- ✓ DDC: NCO mix → Maiden.Cic ÷512 → Maiden.Fir at 65 MSPS (`PM.Ddc`, pm-dsp)
- ✓ Goertzel single-tone detector, runtime coefficient, hysteresis (`PM.Goertzel`)
- ✓ AM envelope demod via CORDIC + IIR + DC tracker (`PM.AmDemod`)
- ✓ Karplus-Strong voice + N-string bank, allpass fractional delay, bit-exact vs Python golden (`PM.Ks`, pm-ks)

**Audio and synthesis**
- ✓ Sigma-delta DAC and PWM (`PM.Audio`, `Theremin.Pwm`)
- ✓ 4-channel saturating fixed-point mixer
- ✓ Note-to-phase table, 10-pattern pulse oscillator, ADSSR envelope (`PM.Synth`)
- ✓ Volume curve, musical NoteMap A0..G7
- ✓ Vibrato/tremolo triangle LFO with depth ramp (`PM.Lfo`)
- ✓ 10-pattern rhythm ROM, LFSR percussion voices, tempo step sequencer (`PM.Rhythm`)
- ✓ 100-entry REC/PLAY/One-Key-Play event sequencer (`PM.Seq`)
- ✓ I²S master TX/RX, 24-in-32, 96 kHz (`PM.I2s`)

**I/O and links**
- ✓ UART with FIFO (`H2.SystemUart`)
- ✓ SPI mode-0 master — SD and ADCs (`PM.Spi`)
- ✓ 8×8 key matrix scanner with debounce and event FIFO (`PM.Matrix`)
- ✓ Slider zone decoder with hysteresis and 1 s dwell (`PM.Zones`)
- ✓ Framed 8N1 event link, A5 + checksum, corruption resync (`PM.HarpLink`)
- ✓ Sleigh Glide coil sequencer in the box: Moore FSM, dwell table, pacer, ribbon dead-man, PWM, 0x4050 helpers (`PM.Sleigh`, Rev D)
- ✓ NMEA `$GxRMC` time parser with checksum gate (`PM.Gps`)
- ✓ RMII 100BASE-TX UDP/IPv4 transmitter with CRC32 (`PM.Net`)
- ✓ Tagged-record framers (PPS_STATUS, TIME_MARK, STROBE_STAMP, CENTROID), N-port round-robin mux, 4 KB elastic FIFO, 1400 B datagram packer (`PM.Records`)
- ✓ RMII 100BASE-TX MAC receiver, CRC-32 check, address filter, runt reject (`PM.NetRx`)
- ✓ DVP camera capture 640×400 with frame seq (`PM.Dvp`, pm-vision)
- ✓ Run-length blob labeller, 32 labels, per-blob centroids, area filter (`PM.Blob`)
- ✓ TMDS 8b/10b encoder + 10:1 sequencer, ODDR left as vendor black box (`PM.Video.Tmds`)
- ✓ WSPR 162-symbol 4-FSK sequencer with hardware interlock; encoder golden in Python (`PM.Wspr`, pm-wspr)

**Timing and clock domains**
- ✓ 2-flop synchroniser, pulse synchroniser, Gray-code async FIFO (`PM.Cdc`)
- ✓ IRIG-B DCLS + AM framer with settable BCD RTC (`IRIG/clash`)
- ✓ PPS discipline with 48-bit RTC and holdover watchdog, ported from `pps_discipline.vhd` with quirks Q1–Q4 reproduced (`PM.PpsDiscipline`, pm-time)
- ✓ Async strobe timestamp latch, 16-deep, sticky overflow, ported from `strobe_latch.vhd` (`PM.StrobeLatch`)
- ○ PPS-locked 10 MHz DPLL, SDRAM controller

**Control and display**
- ✓ H2 stack CPU booting the real eForth image (`Oracle/clash-h2`)
- ✓ Memory-mapped register file: FIFO-popping reads, command pulses, hardware TX interlock (`PM.RegFile`)
- ✓ CW keyer and Morse decoder (`PM.Keyer`)
- ✓ 1920×480 text console, pixel-exact IBM VGA glyphs (`Oracle/pm-video`)
- ✓ 480×120 1-bpp overlay strip framebuffer, column plot, 2-cycle aligned to the console (`PM.Video.Overlay`)

## Algorithms — what the blocks compute

**Signal processing:** CIC decimation · 15-tap systolic FIR (CIC droop compensation) ·
N-stage IIR · radix-2 SDF streaming FFT, 512 pt · CORDIC vectoring (magnitude/phase) ·
cell-averaging CFAR · digital down-conversion (NCO mix to I/Q) · Goertzel single-tone
detection · AM envelope demodulation · Doppler velocity from FFT bin index.

**Synthesis and audio:** direct digital synthesis (phase accumulator + quarter-wave sine
table) · sigma-delta 1-bit DAC · PWM · Karplus-Strong plucked string with allpass
fractional delay · ADSSR envelope · pulse-pattern oscillators, vibrato/tremolo LFOs ·
fixed-point saturating mixing.

**Detection and vision:** period measurement by edge sampling / pulse position ·
run-length blob labelling with run-overlap union · single-pass weighted centroid
(running sums, one divide per frame) · nearest-neighbour track association.

**Timing and clocks:** PLL discipline of a local oscillator to GPS PPS · holdover with
drift estimate · IRIG-B pulse-width timecode + BCD time · asynchronous event
timestamping via 2-flop sync · Gray-code pointer async FIFO.

**Communications and coding:** CRC-32 (Ethernet FCS) · IPv4/UDP one's-complement
checksums · Morse keying/decoding with adaptive element timing · WSPR encoding
(convolutional code, interleave, 4-FSK) · NMEA parse with XOR checksum · framed serial
links (sync byte, checksum, resync) · debounce and hysteresis.

**Control:** stack-machine instruction execution (H2 Forth) · open-loop stepping
schedule with virtual-tick pacing (linear reluctance motor) · Moore state machines with
dead-man watchdogs.

## Library roll-up

| Family | Components ✓ | ◐ | ○ |
|---|---|---|---|
| DSP core | Cic, Fir, Fft512, Cordic, Cfar, Nco, SineLut, IirNStage, DelayDiffFilter, EdgeSampler, Ddc, Goertzel, AmDemod, Ks | doppler chain | — |
| Audio | DsmDac, Pwm, Mixer, Synth osc/ADSSR, note table, Lfo, Rhythm, Seq, I2s | — | — |
| I/O + links | Uart, Spi, Matrix, Zones, HarpLink, Net TX, NetRx, Records, Gps parser, Sleigh, Dvp, Blob, Tmds, Wspr | — | ASCII layer |
| Timing / CDC | Cdc (sync, pulse, Gray FIFO), IRIG-B, PpsDiscipline, StrobeLatch | — | DPLL, SDRAM controller |
| Control | H2 SoC boot, RegFile, Keyer/decoder, Video console, Overlay | H2 Clash port | — |

Rules carried over from `LIBRARY.md`: measured VHDL stays usable as a black box; a Clash
port happens when a demonstrator part needs it; every port gets hedgehog + cycle-exact +
GHDL checks; re-measure area on ECP5 after porting; the theremin suite is the regression
gate for every shared-library change.
