-- Lesson 04: modular design -- instantiation is application; generics are type-level numbers.
--
--     Build:  cabal exec -- clash -isrc Lesson04 --vhdl
--     Output: vhdl/Lesson04.topEntity/topEntity.vhdl
--
-- Add `Lesson04` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson04 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Half of a Verilog textbook is plumbing: breaking buses out, declaring intermediate wires,
-- writing port maps, keeping instance names straight. All of it exists because a module
-- boundary in Verilog is a textual convention, so connecting things is a separate activity
-- with its own error modes -- ports connected positionally in the wrong order, a wire
-- declared 8 bits wide feeding a 12-bit port, an output left dangling, all elaborating
-- without complaint.
--
-- A Clash block is a function. Instantiating it is calling it. The port map is the argument
-- list, the instance "name" is the let-binding you give the result, and an intermediate wire
-- is just a name for a subexpression -- it cannot have a width other than what flows through
-- it, because its width is not declared anywhere. It is inferred, and checked at every use.
--
-- A generic becomes a *type-level number*. That is the part with teeth, because the compiler
-- can do arithmetic on it: widths downstream of a parameter are computed from it, and a block
-- that disagrees about the arithmetic does not build.

------------------------------------------------------------------------------------------------
-- The block: a decimating boxcar accumulator, ratio as a parameter
------------------------------------------------------------------------------------------------
--
-- Sum r consecutive samples, emit the sum, repeat: a boxcar decimator. The interesting part
-- is the type. Summing r values of inW bits needs CLog 2 r extra bits (ceiling log base 2),
-- and the output type SAYS so:

type SumWidth inW r = inW + CLog 2 r

boxcar ::
  forall r inW dom.
  (HiddenClockResetEnable dom, KnownNat inW, KnownNat r, 1 <= r) =>
  SNat r ->
  Signal dom (Unsigned inW) ->
  Signal dom (Maybe (Unsigned (SumWidth inW r)))
