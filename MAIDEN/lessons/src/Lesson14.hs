-- Lesson 14: ON HARDWARE.
--
--     ██ BLOCKED ██  The board -- an Alchitry Cu (iCE40HX8K-CB132) with the Br breakout,
--     ordered 27 Aug 2026 -- has not arrived. Everything through `icepack` below has been
--     RUN and its output quoted; everything from `openFPGALoader` on has NOT, and this
--     lesson does not pretend otherwise. Unblock by plugging in the board and following
--     theremin/clash/bringup/BRINGUP.md, the arrival-day runbook this lesson is built on.
--
--     Build:  cabal exec -- clash -isrc Lesson14 --vhdl
--     Output: vhdl/Lesson14.topEntity/topEntity.vhdl
--
-- Add `Lesson14` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson14 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Thirteen lessons ran without a board, and that was a feature: types, simulation, GHDL
-- elaboration, and place-and-route each catch a failure class on the laptop, minutes after
-- the mistake. Hardware is where the remaining classes live -- wrong pins, bad cables,
-- analog reality -- and the discipline for meeting them is the same one as everywhere else
-- in this series: change one variable at a time, and make the first test the one with the
-- fewest ways to fail.
--
-- The target is the Alchitry Cu: a Lattice iCE40HX8K in the CB132 package, 100 MHz
-- oscillator on board, USB programming through its FTDI, LEDs on the base board, and the
-- Br breakout stacked on top for real I/O. The theremin fit check (results/design-notes/
-- ice40-theremin-fit.md) measured the complete instrument at 2,432 of its 7,680 logic
-- cells -- 3x headroom -- which is why this board and not a bigger one.

------------------------------------------------------------------------------------------------
-- The block: a blinky, because the blinky is a test instrument
------------------------------------------------------------------------------------------------
--
-- The first bitstream on any board should be the one whose only failure modes are the
-- board, the cable, and the pins -- no logic worth doubting. One LED walking along the
-- bank about once per second proves: the clock oscillator runs, the design got placed on
-- real pins, the programmer works, and your eyes are on the right board.

ledWalk :: HiddenClockResetEnable dom => Signal dom (BitVector 8)
ledWalk = walk <$> cnt
  where
    cnt = register (0 :: Unsigned 30) (cnt + 1)
    walk c = 1 `shiftL` fromIntegral (slice d29 d27 c)

-- At the Cu's 100 MHz, bit 27 advances every 2^27 / 1e8 = 1.34 s: an eight-LED walk with a
-- period of about eleven seconds. Slow is deliberate -- a blink too fast to see and a stuck
-- LED look identical.

-- Board-shaped, not lesson-shaped: the Cu's blinky reality is one clock in and eight LEDs
-- out, so reset and enable are supplied internally instead of exposed as ports. A port the
-- board does not have is a .pcf line you cannot write.

topEntity ::
  Clock System ->
  Signal System (BitVector 8)
topEntity clk = withClockResetEnable clk resetGen enableGen ledWalk

------------------------------------------------------------------------------------------------
-- The iCE40 flow, run 27 Aug 2026 (board absent -- none of this needs it)
------------------------------------------------------------------------------------------------
--
-- Same shape as Lesson 11's ECP5 flow with the family swapped, plus `icepack`, which turns
-- nextpnr's textual output into the binary bitstream the programmer wants:
--
--     source ~/tools/oss-cad-suite/environment
--     cabal exec -- clash -isrc Lesson14 --verilog
--     yosys -p 'read_verilog verilog/Lesson14.topEntity/topEntity.v;
--               synth_ice40 -top topEntity -json build/lesson14.json'
--     nextpnr-ice40 --hx8k --package cb132 --freq 100 \
--         --json build/lesson14.json --pcf lesson14.pcf --asc build/lesson14.asc
--     icepack build/lesson14.asc build/lesson14.bin
--
-- What nextpnr printed for this blinky, run 27 Aug 2026 (abridged as in Lesson 11):
--
--     Info: Device utilisation:
--     Info:          ICESTORM_LC:      41/   7680     0%
--     Info:         ICESTORM_RAM:       0/     32     0%
--     Info:                SB_IO:       9/     95     9%
--     Info:                SB_GB:       1/      8    12%
--
--     Info: Max frequency for clock 'clk$SB_IO_IN_$glb_clk':
--         164.02 MHz (PASS at 100.00 MHz)
--
-- (The Max frequency line is one line in the log, wrapped to fit.) 41 logic cells -- the
-- 30-bit counter plus the 3-to-8 decode -- and `icepack` then produced a 135,100-byte
-- build/lesson14.bin. That is where the laptop's reach ends: the bitstream exists and is
-- correct as far as any tool can know; whether it blinks is a fact about the physical
-- world.
--
-- The remaining step, VERBATIM FROM THE RUNBOOK AND NOT YET RUN -- no board:
--
--     openFPGALoader -b alchitry_cu build/lesson14.bin
--
-- (If `-b alchitry_cu` is not in your openFPGALoader build, BRINGUP.md's fallback is
-- `iceprog build/lesson14.bin`.)

