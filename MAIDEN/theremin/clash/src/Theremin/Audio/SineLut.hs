{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

{-|
Quarter-wave-folded sine lookup: a 10-bit phase to a 16-bit signed sample
from a 256-entry first-quadrant ROM ('Theremin.Audio.SineQuarter').

The phase splits as @{quadrant[1:0], index[7:0]}@ and the two symmetries of
the sine fold the other three quadrants onto the stored one:

@
  quadrant 0:   sineQuarter[index]          rising, positive
  quadrant 1:   sineQuarter[255 - index]    falling, positive
  quadrant 2:  -sineQuarter[index]          falling, negative
  quadrant 3:  -sineQuarter[255 - index]    rising, negative
@

The table samples at half-index offsets — entry @i@ holds
@sin((2i+1) * pi \/ 1024)@ — which makes the folding /exact/: the mirrored
index lands precisely on the ideal sample points of the other quadrants
(@sin(pi\/2 + x) = sin(pi\/2 - x)@), so the only error against
@round(32767 * sin)@ at any of the 1024 phases is the table's own rounding.
It also means no entry holds 0 or -32768, so negation cannot overflow.

Cost: 256 x 16 ROM (fits distributed RAM or a fraction of one DP16KD)
instead of the 1024 x 16 a full-wave table would take.
-}
module Theremin.Audio.SineLut
  ( sineLookup
  , topEntity
  ) where

import Clash.Prelude

import Theremin.Audio.SineQuarter (sineQuarter)

-- | Look up @sin(2 * pi * (phase + 0.5) \/ 1024)@ in Q1.15. Pure and
-- combinational; register the result where timing needs it.
sineLookup :: BitVector 10 -> Signed 16
sineLookup phase = if negative then negate magnitude else magnitude
 where
  (quadrant, index) = split phase :: (BitVector 2, BitVector 8)

  mirror   = lsb quadrant == high  -- quadrants 1 and 3 run backwards
  negative = msb quadrant == high  -- quadrants 2 and 3 are the lower half

  address :: Index 256
  address = unpack (if mirror then complement index else index)
    -- @complement index == 255 - index@ for an 8-bit vector.

  magnitude = asyncRom sineQuarter address

-- | Synthesis root for standalone area measurement.
topEntity ::
  Clock System ->
  Signal System (BitVector 10) ->
  Signal System (Signed 16)
topEntity clk phase =
  withClockResetEnable clk resetGen enableGen
    (register 0 (sineLookup <$> phase))
{-# ANN topEntity
  (Synthesize
    { t_name = "audio_sine_lut"
    , t_inputs = [PortName "CLK", PortName "PHASE"]
    , t_output = PortName "SAMPLE"
    }) #-}
{-# NOINLINE topEntity #-}
