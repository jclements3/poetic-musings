{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RecordWildCards #-}
{-|
MAIDEN Doppler magnitude\/phase extractor: a 16-iteration vectoring-mode
CORDIC, pipelined one iteration per stage.

Position in the chain: the 512-pt FFT produces complex bins; this block
turns a bin (I, Q) into polar form — magnitude for CFAR detection, signed
phase for the fine-Doppler\/direction discriminant.

== Algorithm

Vectoring mode drives @y@ to zero by conditional rotations through
@atan(2^-i)@, accumulating the applied angle in @z@:

@
  y >= 0:  x' = x + (y >> i);  y' = y - (x >> i);  z' = z + atan(2^-i)
  y <  0:  x' = x - (y >> i);  y' = y + (x >> i);  z' = z - atan(2^-i)
@

CORDIC only converges over |θ| ≲ 99.9°, so a pre-rotation stage first maps
the left half-plane to the right by negating both coordinates and seeding
@z@ with π. Angles are held in /binary angular measure/ (BAM): a wrapping
'Signed' 16 where one LSB is 2π\/2^16 ≈ 95.9 µrad and ±32768 ≡ ±π. Wrapping
two's-complement addition then implements angle arithmetic modulo 2π with no
special cases — the seed π and seed −π are the same bit pattern, as they
should be.

== Scaling and error bounds (documented, tested in @CordicSpec@)

* Magnitude carries the CORDIC gain @G = Π cos⁻¹(atan 2^-i) ≈ 1.6467603@:
  @mag ≈ G · √(I² + Q²)@, up to ~76 470 for full-scale inputs, so the output
  is 'Unsigned' 18. The gain is /not/ compensated here — downstream CFAR is
  scale-invariant (threshold is a ratio), and compensating would spend a
  multiplier for nothing.
* Datapath: 'Signed' 21. The input is pre-scaled left by 3 guard bits at
  the pre-rotation stage, so the ≤1-count truncation loss of each
  arithmetic right shift lands /below/ the output LSB; the extraction
  stage shifts back down. Width: 16 input + 3 guard + 1 gain\/√2 growth
  + sign headroom (max |x| = G·√2·2^18 ≈ 610 512 < 2^20).
* Phase error bound: convergence residue @atan(2^-15) ≈ 30.5 µrad@, table
  rounding (≤ 0.5 LSB per entry, signs vary), and datapath truncation
  worth ≈ 2 output counts of cross-error. Tested bound: **±4 BAM LSB
  (±3.84e-4 rad ≈ 0.022°) for ‖v‖ ≥ 8192** (quarter scale, the regime a
  detected Doppler bin lives in), relaxing to **±32 BAM LSB for
  ‖v‖ ≥ 1024** — angle error is inversely proportional to amplitude.
* Magnitude error bound: tested as **±8 counts absolute** (at quarter
  scale ≤ 0.06%, at full scale ≤ 0.01%).
* The phase of the zero vector is unspecified (atan2 0 0 is a convention);
  the magnitude there is exactly 0.

== Pipeline

17 register stages (1 pre-rotation + 16 iterations): one result per clock,
17-clock latency. 'cordicModel' is the zero-latency pure composition of the
same per-stage functions, so the numerical tests run without a simulator and
a single 'simulateN' test pins the latency.
-}
module Maiden.Cordic
  ( CordicVec (..)
  , Iterations
  , preRotate
  , cordicIter
  , atanTable
  , cordicModel
  , cordic
  , topEntity
  ) where

import Clash.Prelude

-- | Iteration count; also the pipeline depth after pre-rotation.
type Iterations = 16

-- | One pipeline stage's worth of working state.
data CordicVec = CordicVec
  { cvX :: Signed 21  -- ^ Rotator x (input × 8); converges to @8·G·‖v‖ ≥ 0@.
  , cvY :: Signed 21  -- ^ Rotator y (input × 8); driven towards 0.
  , cvZ :: Signed 16  -- ^ Accumulated angle, BAM (wrapping, LSB = 2π\/2^16).
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | @round(atan(2^-i) · 2^16 / 2π)@ for i = 0..15. Hard-coded so synthesis
-- cannot depend on elaboration-time floating point; @CordicSpec@ recomputes
-- the table from 'Prelude.atan' and asserts equality.
atanTable :: Vec Iterations (Signed 16)
atanTable =
  8192 :> 4836 :> 2555 :> 1297 :> 651 :> 326 :> 163 :> 81 :>
  41 :> 20 :> 10 :> 5 :> 3 :> 1 :> 1 :> 0 :> Nil

-- | Stage 0: widen, pre-scale into the guard bits, and fold the left
-- half-plane into the convergence region. The negations are exact because
-- they happen after widening to 21 bits (so @-(-32768)@ cannot overflow).
preRotate :: (Signed 16, Signed 16) -> CordicVec
preRotate (i, q)
  | i < 0     = CordicVec { cvX = negate xw, cvY = negate yw, cvZ = minBound }
      -- minBound = -32768 ≡ π in BAM; wrapping addition makes ±π identical.
  | otherwise = CordicVec { cvX = xw, cvY = yw, cvZ = 0 }
 where
  xw = resize i `shiftL` 3 :: Signed 21
  yw = resize q `shiftL` 3 :: Signed 21

-- | Iteration @i@: one conditional rotation by @atan(2^-i)@.
cordicIter :: Index Iterations -> CordicVec -> CordicVec
cordicIter i CordicVec{..} =
  if cvY >= 0
    then CordicVec { cvX = cvX + ys, cvY = cvY - xs, cvZ = cvZ + a }
    else CordicVec { cvX = cvX - ys, cvY = cvY + xs, cvZ = cvZ - a }
 where
  sh = fromEnum i
  xs = cvX `shiftR` sh   -- arithmetic shift: Signed
  ys = cvY `shiftR` sh
  a  = atanTable !! i

-- | Result extraction: drop the 3 guard bits; x has converged to
-- @8·G·‖v‖ < 2^20@, so after the shift the truncation to 18 bits is
-- lossless.
extract :: CordicVec -> (Unsigned 18, Signed 16)
extract CordicVec{..} = (unpack (truncateB (pack (cvX `shiftR` 3))), cvZ)

-- | Zero-latency reference: the exact per-stage functions composed
-- combinationally. The pipeline computes precisely this, 17 clocks later.
cordicModel :: (Signed 16, Signed 16) -> (Unsigned 18, Signed 16)
cordicModel =
  extract . flip (foldl (flip cordicIter)) indicesI . preRotate

-- | Pipelined CORDIC: 17-clock latency, one (magnitude, phase) per clock.
cordic ::
  HiddenClockResetEnable dom =>
  Signal dom (Signed 16, Signed 16) ->
  Signal dom (Unsigned 18, Signed 16)
cordic inp = extract <$> pipe
 where
  idle = CordicVec 0 0 0
  v0   = register idle (preRotate <$> inp)
  pipe = foldl (\sig i -> register idle (cordicIter i <$> sig)) v0 indicesI

-- | Synthesis root: 16-bit I\/Q in, magnitude + BAM phase out.
topEntity ::
  Clock System ->
  Signal System (Signed 16, Signed 16) ->
  Signal System (Unsigned 18, Signed 16)
topEntity clk inp =
  withClockResetEnable clk resetGen enableGen (cordic inp)
{-# ANN topEntity
  (Synthesize
    { t_name = "maiden_cordic"
    , t_inputs = [PortName "CLK", PortProduct "" [PortName "I_IN", PortName "Q_IN"]]
    , t_output = PortProduct "" [PortName "MAG", PortName "PHASE"]
    }) #-}
{-# NOINLINE topEntity #-}
