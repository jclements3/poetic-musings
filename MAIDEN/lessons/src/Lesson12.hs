-- Lesson 12: porting from Verilog -- what stating every width surfaces.
--
--     Build:  cabal exec -- clash -isrc Lesson12 --vhdl
--     Output: vhdl/Lesson12.topEntity/topEntity.vhdl
--
-- Add `Lesson12` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson12 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Porting Verilog to Clash is not translation. Verilog lets a width live implicitly in a
-- connection -- extend here, truncate there, whatever makes the assignment legal -- and a
-- port to a language where every width is a type turns each of those silent adjustments
-- into a question the compiler asks out loud. Most of the questions are boring. The ones
-- that are not boring are *findings*: places where the original design does something its
-- author did not know about.
--
-- This is not hypothetical. The theremin port (theremin/clash/README.md, "Defects found in
-- the upstream SystemVerilog") surfaced exactly two real bugs in a working, shipped design,
-- both of them width adjustments Verilog performed without comment. This lesson rebuilds
-- both in miniature, shows the compile error that surfaces each one, and then covers the
-- three habits of Verilog that a faithful port must *preserve* rather than fix.

------------------------------------------------------------------------------------------------
-- The block: a pulse-centre converter, generic in its width
------------------------------------------------------------------------------------------------
--
-- The theremin measures an oscillator's period by summing each edge position with the
-- previous one -- twice the midpoint of the pulse, which cancels duty-cycle modulation.
-- The sum of two n-bit positions needs n+1 bits for the carry, and the upstream module says
-- so in its port list (edge_to_pulse_position.sv:49):
--
--     output logic [EDGE_POSITION_BITS : 0] PULSE_POSITION
--
-- Here is the same idea in Clash, one register and one widening add. The width appears
-- once, as a type variable, and the +1 is part of the function's signature -- not a
-- convention the instantiator must remember, a fact the type checker enforces:

pulseCentre ::
  forall n dom.
  (HiddenClockResetEnable dom, KnownNat n) =>
  Signal dom (Unsigned n) ->
  Signal dom (Unsigned (n + 1))
pulseCentre pos = add <$> prev <*> pos
  where
    prev = register 0 pos

-- The theremin has two of these, and their widths differ: the pitch axis oversamples 3x,
-- the volume axis 1x, so their edge positions are 23 and 21 bits. In the SV these are
-- localparams threaded by hand into each instantiation; here they are types:

type PitchBits  = 23
type VolumeBits = 21

sensorPair ::
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned PitchBits) ->
  Signal dom (Unsigned VolumeBits) ->
  Signal dom (Unsigned (PitchBits + 1), Unsigned (VolumeBits + 1))
sensorPair pitchPos volPos = bundle (pulseCentre pitchPos, pulseCentre volPos)

-- Note what is absent: `pulseCentre volPos` names no width at all. The 21 flows from the
-- input's type into `n`, and the output is 22 bits because the signature says n+1. There
-- is no keyboard position from which to hand the volume instance the pitch width -- which
-- is precisely the mistake the upstream design made. Both failure sections below try to
-- re-create one of the real defects; neither survives the compiler.

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Unsigned PitchBits) ->
  Signal System (Unsigned VolumeBits) ->
  Signal System (Unsigned (PitchBits + 1), Unsigned (VolumeBits + 1))
topEntity clk rst en = exposeClockResetEnable sensorPair clk rst en

