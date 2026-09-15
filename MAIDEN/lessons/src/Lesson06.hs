{-# LANGUAGE TemplateHaskell #-}
-- Lesson 06: clock domains -- a clock is a type, and every crossing is visible in the source.
--
--     Build:  cabal exec -- clash -isrc Lesson06 --vhdl
--     Output: vhdl/Lesson06.topEntity/topEntity.vhdl
--
-- Add `Lesson06` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson06 where

import Clash.Prelude
import qualified Clash.Explicit.Prelude as E

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Every `Signal dom a` so far has carried a `dom` we ignored because there was only one. That
-- parameter is the whole clock-domain discipline: two signals in different domains are
-- different TYPES, so using a wire on the wrong side of a clock boundary -- the bug class
-- that produces the least reproducible failures hardware has to offer -- is a type error at
-- the exact line where the wire crosses.
--
-- In Verilog a wire carries no clock. Which always block last drove it, and which clock that
-- block was sensitive to, is a fact about the whole netlist that lint tools reconstruct
-- statistically and reviewers reconstruct by grep. Here it is written on the wire.

------------------------------------------------------------------------------------------------
-- Defining domains
------------------------------------------------------------------------------------------------
--
-- A domain bundles a name, a period, and the reset/edge conventions. `createDomain` (Template
-- Haskell, hence the pragma up top) takes `vSystem` -- the 100 MHz default you have been
-- using -- and a record update of whatever differs:

createDomain vSystem{vName="Dom25", vPeriod=40000, vResetPolarity=ActiveLow}
createDomain vSystem{vName="Dom75", vPeriod=13333}

-- Dom25 is the ULX3S's 25 MHz oscillator (40,000 ps -- vPeriod is picoseconds); Dom75 is the
-- 75 MHz the theremin port closes timing at (theremin/clash/README.md). Each line generates a
-- type-level name and its `KnownDomain` instance; from here on `Signal Dom25 Bit` and
-- `Signal Dom75 Bit` are as incompatible as `Unsigned 8` and `Unsigned 4` were in Lesson 01.
--
-- The other fields worth knowing: `vResetKind` (Synchronous / Asynchronous), `vActiveEdge`,
-- `vInitBehavior`. Note what Dom25's update just did: boards routinely hand you an active-low
-- reset, and that fact now lives in the DOMAIN -- stated once, honoured by every register and
-- reset function in that domain -- instead of as a `~rst_n` convention sprinkled through
-- every always block and wrong in one of them.
--
-- A word for readers of Readler's clock-buffer chapter: the reason it exists is that in
-- Verilog a clock is just a wire, so nothing stops you gating it with an AND, buffering it by
-- hand, or using it as data. Here `Clock dom` is its own type -- there is no Num, no Bits,
-- no way to write logic on one. Run-time gating goes through the `Enable` port, where it is
-- flow control instead of clock surgery. That chapter evaporates.

------------------------------------------------------------------------------------------------
-- The crossing: a two-flop synchronizer, built honestly
------------------------------------------------------------------------------------------------
--
-- One bit, produced in Dom25, needed in Dom75. The hardware answer is two chained flip-flops
-- on the destination clock; here is that circuit, with the boundary explicit. Multi-domain
-- code uses the explicit-clock API (`Clash.Explicit.Prelude`, imported as E) because "the"
-- hidden clock stops being a meaningful idea the moment there are two.

sync2FF ::
  forall src dst a.
  (KnownDomain src, KnownDomain dst, NFDataX a) =>
  Clock src ->
  Clock dst ->
  Reset dst ->
  Enable dst ->
  a ->
  Signal src a ->
  Signal dst a
sync2FF clkA clkB rstB enB i x = ff2
 where
  crossed = E.unsafeSynchronizer clkA clkB x
  ff1     = E.register clkB rstB enB i crossed
  ff2     = E.register clkB rstB enB i ff1

topEntity ::
  Clock Dom25 ->
  Clock Dom75 ->
  Reset Dom75 ->
  Enable Dom75 ->
  Signal Dom25 Bit ->
  Signal Dom75 Bit
topEntity clkA clkB rstB enB = sync2FF clkA clkB rstB enB 0

-- The boundary, drawn:
--
--             Dom25 (40 ns)        ┆              Dom75 (13.3 ns)
--                                  ┆
--                                  ┆         ┌────────┐      ┌────────┐
--     x ───────────────────────────┆────────▶│   FF   │─────▶│   FF   │─────▶ out
--        (whatever Dom25 logic     ┆   ▲     │  clkB  │      │  clkB  │
--         last registered it)      ┆   │     └────────┘      └────────┘
--                                  ┆   │          ▲ may go metastable; the second
--                                  ┆   │            FF is what makes that rare
--                                  ┆   └ crossed: a wire, not hardware
--
--     crossed = E.unsafeSynchronizer clkA clkB x
--     ff1     = E.register clkB rstB enB i crossed
--     ff2     = E.register clkB rstB enB i ff1
--     │                    │
--     │                    └── both FFs clock on the DESTINATION side of the boundary
--     └───────────────────────── the dashed line itself: in the netlist, just the wire
--
-- `unsafeSynchronizer` generates NO hardware. In the netlist it is a wire; in simulation it
-- resamples the stream between the two periods (40000:13333) so behaviour is modelled. All
-- it really does is change the domain in the type -- which is exactly why it carries the
-- word `unsafe`: it is the one function that tells the type checker "I know what I am
-- doing", and the two registers behind it are what make that claim true. The library's
-- `E.dualFlipFlopSynchronizer` packages this same pattern; we built it once to know what is
-- in the box.

------------------------------------------------------------------------------------------------
-- FAILURE 1: using a wire on the wrong side of the boundary
------------------------------------------------------------------------------------------------
--
-- Skip the synchronizer and register the Dom25 bit directly on the Dom75 clock -- the
-- straight-line connection every RTL tool accepts and every CDC lint tool exists to catch:
--
--     topEntity clkA clkB rstB enB x = E.register clkB rstB enB 0 x
--
--     src/Lesson06.hs:90:61: error: [GHC-83865]
--         * Couldn't match type `"Dom25"' with `"Dom75"'
--           Expected: Signal Dom75 Bit
--             Actual: Signal Dom25 Bit
--         * In the fifth argument of `E.register', namely `x'
--           In the expression: E.register clkB rstB enB 0 x
--
-- Compiled and confirmed 27 Aug 2026, and for once the message is exactly the tidy shape you
-- would hope for: the two domain names, the two Signal types, and a caret under the one wire
-- that crossed.
--
-- In Verilog this compiles, simulates perfectly (simulators do not model metastability), and
-- fails in the field at a rate set by your clock ratio and the phase of the moon. Here it is
-- a type error at the exact wire that crosses. That is the discipline: not that crossings
-- are forbidden, but that every one must be spelled `unsafeSynchronizer` (or a library
-- function built on it), which makes "grep for the crossings" a complete audit.

------------------------------------------------------------------------------------------------
-- FAILURE 2: a reset from the wrong domain
------------------------------------------------------------------------------------------------
--
-- Clocks are not the only thing with a domain -- `Reset dst` and `Enable dst` carry one too.
-- Wire the Dom25 reset into the Dom75 registers:
--
--     topEntity :: Clock Dom25 -> Clock Dom75 -> Reset Dom25 -> ...   -- wrong domain
--     topEntity clkA clkB rstB enB = sync2FF clkA clkB rstB enB 0
--
--     src/Lesson06.hs:90:50: error: [GHC-83865]
--         * Couldn't match type `"Dom25"' with `"Dom75"'
--           Expected: Reset Dom75
--             Actual: Reset Dom25
--         * In the third argument of `sync2FF', namely `rstB'
--
-- Compiled and confirmed 27 Aug 2026 -- same shape as FAILURE 1, with `Reset` in place of
-- `Signal`: the domain discipline covers the whole clock/reset/enable trio, not just data.
--
-- This is the reset-domain-crossing bug: a reset released asynchronously to the clock of the
-- registers it resets is itself a synchronization hazard (all your state machines come out
-- of reset on different cycles, once a month). The type system treats "which domain may this
-- reset touch" exactly like it treats clocks, so the mistake cannot be made quietly. A reset
-- that genuinely must serve both domains goes through a reset synchronizer, and Clash makes
-- you say so.

------------------------------------------------------------------------------------------------
-- The honest part: what the types do NOT buy you
------------------------------------------------------------------------------------------------
--
-- Metastability is still physics. Read the claim precisely: the type system guarantees you
-- cannot cross domains *by accident*. It does not, and cannot, make a crossing *correct*:
--
--   * Two flip-flops buy you an MTBF, not a certainty. The failure rate is set by the
--     technology and the clock ratio; the second register moves it from "daily" to "heat
--     death of the universe", but it is engineering, not proof.
--   * `sync2FF` is only sound for ONE BIT. Its type cheerfully accepts
--     `Signal Dom25 (Unsigned 16)` -- and the hardware will tear that word apart, each bit
--     resolving on its own cycle, assembling values that never existed. The compiler has no
--     opinion; the polymorphic `a` in the signature is a loaded gun. Multi-bit crossings
--     need a gray-coded counter, a handshake, or `E.asyncFIFOSynchronizer` -- design
--     patterns, chosen by you.
--   * `unsafeSynchronizer` with no registers after it type-checks. The name is the only
--     warning.
--
-- What you actually bought: in a Verilog netlist the crossings are wherever they are, and a
-- CDC audit starts by finding them. Here the audit starts complete -- every crossing is a
-- visible, greppable call -- and spends its time where it belongs, on whether each one's
-- synchronizer is the right design.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Replace `sync2FF` with `E.dualFlipFlopSynchronizer` and diff the VHDL. It should be the
--    same two flip-flops -- confirm, don't trust.
--
-- 2. Change topEntity's input to `Signal Dom25 (Unsigned 16)` and watch it compile anyway --
--    the FAILURE that isn't (compiled and confirmed PASS, 27 Aug 2026). Then fix it
--    properly: synchronize a one-bit "data ready"
--    toggle through `sync2FF` and capture the 16-bit word in Dom75 only when the toggle
--    changes -- the standard toggle-handshake. What guarantees the word is stable when you
--    sample it, and is that guarantee in the types or in your head?
--
-- 3. Rebuild Dom75 with `vResetKind=Asynchronous` and diff the generated process against the
--    synchronous version: the reset moves into the sensitivity list. Then find where Dom25's
--    ActiveLow declaration surfaces. The conventions you used to enforce by code review are
--    compiler output now.
