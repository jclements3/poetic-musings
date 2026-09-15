-- Lesson 1-2: a wire is a function; widths are types.
--
--     Build:  cabal exec -- clash -isrc Lesson01 --vhdl
--     Output: vhdl/Lesson01.topEntity/topEntity.vhdl
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson01 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- 0. The starting point: widths agree, nothing to decide.
------------------------------------------------------------------------------------------------
--
-- Generates:
--
--     port(x      : in  unsigned(7 downto 0);
--          result : out unsigned(7 downto 0));
--     result <= x + to_unsigned(1,8);
--
-- Note what is absent: no port list, no process, no sensitivity list. Combinational logic is
-- an expression, so the classic Verilog bug of omitting a signal from the sensitivity list
-- has no way to exist here. The width `8` is written in the type and nowhere else.

topEntity :: Unsigned 8 -> Unsigned 8
topEntity x = x + 1

-- The whole circuit, and which subexpression each part is:
--
--                x                ┌──────┐            result
--     ───────────────────────────▶  + 1 │──────────────────────▶
--         unsigned(7 downto 0)   └──────┘    unsigned(7 downto 0)
--
--     topEntity x  =  x + 1
--         │           │   │
--         │           │   └── the adder box
--         │           └────── the left wire, width carried by the type of x
--         └────────────────── the right wire: a function's result IS the output port

------------------------------------------------------------------------------------------------
-- 1. THE ONE THAT DOES NOT COMPILE -- and why that is the point.
------------------------------------------------------------------------------------------------
--
--     topEntity :: Unsigned 8 -> Unsigned 4
--     topEntity x = x + 1
--
--     src/Lesson01.hs:5:15: error: [GHC-83865]
--         * Couldn't match type `8' with `4'
--           Expected: Unsigned 4
--             Actual: Unsigned 8
--
-- (+) has type  a -> a -> a : both operands and the result are the SAME type. The signature
-- demands Unsigned 4 out; x is Unsigned 8; there is no consistent choice, so compilation
-- stops.
--
-- Verilog accepts the equivalent without comment:
--
--     assign result = x + 1;     // result 4-bit, x 8-bit
--
-- It elaborates, synthesises, and silently discards the top four bits. The failure surfaces
-- on the bench when a value above 15 wraps.
--
-- This is not hypothetical. Upstream fpga-theremin has exactly this bug:
-- edge_to_pulse_position outputs EDGE_POSITION_BITS+1 bits (summing two edge positions needs
-- the carry), but the top level connects it to a signal declared at EDGE_POSITION_BITS. The
-- MSB is dropped and an overflowing pulse-centre sum wraps. Nothing in the Verilog toolchain
-- complains; porting to a language that insists widths be stated is what surfaced it.
--
-- The rule: narrowing is never something you do by accident. You must say so -- and WHICH
-- narrowing you want is a real design decision.

------------------------------------------------------------------------------------------------
-- 2. Truncate: add at 8 bits, keep the low 4. Wraps.
------------------------------------------------------------------------------------------------
--
--     topEntity :: Unsigned 8 -> Unsigned 4
--     topEntity x = truncateB (x + 1)
--
-- Generates a bare slice after the adder. Input 20 -> 21 -> 5.
--
-- Parenthesisation is itself the design:
--
--     truncateB (x + 1)     -- add at 8 bits, then narrow
--     truncateB x + 1       -- narrow to 4 bits, then add
--
-- Different hardware. Both compile. The type forces you to pick.

------------------------------------------------------------------------------------------------
-- 3. Resize: identical hardware to (2) when narrowing an Unsigned.
------------------------------------------------------------------------------------------------
--
--     topEntity :: Unsigned 8 -> Unsigned 4
--     topEntity x = resize (x + 1)
--
-- `diff` against (2) is empty -- resize on an Unsigned narrowing IS truncation. It differs
-- from truncateB only in that it also works in the widening direction (zero-extend for
-- Unsigned, sign-extend for Signed), so it is the one to reach for in parameterised code.

------------------------------------------------------------------------------------------------
-- 4. Saturate: clamp at 15 rather than wrapping.
------------------------------------------------------------------------------------------------
--
--     topEntity :: Unsigned 8 -> Unsigned 4
--     topEntity x = satSucc SatBound (resize x)
--
-- Generates a comparison and a mux that (2) and (3) do not have -- real gates bought in
-- exchange for defined overflow behaviour.
--
-- CAUTION, and worth breaking on purpose now rather than in the Doppler chain later:
-- `resize x` narrows FIRST, then satSucc increments with clamping. Input 20 truncates to 4,
-- then increments to 5 -- not 15. The saturation protects the increment, not the narrowing.
-- To clamp the narrowing itself you must compare at the wide width before resizing.
--
-- This is the same ordering lesson as (2), and it is the reason the FFT carries explicit
-- per-stage 1/2 scaling: where the rounding and clipping happen is a decision, and the type
-- system makes you make it rather than discovering it in a spectrum that looks almost right.

------------------------------------------------------------------------------------------------
-- Exercise
------------------------------------------------------------------------------------------------
--
-- Write a version that clamps the NARROWING correctly -- input 20 should give 15, not 5.
