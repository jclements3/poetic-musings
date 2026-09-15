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
| Sleigh speed link: theremin pitch/vol -> (0xA5,speed) @ 250 kbaud | `Oracle/pm-lib` (PM.SleighSpeed) + `Coil/SantaGlide/firmware` Rev C rx/watchdog/pacer | tx: frames track pitch, clamps, dead-man 0 (sleighspeed-test); rx: waveform decode, 250 ms watchdog, exact pacer rates, FSM hold (SleighSim); Cu bitstream 59.1 MHz PASS |
| eForth-PM register file: H2 bus decode 0x4020–0x403F, binds zones+matrix, cmd ports for synth/keyer, HW TX interlock | `Oracle/pm-lib` (PM.RegFile) | 8 semantics: iPanel read, FIFO-popping 0x4024 read, reset-muted audio, single command pulses, arm-key + mode-C hardware gate |
| 1920x480 text console (0x4026) | `Oracle/pm-video` | pixel-exact IBM-VGA glyph render, timing/polarity asserted both senses; ~200 LUT4, 5 BRAM |
| SD block model + IRIG peripheral in the eForth sim | `Oracle/clash-h2` (SystemUart) | personal-card boot: owner greet from block 0, real `1 load` from block 1, live IRIG clock + TOD set — all from interactive Forth |
| NMEA $GxRMC time parser -> TOD-set block (0x4040) | `Oracle/pm-gps` (PM.Gps) | checksum-gated BCD fields in the Irig set-word formats, incl. leap day-of-year; corrupt sentence and $GPGGA rejected, V-flag applies time without lock, one tod_set strobe per accepted fix |
| RMII 100BASE-TX UDP/IPv4 status beacon (0x40xx TBD) | `Oracle/pm-net` (PM.Net) | dibit stream reassembled in the test: FCS vs independent table CRC32, IP checksum sums 0xFFFF, 64-byte min frame incl. pad, >= 96-bit IFG, seq +1 across two frames |
