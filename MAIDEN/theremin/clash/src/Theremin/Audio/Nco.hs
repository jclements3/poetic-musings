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
Numerically controlled oscillator: a 32-bit phase accumulator.

Each clock the accumulator advances by the tuning word, wrapping modulo
@2^32@, so the output frequency is /exactly/

@
  f_out = freq_word * f_clk \/ 2^32
@

with a resolution of @f_clk \/ 2^32@ (0.047 Hz at 200 MHz) — far finer than
a cent anywhere in the audio band, which is why a plain accumulator is the
whole pitch-generation story and no divider or PLL is involved.

The full 32-bit phase is exposed; consumers take as many MSBs as they need
('Theremin.Audio.SineLut' takes the top 10). Wrapping is the intended
behaviour, not an overflow: phase is an angle.
-}
module Theremin.Audio.Nco
  ( ncoStep
  , nco
  , phaseMsbs
  , topEntity
  ) where

import Clash.Prelude

-- | One clock edge: advance the phase by the tuning word, modulo @2^32@.
-- Pure, so tests can drive it without a simulator.
ncoStep ::
  Unsigned 32 ->  -- ^ frequency (tuning) word
  Unsigned 32 ->  -- ^ current phase
  Unsigned 32
ncoStep freqWord phase = phase + freqWord

-- | Free-running phase accumulator. The output is the /registered/ phase, so
-- it moves one cycle after the tuning word does.
nco ::
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned 32) ->  -- ^ frequency word
  Signal dom (Unsigned 32)     -- ^ phase
nco freqWord = phase
 where
  phase = register 0 (ncoStep <$> freqWord <*> phase)

-- | The top @n@ bits of the phase, as an index into a waveform table.
phaseMsbs ::
  forall n. (KnownNat n, n <= 32) =>
  Unsigned 32 ->
  BitVector n
phaseMsbs = resize . (`shiftR` (32 - natToNum @n)) . pack

-- | Synthesis root for standalone area measurement.
topEntity ::
  Clock System ->
  Signal System (Unsigned 32) ->
  Signal System (Unsigned 32)
topEntity clk freqWord =
  withClockResetEnable clk resetGen enableGen (nco freqWord)
{-# ANN topEntity
  (Synthesize
    { t_name = "audio_nco"
    , t_inputs = [PortName "CLK", PortName "FREQ_WORD"]
    , t_output = PortName "PHASE"
    }) #-}
{-# NOINLINE topEntity #-}
