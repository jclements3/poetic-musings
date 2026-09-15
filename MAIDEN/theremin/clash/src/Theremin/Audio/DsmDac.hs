{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

{-|
First-order sigma-delta modulator: 16-bit signed audio in, 1-bit bitstream
out, for the ULX3S 3.5mm jack (drive one DAC pin with the bit; the jack's RC
network and the headphones' own rolloff are the reconstruction filter).

The implementation is the carry-out form: convert the sample to offset
binary (@u = x + 32768@, a 16-bit unsigned value), add it into a 16-bit
accumulator every clock, and output the /carry/ of that addition:

@
  {out, acc'} = acc + u        -- 17-bit sum
@

This is exactly a first-order error-feedback modulator with a mid-tread
quantiser: the accumulator holds the running quantisation error, and the
carry fires whenever the error crosses a full LSB. For a constant input the
long-run density of 1s is @u \/ 65536@ — in fact over @n@ cycles from a zero
accumulator the count of 1s is exactly @floor(n * u \/ 65536)@, which is what
the tests assert.

Stability is by construction, not by argument: the accumulator is a 16-bit
register and wraps modulo @2^16@, so it cannot diverge, and the extremes
degenerate cleanly — @x = -32768@ gives @u = 0@ and a constant-0 output
(no limit cycle), @x = 32767@ gives a single 0 every 65536 cycles.

Also here: 'pcm4', the top four offset-binary bits of a sample, for driving
the ULX3S 4-bit resistor-ladder DAC directly as plain PCM. Crude (16-to-4-bit
truncation is -24 dB SNR territory) but useful as a bring-up fallback that
needs no reconstruction filter at all.
-}
module Theremin.Audio.DsmDac
  ( DsmState (..)
  , initialState
  , dsmStep
  , dsmDac
  , pcm4
  , topEntity
  ) where

import Clash.Prelude

-- | The accumulator (the running quantisation error) and the registered
-- output bit.
data DsmState = DsmState
  { dsAcc :: Unsigned 16
  , dsOut :: Bit
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Power-up / reset value: zero error, output low.
initialState :: DsmState
initialState = DsmState 0 0

-- | Offset binary: flip the sign bit, so -32768 maps to 0 and 32767 to 65535.
toOffsetBinary :: Signed 16 -> Unsigned 16
toOffsetBinary x = unpack (pack x `xor` 0x8000)

-- | One clock edge. Pure, so tests can drive it without a simulator.
dsmStep :: DsmState -> Signed 16 -> DsmState
dsmStep s x = DsmState
  { dsAcc = truncateB total
  , dsOut = msb total
  }
 where
  total :: Unsigned 17
  total = zeroExtend (dsAcc s) + zeroExtend (toOffsetBinary x)

-- | Synchronous modulator; the output bit is registered, ready for a pin.
dsmDac ::
  HiddenClockResetEnable dom =>
  Signal dom (Signed 16) ->  -- ^ audio sample
  Signal dom Bit             -- ^ 1-bit DSM bitstream
dsmDac = moore dsmStep dsOut initialState

-- | Top four bits of the sample in offset binary, for the 4-bit ladder DAC.
pcm4 :: Signed 16 -> BitVector 4
pcm4 = slice d15 d12 . pack . toOffsetBinary

-- | Synthesis root for standalone area measurement.
topEntity ::
  Clock System ->
  Signal System (Signed 16) ->
  Signal System Bit
topEntity clk sample =
  withClockResetEnable clk resetGen enableGen (dsmDac sample)
{-# ANN topEntity
  (Synthesize
    { t_name = "audio_dsm_dac"
    , t_inputs = [PortName "CLK", PortName "SAMPLE"]
    , t_output = PortName "AUDIO_1BIT"
    }) #-}
{-# NOINLINE topEntity #-}