------------------------------------------------------------------------------------------------
-- FAILURE: the missing pin -- and the non-failure that is worse
------------------------------------------------------------------------------------------------
--
-- A .pcf maps the design's port names to package balls. The lesson-sized lesson14.pcf
-- (alongside this file) takes its pins from the bring-up runbook's blinky.pcf, which took
-- them from the Alchitry base project:
--
--     set_io clk       P7      # 100 MHz oscillator
--     set_io result[0] J11     # led[0]
--     ...                      # (result[1..7]: K11 K12 K14 L12 L14 M12 N14)
--
-- Delete ONE line of it -- result[7] -- and re-run nextpnr (done 27 Aug 2026):
--
--     ERROR: IO 'result[7]' is unconstrained in PCF (override this error with
--         --pcf-allow-unconstrained)
--     ERROR: Loading PCF failed.
--
-- (First ERROR wrapped to fit.) Good: an incomplete pin map is a hard stop. But here is
-- the finding this lesson expected to be different -- omit the `--pcf` argument ENTIRELY,
-- and nextpnr does NOT fail:
--
--     Warning: No PCF file specified; IO pins will be placed automatically
--     ...
--     Info: Max frequency for clock 'clk$SB_IO_IN_$glb_clk': 170.50 MHz (PASS at 100.00 MHz)
--
-- Exit code zero, a bitstream on disk, every pin chosen by the placer's convenience. A
-- constraint file protects you only from its own gaps, not from its absence -- and a
-- bitstream driving the placer's pin choices is indistinguishable from a dead board at
-- exactly the moment you are least equipped to tell them apart. (It is why Lesson 11 and
-- the fit checks could run pinless: for area and Fmax numbers, auto-placed IO is a
-- feature. For a board it is the trap.) The moral for the flow above: the .pcf is as much
-- a part of the design as the HDL, and the Makefile, not your memory, is what guarantees
-- the flag is present.
--
-- The caveat that matters, straight from the runbook: pins copied from a vendor base
-- project are high-confidence; pins *deduced* from a schematic are best guesses until a
-- signal has actually wiggled on them. BRINGUP.md flags its three Br-bank pins (audio,
-- fake_osc, pitch_in) as exactly that. A wrong guess on the iCE40 means silence, never
-- damage -- but "verify against the schematic before wiring" is the cheap version of that
-- lesson and "silence" is the expensive one.

------------------------------------------------------------------------------------------------
-- Arrival day: the self-test-first ladder (blocked until the Cu arrives)
------------------------------------------------------------------------------------------------
--
-- BRINGUP.md scripts arrival day as a ladder where each rung adds exactly one new way to
-- fail, so whatever breaks names its own culprit:
--
--     rung                                adds only            if it fails, suspect
--     ------------------------------------------------------------------------------------
--     1  factory demo LEDs                board + power        the board, the USB port
--     2  openFPGALoader --detect          the cable, the OS    a charge-only micro-USB
--                                                              cable (the classic; carry
--                                                              two cables)
--     3  openFPGALoader -b alchitry_cu    OUR toolchain        the flow above, the LED pins
--          bin/blinky.bin
--     4  theremin-selftest.bin            the whole DSP chain  pitch-map constants, audio
--          (synthetic oscillators         driven by synthetic  pin guess -- NOT the chain
--           inside; zero wiring)          inputs               itself, which simulation
--                                                              already pinned down
--     5  theremin-jumper.bin, one wire    the real input path  the Br pin guesses, the
--          from fake_osc to pitch_in                           jumper
--     6  the Colpitts breadboard          analog reality       the analog -- and ONLY the
--                                                              analog, because rungs 1-5
--                                                              cleared everything else
--
-- Rung 4 is the philosophy in miniature: the complete digital instrument -- edge capture
-- to pulse centres to both filter stages to NCO to delta-sigma DAC -- validated audibly
-- with zero wiring, because the stimulus is synthesised inside the FPGA. Self-test first:
-- when the breadboard finally connects at rung 6, every wire it meets is already known
-- good. The prebuilt bitstreams for rungs 3-5 exist today (timing-clean at 50 MHz:
-- selftest 58.3 MHz, jumper 62.5 MHz -- BRINGUP.md), which is what "written but blocked"
-- means: the software half of arrival day is finished and measured, and the remaining
-- work is a parcel.
--
-- The bench, as it will be wired (Br pins marked ? are the best-guesses of the runbook):
--
--     laptop ──USB (DATA cable!)──▶┌─────────────────────────┐
--                                  │ Alchitry Cu             │
--                                  │   FTDI ──▶ iCE40HX8K    │
--                                  │   100 MHz osc, 8 LEDs   │
--                                  └───────────┬─────────────┘
--                                              │ stacked headers
--                                  ┌───────────┴─────────────┐
--                                  │ Br breakout             │
--                                  │  A5? audio ─────────────┼──▶ 1 kOhm ──┬──▶ powered
--                                  │  A6? fake_osc ──┐       │           10 nF   speaker
--                                  │  A7? pitch_in ◀─┘jumper │             │
--                                  └─────────────────────────┘            GND
--                                       (rung 5: the one wire)
--
--     The RC pair is the reconstruction filter for the 1-bit delta-sigma DAC output --
--     the analog low-pass that turns a bit stream into a waveform (rung 4's "probe the
--     audio pin through 1 kOhm + 10 nF").

------------------------------------------------------------------------------------------------
-- Exercises (the first two run today; the third is the board's first job)
------------------------------------------------------------------------------------------------
--
-- 1. `sampleN` proves a blinky the same way it proves a filter: sample `ledWalk` past the
--    first walk step and check the one-hot position. How many cycles is that, and is your
--    simulator run of 2^27 cycles a good idea? (This is why self-test bitstreams synthesise
--    their stimulus at speed instead of simulating wall-clock seconds.)
--
-- 2. Retarget the Lesson 11 autocorrelator at this part: swap `synth_ecp5`/`nextpnr-ecp5`
--    for the commands above and read what became of the DSP and BRAM columns -- the HX8K
--    has no multipliers, so watch where `mul` lands and what that does to Fmax.
--
-- 3. When the Cu arrives: run the BRINGUP.md ladder, and before wiring anything to the Br,
--    verify the three ?-pins against the Alchitry Cu schematic and correct theremin.pcf.
--    The notes you take on what was actually wrong are the raw material for Lesson 15.
