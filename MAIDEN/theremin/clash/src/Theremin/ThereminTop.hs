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
The end-to-end theremin: oscillator pins to sound, for the ULX3S 85F.

@
  PITCH_OSC_IN  -> sensorTop -> pitchToFreqWord -> nco -> sineLookup
  VOLUME_OSC_IN ---^                 |                        |
                                     +-- periodToAttenuation ->> (>>)
                                                                  |
                                        AUDIO_1BIT  <- dsmDac ----+
                                        AUDIO_PCM4  <- pcm4  -----+
@

'Theremin.SensorTop' measures both oscillator periods; the pitch period sets
the NCO tuning word ('Theremin.Audio.PitchMap'), the phase indexes a folded
sine ROM ('Theremin.Audio.SineLut'), the volume period attenuates the sample,
and the result leaves the chip two ways at once:

* @AUDIO_1BIT@ — the first-order sigma-delta bitstream
  ('Theremin.Audio.DsmDac'), for a single pin of the ULX3S audio jack;
* @AUDIO_PCM4@ — the top four offset-binary sample bits, plain PCM for the
  jack's 4-bit resistor-ladder DAC, as a bring-up fallback.

== Two pitch maps

* 'thereminAudio' \/ 'thereminTop' use the clamped /linear/ first cut of
  'Theremin.Audio.PitchMap' — the original proof of the datapath, kept for
  its tests.
* 'thereminAudioNote' \/ 'thereminTopNote' use the musical map of
  'Theremin.Audio.NoteMap', the port of upstream's linearisation + note
  table + note-to-phase pipeline. That is what 'topEntity' synthesises:
  A0..G7 spread evenly over the hand's travel.

The musical build's volume is upstream's @(1 - linear)^2@ curve
('Theremin.Audio.NoteMap.ampMap') applied by a real multiply. Both maps'
constants are the synthetic-bench defaults until the real LC tanks are
calibrated (parameters only, no RTL change).
-}
module Theremin.ThereminTop
  ( AudioOut (..)
  , thereminAudio
  , thereminTop
  , thereminAudioNote
  , thereminTopNote
  , topEntity
  ) where

import Clash.Prelude

import Theremin.Audio.DsmDac (dsmDac, pcm4)
import Theremin.Audio.Nco (nco, phaseMsbs)
import Theremin.Audio.NoteMap
import Theremin.Audio.NoteTables (defaultPhaseTable)
import Theremin.Audio.PitchMap
import Theremin.Audio.SineLut (sineLookup)
import Theremin.SensorPeriodMeasure (SensorOut (..))
import Theremin.SensorTop (SensorTopIn (..), sensorTop)

-- | Both audio output formats, driven from the same sample stream, plus
-- the sample itself (for telemetry / an I2S DAC later).
data AudioOut = AudioOut
  { aoAudio1Bit :: Bit          -- ^ sigma-delta bitstream
  , aoAudioPcm4 :: BitVector 4  -- ^ offset-binary PCM for the ladder DAC
  , aoSample    :: Signed 16    -- ^ the sample
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | The audio back half on its own: filtered period measurements in, audio
-- out. Split from 'thereminTop' so tests can drive it with known periods
-- without simulating the sensor chain.
thereminAudio ::
  HiddenClockResetEnable dom =>
  PitchMapParams ->
  VolMapParams ->
  Signal dom SensorOut ->
  Signal dom AudioOut
thereminAudio pitchParams volParams sens =
  AudioOut <$> dsmDac sample <*> (pcm4 <$> sample) <*> sample
 where
  freqWord = pitchToFreqWord pitchParams . soPitchPeriodStage2 <$> sens
  attShift = periodToAttenuation volParams . soVolPeriodStage2 <$> sens

  phase = nco freqWord

  -- The ROM lookup is registered to keep it off the sample's critical path.
  rawSample = register 0 (sineLookup . phaseMsbs @10 <$> phase)

  -- Arithmetic shift: power-of-two attenuation, sign preserved.
  sample = register 0
    ((\s a -> s `shiftR` fromIntegral a) <$> rawSample <*> attShift)

-- | The audio back half with the musical pitch map: the tuning word comes
-- from 'noteMap' instead of the linear 'pitchToFreqWord'; everything after
-- the NCO is shared with 'thereminAudio'.
thereminAudioNote ::
  HiddenClockResetEnable dom =>
  (Signal dom (BitVector 32) -> Signal dom (Unsigned 32)) ->  -- ^ a 'noteMap' or 'noteMapFile'
  (Signal dom (BitVector 32) -> Signal dom (Unsigned 12)) ->  -- ^ an 'ampMap' or 'ampMapFile'
  Signal dom SensorOut ->
  Signal dom AudioOut
thereminAudioNote pitchMap volMap sens =
  AudioOut <$> dsmDac sample <*> (pcm4 <$> sample) <*> sample
 where
  freqWord = pitchMap (soPitchPeriodStage2 <$> sens)
  amp = volMap (soVolPeriodStage2 <$> sens)
  phase = nco freqWord
  rawSample = register 0 (sineLookup . phaseMsbs @10 <$> phase)
  sample = ampScaleP rawSample amp

-- | The full instrument with the musical pitch map.
thereminTopNote ::
  HiddenClockResetEnable dom =>
  (Signal dom (BitVector 32) -> Signal dom (Unsigned 32)) ->
  (Signal dom (BitVector 32) -> Signal dom (Unsigned 12)) ->
  Signal dom SensorTopIn ->
  Signal dom AudioOut
thereminTopNote pitchMap volMap =
  thereminAudioNote pitchMap volMap . sensorTop

-- | The full instrument: raw oscillator inputs to audio outputs.
thereminTop ::
  HiddenClockResetEnable dom =>
  PitchMapParams ->
  VolMapParams ->
  Signal dom SensorTopIn ->
  Signal dom AudioOut
thereminTop pitchParams volParams =
  thereminAudio pitchParams volParams . sensorTop

-- | Synthesis root: the musical map at its synthetic-bench defaults. The
-- note table comes from @$readmemb@ files next to the netlist (write them
-- with 'writeNoteTableFiles'; the Makefile's @notemap-files@ target does).
topEntity ::
  Clock System ->
  Signal System Bit ->  -- ^ @RESET@
  Signal System Bit ->  -- ^ @PITCH_OSC_IN@, asynchronous
  Signal System Bit ->  -- ^ @VOLUME_OSC_IN@, asynchronous
  Signal System AudioOut
topEntity clk rst pitchOsc volOsc =
  withClockResetEnable clk resetGen enableGen $
    thereminTopNote
      (noteMapFile defaultNoteMapParams "notemap_lo.bin" "notemap_hi.bin" defaultPhaseTable)
      (ampMapFile defaultAmpMapParams "ampmap_lo.bin" "ampmap_hi.bin")
      (SensorTopIn <$> rst <*> pitchOsc <*> volOsc)
{-# ANN topEntity
  (Synthesize
    { t_name = "theremin_top"
    , t_inputs =
        [ PortName "CLK"
        , PortName "RESET"
        , PortName "PITCH_OSC_IN"
        , PortName "VOLUME_OSC_IN"
        ]
    , t_output = PortProduct "" [PortName "AUDIO_1BIT", PortName "AUDIO_PCM4", PortName "AUDIO_S16"]
    }) #-}
{-# NOINLINE topEntity #-}
