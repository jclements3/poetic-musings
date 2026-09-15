-- Lesson 9: verification that actually gates.
--
--     Build:  cabal exec -- clash -isrc Lesson09 --vhdl
--     Output: vhdl/Lesson09.topEntity/topEntity.vhdl
--
-- Add `Lesson09` to exposed-modules in lessons.cabal first. This lesson also needs
-- `hedgehog` in the library's build-depends (added alongside this file), so its property
-- code compiles with everything else -- a property that does not compile cannot gate
-- anything.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson09 where

import Clash.Prelude
import qualified Data.List as L
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Lesson 8 ended with `and (P.map measuresExactly [2 .. 255])` -- an exhaustive check typed
-- into a repl. That is a fine experiment and a poor gate: nothing re-runs it, nothing
-- shrinks a failure to something readable, and it exercises only the Haskell model, never
-- the VHDL that reaches the synthesiser. MAIDEN's blocks gate on three separate checks, and
-- this lesson builds all three around one small circuit:
--
--     CHECK 1  property test against an independently written reference model
--              -- catches design errors: wrong math, wrong widths, wrong latency.
--     CHECK 2  cycle-exact equivalence between a structural rewrite and the pure model
--              -- catches rewrite errors: memory idioms, pipeline slips, reset behaviour.
--     CHECK 3  GHDL elaboration of the GENERATED VHDL
--              -- catches code-generation faults no Haskell-side test can even see.
--
-- Each is blind to the failure classes of the other two. That is why there are three.

------------------------------------------------------------------------------------------------
-- The circuit and its reference model
------------------------------------------------------------------------------------------------
--
-- A four-tap boxcar: the sum of the last four samples, the same shape as the theremin's
-- stage-1 pulse-centre filter. Output is Unsigned 10 because summing four 8-bit values
-- needs exactly two more bits -- Lesson 10 makes a meal of this; here it is just correct.

boxcar4 ::
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned 8) ->
  Signal dom (Unsigned 10)
boxcar4 x = w x + w x1 + w x2 + w x3
  where
    x1 = register 0 x
    x2 = register 0 x1
    x3 = register 0 x2
    w  = fmap resize

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Unsigned 8) ->
  Signal System (Unsigned 10)
topEntity clk rst en = withClockResetEnable clk rst en boxcar4

-- The reference model is a different ARTIFACT in a different shape: no registers, no
-- Signals, just the specification "output n is the sum of inputs n-3 .. n (zeros before
-- the start)" transcribed as list arithmetic. The point of writing it independently is
-- that a mistake must now be made twice, in two idioms, to slip through.

modelBoxcar :: [Unsigned 8] -> [Unsigned 10]
modelBoxcar xs = L.zipWith4 sum4 xs (z xs) (z (z xs)) (z (z (z xs)))
  where
    z = (0 :)                                        -- delay by one sample
    sum4 a b c d = resize a + resize b + resize c + resize d

------------------------------------------------------------------------------------------------
-- CHECK 1: the property, and the road that leads to it
------------------------------------------------------------------------------------------------
--
-- Readler's verification chapters walk a road worth naming. First a testbench with
-- hand-written vectors -- Lesson 8, ex-20 in his numbering: you pick the inputs, you know
-- the answers. Then the same testbench with `$random`: seed it, loop it a thousand times,
-- compare against a behavioural model, and inputs you never thought of start finding bugs.
-- That second step is the important insight, and it deserves a blunt restatement:
--
--     A $random testbench with a fixed seed IS a property test -- with worse ergonomics
--     and no shrinking.
--
-- The seed is your only handle on reproduction (record it or the failure is gone); the
-- failing evidence is vector #973 of a thousand, buried in a waveform; and nothing reduces
-- that vector to the SMALL case that shows the mechanism. Hedgehog keeps the random-vector
-- insight and fixes all three: failures replay themselves, and a shrinker re-runs the test
-- on ever-smaller inputs until it finds a minimal counterexample. The property:

