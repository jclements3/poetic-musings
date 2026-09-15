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

## 9. Network, Imaging, Radar, Coil spokes (letters N, I, M, C)

| Hardware part | Clash capability demonstrated | Library component | Status |
|---|---|---|---|
| Santa Glide sleigh tube (Alchitry Cu, 8 coils) | 250 kbaud speed frames, dead-man, 250 ms watchdog, coil pacer FSM | `PM.SleighSpeed` + `Coil/SantaGlide/firmware` Rev C (Cu 59.1 MHz PASS) | ✓ |
| RMII PHY / RJ45 | 100BASE-TX dibit stream, CRC32 FCS, IPv4 checksum, 64-byte pad, IFG | `PM.Net` (`Oracle/pm-net`) TX ✓ · MAC RX ○ | ✓ / ○ |
| Ch.10 recorder link (N) | Tagged-record UART framing, TMATS payloads | `MAIDEN/firmware/recorder/PROTOCOL.md` | ◐ (Python + wire spec) |
| OV9281 global-shutter camera + strobe line (Imaging) | DVP capture, external trigger, centroid | DVP + centroid | ○ |
| Doppler radar front end (M) | CIC → FFT → CFAR → velocity records | `MAIDEN/firmware/doppler/doppler_core.vhd` | ◐ |

## Library roll-up

| Family | Components ✓ | ◐ | ○ |
|---|---|---|---|
| DSP core | Cic, Fir, Fft512, Cordic, Cfar, Nco, SineLut, IirNStage, DelayDiffFilter, EdgeSampler | doppler chain | DDC wiring, Goertzel, KS waveguide, AM demod |
| Audio | DsmDac, Pwm, Mixer, Synth osc/ADSSR, note table | — | LFOs, rhythm, sequencer, I²S |
| I/O + links | Uart, Spi, Matrix, Zones, HarpLink, SleighSpeed, Net TX, Gps parser | Ch.10 recorder | MAC RX, TMDS, DVP, ASCII layer |
| Timing / CDC | Cdc (sync, pulse, Gray FIFO), IRIG-B | pps_discipline, strobe_latch | DPLL, SDRAM controller |
| Control | H2 SoC boot, RegFile, Keyer/decoder, Video console | H2 Clash port | overlay FB |

Rules carried over from `LIBRARY.md`: measured VHDL stays usable as a black box; a Clash
port happens when a demonstrator part needs it; every port gets hedgehog + cycle-exact +
GHDL checks; re-measure area on ECP5 after porting; the theremin suite is the regression
gate for every shared-library change.
