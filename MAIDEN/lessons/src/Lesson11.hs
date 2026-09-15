-- Lesson 11: area is a measurement, not an opinion.
--
--     Build:  cabal exec -- clash -isrc Lesson11 --vhdl
--     Output: vhdl/Lesson11.topEntity/topEntity.vhdl
--
-- Add `Lesson11` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson11 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Every sizing argument you will ever have about an FPGA design ends the same way: somebody
-- runs the flow and reads the number. This lesson is about ending the argument early. The
-- open toolchain -- yosys for synthesis, nextpnr for place and route -- runs on the same
-- laptop that runs `cl`, takes seconds on a lesson-sized block, and prints exactly the five
-- numbers that decide whether a design fits: LUTs, flip-flops, DSPs, block RAMs, Fmax.
--
-- No board is attached, and none is needed. Place and route targets a *part*, not a board;
-- the numbers below are for the Lattice ECP5 LFE5U-85F (83,640 LUT4s), the largest part in
-- the family, and they are as real as they would be with the chip on the desk.

------------------------------------------------------------------------------------------------
-- The block under measurement: a lag-512 autocorrelation MAC
------------------------------------------------------------------------------------------------
--
-- Chosen so that every column of the report is nonzero: a block RAM delay line (BRAM), an
-- 18x18 multiply (DSP), a 48-bit accumulator (FF), and the adders and address counter (LUT).
-- A block that exercises only LUTs teaches you to read one column; this one makes you read
-- all four.
--
-- The circuit multiplies the input by itself 512 samples ago and accumulates the products --
-- the inner loop of an autocorrelator, the standard trick for finding a period you cannot
-- trigger on. `blockRam` is read-first (a read of the address being written returns the OLD
-- contents), so reading and writing the same circulating address gives back the value stored
-- exactly 512 cycles earlier. The register on `x` matches the RAM's one-cycle read latency
-- (Lesson 5's discipline: the latency is part of the design, not an inconvenience).

macAutocorr ::
  HiddenClockResetEnable dom =>
  Signal dom (Signed 18) ->
  Signal dom (Signed 48)
macAutocorr x = acc
  where
    addr    = register (0 :: Unsigned 9) (addr + 1)
    delayed = blockRam (replicate d512 0) addr (Just <$> bundle (addr, x))
    x1      = register 0 x
    prod    = mul <$> x1 <*> delayed
    acc     = register 0 (acc + (resize <$> prod))

-- 48 bits of accumulator against a 36-bit product leaves 12 bits of headroom: 4,096 maximal
-- products before the sum can wrap. Sizing that headroom is Lesson 10's business; here it
-- exists so the flow has a wide adder to place.
--
-- The datapath, drawn. Every wire in the figure is a subexpression:
--
--     x ──┬──▶┌──────────────┐   x1     ┌──────────────┐
--         │   │ register 0   │─────────▶│              │
--         │   └──────────────┘          │     mul      │ prod  ┌────────┐
--         │   ┌──────────────┐ delayed  │  18x18 → 36  │──────▶│ resize │
--         └──▶│ blockRam 512 │─────────▶│              │       │ 36→48  │
--     addr ──▶│ (read-first) │          └──────────────┘       └───┬────┘
--             └──────────────┘                                     │
--                                            ┌─────────────────────┘
--                                            ▼
--                                       ┌─────────┐      ┌──────────────┐
--                             ┌────────▶│    +    │─────▶│ register 0   │──┬──▶ result
--                             │         └─────────┘      │ (acc)        │  │
--                             │                          └──────────────┘  │
--                             └────────────────────────────────────────────┘
--
--     prod = mul <$> x1 <*> delayed
--            │       │      └────── the delay-line output (bottom path)
--            │       └───────────── the registered input (top path)
--            └───────────────────── the multiplier box
--
--     acc = register 0 (acc + (resize <$> prod))
--           │           │      └──────────────── the 36-to-48 widening
--           │           └─────────────────────── the feedback wire into `+`
--           └─────────────────────────────────── the accumulator register, and result

-- A pipelined variant, measured in "Timing is a measurement too" below: same datapath, two
-- pipeline stages dropped in -- registers in front of the multiplier and one behind it.
-- `x2` exists only to keep the two multiplier operands aligned after `dReg` delays the
-- bottom path: pipeline registers are added in matched pairs or the answer changes.

macAutocorrP ::
  HiddenClockResetEnable dom =>
  Signal dom (Signed 18) ->
  Signal dom (Signed 48)
macAutocorrP x = acc
  where
    addr    = register (0 :: Unsigned 9) (addr + 1)
    delayed = blockRam (replicate d512 0) addr (Just <$> bundle (addr, x))
    x1      = register 0 x
    dReg    = register 0 delayed              -- give the RAM's slow output its own cycle
    x2      = register 0 x1                   -- ... and keep the operands aligned
    prod    = register 0 (mul <$> x2 <*> dReg)  -- register the product before the wide add
    acc     = register 0 (acc + (resize <$> prod))

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Signed 18) ->
  Signal System (Signed 48)
