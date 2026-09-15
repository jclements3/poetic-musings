{-# LANGUAGE NumericUnderscores #-}
{-|
MAIDEN detector: cell-averaging CFAR over the Doppler magnitude stream.

Position in the chain: consumes CORDIC bin magnitudes ("Maiden.Cordic") at
one cell per clock and flags cells whose magnitude exceeds @α ×@ the mean
of the surrounding noise estimate — constant false-alarm rate against a
varying noise floor.

== Window geometry

@
  newer  ←  16 reference | 2 guard | CUT | 2 guard | 16 reference  →  older
@

32 reference cells total, 2 guard cells each side of the cell under test.
The noise estimate is the /mean/ of the reference cells; the threshold is
@α · mean@ with @α@ in unsigned Q4.4 (so α covers 1\/16 … 15.9375, term
parameter, 5.0 in 'topEntity'). The compare is done cross-multiplied so
there is no divider:

@
  detect  ⇔  cut · 32 · 16  >  α_q44 · Σ(reference)
@

Strictly greater: an all-zero stream must not detect (0 > 0 is false).

== Structure — RAM shift line, not a fabric-FF shift register

A 37-cell window of 18-bit cells as flops would be 666 FFs of pure
shift register. Instead the window lives in RAM-based delay lines: a
'blockRam' with a cycling write pointer and the read pointer one slot
/ahead/ of it, so the read always hits the oldest entry and never collides
with the write (Clash's 'blockRam' is write-first on a collision, which
would leak the input straight through). A depth-@d@ RAM plus its one-cycle
read latency is then exactly a @d@-cycle delay — and depth 16 × 18 bits is
precisely one column of @TRELLIS_DPR16X4@ distributed RAM on ECP5. The two
reference sums are /running/ sums: each clock adds the cell entering the
window and subtracts the one leaving. Only four taps of the delay chain
are ever read:

@
  x ─ RAM(16) ─ x[n-16] ─ 3 regs ─ x[n-19] ─ 2 regs ─ x[n-21] ─ RAM(16) ─ x[n-37]
       (lead sum in/out)            (CUT)            (lag sum in)          (lag sum out)
@

(The short 2–3 cycle hops are plain registers; burning a RAM on a depth-2
delay would cost more than the flops it saves.) With the registered sums,
at clock @n@ the lead window is @x[n-1 .. n-16]@, guards @x[n-17], x[n-18]@,
CUT @x[n-19]@, guards @x[n-20], x[n-21]@, lag window @x[n-22 .. n-37]@.
The compare is pipelined: the reference total @Σref@ is registered, then
@α·Σref@ and @cut·2^9@ are registered, then the strict compare feeds the
registered output (detect flag + the CUT magnitude it refers to). Without
those two stages the add → DSP multiply → 31-bit carry-chain compare land
in one cycle and cap Fmax around 70 MHz on the LFE5U-85; with them the
block clears 100 MHz. **Latency: 22 clocks** from a cell entering to its
verdict appearing.

Zero-initialised RAMs and sums mean the warm-up transient behaves exactly
as if the stream had been all-zero forever — the golden model in
@CfarSpec@ relies on that to check the hardware cycle-for-cycle.
-}
module Maiden.Cfar
  ( RefCells
  , GuardCells
  , cfar
  , ramDelay
  , topEntity
  ) where

import Clash.Prelude

-- | Reference cells per side.
type RefCells = 16

-- | Guard cells per side.
type GuardCells = 2

-- | A @d@-cycle delay through a depth-@d@ RAM: cycling write pointer, read
-- pointer one slot ahead (the oldest entry, written @d-1@ cycles earlier),
-- plus one cycle of RAM read latency. Reading ahead of the write avoids
-- the same-address collision, on which Clash's 'blockRam' is write-first.
ramDelay ::
  forall d dom a.
  (HiddenClockResetEnable dom, NFDataX a, KnownNat d, 2 <= d) =>
  SNat d ->
  a ->
  Signal dom a ->
  Signal dom a
ramDelay SNat z xs = blockRam (replicate (SNat @d) z) rdAddr wr
 where
  wrAddr, rdAddr :: Signal dom (Index d)
  wrAddr = register 0 (satSucc SatWrap <$> wrAddr)
  rdAddr = satSucc SatWrap <$> wrAddr
  wr     = Just <$> bundle (wrAddr, xs)

-- | CA-CFAR over a magnitude stream, one cell per clock.
cfar ::
  forall dom.
  HiddenClockResetEnable dom =>
  Unsigned 8 ->                          -- ^ α in Q4.4
  Signal dom (Unsigned 18) ->            -- ^ cell magnitudes
  Signal dom (Bool, Unsigned 18)         -- ^ (detect, that cell), 22 clocks later
cfar alphaQ44 x = register (False, 0) (bundle (detect, cutDelayed))
 where
  -- The four taps of the window delay chain.
  x16 = ramDelay (SNat @16) 0 x          -- x[n-16]: leaves the lead window
  x19 = regs (SNat @3) x16               -- x[n-19]: the CUT
  x21 = regs (SNat @2) x19               -- x[n-21]: enters the lag window
  x37 = ramDelay (SNat @16) 0 x21        -- x[n-37]: leaves the lag window

  regs :: KnownNat k => SNat k -> Signal dom (Unsigned 18) -> Signal dom (Unsigned 18)
  regs k = repeatN k (register 0)
   where repeatN :: SNat k -> (b -> b) -> b -> b
         repeatN n f = foldr (.) id (replicate n f)

  -- Running window sums: 16 cells × 18 bits needs 22 bits.
  leadSum, lagSum :: Signal dom (Unsigned 22)
  leadSum = register 0 (leadSum + (resize <$> x) - (resize <$> x16))
  lagSum  = register 0 (lagSum + (resize <$> x21) - (resize <$> x37))

  cut = x19

  -- detect ⇔ cut·2^9 > α_q44 · Σref  (2^9 = 32 cells × 16 for Q4.4).
  -- Pipelined: Σref registered, then α·Σref and cut·2^9 registered, then
  -- the compare into the output register.
  refTotal :: Signal dom (Unsigned 23)
  refTotal = register 0 ((\ls gs -> resize ls + resize gs)
                           <$> leadSum <*> lagSum)

  cutScaled, thresh :: Signal dom (Unsigned 31)
  cutScaled = regs2 ((\c -> resize c `shiftL` 9) <$> cut)
  thresh    = register 0 ((\t -> resize alphaQ44 * resize t) <$> refTotal)

  regs2 :: NFDataX b => Num b => Signal dom b -> Signal dom b
  regs2 = register 0 . register 0

  cutDelayed = regs2 cut
  detect     = (>) <$> cutScaled <*> thresh

-- | Synthesis root: α = 5.0 (Q4.4 = 80).
topEntity ::
  Clock System ->
  Signal System (Unsigned 18) ->
  Signal System (Bool, Unsigned 18)
topEntity clk x =
  withClockResetEnable clk resetGen enableGen (cfar 80 x)
{-# ANN topEntity
  (Synthesize
    { t_name = "maiden_cfar"
    , t_inputs = [PortName "CLK", PortName "MAG"]
    , t_output = PortProduct "" [PortName "DETECT", PortName "CELL"]
    }) #-}
{-# NOINLINE topEntity #-}
