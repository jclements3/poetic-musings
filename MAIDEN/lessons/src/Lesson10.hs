-- Lesson 10: types as the sizing tool.
--
--     Build:  cabal exec -- clash -isrc Lesson10 --vhdl
--     Output: vhdl/Lesson10.topEntity/topEntity.vhdl
--
-- Add `Lesson10` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson10 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- Every DSP datapath is a sizing problem wearing a math problem's clothes. Multiply two
-- 16-bit samples: 32 bits. Sum four of those: 34. Chain nine FFT stages: nine more bits, or
-- nine deliberate scalings. In Verilog the sizing plan lives in a comment, a spreadsheet,
-- or the designer's head, and the language wraps whatever disagrees with it -- silently, per
-- Lesson 1. In Clash the plan IS the type. This lesson sizes one multiply-accumulate chain
-- three ways, and ends at the real decision MAIDEN's FFT had to make when the plan met a
-- 16-bit memory.
--
-- Two operator families do arithmetic here, and the split is the whole tool:
--
--     (+), (*)   :: a -> a -> a              -- SAME width in, same width out: wraps.
--                                            -- You chose the width; you own the wrap.
--     add, mul   :: a -> b -> (bigger)       -- from ExtendingNum: the result type GROWS
--                                            -- to hold every possible answer. Never wraps.
--
-- `mul` on two `Signed 16`s returns `Signed 32`, because (-32768)^2 needs it. The full
-- product exists in the type system before any hardware exists at all; narrowing it back
-- down is something you must write, visibly, with `resize` -- and where you put that resize
-- is the design, exactly as it was in Lesson 1.

------------------------------------------------------------------------------------------------
-- A four-tap MAC, sized by hand -- with the type checking the hand
------------------------------------------------------------------------------------------------
--
-- Dot product of four samples with four coefficients: the inner loop of every FIR filter,
-- including the theremin's. The sizing argument: products are Signed 32; each doubling of
-- the number of addends needs one more bit; 4 = 2^2 addends, so the sum needs 32 + 2 = 34
-- bits. Write the conclusion in the signature and let the compiler audit the arithmetic:

mac4 :: Vec 4 (Signed 16) -> Vec 4 (Signed 16) -> Signed 34
mac4 xs cs = fold (+) (map resize products)
  where
    products :: Vec 4 (Signed 32)
    products = zipWith mul xs cs

topEntity :: Vec 4 (Signed 16) -> Vec 4 (Signed 16) -> Signed 34
topEntity = mac4

-- The datapath, widths on every wire -- the numbers are the lesson, and every box is the
-- exact subexpression that makes it:
--
--     xs!0 ─16─┐
--              ├ mul ─32─ resize ─34─┐
--     cs!0 ─16─┘                     ├ (+) ─34─┐
--     xs!1 ─16─┐                     │         │
--              ├ mul ─32─ resize ─34─┘         │
--     cs!1 ─16─┘                               ├ (+) ─34──► mac4 xs cs :: Signed 34
--     xs!2 ─16─┐                               │
--              ├ mul ─32─ resize ─34─┐         │
--     cs!2 ─16─┘                     ├ (+) ─34─┘
--     xs!3 ─16─┐                     │
--              ├ mul ─32─ resize ─34─┘
--     cs!3 ─16─┘
--
--     mul    column: zipWith mul xs cs      -- 16x16 -> 32, the full product, by type
--     resize column: map resize products    -- 32 -> 34: sign-extend INTO the sum width
--     (+)    tree:   fold (+)               -- all adds at 34; wrapping, but unreachable
--
-- Two honest notes on that figure. The first-layer adds carry 34 bits but could only ever
-- need 33 -- one bit of slack, spent to keep the whole tree at one type so `fold` applies.
-- And the `(+)`s are the WRAPPING operator -- safe here only because the resize bought
-- enough headroom that no sum can reach the edge. The type checker verified the widths
-- agree; the claim that 34 is ENOUGH is still yours (the sizing argument above). Lesson 9
-- is how you check claims; FAILURE 2 below is what happens when you get this one wrong.

