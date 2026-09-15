{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

{-|
Measured period to NCO tuning word — the "musical instrument" part of the
datapath, and a /documented first cut/.

An analogue heterodyne theremin mixes the variable oscillator against a
fixed reference and plays the difference frequency: at rest the two are near
zero beat (silence), and a hand approaching the antenna raises the oscillator
frequency — shrinks its period — pushing the beat up into the audio band.
This module reproduces that behaviour digitally with a clamped linear map:

@
  freq_word(period) = clamp[0, max] (base - (period >> shift))
@

so a /larger/ period gives a /lower/ pitch, @base@ plays the role of the
reference oscillator (the zero-beat point is @period == base << shift@), and
periods at or beyond the silence threshold give a tuning word of 0, freezing
the NCO — the digital equivalent of sitting at zero beat.

== Why this is a first cut

The true period-to-frequency relation of a heterodyne pair is not linear in
the period, and musicians expect a further exponential shaping so equal hand
movements give equal /intervals/. Both corrections live behind this one
function signature; the linear map is enough to prove the datapath
end-to-end (oscillator pins to sound) and to hear the pitch move the right
way. The constants are term-level parameters precisely so bench calibration
against the real LC oscillators can retune them without touching the RTL.

'defaultPitchMapParams' and 'defaultVolMapParams' are scaled to the
/synthetic testbench/ oscillators (16-24-tick half-periods, giving stage-2
pitch readings around 8-13 M) so simulation produces audio-band tones; the
real 600 kHz oscillators sit at different absolute readings and need
recalibrated constants at bring-up.

Also here: the equally crude volume map. The volume period, right-shifted,
is used directly as an attenuation /shift amount/ for the audio samples —
power-of-two volume steps only. Louder-quieter works; smooth fades need a
multiplier, later.
-}
module Theremin.Audio.PitchMap
  ( PitchMapParams (..)
  , defaultPitchMapParams
  , pitchToFreqWord
  , VolMapParams (..)
  , defaultVolMapParams
  , periodToAttenuation
  ) where

import Clash.Prelude

-- | Constants of the linear pitch map. Term-level, like
-- 'Theremin.IirNStage.IirParams': they are elaboration-time configuration,
-- not signals, so every shift and comparison below folds to constants.
data PitchMapParams = PitchMapParams
  { pmBase    :: Unsigned 32
    -- ^ The digital "reference oscillator": tuning word at period 0.
  , pmShift   :: Int
    -- ^ Right shift applied to the period first; sets the cents-per-tick
    -- sensitivity of the instrument.
  , pmMaxWord :: Unsigned 32
    -- ^ Upper clamp on the tuning word (keeps the tone below Nyquist \/ out
    -- of the ultrasonic when the period reads low, e.g. during filter
    -- warm-up).
  , pmSilence :: Unsigned 32
    -- ^ Periods at or beyond this read as "hand at rest": tuning word 0.
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Testbench-scale defaults (see the module header): zero beat at a stage-2
-- reading of @2^21 << 3 = 2^24@, well above the ~8.4 M a 16-tick oscillator
-- measures, so the synthetic tones land around @2^20 \/ 2^32@ of the clock.
defaultPitchMapParams :: PitchMapParams
defaultPitchMapParams = PitchMapParams
  { pmBase    = 2_097_152   -- 2^21
  , pmShift   = 3
  , pmMaxWord = 4_194_304   -- 2^22
  , pmSilence = 0x2000_0000
  }

-- | The clamped linear map. Pure and combinational.
--
-- Monotone non-increasing in the period by construction: the shifted period
-- is non-decreasing, subtraction from a constant reverses that, and each
-- clamp region (upper clamp, linear, floor at 0, silence) only ever steps
-- downward as the period grows.
pitchToFreqWord :: PitchMapParams -> BitVector 32 -> Unsigned 32
pitchToFreqWord PitchMapParams{..} period
  | p >= pmSilence     = 0            -- at rest: zero beat
  | scaled >= pmBase   = 0            -- past the zero-beat point: silence
  | otherwise          = min pmMaxWord (pmBase - scaled)
 where
  p = unpack period :: Unsigned 32
  scaled = p `shiftR` pmShift

-- | Constants of the shift-based volume map.
data VolMapParams = VolMapParams
  { vmPreShift :: Int
    -- ^ Right shift turning the raw volume period into a small shift count.
  , vmMaxShift :: Unsigned 5
    -- ^ Attenuation ceiling; 15 already shifts a 16-bit sample to +/-1.
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Testbench-scale defaults: the synthetic volume readings (~2^25) map to
-- 2-3 bits of attenuation, audible in the DSM density but far from mute.
defaultVolMapParams :: VolMapParams
defaultVolMapParams = VolMapParams
  { vmPreShift = 24
  , vmMaxShift = 12
  }

-- | Volume period to attenuation shift: larger period, quieter. Monotone
-- non-decreasing and clamped at 'vmMaxShift'.
periodToAttenuation :: VolMapParams -> BitVector 32 -> Unsigned 5
periodToAttenuation VolMapParams{..} period =
  if scaled >= zeroExtend vmMaxShift then vmMaxShift else truncateB scaled
 where
  p = unpack period :: Unsigned 32
  scaled = p `shiftR` vmPreShift
