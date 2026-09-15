-- Lesson 03: state machines -- a state is a datatype, a machine is one pure function.
--
--     Build:  cabal exec -- clash -isrc Lesson03 --vhdl
--     Output: vhdl/Lesson03.topEntity/topEntity.vhdl
--
-- Add `Lesson03` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson03 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- A Verilog state machine is a ritual with three parts: a `localparam` block inventing bit
-- encodings for the states, a state register, and a `case` over the encodings -- split across
-- one, two, or three `always` blocks depending on which book you learned from. Every part of
-- that ritual is a place to be wrong: a state constant used before it is declared, a `case`
-- arm missing, a bit pattern that is a legal register value but not a legal state.
--
-- In Clash a state is a datatype and the machine is one pure function:
--
--     step :: state -> input -> (state, output)
--
-- `mealy` turns that function plus a reset state into a circuit:
--
--     mealy :: (NFDataX s, HiddenClockResetEnable dom)
--           => (s -> i -> (s, o)) -> s -> Signal dom i -> Signal dom o
--
-- The state register, the next-state mux tree, and the output logic all fall out of the one
-- function. There is nothing else to keep consistent with it.
--
-- A whole chapter of the Verilog literature evaporates here. Readler teaches the SR flop and
-- counter twice -- as two always blocks, then as one -- and the state machine twice again,
-- because in Verilog *which block owns which register* and *blocking vs non-blocking
-- assignment* are real hazards with a scheduling semantics you must internalise or be bitten
-- by. A mealy transition function is one pure function; evaluation order cannot be observed,
-- so there is no how-many-blocks question to have an opinion about. The chapter is not
-- summarised here. It is deleted.

------------------------------------------------------------------------------------------------
-- The machine: a pulse-width measurer
------------------------------------------------------------------------------------------------
--
-- The front of the theremin sensor chain is variations on this machine: watch a comparator
-- bit, time something, report a number. This one reports how many cycles the input was high,
-- on the cycle it goes low.

data PwState
  = WaitHigh              -- input is low; nothing in flight
  | Timing (Unsigned 16)  -- input is high; cycles high so far
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- Look at what the payload buys. The Verilog version of this machine is a state register PLUS
-- a separate 16-bit counter register that is only *meaningful* in the timing state -- a
-- relationship that exists in the designer's head and nowhere in the source. Here the count
-- lives inside the `Timing` constructor: a count with no measurement in flight is not a bug
-- you can hunt for, it is a sentence you cannot write.
--
-- Encoding anxiety evaporates the same way. There is no localparam block: Clash derives a bit
-- representation from the datatype (here 17 bits -- one tag bit and the 16-bit payload), and
-- downstream synthesis is free to re-encode the reachable states as it sees fit. One-hot vs
-- binary stops being something you commit to in the source.

pwStep :: PwState -> Bool -> (PwState, Maybe (Unsigned 16))
pwStep WaitHigh   False = (WaitHigh, Nothing)
pwStep WaitHigh   True  = (Timing 1, Nothing)
pwStep (Timing n) True  = (Timing (satSucc SatBound n), Nothing)
pwStep (Timing n) False = (WaitHigh, Just n)

-- The machine, drawn. Each arrow is exactly one line of `pwStep`, labelled `input / output`
-- plus what happens to the payload:
--
--        ┌───┐                                          ┌───┐
--        ▼   │                                          ▼   │
--     ┌──────┴───┐      True / Nothing,  n := 1      ┌──────┴───┐
--     │ WaitHigh │──────────────────────────────────▶│ Timing n │
--     │ (reset)  │◀──────────────────────────────────│          │
--     └──────────┘      False / Just n               └──────────┘
--      False / Nothing                                True / Nothing,
--                                                     n := satSucc SatBound n
--
--     pwStep (Timing n) False = (WaitHigh, Just n)
--             │                  │         │
--             │                  │         └── the label on the lower arrow, right to left
--             │                  └──────────── that arrow's destination box
--             └─────────────────────────────── that arrow's source box, payload and all
--
-- Four lines, one per (state, input) pair. `satSucc SatBound` is Lesson 01's deliberate
-- overflow decision showing up in context: a pulse longer than 65535 cycles reads as 65535
-- rather than wrapping to a short pulse -- chosen, not hoped.
--
-- The output type `Maybe (Unsigned 16)` is the valid/data pair you would write by hand in
-- Verilog, fused into one value. In the generated VHDL it is a 17-bit vector (valid bit plus
-- data), but in the source you cannot touch the data without going through `Just` -- reading
-- the payload on a not-valid cycle is a pattern match that will not type-check, not a bench
-- bug.

pulseWidth :: HiddenClockResetEnable dom => Signal dom Bool -> Signal dom (Maybe (Unsigned 16))
pulseWidth = mealy pwStep WaitHigh

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System Bool ->
  Signal System (Maybe (Unsigned 16))
topEntity = exposeClockResetEnable pulseWidth

------------------------------------------------------------------------------------------------
-- Mealy or Moore
------------------------------------------------------------------------------------------------
--
-- `mealy` computes the output from state AND current input, so `Just n` appears on the same
-- cycle the input falls. `moore` takes the transition and the output as two functions,
--
--     moore :: (NFDataX s, HiddenClockResetEnable dom)
--           => (s -> i -> s) -> (s -> o) -> s -> Signal dom i -> Signal dom o
--
-- and the output depends on the registered state only, so it changes one cycle after the
-- input that caused it -- and cannot glitch with the input, which is why Moore is what you
-- want on an output that leaves the chip. The choice is the same one Verilog makes you take;
-- the difference is that here it is two library functions rather than two disciplines about
-- where assignments go.

