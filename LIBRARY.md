# LIBRARY — PM shared-block inventory (harvested from the `MAIDEN/` source archive, 2026-08-31)

What already exists, where it lives, and which PM letters consume it. The I + M pair
is the snooker-table demo (PLAN.md Phases 11–12): camera centroids + radar speed,
IRIG-aligned. Consumers per
`fpga-development-plan.md` gates and the per-module SWAG in `fpga-resource-swag.md`.
Everything under `MAIDEN/` is read-only source material (its own git repo); blocks are
consumed in place or ported, never edited there.

**Location correction (supersedes the PROGRAM.md note):** the *measured Clash library*
— `Maiden.{Cic,Fir,Cordic,Cfar}` and the complete theremin port with its hedgehog
specs — lives in **`MAIDEN/theremin/clash/`**. The top-level `Theremin/` repo is the
*older* VHDL-era repo (phase1 NCO, ROADMAP, D-Lev references); it has no `clash/`
directory. PROGRAM.md has this backwards ("MAIDEN/theremin/ is an older embedded
copy"): for gateware harvesting, MAIDEN's embedded copy is the newer, load-bearing one.

## Inventory

| Block | Where it exists today | Language / status | PM consumers |
|---|---|---|---|
| CIC decimator | `MAIDEN/firmware/doppler/rtl/cic_dec.vhd` (+`tb/cic_dec_tb.vhd`, `golden/model.py`) · `MAIDEN/theremin/clash/src/Maiden/Cic.hs` (+`test/CicSpec.hs`) | measured VHDL (sim green, bit-true vs golden model; N=3, R generic 4/8 per decimation-audit) **and** Clash w/ type-level ratio | **T** · **S** (DDC) · **M** (Doppler front end) |
| FIR (CIC droop compensator) | `MAIDEN/theremin/clash/src/Maiden/Fir.hs` (+`test/FirSpec.hs`) | Clash, 15-tap transposed/systolic, spec-tested | **T** · **S** (DDC comp) · **M** |
| FFT512 | `MAIDEN/firmware/doppler/rtl/fft512_serial.vhd` (serial radix-2 DIT, sliding window, tb + golden vectors) · `MAIDEN/theremin/clash/src/Theremin/Fft.hs` (R2SDF streaming) | measured VHDL (iCE40-shaped: LUT mults, max+min/2 mag) **and** measured Clash — **4,620 LUT4 / 34 DSP / 3 BRAM, 5.5% of ECP5-85F** (vs 139k LUT4 behavioral; `MAIDEN/hardware/BOM.md` Note A) | **O/T** (spectrum view) · **S** (waterfall) · **M** — one arbitered instance per SWAG |
| CORDIC (vectoring, mag/phase) | `MAIDEN/theremin/clash/src/Maiden/Cordic.hs` (+`test/CordicSpec.hs`) | Clash, 16-iteration pipelined, spec-tested | **E** (pluck detect mag) · **M** · **S** |
| CA-CFAR | `MAIDEN/firmware/doppler/rtl/cfar.vhd` (+tb, alpha table with derivation: α = N_t(P_fa^(-1/N_t)−1), integer compare, no divide) · `MAIDEN/theremin/clash/src/Maiden/Cfar.hs` (+`test/CfarSpec.hs`) | measured VHDL **and** Clash | **E** (pluck detect) · **M** |
| UART TX | `MAIDEN/firmware/doppler/rtl/uart_tx.vhd` (requirement-tagged R1–R4, tb-verified) · `Oracle/clash-h2/src/H2/SystemUart.hs` (full UART + FIFO, boots eForth) | measured VHDL + working Clash | **O** · **N** · **E** (event link) · **M** (recorder link) — stock everywhere |
| Timebase: PPS + RTC | `MAIDEN/firmware/timebase/rtl/pps_discipline.vhd` | measured VHDL (maiden37, sim green: nominal/±ppm/holdover; free-running 48-bit Ch.10-width RTC, offset/lock report, 1.5 s watchdog) | **G** · **N** (TIME_MARK source) · **Imaging** · **M** · **U** |
| IRIG-B generator | `MAIDEN/firmware/timebase/rtl/irigb_gen.vhd` (bit-for-bit DCLS framer; fixes a lesson-18 SBS/P9 erratum — P9 at cell 89, SBS split 80–88/90–97) | measured VHDL (maiden38, decoder-verified in `tb/timebase_tb.vhd`) | **I** (Phase 2 is largely *already written*) · **G** · **M** |
| Strobe/trigger timestamp latch | `MAIDEN/firmware/timebase/rtl/strobe_latch.vhd` (async→2FF→(rtc,seq) FIFO, sticky loud overflow) | measured VHDL (maiden38) | **Imaging** (IRIG-stamps every snooker camera frame) · **M** (stamps radar velocity records) |
| Recorder + Ch.10 protocol | `MAIDEN/firmware/recorder/` — `PROTOCOL.md` (tagged-record UART framing, single owner), `protocol.py/sources.py/rings.py/writer.py/record.py`; Ch.10 payload structs in `MAIDEN/software/` (`maiden.ch10.payloads`); ICD = `MAIDEN/docs/MAIDEN_D4_ICD.html` IF-1 (Ch 0–6) | working Python + pinned wire spec | **N** (transport payloads) · **M** · **Imaging** (STROBE_STAMP/centroid records) |
| Theremin DSP suite | `MAIDEN/theremin/clash/src/Theremin/` — NCO, SineLut/Quarter, DsmDac, Pwm, EdgeSampler, DelayDiffFilter, IirNStage, SensorTop, ThereminTop (+bringup/) | measured Clash: theremin_top **1,816 LUT4 / 452 FF / 2 BRAM** (20× from the Vec→blockRam rewrite); IirNStage **175 LUT4 @ 132 MHz** | **T** (regression target) · **S** (NCO/DDC, antennas) · **P** (voice source) |
| H2 Forth SoC | `Oracle/clash-h2/` (CPU + UART + reg bus; real eForth image boots in Clash sim, reads 0x4020) · black-box VHDL in `Oracle/forth-cpu-upstream/` | Clash, compile + boot-test green (Phase 0 gate met) | **O** — and every letter, via the 0x40xx register bus (`Oracle/eforth-pm.md`) |
| Doppler chain integration | `MAIDEN/firmware/doppler/rtl/doppler_core.vhd`, `doppler_top.vhd` (CIC→FFT→CFAR→DOPPLER_V records; SPI ADC front end; v_cm Q8 scaling) | measured VHDL (sim green vs golden model) | **M** Motion radar — the snooker cue-ball speed chain, used as a black box first then ported; also reference wiring for the S DDC and E detect chains |
| Clash lesson series | `MAIDEN/lessons/src/Lesson01–14.hs` (+`lessons.cabal`, verified per `MAIDEN/clash-lessons-prompt.md`: every FAILURE case actually compiled) · course layer `MAIDEN/course/` (CURRICULUM.md, lesson00–24, maiden00–67 sprint cards) | teaching assets, build-verified | **O** (H2 Clash port = Lessons 12–14 per PLAN Phase 3) · every letter's onboarding |

Planned-only blocks (no artifact yet, SWAG-sized): Goertzel keyer/decoder (O/C mode),
KS waveguide + ADSSR (E/P), RMII MAC RX + general TX (N — the beacon TX seed now
exists in `Oracle/pm-net`, see below; MAIDEN has **no** Ethernet anywhere; its
Ch.10 transport is UART→Pi 5 SBC), DVP capture + run-length blob labeller + ≤32 per-ball centroids (Imaging — snooker
table; MAIDEN's video path was USB3→SBC H.264, no fabric vision to harvest), TMDS/video text renderer (O; upstream vga.vhd reusable),
SDRAM controller, async-FIFO/CDC library (load-bearing per SWAG clock-domain list).

## Porting rule

Per `MAIDEN/clash-lessons-prompt.md` and PLAN Phase 3 practice (H2 black-box VHDL
first, Clash port as Lessons 12–14):

1. **Measured VHDL stays usable as-is** — instantiated as a black box under a Clash
   top (Lesson 07's finding: Clash changes what *surrounds* vendor/foreign blocks,
   not the need for them). GHDL testbenches remain the verification of record.
2. **A Clash port happens when a consuming letter needs the block** — not
   speculatively. The port follows Lesson 12's method: every width explicit, upstream
   defects reproduced with comments (not silently fixed) until the port is proven
   equivalent, then property tests (Lesson 09's three checks: hedgehog vs reference
   model, cycle-exact equivalence, GHDL elaboration of the generated VHDL).
3. **Re-measure on ECP5 after porting** (Lesson 11: area is a measurement). The
   doppler VHDL is iCE40-shaped (LUT multipliers, no sqrt, 12 MHz); on the 85F the
   multiplies belong in MULT18X18D and budgets change.
4. The theremin suite is the regression gate for every shared-library change after
   Phase 4 (PLAN standing rule).

## Known deltas vs PM plan docs

- PROGRAM.md's Theremin note is inverted — see the location correction above.
- PLAN Phase 7 says "PPS-locked 10 MHz **DPLL**"; MAIDEN's measured timebase
  deliberately chose the opposite (lesson 18 option 2: never steer, publish the
  RTC↔UTC mapping in Ch 1 time packets). `GPS/DESIGN.md` reconciles: both, in layers.
- `IRIG/DESIGN.md`'s provisional set-registers (0x4036–0x403A) collide with
  `Oracle/eforth-pm.md`'s 0x4036 oHarp. Flagged in `GPS/DESIGN.md`; GPS takes 0x4040+.
- ULX3S 85F: ordered → canceled (MAIDEN BOM line 7); `fpga-resource-swag.md` verdict
  is re-order. Lessons' Lesson14 was rewritten against the Alchitry Cu meanwhile.

## PM gateware written this session (Clash, sim-verified, Verilog generated)

| block | where | proof |
|---|---|---|
| CW keyer + Morse decoder | `Oracle/pm-keyer` (PM.Keyer) | PARIS 73 keyer->decoder round trip asserted; runtime WPM |
| Sigma-delta DAC, sine NCO, 4-ch saturating mixer | `Oracle/pm-audio` (PM.Audio) | DAC density 1% across codes; NCO freq + full-scale; mixer unity/-12dB/sat/mute |
| VL-1 voice: note table, 10-pattern pulse osc, ADSSR | `Oracle/pm-synth` (PM.Synth) | A4 within 0.01 cent; exact octaves; square duty; full ADSSR envelope trace incl. release |
| SPI mode-0 master (SD, ADC) | `Oracle/pm-spi` (PM.Spi) | full-duplex byte exchange vs behavioral slave at two dividers; 8 edges/transfer |
| 8x8 key matrix scanner + event FIFO (0x4024) | `Oracle/pm-lib` (PM.Matrix) | debounce, keycode fold, FIFO order/flags, glitch rejection — 6 assertion groups |
| Slider zone decoder + S3 mode dwell (0x4020) | `Oracle/pm-lib` (PM.Zones) | hysteresis no-flicker, sweeps, 1 s dwell single-fire, register packing |
| CDC: 2-flop sync, pulse sync, Gray async FIFO | `Oracle/pm-lib` (PM.Cdc) | level/pulse crossing + lossless 60-element streams both directions across a 3.6x non-integer clock ratio |
| Harp event link: 8N1 UART + A5/cksum framing (0x4036) | `Oracle/pm-lib` (PM.HarpLink) | 3-frame byte-exact loop; full-bit corruption drops exactly the hit frame, resyncs (stop-bit check + inter-frame gap) |
| Sleigh: theremin pitch/vol -> speed; coil FSM/pacer/watchdog (**Rev D: in the box as `PM.Sleigh`, one FPGA rule 2026-09-15**; the 250 kbaud link is retired) | `Oracle/pm-lib` (PM.SleighSpeed, tx side, retired) + `Coil/SleighGlide/firmware` (FSM/pacer sims — port target) | tx: frames track pitch, clamps, dead-man 0 (sleighspeed-test); rx: waveform decode, 250 ms watchdog, exact pacer rates, FSM hold (SleighSim); Cu bitstream 59.1 MHz PASS |
| eForth-PM register file: H2 bus decode 0x4020–0x403F, binds zones+matrix, cmd ports for synth/keyer, HW TX interlock | `Oracle/pm-lib` (PM.RegFile) | 8 semantics: iPanel read, FIFO-popping 0x4024 read, reset-muted audio, single command pulses, arm-key + mode-C hardware gate |
| 1920x480 text console (0x4026) | `Oracle/pm-video` | pixel-exact IBM-VGA glyph render, timing/polarity asserted both senses; ~200 LUT4, 5 BRAM |
| SD block model + IRIG peripheral in the eForth sim | `Oracle/clash-h2` (SystemUart) | personal-card boot: owner greet from block 0, real `1 load` from block 1, live IRIG clock + TOD set — all from interactive Forth |
| NMEA $GxRMC time parser -> TOD-set block (0x4040) | `Oracle/pm-gps` (PM.Gps) | checksum-gated BCD fields in the Irig set-word formats, incl. leap day-of-year; corrupt sentence and $GPGGA rejected, V-flag applies time without lock, one tod_set strobe per accepted fix |
| RMII 100BASE-TX UDP/IPv4 status beacon (0x40xx TBD) | `Oracle/pm-net` (PM.Net) | dibit stream reassembled in the test: FCS vs independent table CRC32, IP checksum sums 0xFFFF, 64-byte min frame incl. pad, >= 96-bit IFG, seq +1 across two frames |

## PM gateware written 2026-09-15 (parallel build-out; Clash, sim-verified)

| block | where | proof |
|---|---|---|
| Karplus-Strong voice + N-string bank, allpass fractional delay | `Oracle/pm-ks` (PM.Ks) + `golden/ks_model.py` | pitch within 0.1 cent at delays 40/100/400; frac 0.5 between neighbours; decay monotone in gain; 4-string bank no cross-talk; first 64 samples bit-exact vs Python |
| Goertzel tone detector · AM envelope demod · SDR DDC (NCO → Cic ÷512 → Fir) | `Oracle/pm-dsp` (PM.Goertzel, PM.AmDemod, PM.Ddc) — depends on `MAIDEN/theremin/clash` | 700 Hz true / 1200 Hz false, quadratic power; AM 1 kHz recovered, ratio within 0.1 %; DDC DC on I within 0.1 %, 5 kHz offset rotation period 25.4 |
| DVP capture 640×400 · run-length blob labeller + per-ball centroids | `Oracle/pm-vision` (PM.Dvp, PM.Blob) + `golden/blob_model.py`, `golden/vectors.txt` | 256000 px/frame, 1 sof/eof; 1, 5 discs → exact records, centroid error 0/16 px; speck rejected; diagonal-touch merge documented |
| WSPR type-1 encoder (golden) · 162-symbol 4-FSK sequencer with interlock | `Oracle/pm-wspr` (PM.Wspr) + `golden/wspr_model.py` | 17 doctests (structure + hand-verified packing; cross-check vs wsprsim before air); 162 symbols at exact period, tx_on 162 periods, unarmed never asserts, disarm drops same clock |
| Strobe timestamp latch · PPS discipline (ports of measured VHDL) | `Oracle/pm-time` (PM.StrobeLatch, PM.PpsDiscipline) | timebase_tb cases reproduced: lock, ±30 ppm, jitter, 1.5 s holdover, relock; 17-strobe overflow sticky, seq counts dropped; quirks Q1–Q4 kept |
| Vibrato/tremolo LFO · rhythm ROM + LFSR percussion · 100-note sequencer | `Oracle/pm-synth` (PM.Lfo, PM.Rhythm, PM.Seq) | period exact, zero-mean, depth ramp; LFSR period 65535, voices decay, no clip; rec 5 → play in order, okp wraps, stops at 100 |
| I²S master TX/RX 24-in-32 | `Oracle/pm-audio` (PM.I2s) | 64 sck/frame, MSB one sck after ws, loop byte-exact incl. extremes, mid-frame resync |
| RMII MAC receiver · tagged-record framers, N-port mux, elastic FIFO, datagram packer | `Oracle/pm-net` (PM.NetRx, PM.Records) | TX→RX loop byte-exact, CRC bad/runt/filter counted; 25 record checks: hand vectors, no interleave, SEQ monotone, size/timeout/TIME_MARK flushes |
| In-box sleigh sequencer (Rev D) | `Oracle/pm-lib` (PM.Sleigh; calls PM.SleighSpeed.speedOf) | SS-004 walk, pacer 255/128/0 exact, ribbon-out gates low next clock, show-switch freeze, manual park, live dwell write on next glide |
| Overlay strip framebuffer 480×120 · TMDS 8b/10b encoder | `Oracle/pm-video` (PM.Video.Overlay, PM.Video.Tmds) | bar/plot/origin/clear, containment, 2-cycle alignment; ≤5 transitions, control words, disparity bound ±8, invertible 0..255 |

## PM gateware written 2026-09-15, wave 2 (Clash, sim-verified)

| block | where | proof |
|---|---|---|
| PPS-locked 10 MHz DPLL (frac-N NCO, FLL acquire, type-II PI track, holdover, lock, 1 PPS out) | `Oracle/pm-time` (PM.Dpll) | +30 ppm → −29 997 ppb trim at 30 s (0.1 ppm), locked; holdover freezes trim; relock; tick step ≤ 1 |
| Hedgehog property suites for StrobeLatch and PpsDiscipline; GHDL elaboration of all three timing tops | `Oracle/pm-time` (test/Prop.hs, VERIFY.md) | 300/300 each, cycle-exact vs pure models incl. quirks Q1–Q4; `ghdl -a/-e` OK |
| SDRAM controller (IS42S16160G, CL2, open-page, auto-refresh) + byte ring | `Oracle/pm-sdram` (PM.Sdram) | init order/timing; 256 words over 3 banks × 2 rows; 1 ms random traffic, refresh gap ≤ 780; row-miss sequence; ring 4096 B in order — all vs a timing-enforcing chip model |
| Variable-length UDP/IPv4/Ethernet TX, double-buffered, UDP checksum | `Oracle/pm-net` (PM.UdpTx) | 10 B / 1400 B datagrams through NetRx + parser: headers, IP/UDP checksums, pad, FCS; IFG 49 clk; drop counting |
| End-to-end snooker chain | `Oracle/pm-net` (test/ChainSpec.hs; deps pm-vision, pm-time) | 5 × 640×400 frames, 3 discs → Dvp → Blob → Records (+STROBE_STAMP) → UdpTx → NetRx → parse: every centroid exact, stamps precede, SEQs contiguous, zero drops |
| Register-bus integration proven from Forth (0x4050 sleigh, 0x4060 imaging, 0x4070 WSPR, 0x4080 net) | `Oracle/clash-h2` (SystemUart.hs, BootSpec.hs), `Oracle/eforth-pm.md` §1.1 | h2-boot: 13 new assertions from typed Forth — parked/gliding, dwell write, symbol write, arm refused outside C, threshold + centroid readback, record → frame → rxGood |
| KS bank state + packed delay pool in BRAM (49 Erard strings) | `Oracle/pm-ks` (PM.Ks ksBank, ks49) | 15/15; A0 +0.11 ¢, C4 −0.006 ¢, G7 +0.47 ¢; 39 260 words; yosys 2 021 LUT4 / 44 DP16KD / 3 DSP |
| Blob labeller accumulator table → RAM | `Oracle/pm-vision` (PM.Blob) | 11/11 identical; records bit-identical; 34 910 → 3 498 LUT4 |
| WSPR independent reference encoder + FSK tone check | `Oracle/pm-wspr` (golden/wspr_ref.py, test/FskSpec.hs) | 24 call/grid/power cases agree at every stage; tones within 0.02 Hz |