------------------------------------------------------------------------------------------------
-- FAILURE 1: the copy-pasted parameter (upstream defect #1)
------------------------------------------------------------------------------------------------
--
-- theremin_sensor_period_measure.sv:331 instantiates the *volume* converter with the
-- *pitch* width -- almost certainly a copy-paste from the pitch instance directly above it:
--
--     edge_to_pulse_position
--     #(
--         .EDGE_POSITION_BITS(PITCH_EDGE_POSITION_BITS)     // 23 -- on the VOLUME path
--     )
--     volume_edge_to_pulse_position_inst
--     (   ...
--         .EDGE_POSITION(volume_edge_position),             // declared [20:0] -- 21 bits
--
-- Verilog's reaction: zero-extend the 21-bit signal into the 23-bit port, truncate the
-- 24-bit result back into the 21-bit destination, say nothing. The instrument works --
-- by luck of the ranges involved -- and the mismatch sat in a shipped design until a port
-- to Clash forced every width to be written down.
--
-- The datapath as the SV actually builds it, widths on the wires:
--
--     volume_edge_position     ┌────────────┐      ┌──────────────────────┐
--     ────────── 21 ──────────▶│ zero-extend│─ 23 ▶│ edge_to_pulse_pos    │
--                              │  (implicit)│      │ #(.EDGE_POSITION_    │
--                              └────────────┘      │    BITS(23))  COPY-  │
--                                                  │               PASTE  │
--     volume_pulse_position    ┌────────────┐      │                      │
--     ◀───────── 21 ───────────│  truncate  │◀ 24 ─│  PULSE_POSITION      │
--                              │  (implicit)│      │  [23:0]              │
--                              └────────────┘      └──────────────────────┘
--
-- Neither adjustment box exists anywhere in the source. Both are inserted by connection
-- rules, and neither insertion produces a diagnostic.
--
-- The same mistake, attempted in Clash -- explicitly instantiating the volume converter at
-- the pitch width, which is what a type application is:
--
--     sensorPair pitchPos volPos =
--       bundle (pulseCentre pitchPos, pulseCentre @PitchBits volPos)     -- ERROR (twice)
--
--     src/Lesson12.hs:67:60: error: [GHC-83865]
--         * Couldn't match type `24' with `22'
--           Expected: Signal dom (Unsigned 22)
--             Actual: Signal dom (Unsigned (PitchBits + 1))
--         * In the expression: pulseCentre @PitchBits volPos
--
--     src/Lesson12.hs:67:83: error: [GHC-83865]
--         * Couldn't match type `21' with `23'
--           Expected: Signal dom (Unsigned PitchBits)
--             Actual: Signal dom (Unsigned VolumeBits)
--         * In the second argument of `pulseCentre', namely `volPos'
--
-- (Compiled and confirmed 27 Aug 2026; the "In the first argument of `bundle'..." context
-- lines are trimmed from both.) Two errors, not one, and look at where they land: 21-vs-23
-- at the input argument and 24-vs-22 at the output connection -- one error for each of the
-- two adjustment boxes in the diagram. The places Verilog silently patched are exactly the
-- places Clash reports. In the 515-line SV top this defect hid in plain sight in a working
-- instrument; here it cannot be typed. And the usual case is better still: leave the type
-- application off, as `sensorPair` does above, and the question evaporates -- a parameter
-- that is inferred cannot be copy-pasted wrongly.

