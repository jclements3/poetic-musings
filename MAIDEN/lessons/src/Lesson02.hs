-- Lesson 3: a register is a delay; Signal is a wire over all time.
--
--     Build:  cabal exec -- clash -isrc Lesson02 --vhdl
--     Output: vhdl/Lesson02.topEntity/topEntity.vhdl
--
-- Add `Lesson02` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson02 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Lesson 1 built combinational logic: a function from a value to a value. Adding a clock
-- changes the type, not just the body.
--
--     Unsigned 8               a value
--     Signal dom (Unsigned 8)  that value on every clock edge, forever
--
-- `Signal dom a` is an infinite stream of `a`, one per tick of clock domain `dom`. It is NOT
-- an `a`. That distinction is enforced, and it is what this lesson is about.
--
-- `register` is the only primitive that matters here:
--
--     register :: HiddenClockResetEnable dom => a -> Signal dom a -> Signal dom a
--                                               ^          ^                ^
--                                        reset value    input        output, delayed 1 cycle
--
-- One clock of delay. That is the whole of it. A D flip-flop, typed.

------------------------------------------------------------------------------------------------
-- A counter, and the knot it ties
------------------------------------------------------------------------------------------------
--
-- Read the `where` clause as a circuit, not as a computation: the output of the register
-- feeds an adder whose result feeds the register's input. A loop in hardware. Haskell's
-- laziness lets you write it as a loop in the source too -- `r` appears on both sides -- and
-- it terminates because `register` does not need its input until the next cycle.
--
-- In Verilog terms it is:
--
--     always @(posedge clk) r <= r + 1;
--
-- with the reset value moved into the declaration where it cannot be forgotten.

counter :: HiddenClockResetEnable dom => Signal dom (Unsigned 8)
counter = r
  where
    r = register 0 (r + 1)

-- The loop, drawn. Every wire in the figure is a subexpression:
--
--     ┌──────────────────────────────────────────────┐
--     │                                              │
--     │      ┌─────┐        ┌──────────────┐         │
--     └─────▶│  +1 │───────▶│   register   │─────┬───┘
--            └─────┘        │   reset = 0  │     │
--                       clk─▶              │     ▼
--                       rst─▶              │   result
--                           └──────────────┘
--
--     r = register 0 (r + 1)
--       │             │  │
--       │             │  └── the feedback path drawn above
--       │             └───── the adder
--       └─────────────────── the flip-flop, and the wire it drives

-- Why `r + 1` type-checks: Signal has a Num instance, so arithmetic lifts elementwise over
-- the stream. `+` on two Signals is an adder.

------------------------------------------------------------------------------------------------
-- The top entity: hidden constraints become real ports
------------------------------------------------------------------------------------------------
--
-- `HiddenClockResetEnable dom` is a constraint, and constraints are not hardware. Clash
-- cannot generate an entity for something with one still attached. `exposeClockResetEnable`
-- discharges it by turning it into three explicit arguments -- which become three explicit
-- ports.
--
-- `System` is a predefined domain (100 MHz, rising edge, synchronous active-high reset).
-- Later lessons define their own.

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Unsigned 8)
topEntity = exposeClockResetEnable counter

-- Generated VHDL now has clk/rst/en ports and a clocked process, where Lesson 1 had a bare
-- concurrent assignment. Go read it.

------------------------------------------------------------------------------------------------
-- FAILURE 1: treating a Signal as a value
------------------------------------------------------------------------------------------------
--
--     counter :: HiddenClockResetEnable dom => Signal dom (Unsigned 8)
--     counter = r
--       where
--         r       = register 0 (r + 1)
--         stopped = r == 255                            -- ERROR
--
--     src/Lesson02.hs:54:17: error: [GHC-39999]
--         * Could not deduce `Eq (Signal dom (Unsigned 8))'
--             arising from a use of `=='
--
-- Compiled and confirmed 27 Aug 2026 (an earlier draft of this lesson quoted a type-mismatch
-- error here from memory; the compiler actually says the above). The message is a MISSING
-- INSTANCE, and that absence is deliberate: `==` would have to compare two infinite streams
-- and answer with one Bool -- there is no single moment at which to compare. Clash simply
-- refuses to define it. The lifted operator `.==.` gives you `Signal dom Bool`, a wire that
-- is high on some cycles and low on others -- which is what a comparator actually is.
--
-- Lifted forms:
--
--     .==.   ./=.   .<.   .>.   .<=.   .>=.   .&&.   .||.

