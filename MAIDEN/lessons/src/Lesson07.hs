-- Lesson 7: I/O flavors, and where portability actually ends.
--
--     Build:  cabal exec -- clash -isrc Lesson07 --vhdl
--     Output: vhdl/Lesson07.topEntity/topEntity.vhdl
--
-- Add `Lesson07` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

{-# LANGUAGE TemplateHaskell #-}

module Lesson07 where

import Clash.Prelude
import Clash.Explicit.DDR (ddrIn)

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Every port so far has been a plain input or a plain output: a std_logic_vector going one
-- way. Real pins have more flavors: bidirectional, double-data-rate, delay-calibrated,
-- deserialised. The first two Clash can express in types, and this lesson builds one of each.
-- The rest are vendor primitives -- and the honest finding, from a real port, is that Clash
-- does not get you out of vendor primitives. It only changes what surrounds them. That
-- boundary is the second half of the lesson.

------------------------------------------------------------------------------------------------
-- 1. Bidirectional: BiSignal, the typed inout
------------------------------------------------------------------------------------------------
--
-- In Verilog a shared bus is an `inout` port and a conditional driver:
--
--     inout [7:0] bus;
--     assign bus = oe ? value : 8'bz;
--
-- Nothing stops a second `assign` from driving the same wire at the same time; you find out
-- at runtime, as X's, if your testbench happens to provoke it. Readler's single-port-memory
-- chapter is built around exactly this structure -- one data bus, direction switched by an
-- output-enable.
--
-- Clash splits the one `inout` into two typed halves:
--
--     BiSignalIn  ds dom n   -- the pin as seen from inside: what is ON the bus
--     BiSignalOut ds dom n   -- your driver: what you PUT on the bus, when you choose to
--
--     readFromBiSignal :: BitPack a => BiSignalIn ds d (BitSize a) -> Signal d a
--     writeToBiSignal  :: (BitPack a, NFDataX a)
--                      => BiSignalIn ds d (BitSize a)
--                      -> Signal d (Maybe a)          -- Nothing = release the bus (Z)
--                      -> BiSignalOut ds d (BitSize a)
--
-- The output-enable is not a separate wire you might forget: driving is `Just v`, releasing
-- is `Nothing`. There is no way to write a driver without saying when it lets go. `ds` says
-- what an undriven bus reads as ('Floating, 'PullUp, 'PullDown) -- on a real pin that is the
-- I/O-cell configuration, and here it is in the type instead of in a constraints file.
--
-- The working example is a bus latch: while `drive` is low it listens and stores what some
-- other device put on the bus; while `drive` is high it drives the stored value back. Wire
-- and box labels below are the exact subexpressions in the source:
--
--                        portable interior               ┊        the pad cell (vendor)
--                                                        ┊
--               ┌────────────────────────────┐           ┊
--    drive ──┬─►│ mux drive                  │  driven   ┊   ┌────────────────────────┐
--            │  │   (Just <$> stored)        ├───────────┊──►│ writeToBiSignal bus    │
--            │  │   (pure Nothing)           │           ┊   │   = the tristate drv.  ├◄──► PAD
--            │  └─────────────▲──────────────┘           ┊   └────────────────────────┘
--            │                │ stored                   ┊
--            │  ┌─────────────┴──────────────┐           ┊   ┌────────────────────────┐
--            └─►│ regEn 0 (not <$> drive)    │   seen    ┊   │ readFromBiSignal bus   │
--               │   seen                     │◄──────────┊───┤   = the input buffer   │◄─── PAD
--               └────────────────────────────┘           ┊   └────────────────────────┘
--
-- Everything left of the boundary is ordinary logic: a register, a mux, and the rule from
-- Lesson 2 that a choice is a mux you can see. The two functions on the right are the only
-- things that touch the pad, and they exist so that the tristate driver -- a vendor I/O cell,
-- not fabric logic -- has exactly one, typed, place to be.

busLatch ::
  forall dom.
  HiddenClockResetEnable dom =>
  Signal dom Bool ->
  BiSignalIn 'Floating dom 8 ->
  BiSignalOut 'Floating dom 8
busLatch drive bus = writeToBiSignal bus driven
  where
    seen :: Signal dom (Unsigned 8)
    seen = readFromBiSignal bus
    stored = regEn 0 (not <$> drive) seen
    driven = mux drive (Just <$> stored) (pure Nothing)

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System Bool ->
  BiSignalIn 'Floating System 8 ->
  BiSignalOut 'Floating System 8
topEntity clk rst en = withClockResetEnable clk rst en busLatch

-- The generated entity has a real `inout` port -- run `cl Lesson07 -s` and look:
--
--     carg_0 : inout std_logic_vector(7 downto 0)
--
-- One honest caveat, stated plainly: modern FPGA fabric has no internal tristates. An
-- `inout` inside a design gets synthesised into muxes anyway, on every vendor's tools.
-- So BiSignal earns its keep at the top level, where the pad is; between internal blocks
-- a shared bus is a mux you should write as a mux. The type being slightly unwieldy
-- inside a design is the language agreeing with the silicon.

------------------------------------------------------------------------------------------------
-- 2. Double data rate: two values per clock, in the type
------------------------------------------------------------------------------------------------
--
-- A DDR input captures on both clock edges, so one physical pin at clock f carries the data
-- of two wires at f/2. Clash types this as two DOMAINS, one twice the period of the other:
--
--     ddrIn :: ( NFDataX a
--              , KnownConfiguration fast ('DomainConfiguration fast fPeriod e r i p)
--              , KnownConfiguration slow ('DomainConfiguration slow (2*fPeriod) e r i p) )
--           => Clock slow -> Reset slow -> Enable slow
--           -> (a, a, a)                -- values driven during reset
--           -> Signal fast a            -- the pin
--           -> Signal slow (a, a)       -- both captured values, one slow cycle
--
-- The 2x relationship is not a comment or a naming convention; it is the constraint
-- `2 * fPeriod`. Hand it two domains that are not in an exact 2:1 period ratio and the
-- program is rejected (FAILURE 2 below does exactly that). `Fast` here is System's 10000 ps
-- halved:

createDomain vSystem{vName = "Fast", vPeriod = 5000}

ddrCapture ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal Fast Bit ->
  Signal System (Bit, Bit)
ddrCapture clk rst en = ddrIn clk rst en (0, 0, 0)

-- `Clash.Explicit.DDR` is the generic, simulatable version: it synthesises to ordinary
-- flops, and whether the tools pack those into the I/O cell's dedicated DDR registers is
-- between you and the fitter. For guaranteed vendor DDR cells Clash ships
-- `Clash.Xilinx.DDR` (IDDR/ODDR) and `Clash.Intel.DDR` (altddio) -- the same type
-- signatures, but the netlist instantiates the primitive by name. Notice what does NOT
-- exist: `Clash.Lattice.DDR`. For the ECP5 target these lessons measure against, the
-- library has no wrapper for IDDRX1F and friends. That is the boundary showing itself, and
-- it is the subject of the next section.

------------------------------------------------------------------------------------------------
-- 3. The vendor-primitive boundary
------------------------------------------------------------------------------------------------
--
-- How does `register` become VHDL at all? Every Clash primitive is a Haskell function whose
-- body is a behavioural model (that is what simulation runs) plus a BLACKBOX: a template,
-- attached via `Clash.Annotations.Primitive`, that tells the netlist generator what text to
-- emit instead of compiling the body. `register`, `blockRam`, `ddrIn` -- all of them work
-- this way. The mechanism is open to you: write a function whose model fakes the behaviour,
-- annotate it with a template that instantiates ISERDESE2 or EHXPLLL by name, and Clash
-- will place your vendor macro like any other component. It is the FFI of hardware: the
-- type signature is a promise the compiler cannot check against the body.
--
-- So Clash CAN express vendor primitives. What it cannot do is make them portable, and no
-- language can. The evidence is Jim's own theremin port. Upstream fpga-theremin's front end
-- oversamples a ~600 kHz LC oscillator at ~1.2 Gbps using a Xilinx ISERDESE2 deserialiser
-- (1:8 gearing at a 600 MHz shift clock) plus IDELAYE2 delay lines calibrated by an
-- IDELAYCTRL. On ECP5 none of that exists: input gearing tops out at IDDRX2F (1:4) and
-- IDDR71B (1:7), and the DELAYG/DELAYF delay elements are uncalibrated. There is no
-- combination of ECP5 primitives that reproduces the Xilinx front end; it would have to be
-- redesigned around a different primitive family. (Theremin.EdgeSampler's header works
-- through the details.)
--
-- The port's answer is to draw the boundary where portability actually ends. In
-- Theremin.SensorPeriodMeasure the vendor front end is simply not ported: the module takes
-- the edge stream as INPUTS -- `spPitchEdge`, `spPitchEdgePos`, and the volume twins --
-- exactly the signals the oversampling edge detectors would present:
--
--               Xilinx-only (not ported)          │        portable Clash (all of it)
--                                                 │
--       ┌────────────┐    ┌───────────────────┐   │   ┌───────────────────────────────┐
--   LC  │ IDELAYE2 + │    │ ISERDESE2 1:8     │   │   │ sensorPeriodMeasure:          │
--   osc►│ IDELAYCTRL ├───►│ oversampling_     ├───┼──►│  spPitchEdge    (Bit)         │
--       │ (calibr.)  │    │ edge_detector     │   │   │  spPitchEdgePos (BitVector 23)│
--       └────────────┘    └───────────────────┘   │   │  -> pulse centres -> boxcar   │
--                                                 │   │  -> IIR -> SensorOut          │
--                         the wall is HERE ───────┘   └───────────────────────────────┘
--
-- Everything to the right of the wall -- clock-domain crossing, pulse-centre averaging,
-- both filter stages, output packing -- is ordinary Clash, and all of it synthesises for
-- ECP5. The thing to notice: a hand-written VHDL port would hit the IDENTICAL wall in the
-- identical place. Replacing an ISERDESE2 is a hardware design problem, not a translation
-- problem, and no choice of source language moves it.
--
-- The epilogue is better than the boundary. When the ECP5 replacement was actually designed
-- (Theremin.EdgeSampler), the analysis showed the oversampling front end was never needed:
-- measurement resolution is the product of the sample tick AND the averaging window, and
-- the downstream filter already averages over 512 half-cycles. Plain 1x sampling gives
-- ~0.02 cents of pitch resolution at 200 MHz, ~0.055 cents at 75 MHz (Jim's EdgeSampler
-- analysis) -- against a budget of one cent and an LC tank whose own phase noise dominates
-- either number. Three flip-flops of synchroniser replaced the deserialiser, the delay
-- lines, and the calibration controller. The best vendor primitive is the one you delete;
-- the second best is one behind a boundary this narrow.

------------------------------------------------------------------------------------------------
-- FAILURE 1: treating the pin as a wire
------------------------------------------------------------------------------------------------
--
-- A BiSignalIn is not a Signal, and the compiler will not let you forget which side of the
-- pad you are on. Here is `busLatch` with the readFromBiSignal step "optimised away" --
-- feeding the pin straight into the register:
--
--     busLatchBad drive bus = writeToBiSignal bus driven
--       where
--         stored = regEn 0 (not <$> drive) bus              -- ERROR: bus is the pin
--         driven = mux drive (Just <$> stored) (pure Nothing)
--
--     src/Lesson07.hs:88:38: error: [GHC-83865]
--         * Couldn't match expected type: Signal dom a0
--                       with actual type: BiSignalIn 'Floating dom 8
--         * In the third argument of `regEn', namely `bus'
--           In the expression: regEn 0 (not <$> drive) bus
--
-- Compiled and confirmed 27 Aug 2026 (bindings list trimmed). The error is right because
-- the two types genuinely denote different things: a Signal is a value stream your logic
-- computes with; a BiSignalIn is a pad that something else may be driving, or nothing. The
-- Verilog equivalent -- using an `inout` directly in an expression -- elaborates without
-- comment and hands you a design where half the reads race the output enable. Here the
-- conversion is a named function, so every crossing from pad to logic is visible and
-- greppable.

------------------------------------------------------------------------------------------------
-- FAILURE 2: DDR between domains that are not 2:1
------------------------------------------------------------------------------------------------
--
-- `ddrIn` with the SAME domain on both sides -- morally, claiming a pin can carry two values
-- per clock into a domain running at the pin's own rate:
--
--     ddrSame ::
--       Clock System -> Reset System -> Enable System ->
--       Signal System Bit ->
--       Signal System (Bit, Bit)
--     ddrSame clk rst en = ddrIn clk rst en (0, 0, 0)
--
--     src/Lesson07.hs:146:22: error: [GHC-18872]
--         * Couldn't match type `10000' with `20000'
--             arising from a use of `ddrIn'
--         * In the expression: ddrIn clk rst en (0, 0, 0)
--
-- Compiled and confirmed 27 Aug 2026. The constraint demands the slow period be exactly
-- `2 * fPeriod`; with System (10000 ps) on both sides it needs 10000 ~ 20000 and stops.
-- The Verilog behaviour this replaces is silence: clock both halves of a DDR capture from
-- whatever you like and nothing complains until timing analysis -- or the bench -- notices
-- that half your samples are the same sample. The period arithmetic that catches it here is
-- the same type-level arithmetic that checked vector lengths in Lesson 4; domains are just
-- one more thing it is allowed to count.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Put a second device on the bus: another `busLatch`-like driver, and combine the two
--    BiSignalOuts with `mergeBiSignalOuts` (it takes a Vec of drivers -- the fan-in is
--    counted, like everything else). Then make both drive at once and simulate: what value
--    does `readFromBiSignal` see? The answer is the simulation model of contention, and it
--    is worth knowing before a pad fight happens on hardware.
--
-- 2. Write `ddrSend`, the `ddrOut` counterpart of `ddrCapture`, System-to-Fast. Generate
--    both and compare the port lists: which side of each function is the pin?
--
-- 3. Suppose the oversampling front end had been necessary after all. Sketch the blackbox
--    you would write for ECP5: which signals of Theremin.SensorPeriodMeasure's SensorIn
--    would come from IDDRX2F outputs, what the behavioural model would have to fake, and
--    what the template would instantiate. You will find the Haskell part is an afternoon
--    and the hardware part is the project.