topEntity clk rst en = exposeClockResetEnable macAutocorr clk rst en

--     topEntity clk rst en = exposeClockResetEnable macAutocorrP clk rst en

------------------------------------------------------------------------------------------------
-- Running the flow
------------------------------------------------------------------------------------------------
--
-- From the lessons directory, four commands (`mkdir -p build` once, first). The `source`
-- activates the pinned OSS CAD Suite -- per shell, not in .bashrc, it shadows the system
-- python3:
--
--     source ~/tools/oss-cad-suite/environment
--     cabal exec -- clash -isrc Lesson11 --verilog
--     yosys -p 'read_verilog verilog/Lesson11.topEntity/topEntity.v;
--               synth_ecp5 -top topEntity -json build/lesson11.json'
--     nextpnr-ecp5 --85k --package CABGA381 --freq 100 \
--         --json build/lesson11.json --textcfg build/lesson11.config
--
-- The same Clash source that `cl` checks into VHDL emits Verilog with one flag; the open
-- flow consumes the Verilog. `--85k --package CABGA381` names the real part; `--freq 100`
-- states the timing constraint the router must be judged against.
--
-- What nextpnr printed, measured 27 Aug 2026 (yosys 0.68, nextpnr-0.11.1), abridged to the
-- lines that matter:
--
--     Info: Device utilisation:
--     Info:               DP16KD:       1/    208     0%
--     Info:           MULT18X18D:       1/    156     0%
--     Info:           TRELLIS_FF:      75/  83640     0%
--     Info:         TRELLIS_COMB:      69/  83640     0%
--
--     ERROR: Max frequency for clock '$glbnet$clk$TRELLIS_IO_IN':
--         66.12 MHz (FAIL at 100.00 MHz)
--
-- (That ERROR is one line in the log, wrapped here to fit; nextpnr also exits nonzero, so a
-- failed constraint stops a Makefile the way a failed test does.)
--
-- Read the utilisation against the diagram: one DP16KD is the delay line, one MULT18X18D is
-- `mul`, 75 flip-flops are exactly 48 (`acc`) + 18 (`x1`) + 9 (`addr`), and the 69 LUT4s
-- are dominated by the 48-bit carry chain of `+` plus the address increment. Every number
-- has a subexpression to point at -- that is what makes the report readable rather than
-- merely printable.
--
-- And then the fifth number says no. The critical path report explains itself:
--
--     Info: Critical path report for clock '$glbnet$clk$TRELLIS_IO_IN' (posedge -> posedge):
--     Info:       type curr  total name
--     Info:   clk-to-q  5.61  5.61 Source result_RAM.0.0.DOA3
--     Info:    routing  1.67  7.28 Net result[3] (73,46) -> (73,34)
--     Info:      logic  3.93  11.20 Source c$acc_app_arg_1_MULT18X18D_P9.P2
--     ...       (the 48-bit carry chain, many small steps)
--     Info:      setup  0.00  15.12 Source acc_TRELLIS_FF_Q_13.DI
--
-- The whole datapath -- RAM output (5.61 ns clock-to-q by itself!), multiplier, widening,
-- 48-bit add -- runs in a single cycle, 15.12 ns end to end: 66 MHz. The tool is not
-- objecting to the design; it is measuring it. The diagram shows the fix: nothing forces
-- those boxes to share a cycle.

------------------------------------------------------------------------------------------------
-- Timing is a measurement too
------------------------------------------------------------------------------------------------
--
-- `macAutocorrP` above is the same datapath with a register after the RAM and a register
-- after the multiplier. Point topEntity at it (swap the two lines below the definition) and
-- re-run the identical flow. Measured 27 Aug 2026, same abridgement:
--
--     Info:               DP16KD:       1/    208     0%
--     Info:           MULT18X18D:       1/    156     0%
--     Info:           TRELLIS_FF:     147/  83640     0%
--     Info:         TRELLIS_COMB:      69/  83640     0%
--
--     Info: Max frequency for clock '$glbnet$clk$TRELLIS_IO_IN':
--         135.81 MHz (PASS at 100.00 MHz)
--
-- Fmax doubled, 66.12 -> 135.81 MHz, and the price was flip-flops alone: 75 -> 147, a rise
-- of exactly 72 = 36 (`prod`) + 18 (`dReg`) + 18 (`x2`), with the LUT4 count unchanged at
-- 69. Flip-flops are the resource the ECP5 has most of and the design was using least. The
-- output now arrives two cycles later -- latency is the currency pipelining spends, and for
-- a streaming accumulator two cycles is free.