------------------------------------------------------------------------------------------------
-- FAILURE 2: branching on a wire
------------------------------------------------------------------------------------------------
--
--     counter10 = r
--       where
--         r = register 0 (if r .==. 9 then 0 else r + 1)   -- ERROR
--
--     src/Lesson02.hs:125:9: error: [GHC-25897]
--         * Couldn't match type `dom1' with `dom'
--             arising from a functional dependency between constraints:
--               `?clock::Clock dom1'
--                 arising from a use of `register' at src/Lesson02.hs:125:9-16
--               `?clock::Clock dom'
--                 arising from the type signature for: counter10 ...
--
-- Compiled and confirmed 27 Aug 2026 -- and the message is NOT the tidy "expected Bool, got
-- Signal dom Bool" an earlier draft promised. What happens: `if` demands a plain Bool, so
-- inference stops unifying `r` with the surrounding domain and the hidden-clock constraint
-- tears in two (`dom1` vs `dom`). The root cause is still "you branched on a wire"; the
-- symptom is a constraint tangle. Worth knowing, because you will see this shape again: when
-- a Signal is used where a value belongs, the error often surfaces in the hidden clock
-- plumbing rather than at the `if` itself. The mechanics are still the semantics of
-- hardware:
--
-- `if` picks one branch and discards the other. Hardware cannot do that. Both the constant 0
-- and the incrementer exist as gates, permanently, and a select line chooses which reaches
-- the output this cycle. There is nothing to discard.
--
-- So you write the mux, because the mux is what is there:
--
--     mux :: Signal dom Bool -> Signal dom a -> Signal dom a -> Signal dom a

counter10 :: HiddenClockResetEnable dom => Signal dom (Unsigned 4)
counter10 = r
  where
    r = register 0 (mux (r .==. 9) 0 (r + 1))

-- Verilog lets you write the `if` and infers the mux silently. That is convenient right up to
-- the point where you write an `if` with a missing `else` and get a latch you did not ask
-- for. Here the latch has no way to appear: `mux` takes three arguments and the type checker
-- counts.

------------------------------------------------------------------------------------------------
-- NOT A FAILURE: a top entity that still has a hidden constraint (a corrected claim)
------------------------------------------------------------------------------------------------
--
--     topEntity :: HiddenClockResetEnable System => Signal System (Unsigned 8)
--     topEntity = counter
--
-- An earlier draft claimed this compiles as Haskell but fails in Clash. Tested 27 Aug 2026:
-- it does NOT fail. Clash 1.8.5 discharges the hidden constraint itself and the generated
-- entity gains real clock and reset ports (as a record-typed port in the VHDL):
--
--     port(-- clock
--          d_0_0  : in Lesson02_topEntity_types.clk_System;
--          d_1_0  : in Lesson02_topEntity_types.rst_System;
--          ...
--
-- So `exposeClockResetEnable` is about explicitness and port naming, not about making
-- synthesis possible: with it, you choose the ports and their order; without it, Clash
-- chooses. Every lesson in this series exposes them explicitly for that reason. The
-- mirror-image function is `withClockResetEnable`, which supplies clock/reset/enable
-- instead -- that is what you use in simulation, below.

------------------------------------------------------------------------------------------------
-- Run it without hardware
------------------------------------------------------------------------------------------------
--
--     cabal repl
--     ghci> import Clash.Prelude
--     ghci> sampleN @System 12 (withClockResetEnable clockGen resetGen enableGen counter)
--
-- `sampleN` runs the circuit for n cycles and hands back the outputs as a list. No board, no
-- simulator, no testbench file -- and `counter` is an ordinary Haskell value you can poke at
-- in a repl.
--
-- Expect the first value or two to repeat: `resetGen` holds reset asserted at the start, so
-- the register sits at its reset value before counting begins. That is the real behaviour of
-- the real circuit, not a simulation artefact, and noticing it here is cheaper than noticing
-- it on a scope.
--
-- This is the seed of the verification chapter. The whole property-test discipline --
-- comparing a synthesisable implementation against a pure reference model, cycle for cycle --
-- is built on the fact that `sampleN` needs nothing but GHC.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Point topEntity at counter10 and diff the generated VHDL against the plain counter.
--    Find the comparator and the mux.
--
-- 2. Write a counter that counts DOWN from 9 to 0 and wraps. Note that `r .==. 0` before
--    decrementing and `r .==. 9` after are different circuits with different reset
--    behaviour -- pick deliberately.
--
-- 3. Add an enable: take a `Signal dom Bool` argument and hold the count when it is low.
--    Two ways to do it -- `mux` on the register input, or `regEn`. Build both and compare
--    the VHDL. One of them is what the `Enable` port already does for you, which is worth
--    understanding before you start using clock gating for flow control.
