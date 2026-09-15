-- Lesson 8: simulation without a simulator.
--
--     Build:  cabal exec -- clash -isrc Lesson08 --vhdl
--     Output: vhdl/Lesson08.topEntity/topEntity.vhdl
--
-- Add `Lesson08` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson08 where

import Clash.Prelude
import qualified Prelude as P

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- A Verilog design needs a simulator to run: a testbench module, an `initial` block full of
-- `#10;` delays, a waveform viewer to read the answer out of. Readler's book spends a chapter
-- building exactly that -- a small design, then a testbench that pokes hand-written vectors
-- at it and `$display`s what comes back.
--
-- A Clash circuit is a Haskell function. It runs wherever Haskell runs, which includes a
-- repl you already have open. This lesson runs the same design three ways, each cheaper than
-- the last: `simulateN` with hand vectors (the testbench, minus the testbench), `sampleN`
-- (for circuits with no inputs), and finally no simulation machinery at all -- calling the
-- step function directly, hundreds of times, as a property.

------------------------------------------------------------------------------------------------
-- The design under test: a period meter
------------------------------------------------------------------------------------------------
--
-- A miniature of the theremin's sensor problem: given a slow square-ish input, measure its
-- period in clock cycles. One register bank, one rule: a free-running count since the last
-- rising edge; on each rising edge, publish the count and restart it.