------------------------------------------------------------------------------------------------
-- FAILURE 1: a state type without NFDataX
------------------------------------------------------------------------------------------------
--
--     data PwState
--       = WaitHigh
--       | Timing (Unsigned 16)
--       deriving stock (Generic, Show, Eq)
--       -- (deriving anyclass (NFDataX) deleted)
--
--     src/Lesson03.hs:103:14: error: [GHC-39999]
--         * Could not deduce `NFDataX PwState' arising from a use of `mealy'
--           from the context: HiddenClockResetEnable dom
--             bound by the type signature for:
--                        pulseWidth :: forall (dom :: Domain).
--                                      HiddenClockResetEnable dom =>
--                                      Signal dom Bool -> Signal dom (Maybe (Unsigned 16))
--         * In the expression: mealy pwStep WaitHigh
--
-- Compiled and confirmed 27 Aug 2026. (Note it says "could not deduce", not "no instance
-- for" -- inside a polymorphic function GHC phrases a missing instance as a deduction it
-- could not make from the constraints you gave it. Same diagnosis, lawyer's wording.)
--
-- The instance `mealy` demands is not boilerplate. NFDataX is Clash's account of *undefined
-- values*: how to detect an X in a value of this type, and what a whole-value X looks like --
-- which is what the simulator propagates through your state register before reset has done
-- its job, exactly as the netlist would. Verilog gives you X-propagation whether you asked or
-- not and lets simulation and synthesis disagree about it; Clash makes the type carry its own
-- X semantics, and refuses to register a type that has none. `deriving anyclass (NFDataX)`
-- (with Generic) is the whole cost.

------------------------------------------------------------------------------------------------
-- FAILURE 2: a transition function with the wrong shape
------------------------------------------------------------------------------------------------
--
-- The classic slip: returning (output, state) from one arm instead of (state, output).
--
--     pwStep :: PwState -> Bool -> (PwState, Maybe (Unsigned 16))
--     pwStep WaitHigh   False = (WaitHigh, Nothing)
--     pwStep WaitHigh   True  = (Timing 1, Nothing)
--     pwStep (Timing n) True  = (Timing (satSucc SatBound n), Nothing)
--     pwStep (Timing n) False = (Just n, WaitHigh)              -- swapped
--
--     src/Lesson03.hs:73:28: error: [GHC-83865]
--         * Couldn't match expected type `PwState'
--                       with actual type `Maybe (Unsigned 16)'
--         * In the expression: Just n
--           In the expression: (Just n, WaitHigh)
--
--     src/Lesson03.hs:73:36: error: [GHC-83865]
--         * Couldn't match expected type `Maybe (Unsigned 16)'
--                       with actual type `PwState'
--         * In the expression: WaitHigh
--
-- Compiled and confirmed 27 Aug 2026. TWO errors, one per tuple element -- the checker
-- doesn't stop at "the tuple is backwards", it tells you both halves and where each one
-- should have gone.
--
-- Contrast with what the same slip is in Verilog: assigning the counter to the state register
-- and the state constant to the output happens to be width-compatible more often than you
-- would like, elaborates, and becomes a machine that jumps to whatever state shares an
-- encoding with your data. Here the state and the output are different *types*, so putting
-- one where the other belongs is caught at the line where you did it -- even though both are
-- just bits in the netlist.

------------------------------------------------------------------------------------------------
-- What an unhandled state even is
------------------------------------------------------------------------------------------------
--
-- The four-line `pwStep` handles every (state, input) pair, and `-Wincomplete-patterns` (in
-- -Wall) flags any arm you forget -- at compile time, listing the missing patterns. But the
-- deeper change is that the *unreachable* states are gone: a Verilog 3-bit state register
-- with five states has three encodings that are legal register values and legal case-arm
-- omissions, and a glitch or an X can land you in one. `PwState` has no values other than the
-- states. The default-arm-recovers-to-idle ritual has nothing to recover from.

------------------------------------------------------------------------------------------------
-- Run it without hardware
------------------------------------------------------------------------------------------------
--
--     cabal repl
--     ghci> import Clash.Prelude
--     ghci> import Lesson03
--     ghci> simulateN @System 8 pulseWidth [False, True, True, True, False, False, True, False]
--     [Nothing,Nothing,Nothing,Nothing,Just 3,Nothing,Nothing,Just 1]
--
-- (Run and confirmed 27 Aug 2026.) `Just 3` lands on the sample where the input falls after
-- three highs, and the one-cycle blip at the end reads back as `Just 1` -- a mealy output
-- answers in the same cycle as the falling edge that caused it.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Rebuild the machine with `moore`. The output function only sees the state, so "report on
--    the falling edge" needs the result to live somewhere: add a `Done (Unsigned 16)` state,
--    or change the output to `Unsigned 16` and hold the last completed measurement. Compare
--    the VHDL with the mealy version and find the cycle of latency you bought.
--
-- 2. Measure the *period* between rising edges instead of the high width. You need to know
--    what the input was last cycle; put it in the state and notice the type checker walking
--    you through every arm that now has to consider it.
--
-- 3. `pwStep` saturates at 65535 and will happily report a saturated width as if it were
--    real. Change the machine to report `Nothing` for any pulse that hit the limit. How many
--    arms did the type checker make you revisit?
