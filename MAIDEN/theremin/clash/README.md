# theremin-clash

A Clash (Haskell HDL) port of DSP blocks from
[fpga-theremin](https://github.com/fpga-theremin/theremin), kept alongside the
untouched upstream clone in `../fpga-theremin/`.

**Purpose.** This is a de-risking spike, not a rewrite. The theremin is a
known-good reference design being used to verify two things *before* radar,
cameras, and AI data fusion are layered on:

1. that Clash is a sound basis for MAIDEN's FPGA DSP work, and
2. that the MAIDEN hardware behaves.

Doing both on a design that already works means anything that breaks is
attributable to the tooling or the board, not to a half-finished datapath.

## Target part

**ULX3S 85F — Lattice ECP5 LFE5U-85F, CABGA381**, per `hardware/BOM.md`
Note A (final call at maiden36 bench bring-up). The iCEstick and HX8K are
bring-up boards only; the behavioural 512-pt FFT is ~139k LUT4s against this
part's 83,640, which is why area is the thing worth measuring.

All numbers below are from real place-and-route on that part, not estimates.

## Status

| Block | SV lines | Ported | Tests |
|---|---|---|---|
| `theremin_pwm` | 104 | yes | yes |
| `iir_nstage_pow2k` | 195 | yes | yes, incl. cycle-exact structural-vs-model equivalence |
| `edge_to_pulse_position` | 78 | yes | via end-to-end chain tests |
| `delay_diff_filter` | 161 | yes | via end-to-end chain tests |
| `theremin_sensor_period_measure` | 515 | yes, below the ISERDES boundary | via end-to-end chain tests |
| `EdgeSampler` (new, replaces ISERDES front end) | — | yes | via end-to-end chain tests |
| `SensorTop` (new: raw osc pins -> filtered period, zero Xilinx primitives) | — | yes | yes — 6 end-to-end cases, exact period recovery |
| `Fft` (new: 512-pt streaming R2SDF, MAIDEN sizing) | — | yes | yes — 6/6 vs Double-precision reference DFT |
| `bit_change_detector` | 269 | no | — |
| `oversampling_edge_detector` | 134 | superseded by `EdgeSampler` (was ISERDESE2-blocked) | — |
| `oversampling_iserdes` | 108 | superseded (resolution analysis: 1x sampling + 512-tap averaging = ~0.02 cent) | — |
| `iserdes_ddr` | 123 | superseded | — |
| `clock_domain_adapter` | 65 | no | — |

Full suite: **24/24 tests pass** (tasty + hedgehog; the end-to-end cases drive
raw square-wave oscillators through the complete chain and recover the exact
theoretical period). Clash-generated VHDL elaborates under GHDL (`make sim`).

## Measured on ECP5 LFE5U-85F (85,640 LUT4 / 208 BRAM / 156 DSP)

Through `yosys synth_ecp5` + `nextpnr-ecp5`, 100 MHz constraint:

| Module | LUT4 | FF | DSP | BRAM | Fmax |
|---|---|---|---|---|---|
| `iir_nstage_pow2k` — SV hand-written | 175 | 67 | 0 | 0 | 132 MHz |
| `iir_nstage_pow2k` — Clash, naive (Vec-in-state) | 519 | 307 | 0 | 0 | 109 MHz |
| **`iir_nstage_pow2k` — Clash, `asyncRam` idiom** | **175** | **67** | 0 | 0 | 129 MHz |
| `edge_to_pulse_position` — SV | 25 | 37 | 0 | 0 | 328 MHz |
| `delay_diff_filter` — SV (defaults) | 241 | 34 | 0 | 0 | 142 MHz |
| `fft512_r2sdf` — Clash, verified + pipelined | 3,537 | 3,729 | 28 | 10 | **123.6 MHz PASS** |
| `theremin_top` — complete instrument, osc pins → audio (linear PitchMap) | 1,816 | 452 | 0 | 2 | 86.7 MHz (**PASS at 75**) |
| `cu_gui_top` — instrument + musical NoteMap + AmpMap volume + UART, **iCE40 HX8K** (Alchitry Cu) | 5,473 LC | — | 0 | 19 | 52.1 MHz (**PASS at 50**) |
| `audio_nco` | 38 | 32 | 0 | 0 | 294 MHz |
| `audio_dsm_dac` | 25 | 17 | 0 | 0 | 348 MHz |

**The memory-idiom lesson, confirmed twice:** `DelayDiffFilter` originally
held its two 512-deep buffers as `Vec`s in Moore state — the sensor top
measured 27.7k LUT4 / 23.5k FF and would not route at 100 MHz. Rewritten on
`blockRam` (pinned by a cycle-exact equivalence test), the complete
`theremin_top` is **1,816 LUT4 / 452 FF / 2 BRAM — a 20x reduction** — and
closes at 75 MHz (Fmax 86.7; the critical path is the 36-bit pitch IIR, and
75 MHz still gives ~0.055-cent period resolution, ~100x below audibility).
Rule: `Vec` in register state is for small banks only; memories go in
`asyncRam`/`blockRam`.

**The Clash-viability headline:** with the right idiom (`asyncRam` for a
distributed-RAM state bank instead of a `Vec` in Moore state), the Clash IIR
synthesises to *exactly* the hand-written SV's resource count — 175 LUT4 /
67 FF, `TRELLIS_DPR16X4` inferred identically, Fmax within 2% — while being
cycle-exact-verified against a property-tested pure model. The 3x penalty of
the naive version was idiom, not language.

**The MAIDEN sizing headline:** the streaming FFT is 4.2% of the part's LUT4s
against the behavioral estimate's 139k (166% of the part), with the work moved
into DSPs and BRAM — verified against a reference DFT (worst error ~5 LSB) and
timing-clean at 123.6 MHz. History and method in `hardware/BOM.md` Note A.

## MAIDEN radar DSP blocks (new, `src/Maiden/`)

The CW-Doppler chain MAIDEN actually needs, written in Clash with tests and
measured through the same flow (post-route, 100 MHz constraint):

| Block | LUT4 | FF | DSP | BRAM | Fmax | Tests |
|---|---|---|---|---|---|---|
| `Maiden.Cic` (N=3, R=4, I+Q pair) | 272 | 257 | 0 | 0 | 136.0 MHz | 7 |
| `Maiden.Cordic` (16-iter vectoring, pipelined) | 2,989 | 909 | 0 | 0 | 189.5 MHz | 8 |
| `Maiden.Fir` (15-tap transposed) | 570 | 553 | 8 | 0 | 236.4 MHz | 6 |
| `Maiden.Cfar` (CA-CFAR, 2x16 ref + guards) | 296 | 246 | 2 | 0* | 123.6 MHz | 5 |

\* CFAR window storage is distributed RAM (10 `TRELLIS_DPR16X4`), not fabric FFs.

**Full-chain estimate** (CIC pair + 2x FIR + verified FFT + CORDIC + CFAR):
**~8,234 LUT4 (9.8%) / ~6,247 FF / 46 DSP (29%) / 10 BRAM (4.8%)** of the
LFE5U-85F — roughly 10x LUT headroom; DSPs are the tightest resource at under
a third used. FIR uses 8 DSPs, not 15: yosys shares the mirrored-tap products
of the symmetric coefficient set. FIR taps are a representative inverse-sinc
shape pending VT-05's band decision.

`delay_diff_filter` here is at its *default* parameters (64-deep, 20-bit),
which take the distributed-RAM path. The theremin instantiates it 512-deep,
crossing `BRAM_ADDR_BITS_THRESHOLD`, so that instance trades these LUTs for a
block RAM.

**Portability result, independent of Clash:** all three of these are written
for Xilinx Series 7 and place and route on Lattice ECP5 unmodified, well above
100 MHz. `iir_nstage_pow2k`'s 8-entry state bank inferred as
`TRELLIS_DPR16X4` distributed RAM, which is what the SV comment intended on
Series 7.

## The ECP5 boundary

`theremin_sensor_period_measure` is ported *below* its front end. The SV top
instantiates `IDELAYCTRL` and two `oversampling_edge_detector`s built on
`ISERDESE2` — Xilinx primitives with no ECP5 equivalent. Getting sub-clock
edge timing on ECP5 means a redesign around `IDDRX*` / `DELAYG`.

That is a hardware design problem, not a translation problem: a hand-written
VHDL port would hit exactly the same wall. So the Clash module takes the edge
stream as inputs, matching what the detectors would present, and everything
downstream — CDC, pulse-centre averaging, both filter stages, output packing —
is ported and synthesises.

This is itself a finding for MAIDEN: **Clash does not get you out of vendor
primitives**, it only changes what surrounds them.

## Defects found in the upstream SystemVerilog

Porting forced every width to be stated explicitly, which surfaced two real
bugs. Both are reproduced faithfully in the Clash (with comments) rather than
silently fixed, so the ports stay equivalent to what the hardware does today.

1. **Volume converter parameterised with the pitch width.**
   `theremin_sensor_period_measure.sv:331` instantiates the *volume*
   `edge_to_pulse_position` with `.EDGE_POSITION_BITS(PITCH_EDGE_POSITION_BITS)`
   — 23 bits, where the volume path is 21. The 21-bit edge position is
   zero-extended in and the 24-bit result truncated back to 21 on the way out.
   Almost certainly copy-paste from the pitch instance directly above.

2. **Pulse position truncated on connection.** `edge_to_pulse_position`
   outputs `EDGE_POSITION_BITS+1` bits (it sums two edge positions, so the
   carry needs the extra bit), but the top connects it to a signal declared at
   `EDGE_POSITION_BITS`. The MSB is dropped, so a pulse-centre sum that
   overflows wraps.

## Toolchain

Nothing needs admin rights, so all of this runs on the WSL laptop.

- GHC 9.6.7 + cabal 3.14 via ghcup.
- Clash 1.8.5, pinned in `cabal.project` (the series validated against GHC
  9.6; 1.10 is untested here).
- GHDL 7.0.0-dev, Yosys 0.68, nextpnr-ecp5 from the pinned OSS CAD Suite.
  Activate per shell — do **not** put this in `.bashrc`, it shadows the system
  `python3`:

  ```sh
  source ~/tools/oss-cad-suite/environment
  ```

## Commands

```sh
make test    # Haskell behavioural tests (tasty + hedgehog)
make vhdl    # generate VHDL   -> build/vhdl/
make verilog # generate Verilog -> build/verilog/
make sim     # generate VHDL, then analyse + elaborate under GHDL
make synth   # yosys synth_ecp5
make pnr     # nextpnr-ecp5 on the LFE5U-85F
make report  # LUT/FF/BRAM/DSP usage and Fmax

# a different block:
make report TOP=Theremin.Pwm ENTITY=theremin_pwm
```

## Verification approach

1. **Model tests** — every `*Step` function is pure, so behaviour is checked
   as Hedgehog properties over full counter periods with no simulator.
   `iir_nstage_pow2k` is additionally checked against an independently written
   scalar reference chain.
2. **Generated-VHDL check** — `make sim` analyses and elaborates the Clash
   output under GHDL, catching code-generation faults a Haskell-only test
   cannot see.
3. **Place and route** — `make report` gives real area and Fmax on the target
   part, which is the number that decides whether MAIDEN fits.

## Porting notes

Details where a naive translation would have changed behaviour:

- **`RESET` is data, not a reset network.** In `theremin_pwm.sv` and
  `iir_nstage_pow2k.sv`, `RESET` is a synchronous active-high *input*. It is
  kept as an ordinary port rather than mapped to a Clash `Reset`, so the
  generated port list still matches the original.
- **Two independent `if`s, not `if/else`.** The RGB channel logic writes its
  "on" and "off" comparisons as separate non-blocking assignments to the same
  target. For a colour nibble of 0 both fire and the later (off) one wins, so
  nibble 0 means dark. Writing it as `if/else` would silently invert that.
- **The state bank survives reset.** `iir_nstage_pow2k`'s `states[8]` is RAM
  and has no reset in the SV; `filter_en` is what makes that safe. The port
  keeps the RAM contents across reset rather than zeroing them.
- **DC droop is real.** Each IIR stage stops moving once `(x - s) < 2^K`, so
  it settles up to `2^K - 1` short; five stages means a worst-case shortfall
  of 315 LSB. This is a property of the shift-based design, present in the
  hand-written SV too — not a porting artefact. The test asserts the bound
  rather than pretending the gain is exactly one.