genFrame :: H.Gen [Unsigned 8]
genFrame = Gen.list (Range.linear 1 64) (Gen.integral Range.linearBounded)

prop_matchesModel :: H.Property
prop_matchesModel = H.property $ do
  ins <- H.forAll genFrame
  simulateN @System (P.length ins) boxcar4 ins === modelBoxcar ins


--     ghci> H.check prop_matchesModel
--       ✓ <interactive> passed 100 tests.
--     True
--
-- One hundred frames of random length and content, hardware simulated against model,
-- cycle for cycle -- reset behaviour included, since sample 0 is compared too.
--
-- Now watch it catch something. `boxcarWrong` sums at 8 bits and widens AFTER -- the
-- classic Verilog accident from Lesson 1, transplanted here deliberately (the resize
-- placates the type checker; choosing WHERE to resize is still yours to get wrong):

boxcarWrong ::
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned 8) ->
  Signal dom (Unsigned 10)
boxcarWrong x = resize <$> (x + x1 + x2 + x3)      -- sums wrap at 8 bits, then widen
  where
    x1 = register 0 x
    x2 = register 0 x1
    x3 = register 0 x2

prop_findsTheBug :: H.Property
prop_findsTheBug = H.property $ do
  ins <- H.forAll genFrame
  simulateN @System (P.length ins) boxcarWrong ins === modelBoxcar ins

--     ghci> H.check prop_findsTheBug
--       ✗ <interactive> failed at src/Lesson09.hs:132:52
--         after 33 tests and 5 shrinks.
--
--             ┏━━ src/Lesson09.hs ━━━
--         129 ┃ prop_findsTheBug :: H.Property
--         130 ┃ prop_findsTheBug = H.property $ do
--         131 ┃   ins <- H.forAll genFrame
--             ┃   │ [ 34 , 66 , 80 , 76 ]
--         132 ┃   simulateN @System (P.length ins) boxcarWrong ins === modelBoxcar ins
--             ┃   │ ━━━ Failed (- lhs) (+ rhs) ━━━
--             ┃   │ - [ 34 , 100 , 180 , 0 ]
--             ┃   │ + [ 34 , 100 , 180 , 256 ]
--
--         This failure can be reproduced by running:
--         > recheckAt (Seed 6052158343448309648 5414101730864349509) "33:b2DiL" <property>
--
--     False
--     (run of 27 Aug 2026, ghci; carets under line 132 trimmed. Your frame will differ.)
--
-- Look at what the shrinker chose: 34 + 66 + 80 + 76 = 256. Five shrinks took a random
-- frame down to the smallest sum that overflows an 8-bit accumulator -- exactly ONE past
-- the boundary -- and the diff shows the wrap itself: 0 where 256 belongs. That minimal
-- counterexample is the ergonomic difference in one line: vector #973 of the $random
-- bench, reduced to four numbers that state the mechanism. And the `recheckAt` line is the
-- fixed seed done right -- paste it back in and this exact failure replays forever, which
-- is what makes the property a GATE rather than a dice roll.