------------------------------------------------------------------------------------------------
-- FAILURE 2: the dropped carry bit (upstream defect #2)
------------------------------------------------------------------------------------------------
--
-- The second defect is the connection Lesson 1 previewed: the converter outputs
-- EDGE_POSITION_BITS+1 bits -- the +1 is the carry of the pulse-centre sum -- but the top
-- level declares the receiving signal one bit narrower (localparam at line 274 sets
-- PULSE_POSITION_BITS = EDGE_POSITION_BITS, not +1):
--
--     output logic [EDGE_POSITION_BITS : 0]      PULSE_POSITION;         // 24 bits out
--     logic [PITCH_PULSE_POSITION_BITS - 1 : 0]  pitch_pulse_position;   // 23 bits in
--
--     ┌──────────────────────┐ PULSE_POSITION      pitch_pulse_position
--     │ edge_to_pulse_pos    │──────── 24 ───────┬──────── 23 ────────▶ (delay filter)
--     │ (the sum needs the   │                   │
--     │  carry: n+1 wide)    │              bit 23 dropped
--     └──────────────────────┘              here, silently
--
-- A pulse-centre sum that overflows 23 bits wraps instead of carrying. The same connection
-- in Clash:
--
--     narrowed :: HiddenClockResetEnable dom =>
--       Signal dom (Unsigned PitchBits) -> Signal dom (Unsigned PitchBits)
--     narrowed pos = pulseCentre pos                                    -- ERROR
--
--     src/Lesson12.hs:77:16: error: [GHC-83865]
--         * Couldn't match type `24' with `23'
--           Expected: Signal dom (Unsigned PitchBits)
--             Actual: Signal dom (Unsigned (PitchBits + 1))
--         * In the expression: pulseCentre pos
--           In an equation for `narrowed': narrowed pos = pulseCentre pos
--
-- (Compiled and confirmed 27 Aug 2026.)
--
-- To port the design *faithfully* -- bug and all, so the Clash stays equivalent to what
-- the hardware does today -- the theremin port writes the truncation out where the SV left
-- it silent, with a comment citing this defect (Theremin/SensorPeriodMeasure.hs:140):
--
--     narrowed pos = truncateB <$> pulseCentre pos
--
-- That is the porting discipline in one line: Clash will not stop you from reproducing a
-- Verilog bug, it stops you from reproducing it *without saying so*. The `truncateB` is
-- greppable forever; the SV connection never was.

------------------------------------------------------------------------------------------------
-- Three things a faithful port must preserve, not fix
------------------------------------------------------------------------------------------------
--
-- The defects above were found because the port refused to change behaviour. That cuts
-- both ways: three upstream idioms *look* like things to clean up, and cleaning them up
-- would silently change the design. All three are from the theremin port's notes
-- (theremin/clash/README.md, "Porting notes").
--
-- 1. RESET is data, not a reset network. In theremin_pwm.sv and iir_nstage_pow2k.sv,
--    RESET is a synchronous active-high *input port* -- upstream fans it out like any
--    other signal. Mapping it onto Clash's `Reset dom` would change the generated entity's
--    port list and its semantics (Clash resets also initialise; see point 3). The port
--    keeps it as an ordinary field and handles it in the step function:
--
--        e2pStep s E2PIn{..}
--          | eiReset == high = initialState
--          | otherwise       = ...
--
-- 2. Two independent `if`s are not `if/else`. The upstream PWM writes its RGB channel
--    compare logic as two separate non-blocking assignments to the same register:
--
--        if (counter == on_time)  out <= 1'b1;
--        if (counter == off_time) out <= 1'b0;
--
--    For a colour nibble of 0, on_time equals off_time, BOTH fire in the same cycle, and
--    SystemVerilog defines that the textually later assignment wins: nibble 0 means dark.
--    The obvious "cleaner" port -- an if/else, or Haskell guards in source order --
--    quietly inverts that priority and makes nibble 0 mean full-on. The faithful port
--    encodes last-write-wins by checking the LATER assignment first:
--
--        out' | counter == offTime = low     -- later SV write: highest priority
--             | counter == onTime  = high
--             | otherwise          = out
--
--    Guards are exclusive by construction, so the priority that Verilog spreads across an
--    ordering rule becomes visible, reorderable -- and testable -- source text.
--
-- 3. State banks survive reset. iir_nstage_pow2k's states[8] memory has no reset in the
--    SV -- filter_en is what makes that safe -- and on ECP5 it infers as distributed RAM
--    precisely *because* nothing resets it. The port keeps the bank in `asyncRam` (which
--    has no reset input) rather than in registers, so the contents ride through reset
--    exactly as the original's do. "Add a reset to be safe" would have pushed the bank
--    into fabric flip-flops -- the naive-idiom penalty the theremin work measured at 3x
--    the LUTs on this very block (theremin/clash/README.md) -- and changed post-reset
--    behaviour at the same time.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Build both endings of defect #2: the faithful `truncateB <$> pulseCentre pos` and the
--    fixed full-width version. Feed both, with `sampleN`, a pair of edge positions whose
--    sum crosses 2^23, and show one wraps where the other carries.
--
-- 2. Port the two-`if` PWM channel (point 2 above) and its if/else mistranslation, and
--    write the one `sampleN` comparison that tells them apart. How many cycles do you need
--    to observe, and at which nibble value?
--
-- 3. The volume path in FAILURE 1 was zero-extended in and truncated out, and the
--    instrument still worked. Work out from `pulseCentre` why: at which oscillator period
--    does the 21-vs-23 mismatch first change an output bit, and is it reachable at the
--    volume antenna's 1x oversampling?
