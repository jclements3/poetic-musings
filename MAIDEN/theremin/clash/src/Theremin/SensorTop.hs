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
The complete ECP5 sensor: raw oscillator inputs to filtered period
measurements, with no Xilinx primitives anywhere.

@
  OSC_IN -> edgeSampler (1x, ECP5-native) -> edgeToPulsePosition
         -> delayDiffFilter (512-tap boxcar) -> iir (time-multiplexed)
@

This is the module that closes the gap 'Theremin.SensorPeriodMeasure' left
open. That one stops at the ISERDES boundary and takes the edge stream as an
input; this one generates that stream itself using
'Theremin.EdgeSampler.edgeSampler', so the whole datapath synthesises for the
ULX3S 85F.
-}
module Theremin.SensorTop
  ( SensorTopIn (..)
  , sensorTop
  , topEntity
  ) where

import Clash.Prelude

import Theremin.EdgeSampler
import Theremin.SensorPeriodMeasure
  (SensorIn (..), SensorOut (..), PitchEdgeBits, VolumeEdgeBits, sensorPeriodMeasure)

-- | Raw inputs: a reset and the two oscillator signals straight off the pins.
data SensorTopIn = SensorTopIn
  { stReset   :: Bit
  , stPitchOsc :: Bit  -- ^ @PITCH_OSC_IN@, asynchronous
  , stVolOsc   :: Bit  -- ^ @VOLUME_OSC_IN@, asynchronous
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Full sensor datapath.
sensorTop ::
  HiddenClockResetEnable dom =>
  Signal dom SensorTopIn ->
  Signal dom SensorOut
sensorTop inp = sensorPeriodMeasure (mkSensorIn <$> rst <*> pitch <*> vol)
 where
  rst = stReset <$> inp

  pitch = edgeSampler @_ @PitchEdgeBits  rst (stPitchOsc <$> inp)
  vol   = edgeSampler @_ @VolumeEdgeBits rst (stVolOsc <$> inp)

  mkSensorIn r p v = SensorIn
    { spReset        = r
    , spPitchEdge    = esoChangeEdge p
    , spPitchEdgePos = esoEdgePosition p
    , spVolEdge      = esoChangeEdge v
    , spVolEdgePos   = esoEdgePosition v
    }

-- | Synthesis root for area and timing on the ECP5.
topEntity ::
  Clock System ->
  Signal System SensorTopIn ->
  Signal System SensorOut
topEntity clk inp =
  withClockResetEnable clk resetGen enableGen (sensorTop inp)
{-# ANN topEntity
  (Synthesize
    { t_name = "theremin_sensor_top"
    , t_inputs = [PortName "CLK", PortName "IN"]
    , t_output = PortName "OUT"
    }) #-}
{-# NOINLINE topEntity #-}