------------------------------------------------------------------------------------------------
-- CHECK 2: the rewrite-pinning equivalence test
------------------------------------------------------------------------------------------------
--
-- Check 1 compares design against spec. Check 2 exists for a different day: the day you
-- REWRITE a working block for area or timing and must prove the new structure is the old
-- behaviour. Lesson 5's measured result is the motivating case: DelayDiffFilter holding
-- its two 512-deep buffers as Vecs in Moore state measured 27.7k LUT4 / 23.5k FF and
-- would not route; rewritten on blockRam, the whole theremin_top is 1,816 LUT4 / 452 FF
-- (Jim's numbers, nextpnr-ecp5). A 20x rewrite you cannot re-verify is a 20x liability.
--
-- The theremin port pins such rewrites with a cycle-exact test: drive the structural
-- implementation and the pure step-function model with the SAME long input -- including a
-- mid-run reset pulse -- and demand equality at every cycle. From Jim's
-- theremin/clash/test/IirSpec.hs, trimmed:
--
--     prop_structural_matches_model = do
--         let n = 4_000
--             ins = [ {- varied deterministic input, plus a reset pulse at i == 1500 -} ]
--             structural = simulateN @System n
--               (\i -> iir (SNat @6) params (fst <$> i) (snd <$> i)) ins
--             model = P.map isOutReg
--               (P.take n (P.scanl (iirStep (SNat @6) params) initialState ins))
--         structural @?= model
--
-- `iir` is the asyncRam-based structure that synthesises; `iirStep` is the pure function
-- that defines what it means. The same file then proves everything else (DC gain,
-- monotonicity, step response) against `iirStep` ONLY -- the equivalence test is the
-- single bridge that lets a whole suite of cheap model tests speak for the expensive
-- structure. Note what it would catch that Check 1 tends to miss: an off-by-one in RAM
-- read latency, a reset that clears the model but not the RAM, a pipeline slip -- bugs of
-- STRUCTURE, invisible in settled behaviour, glaring in a cycle-for-cycle diff.

------------------------------------------------------------------------------------------------
-- CHECK 3: elaborate the VHDL you actually generated
------------------------------------------------------------------------------------------------
--
-- Every check so far ran Haskell. Nobody has yet confirmed that the VHDL Clash writes out
-- is valid VHDL -- that every blackbox template expanded correctly, every identifier
-- survived name mangling, every generated type agrees with every generated port map. Those
-- faults live in the code GENERATOR; no Haskell-side test can even express them. The
-- theremin flow closes the hole with GHDL, an open-source VHDL analyser/elaborator. From
-- Jim's theremin/clash/Makefile, trimmed:
--
--     sim: vhdl
--         ghdl -a $(GHDL_FLAGS) $$(find $(VHDL_DIR) -name '*_types.vhdl' | sort) \
--                               $$(find $(VHDL_DIR) ... ! -name '*_types.vhdl' | sort)
--         ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) $(ENTITY)
--         @echo "GHDL elaborated $(ENTITY) from Clash-generated VHDL."
--
-- `ghdl -a` parses and type-checks every generated file (the `_types` packages first --
-- they define the record types the entities share); `ghdl -e` elaborates the design
-- hierarchy the way a synthesiser would. No testbench, no waveforms: the assertion is
-- simply "this artefact is legal, elaboratable VHDL-2008". It is the cheapest check of the
-- three and the only one aimed at the tool rather than the design. `cl Lesson09` stops at
-- generation; `make sim` in theremin/clash is the runnable exemplar.
--
-- The stack, as a flow -- each box labelled with the exact artefact or command:
--
--     ┌───────────────────────────┐              ┌────────────────────────────────┐
--     │ boxcar4                   │              │ modelBoxcar                    │
--     │ (the circuit: registers,  │              │ (the spec: four lines of list  │
--     │  ships to synthesis)      │              │  arithmetic, written           │
--     └─────┬──────────────┬──────┘              │  independently on purpose)     │
--           │              │                     └───────┬────────────────────────┘
--           │              │ simulateN @System n         │ modelBoxcar ins
--           │              │        boxcar4 ins          │
--           │              ▼                             ▼
--           │        ┌─────────────────────────────────────────────────────┐
--           │        │ CHECK 1+2  prop_matchesModel: hedgehog `===`,       │
--           │        │            random frames, shrinking on failure      │
--           │        │            (theremin: IirSpec structural-vs-model)  │
--           │        └─────────────────────────────────────────────────────┘
--           │ cl Lesson09  (clash --vhdl)
--           ▼
--     ┌───────────────────────────────────┐
--     │ vhdl/Lesson09.topEntity/*.vhdl    │   the generated artefact
--     └─────┬─────────────────────────────┘
--           │ ghdl -a ...; ghdl -e topEntity   (theremin/clash: make sim)
--           ▼
--     ┌───────────────────────────────────┐
--     │ CHECK 3  legal, elaboratable VHDL │──► on to synthesis (Lesson 11: numbers)
--     └───────────────────────────────────┘

------------------------------------------------------------------------------------------------
-- FAILURE 1: comparing wires instead of samples
------------------------------------------------------------------------------------------------
--
-- The property monad lives in the value world. Try to `===` the circuit's output Signal
-- directly against the model -- skipping simulateN by feeding the frame in with
-- `fromList`:
--
--     prop_bad :: H.Property
--     prop_bad = H.property $ do
--       ins <- H.forAll genFrame
--       boxcar4 (fromList ins) === modelBoxcar ins
--
--     src/Lesson09.hs:111:30: error: [GHC-83865]
--         * Couldn't match expected type: Signal dom0 (Unsigned 10)
--                       with actual type: [Unsigned 10]
--         * In the second argument of `(===)', namely `modelBoxcar ins'
--           In a stmt of a 'do' block:
--             boxcar4 (fromList ins) === modelBoxcar ins
--
-- Compiled and confirmed 27 Aug 2026 -- and a finding: this lesson's draft predicted the
-- messier hidden-clock tangle from Lesson 2's FAILURE 2 here, but the compiler does better.
-- `===` unifies its two sides first, `Signal dom0 (Unsigned 10)` against `[Unsigned 10]`
-- fails immediately, and the hidden-clock machinery is never reached. The message is the
-- lesson verbatim: a wire is not a value, and verification compares VALUES. `simulateN` is
-- the border crossing; there is no comparing around it. (Had unification somehow been
-- talked past, `===` would still refuse: Signal has no Eq -- Lesson 2 -- so a property on
-- raw Signals is unwritable twice over.)

------------------------------------------------------------------------------------------------
-- FAILURE 2: a counterexample that could not be printed
------------------------------------------------------------------------------------------------
--
-- Wrap the frame in a newtype and "forget" the Show instance:
--
--     newtype Frame = Frame [Unsigned 8]
--
--     prop_bad2 :: H.Property
--     prop_bad2 = H.property $ do
--       Frame ins <- H.forAll (Frame <$> genFrame)
--       simulateN @System (P.length ins) boxcar4 ins === modelBoxcar ins
--
--     src/Lesson09.hs:112:16: error: [GHC-39999]
--         * No instance for `Show Frame' arising from a use of `H.forAll'
--         * In a stmt of a 'do' block:
--             Frame ins <- H.forAll (Frame <$> genFrame)
--
-- Compiled and confirmed 27 Aug 2026. The constraint is not bureaucracy: `forAll`'s whole
-- contract is that a failing run PRINTS the offending input (that `[ 0 , 255 ]` in the
-- transcript above is `forAll` doing its job). A generator whose values cannot be shown
-- could still find your bug -- and then tell you nothing, which is the $random experience:
-- "mismatch at t=973210ns", go fish in the waveform. Hedgehog refuses the arrangement at
-- compile time. Derive Show and the evidence prints itself.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Why can no 1-element frame make `prop_findsTheBug` fail? (What is the largest sum a
--    single sample can produce?) Rerun `H.check prop_findsTheBug` a few times: the shrunk
--    frames differ per seed, but each one's window sums to just past 255 -- the shrinker
--    walks to the wrap boundary and stops. Explain why it cannot stop short of it.
--
-- 2. Plant a STRUCTURAL bug instead: in `boxcar4`, tap `x2` twice (`w x2 + w x2`) so the
--    oldest sample is dropped. Which check catches it, and what does the shrunk
--    counterexample look like? Note that constant inputs cannot distinguish the two
--    circuits -- the shrinker will hand you the fact by leaving a non-constant frame.
--
-- 3. Run the real thing: `cd theremin/clash && make sim`. Then break it on purpose --
--    delete one generated `_types.vhdl` file from the build directory and rerun the ghdl
--    step -- to see what a Check-3 failure actually looks like. (Regenerate afterwards.)
--
-- 4. Lesson 8's `pmStep`/`periodMeter` pair is exactly a model/structure pair. Write its
--    Check-2 equivalence property: drive `periodMeter` with `simulateN` and `pmStep` with
--    `P.scanl`, on random Bit frames, and `===` them cycle for cycle.