data PmState = PmState
  { pmPrev   :: Bit          -- previous input sample, for edge detection
  , pmSeen   :: Bool         -- has a rising edge been seen since reset?
  , pmCount  :: Unsigned 8   -- cycles since the last rising edge
  , pmPeriod :: Unsigned 8   -- last completed period; 0 until one has been measured
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

pmInit :: PmState
pmInit = PmState 0 False 0 0

-- The step function: ALL the behaviour, and none of the clocking. Note what is legal again
-- in here: `==` on values, `if` on values. Lesson 2 forbade both on Signals -- but this
-- function never sees a Signal. It maps one state and one input sample to the next state
-- and one output sample, and `mealy` (below) is what turns "per sample" into "per clock".

pmStep :: PmState -> Bit -> (PmState, Unsigned 8)
pmStep s x = (s', pmPeriod s')
  where
    rising = pmPrev s == low && x == high
    s' = PmState
      { pmPrev   = x
      , pmSeen   = pmSeen s || rising
      , pmCount  = if rising then 1 else satSucc SatBound (pmCount s)
      , pmPeriod = if rising && pmSeen s then pmCount s else pmPeriod s
      }

-- `satSucc SatBound` instead of `+ 1`: an input that never rises parks the count at 255
-- rather than wrapping to 0 and reporting a crisp, wrong, small period. Overflow behaviour
-- chosen on purpose, per Lesson 1. The `pmSeen` guard earns its keep too: without it the
-- FIRST rising edge publishes the distance from reset to that edge, which is not a period
-- of anything -- an early draft of this lesson omitted the guard, and the very first
-- hand-vector run below exposed it (the transcript read [0,0,2,2,...]: a phantom "period"
-- of 2 measured from reset). Cheap simulation catches cheap bugs cheaply.

periodMeter ::
  HiddenClockResetEnable dom =>
  Signal dom Bit ->
  Signal dom (Unsigned 8)
periodMeter = mealy pmStep pmInit

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System Bit ->
  Signal System (Unsigned 8)
topEntity clk rst en = withClockResetEnable clk rst en periodMeter

------------------------------------------------------------------------------------------------
-- Way 1: simulateN -- the hand-written testbench, minus the testbench
------------------------------------------------------------------------------------------------
--
-- `simulateN` feeds a circuit one input per clock from a list and collects one output per
-- clock into a list. The diagram is the whole mental model -- every box and wire is labelled
-- with the exact subexpression it is in the source:
--
--        ins :: [Bit], one element per clock         outs :: [Unsigned 8], one per clock
--
--                              ┌───────────────────────────────┐
--     [0,0,1,1,0,0,1,1,...] ──►│ periodMeter = mealy pmStep    │──► [0,0,0,0,0,0,4,4,...]
--             ins              │               pmInit          │            outs
--                              │                               │
--                              │  hidden inside: a PmState,    │
--                              │  advanced by pmStep once      │
--                              │  per list element             │
--                              └───────────────────────────────┘
--                        outs = simulateN @System 12 periodMeter ins
--
-- The session, verbatim (`cabal repl`, then):
--
--     ghci> import qualified Prelude as P
--     ghci> let ins = P.concat (P.replicate 3 [low, low, high, high])
--     ghci> simulateN @System 12 periodMeter ins
--     [0,0,0,0,0,0,4,4,4,4,4,4]
--
-- Read it like a waveform: the first period cannot be measured (nothing to measure from),
-- so the output holds 0; at the second rising edge -- cycle 6 -- the meter publishes 4 and
-- holds it. Readler's version of this is a testbench module with an `initial` block, a
-- clock generator, `#` delays to build the square wave, and `$display` calls -- his hand
-- vectors are `ins`, his transcript is the returned list. The content is identical; the
-- overhead is not. There is no testbench FILE anywhere: the "bench" is a list literal and
-- the check is `==` on lists.
--
-- Two mechanical notes. First, `simulateN` (and `sampleN`) supply the hidden clock, reset,
-- and enable themselves -- you hand them `periodMeter`, not `topEntity`. Second, reset is
-- real in simulation: with an asynchronous-reset domain like System the first sample is
-- computed under reset, which is why lesson 2's counter repeated its first value. Here the
-- reset state and the idle state are both `pmInit`, so nothing visibly repeats.

------------------------------------------------------------------------------------------------
-- Way 2: sampleN -- when the stimulus lives inside
------------------------------------------------------------------------------------------------
--
-- A circuit with no inputs (a counter, an LFSR, a design driving its own stimulus) does not
-- need a vector list, just a cycle count. Rather than piling the stimulus into the repl
-- line, wire it up as a named circuit -- it is two lines, and it is reusable:

selfTest :: HiddenClockResetEnable dom => Signal dom (Unsigned 8)
selfTest = periodMeter toggle
  where
    toggle = register low (fmap complement toggle)   -- square wave, period 2

--     ghci> sampleN @System 8 selfTest
--     [0,0,0,0,2,2,2,2]
--
-- `toggle` is the two-line stimulus generator; on hardware it would synthesise right along
-- with the meter, which is exactly what a built-in self-test is.

------------------------------------------------------------------------------------------------
-- Way 3: no simulator at all -- the step function IS the model
------------------------------------------------------------------------------------------------
--
-- `simulateN` still drags in clocks, resets, and Signal plumbing. But every behaviour of
-- `periodMeter` is decided by `pmStep`, and `pmStep` is an ordinary function on ordinary
-- values. Feeding it a list by hand is one `foldl`:

runSteps :: [Bit] -> Unsigned 8
runSteps = snd . P.foldl (\(s, _) x -> pmStep s x) (pmInit, 0)

-- and now "does the meter measure a period-p wave correctly?" is a function too:

squareWave :: Int -> [Bit]
squareWave p = P.replicate (p `div` 2) high P.++ P.replicate (p - p `div` 2) low

measuresExactly :: Int -> Bool
measuresExactly p = runSteps (P.concat (P.replicate 3 (squareWave p))) == fromIntegral p

--     ghci> and (P.map measuresExactly [2 .. 255])
--     True
--
-- That is 254 testbenches -- every measurable period, exhaustively -- in well under a
-- second, with no simulator process, no waveform files, and no clock anywhere in sight.
-- This is not a toy idiom: the theremin port's test suite drives its filters exactly this
-- way (IirSpec.hs runs `iirStep` chains 200,000 deep to find settling values). And it is
-- the foundation Lesson 9 builds on: replace `[2 .. 255]` with a random generator, replace
-- `and` with a property runner that shrinks failures, and you have the verification loop
-- that actually gates MAIDEN's blocks.
--
-- The boundary is worth restating: `pmStep` can be run without Clash, but only because the
-- DESIGN keeps all decisions inside the step function and lets `mealy` do the clocking.
-- A design written as a tangle of `register`s can only be tested through `simulateN`. Both
-- are legal; one of them hands you a free reference model.

------------------------------------------------------------------------------------------------
-- FAILURE 1: handing the simulator a step function
------------------------------------------------------------------------------------------------
--
-- The two worlds -- per-sample functions and per-clock circuits -- have typed border
-- crossings: `mealy` goes one way, `simulateN` comes back. Skip the `mealy`:
--
--     demoBad :: [Unsigned 8]
--     demoBad = simulateN @System 8 pmStep (P.replicate 8 high)
--
--     src/Lesson08.hs:160:31: error: [GHC-83865]
--         * Couldn't match type `PmState' with `Signal System Bit'
--           Expected: Signal System Bit -> Signal System (Unsigned 8)
--             Actual: PmState -> Bit -> (PmState, Unsigned 8)
--         * Probable cause: `pmStep' is applied to too few arguments
--           In the third argument of `simulateN', namely `pmStep'
--
-- Compiled and confirmed 27 Aug 2026. The Expected/Actual pair is the lesson's whole
-- taxonomy in two lines: a simulator runs CIRCUITS (Signal to Signal); a step function is
-- not a circuit until `mealy pmStep pmInit` closes the state loop and lifts it. (Ignore
-- the "probable cause" -- GHC guessing at partial application is the one unhelpful line in
-- an otherwise exact message.) The Verilog analogue of this confusion -- instantiating a
-- task where a module belongs -- is also an error, but here the message names the two
-- artefacts you conflated and their exact types.

------------------------------------------------------------------------------------------------
-- FAILURE 2: simulating a circuit with two input ports
------------------------------------------------------------------------------------------------
--
-- `simulate`/`simulateN` take a ONE-argument circuit: one list in, one list out. A gated
-- variant of the meter has two inputs:
--
--     gatedMeter ::
--       HiddenClockResetEnable dom =>
--       Signal dom Bool -> Signal dom Bit -> Signal dom (Unsigned 8)
--     gatedMeter en x = regEn 0 en (periodMeter x)
--
--     demoBad2 :: [Unsigned 8]
--     demoBad2 = simulateN @System 8 gatedMeter (P.replicate 8 (True, high))
--
--     src/Lesson08.hs:165:32: error: [GHC-83865]
--         * Couldn't match type `Bool' with `(Bool, Bit)'
--           Expected: Signal System (Bool, Bit) -> Signal System (Unsigned 8)
--             Actual: Signal System Bool
--                     -> Signal System Bit -> Signal System (Unsigned 8)
--
-- Compiled and confirmed 27 Aug 2026. The fix is `bundle`'s mirror image: a Signal of
-- pairs and a pair of Signals carry the same wires (Lesson 4), so cross the border with
--
--     demo2 :: [Unsigned 8]
--     demo2 = simulateN @System 8
--               (\i -> let (en, x) = unbundle i in gatedMeter en x)
--               (P.replicate 8 (True, high))
--
-- One list of tuples in, one circuit with however many ports inside. The hand-vector
-- testbench for an N-port design is still just a list -- of N-tuples.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. `measuresExactly 256` is False. Predict what `runSteps` returns for it, from the
--    `satSucc SatBound` line, then check yourself in the repl. Is the failure mode a good
--    one? What would the `+ 1` version have reported?
--
-- 2. The square wave is the friendliest possible input. Write `pulseTrain :: Int -> [Bit]`
--    producing one-cycle-high pulses every p cycles and check the meter still measures p.
--    Then try a wave that GLITCHES -- a one-cycle low dip in the middle of the high phase --
--    and watch the meter lie. Fix `pmStep` to ignore one-cycle dips (this is a debouncer),
--    rerun `and (P.map measuresExactly [2 .. 255])`, and note that your whole regression
--    suite was one repl line.
--
-- 3. Rebuild `demo2` with `bundle`d OUTPUTS too: make `gatedMeter` also return the raw
--    count, simulate it, and confirm you get a list of pairs back. `bundle`/`unbundle` are
--    total and inverse -- wires are wires, however you group them.