------------------------------------------------------------------------------------------------
-- FAILURE: the accumulator that skipped its resize
------------------------------------------------------------------------------------------------
--
--     macAutocorr x = acc
--       where
--         addr    = register (0 :: Unsigned 9) (addr + 1)
--         delayed = blockRam (replicate d512 0) addr (Just <$> bundle (addr, x))
--         x1      = register 0 x
--         prod    = mul <$> x1 <*> delayed
--         acc     = register 0 (acc + prod)                    -- the mistake is HERE
--
--     src/Lesson11.hs:53:15: error: [GHC-83865]
--         * Couldn't match type `36' with `48'
--           Expected: Signed 18 -> Signed 18 -> Signed 48
--             Actual: Signed 18 -> Signed 18 -> MResult (Signed 18) (Signed 18)
--         * In the first argument of `(<$>)', namely `mul'
--           In the first argument of `(<*>)', namely `mul <$> x1'
--           In the expression: mul <$> x1 <*> delayed
--        |
--     53 |     prod    = mul <$> x1 <*> delayed
--        |               ^^^
--
-- Compiled and confirmed 27 Aug 2026. Two things about this error are worth a minute each.
--
-- First, the substance. `mul` produces the full 36-bit product -- that is its whole purpose;
-- `*` at type `a -> a -> a` would wrap at 18 bits -- and a 36-bit value cannot ride a 48-bit
-- adder without someone saying how the extra bits are filled. (`MResult (Signed 18)
-- (Signed 18)` is the type-family spelling of `Signed 36`: the width of a full product,
-- computed from the operand widths.) Verilog would sign-extend silently here -- and silently
-- *truncate* if the widths ran the other way, with the same absence of comment in both
-- directions. Clash makes you write the `resize`, one word of boilerplate in exchange for
-- never wondering which of the two happened.
--
-- Second, the location. The mistake is on the `acc` line; the error points at `mul`, one
-- line up. Inference works outward from the demand: `acc + prod` forces `prod` to be 48
-- bits wide, and the first definition that cannot deliver that is `mul`. Type errors
-- surface where the contradiction is *discovered*, not where you would assign blame -- on a
-- two-line example that is a curiosity, on a two-hundred-line design it is the reason you
-- read the whole "Expected/Actual" pair before hunting by line number.

------------------------------------------------------------------------------------------------
-- The headline: why measuring is not optional
------------------------------------------------------------------------------------------------
--
-- These numbers are from Jim's MAIDEN work (hardware/BOM.md Note A and
-- theremin/clash/README.md), all through the same yosys + nextpnr flow on the same LFE5U-85F.
--
-- A 512-point FFT written behaviourally -- the transform stated as a computation and left to
-- the synthesiser -- came out at ~139k LUT4: 166% of the 83,640 on the largest ECP5. Not
-- tight, not "needs optimisation": physically unbuildable in this family, and no part exists
-- to escalate to. The same transform restructured as a streaming radix-2 single-delay-
-- feedback pipeline measured 3,537 LUT4 (4.2%), 28 DSP, 10 BRAM, timing-clean at 123.6 MHz:
--
--     LUT4 on the LFE5U-85F
--     behavioural, unrolled  ████████████████████████████████████████████████▏ ~139k (166%)
--     the part itself        █████████████████████████████▏ 83,640 (100%)
--     streaming R2SDF        █▏ 3,537 (4.2%)
--
-- Roughly 30x -- and the work did not vanish, it moved into the DSP and BRAM columns that
-- the behavioural version's estimate had left at zero. That is the deep reason a LUT count
-- alone is not an area figure: the report has five columns because the part has five
-- currencies, and a design is only "smaller" if you have read all of them.
--
-- Two more findings from the same work, both of which contradict reasonable intuition, both
-- settled by running the flow rather than arguing:
--
--   * Pipelining the FFT *reduced* its LUT count while fixing timing. Registers between
--     stages let the router stop duplicating logic to meet the constraint.
--
--   * The complete theremin instrument (theremin_top, 1,816 LUT4 on ECP5) was re-run
--     through the identical flow with `synth_ice40` + `nextpnr-ice40` against three iCE40
--     parts (results/design-notes/ice40-theremin-fit.md): HX8K, 2,432 LC, PASS at 48 MHz;
--     UP5K, fits but Fmax 21.65 MHz; HX1K, 190% of the part, will not place. One source,
--     four verdicts. Which board hosts a design is a measurement per part, not a property
--     of the design.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Double the delay line to 1024 (`Unsigned 10`, `d1024`) and re-run the flow. Predict
--    which columns move before you look. (1024 x 18 bits is exactly one 18-kbit DP16KD --
--    did BRAM move?)
--
-- 2. Rewrite the delay line as a `Vec 512` held in a register -- Lesson 5's anti-pattern --
--    and measure it. Where did the BRAM column's contents reappear, and at what exchange
--    rate?
--
-- 3. With topEntity on `macAutocorrP`, raise `--freq` until nextpnr fails the constraint
--    again, and read the new critical path. Which box in the diagram is the long pole now
--    that the RAM and the multiplier each have their own cycle -- and is there a register
--    left to buy it out with, or is 48 bits of carry just 48 bits of carry?