------------------------------------------------------------------------------------------------
-- The same block, parameterised: the sizing memo becomes the signature
------------------------------------------------------------------------------------------------
--
-- Lesson 4 made generics into type parameters. Do it to the MAC and the sizing FORMULA --
-- "product width plus ceil(log2(taps))" -- moves into the type, where it is checked at
-- every instantiation instead of recomputed in a comment at each one:

macN ::
  forall n.
  KnownNat n =>
  Vec (n + 1) (Signed 16) ->
  Vec (n + 1) (Signed 16) ->
  Signed (32 + CLog 2 (n + 1))
macN xs cs = fold (+) (map resize (zipWith mul xs cs))

-- `CLog 2 m` is type-level ceil(log2(m)), from ghc-typelits-extra (the solver plugins in
-- lessons.cabal do the arithmetic). `macN @3` is `mac4` with the same Signed 34; `macN @7`
-- is an 8-tap MAC at Signed 35 -- widths you never compute again. The `n + 1` in the
-- signature is not decoration either: it promises the vector is non-empty, and FAILURE 1
-- shows the compiler holding that line.

------------------------------------------------------------------------------------------------
-- Fixed point, and the decision growth forces eventually
------------------------------------------------------------------------------------------------
--
-- `SFixed int frac` gives the same discipline a binary point. `mul` grows BOTH fields --
--
--     mul :: SFixed 1 15 -> SFixed 1 15 -> SFixed 2 30
--
-- -- and `resizeF` narrows back, truncating toward negative infinity unless you round
-- first. Nothing new: it is `mul`/`resize` with the point tracked for you.
--
-- But growth cannot go on forever, and the interesting case is when it hits a physical
-- wall. MAIDEN's 512-point streaming FFT (Theremin.Fft) is nine butterfly stages of Q1.15
-- complex samples. Let every add grow one bit and the datapath ends 25 bits wide -- except
-- the delay lines between stages live in block RAM and the multipliers are 18x18 DSPs, so
-- a growing word would burst the memory geometry the architecture is built on. Hoping the
-- signal stays small instead is not sizing, and the original model did overflow: Fft.hs's
-- header records "Q1.15 cadd/csub had no growth headroom" as real defect #3, found by the
-- Lesson-9 checks (the reference-DFT comparison in theremin/clash/test/FftSpec.hs).
--
-- The fix is the third option, chosen stage by stage: SCALE. Each butterfly output is
-- computed in 17 bits, halved with round-half-up, and stored back in 16 (per-stage 1/2
-- scaling); nine stages make the transform compute X[k]/512, and with that scaling every
-- internal magnitude is bounded by the input magnitude -- the pipeline cannot overflow
-- (Fft.hs, Numerics section). Same word width at every stage, no hope involved. Measured
-- on the LFE5U-85F: 3,537 LUT4, 28 DSP, 10 BRAM, timing-clean at 123.59 MHz (Jim's
-- numbers, yosys + nextpnr).
--
-- So the sizing toolbox is exactly three tools, all of them types-first:
--
--     grow    add/mul -- carry every bit; right up until a memory or DSP says stop
--     wrap    (+)/(*) at a width YOU proved sufficient (mac4: the resize bought it)
--     scale   divide as you go, and own the precision loss (the FFT: 1/2 per stage)
--
-- What Clash removes is the fourth tool Verilog offers by default: wrap at a width nobody
-- proved anything about, silently, at every assignment.