boxcar SNat = mealy step (0, 0)
 where
  step ::
    (Unsigned (SumWidth inW r), Index r) ->
    Unsigned inW ->
    ((Unsigned (SumWidth inW r), Index r), Maybe (Unsigned (SumWidth inW r)))
  step (acc, phase) x
    | phase == maxBound = ((0, 0), Just acc')
    | otherwise         = ((acc', phase + 1), Nothing)
   where
    acc' = acc + resize x

-- Notes, densest first:
--
--   * `SNat r` is the ratio as a term you can pass -- the value-level shadow of the type-level
--     number. The caller writes `boxcar (SNat @4)`. That one argument is the whole generic.
--   * `Index r` counts 0..r-1 and CANNOT hold r. The phase counter's width follows the ratio
--     for free, and `phase == maxBound` is the wrap test whatever r is.
--   * The `if`/guards on `phase` are legal here, where they were banned in Lesson 02: `step`
--     is a pure function on values, so branching is just choosing what the mux computes.
--     Signals are what you cannot branch on.
--   * `resize x` widens (Lesson 01): the checker knows inW <= SumWidth inW r because the
--     type-level arithmetic says so.
--
-- This mirrors MAIDEN's CIC decimator (theremin/clash/src/Maiden/Cic.hs), which takes its
-- order n and ratio r as type parameters and computes its internal width as
-- `inW + n * CLog 2 r`. Per the decimation audit (results/design-notes/decimation-audit.md),
-- the same source serves R=4 at 24.125 GHz and R=8 at 10.525 GHz: change one type argument
-- and every internal width re-derives itself.

------------------------------------------------------------------------------------------------
-- Composition: the I/Q pair, and where the port map went
------------------------------------------------------------------------------------------------
--
-- MAIDEN's chain is quadrature, so blocks get instantiated twice, I and Q. In Verilog that is
-- two instance blocks and two chances to cross the wires. Here it is two applications:

iqBoxcar ::
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned 12) ->
  Signal dom (Unsigned 12) ->
  Signal dom (Maybe (Unsigned 14), Maybe (Unsigned 14))
iqBoxcar iIn qIn = bundle (iOut, qOut)
 where
  iOut = boxcar (SNat @4) iIn
  qOut = boxcar (SNat @4) qIn

-- The datapath, drawn. Every box is an application, every wire is a name:
--
--                 ┌──────────────────┐
--     iIn ───────▶│  boxcar (SNat 4) │───────▶ iOut : Maybe (Unsigned 14)
--                 └──────────────────┘                        ┐
--                 ┌──────────────────┐                        ├─▶ bundle -> one output port
--     qIn ───────▶│  boxcar (SNat 4) │───────▶ qOut           ┘
--                 └──────────────────┘
--
--     iOut = boxcar (SNat @4) iIn
--     │            │         │
--     │            │         └── the wire entering the upper box
--     │            └──────────── the generic: ratio 4, so 12 + CLog 2 4 = 14 bits out
--     └───────────────────────── the wire leaving it -- the "instance name" is just this name
--
-- What is absent: instance names, `.IN_VALUE(iIn)` port maps, and the fourteen `wire [13:0]`
-- declarations between here and the top. Swapping iIn/qIn is still possible -- they are the
-- same type -- but connecting iOut back into a 12-bit port, dropping a connection, or
-- disagreeing about a width is not, and those are the wiring bugs that survive review.
--
-- `bundle` packs a tuple of Signals into a Signal of tuples -- the boundary between "two
-- wires" and "one wire carrying a pair" that Verilog blurs with concatenation. Its inverse is
-- `unbundle`. The 12-bit input width, for the record, is the MCP3202 ADC sample width used
-- across MAIDEN's front end; the ratio 4 is the decimation audit's default. The output width
-- 14 is not chosen -- it is computed, and writing anything else is FAILURE 2.

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Unsigned 12) ->
  Signal System (Unsigned 12) ->
  Signal System (Maybe (Unsigned 14), Maybe (Unsigned 14))
topEntity = exposeClockResetEnable iqBoxcar

------------------------------------------------------------------------------------------------
-- FAILURE 1: a ratio the arithmetic cannot satisfy
------------------------------------------------------------------------------------------------
--
-- The signature demands 1 <= r. Ask for a ratio of zero:
--
--     iqBoxcar iIn qIn = bundle (iOut, qOut)
--      where
--       iOut = boxcar (SNat @0) iIn
--       ...
--
--     src/Lesson04.hs:94:10: error: [GHC-64725]
--         * Cannot satisfy: 1 <= 0
--         * In the expression: boxcar (SNat @0) iIn
--           In an equation for `iOut': iOut = boxcar (SNat @0) iIn
--
-- Compiled and confirmed 27 Aug 2026. Five words -- "Cannot satisfy: 1 <= 0" -- which for a
-- type-level-arithmetic error is remarkable brevity (thank the type-lits solver plugins in
-- lessons.cabal; without them this class of constraint produces far worse). Note it points at
-- the CALL, not the internals of boxcar.
--
-- A Verilog parameter of 0 elaborates into a [-1:0] range or a zero-width wire, and the
-- diagnostic -- if any -- arrives from deep inside the module, phrased in terms of its
-- internals. Here the constraint is part of the block's signature: the demand is visible at
-- the call site, in the caller's terms, before anything is elaborated.

------------------------------------------------------------------------------------------------
-- FAILURE 2: disagreeing with the computed width
------------------------------------------------------------------------------------------------
--
-- Change the ratio to 8 but leave the declared output width at 14. Ratio 8 makes the sum
-- width 12 + CLog 2 8 = 15.
--
--     iqBoxcar ::
--       HiddenClockResetEnable dom =>
--       Signal dom (Unsigned 12) ->
--       Signal dom (Unsigned 12) ->
--       Signal dom (Maybe (Unsigned 14), Maybe (Unsigned 14))   -- stale width
--     iqBoxcar iIn qIn = bundle (iOut, qOut)
--      where
--       iOut = boxcar (SNat @8) iIn
--       qOut = boxcar (SNat @8) qIn
--
--     src/Lesson04.hs:92:34: error: [GHC-83865]
--         * Couldn't match type `15' with `14'
--           Expected: Signal dom (Maybe (Unsigned 14))
--             Actual: Signal dom (Maybe (Unsigned (SumWidth 12 8)))
--         * In the expression: qOut
--           In the first argument of `bundle', namely `(iOut, qOut)'
--
-- Compiled and confirmed 27 Aug 2026. Read the Actual line: the compiler did the arithmetic
-- (SumWidth 12 8 is 15) AND kept the formula in the message, so the error names both the
-- number that changed and where it came from.
--
-- This is Lesson 01's width discipline compounding through a hierarchy. In Verilog, doubling
-- a decimation parameter widens nothing by itself; every wire and port downstream that
-- someone sized by hand for the old ratio silently truncates the new MSB. Here the width is
-- *derived* from the parameter, so the change either propagates completely or stops the
-- build at each place that baked in the old number. The error list is the complete list of
-- stale assumptions -- which is exactly what you want handed to you after changing a generic.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Fix FAILURE 2 properly: make iqBoxcar polymorphic in the ratio (take `SNat r`, return
--    `Maybe (Unsigned (SumWidth 12 r))`) so topEntity picks the ratio in exactly one place.
--    Rebuild at ratio 8 and confirm the VHDL port widened itself.
--
-- 2. The output is the SUM; the average needs a divide by r. For power-of-two r that is a
--    shift, i.e. dropping CLog 2 r low bits. Write `avg` returning `Unsigned inW` using
--    `shiftR` and `resize` -- and note which end `resize` takes bits from (Lesson 01: check,
--    don't assume).
--
-- 3. Chain two boxcars: feed the Just-outputs of a ratio-4 stage into a ratio-2 stage to get
--    a ↓8 in two hops (`regMaybe` or a mux on the valid holds the second stage's input
--    between strobes -- or gate its Enable, if you read Lesson 02's exercise 3). What is the
--    output width of the composite, and who computed it?