------------------------------------------------------------------------------------------------
-- FAILURE 1: asking fold to grow
------------------------------------------------------------------------------------------------
--
-- If `add` never loses a bit, why not build the whole tree from it?
--
--     macBad :: Vec 4 (Signed 16) -> Vec 4 (Signed 16) -> Signed 34
--     macBad xs cs = fold add (zipWith mul xs cs)
--
--     src/Lesson10.hs:100:21: error: [GHC-83865]
--         * Couldn't match type `35' with `34'
--           Expected: Signed 34 -> Signed 34 -> Signed 34
--             Actual: Signed 34 -> Signed 34 -> AResult (Signed 34) (Signed 34)
--         * In the first argument of `fold', namely `add'
--
--     src/Lesson10.hs:100:34: error: [GHC-83865]
--         * Couldn't match type `32' with `34'
--           Expected: Signed 16 -> Signed 16 -> Signed 34
--             Actual: Signed 16 -> Signed 16 -> MResult (Signed 16) (Signed 16)
--         * In the first argument of `zipWith', namely `mul'
--
-- Compiled and confirmed 27 Aug 2026 -- and the numbers in the message are worth a second
-- look. `fold` demands `a -> a -> a`, one type through the whole tree; the declared result
-- pins that type to Signed 34, so GHC reports `add` producing 35 where 34 must go, and (a
-- second error) `mul` producing 32 where 34 must go. Whichever end inference starts from,
-- the same design fact surfaces: `add`'s result is one bit wider than its arguments ON
-- PURPOSE, so a growing adder tree has a different width at every level, and no
-- single-typed fold can express that. Your options are the two working versions above:
-- resize everything into the final width first (mac4/macN), or write the levels explicitly
-- so each can have its own type (exercise 1; `dtfold` in Clash.Sized.Vector is the fully
-- general form). Verilog answers the same question by wrapping every level at the declared
-- width and saying nothing.

------------------------------------------------------------------------------------------------
-- FAILURE 2: the audit catches a bad sizing memo
------------------------------------------------------------------------------------------------
--
-- Claim the sum fits in the product width -- drop the resize but keep the 34-bit promise:
--
--     macBad2 :: Vec 4 (Signed 16) -> Vec 4 (Signed 16) -> Signed 34
--     macBad2 xs cs = fold (+) (zipWith mul xs cs)
--
--     src/Lesson10.hs:100:35: error: [GHC-83865]
--         * Couldn't match type `32' with `34'
--           Expected: Signed 16 -> Signed 16 -> Signed 34
--             Actual: Signed 16 -> Signed 16 -> MResult (Signed 16) (Signed 16)
--         * In the first argument of `zipWith', namely `mul'
--
-- Compiled and confirmed 27 Aug 2026. Lesson 1's very first error, resurfacing at the far
-- end of the course with real numbers attached: the 34 came from the sizing argument, the
-- 32 came from `mul`, and the compiler is pointing at the two-bit gap where the carry
-- bits of a four-way sum would have gone. (Note `MResult (Signed 16) (Signed 16)` in the
-- message: the error shows `mul`'s result as the unreduced type FAMILY -- the growth rule
-- itself, visible mid-computation, before it evaluates to Signed 32.)
--
-- And one finding, stated honestly because a draft of this lesson expected otherwise:
-- change `macBad2`'s signature to `Signed 32` and it COMPILES -- confirmed 27 Aug 2026.
-- Of course it does: every type then agrees, and `(+)` wraps at 32 exactly as asked. The
-- type system forces your widths to be CONSISTENT; it cannot know 32 was insufficient. The
-- sizing argument -- addends times width, the CLog line in `macN` -- is still engineering
-- you do. What the types guarantee is that the plan is written where the compiler audits
-- every use of it, and Lesson 9's properties are where a consistently-wrong plan goes to
-- be caught (a boxcar summing at 8 bits died exactly that death there).

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Rewrite mac4's tree with explicit `add`s and no resize at all:
--    `(p0 `add` p1) `add` (p2 `add` p3)`. What output type does the compiler compute?
--    Check it against the diagram's widths -- then decide which version you would rather
--    maintain at 64 taps.
--
-- 2. Build the saturating variant: resize the products into 33 bits (one bit short, on
--    purpose) and fold with `satAdd SatBound` -- which IS `a -> a -> a`, so fold takes it.
--    Feed it the worst-case input and watch it clamp where mac4 could not have. Then diff
--    the VHDL: saturation is a comparator and mux per add, and now you can count what the
--    FFT saved by scaling instead.
--
-- 3. The SFixed dot product: four Q1.15 samples, four Q1.15 coefficients, result Q3.15
--    (why 3?). Where does `resizeF` go, and what rounding did you just silently choose?
--    Compare with Fft.hs's round-half-up-then-halve -- which is not silent about it.
--
-- 4. `macN @7` claims Signed 35. Instantiate it, check the claim in the repl with
--    `:t macN @7`, and then work out the first tap count at which the accumulator no
--    longer fits in an ECP5 54-bit DSP cascade. The type-level formula answers in one
--    substitution; that is the point of having it.
