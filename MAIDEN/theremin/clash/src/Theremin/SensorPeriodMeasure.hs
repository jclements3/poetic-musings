{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BinaryLiterals #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-|
Clash port of @theremin_sensor_period_measure.sv@ from fpga-theremin.

This is the sensor datapath top: it turns two oscillator inputs (pitch and
volume) into filtered period measurements. The chain per axis is

@
  edge positions -> pulse centres -> stage 1 boxcar -> stage 2 IIR
@

== What is and is not ported

The SystemVerilog top instantiates two Xilinx-only things that have no ECP5
equivalent and are therefore /not/ ported:

* @IDELAYCTRL@ — the calibration block for @IDELAYE2@ input delay lines;
* two @oversampling_edge_detector@ instances, built on @ISERDESE2@
  deserialisers, which sub-sample the oscillator at ~600 MHz to get
  sub-clock-period edge timing.

On ECP5 that front end has to be redesigned around a different primitive
family (@IDDRX*@ / @DELAYG@), which is a hardware design question, not a
language-translation one — it would be equally true of a hand-written VHDL
port. So the boundary is drawn here: this module takes the edge stream as
/inputs/ (@spPitchEdge@, @spPitchEdgePos@, and the volume equivalents),
exactly as the edge detectors would present it.

Everything downstream of that boundary — the CDC, the pulse-centre averaging,
both filter stages, and the output packing — is ported and synthesises.

== Parameters

Fixed to the values the theremin instantiates, resolved from the SV
@localparam@ ladders:

* pitch: @OVERSAMPLING = 3@, @COUNTER_BITS = 8@ (150 MHz / 0.6 MHz = 250),
  @DELAY_ADDR_BITS = 9@ (512 half-cycles) → @EDGE_POSITION_BITS = 23@;
* volume: @OVERSAMPLING = 1@, @COUNTER_BITS = 8@, @DELAY_ADDR_BITS = 9@
  → @EDGE_POSITION_BITS = 21@;
* stage-2 IIR: @K = 8@, @CYCLE_COUNT = STAGE_COUNT = 4@, value width 36
  (pitch) and 30 (volume).
-}
module Theremin.SensorPeriodMeasure
  ( SensorIn (..)
  , SensorOut (..)
  , sensorPeriodMeasure
  , topEntity
  , PitchEdgeBits
  , VolumeEdgeBits
  ) where

import Clash.Prelude

import Theremin.DelayDiffFilter
import Theremin.EdgeToPulsePosition
import Theremin.IirNStage (IirParams (..), iir)

-- | @3 + PITCH_OVERSAMPLING(3) + PITCH_COUNTER_BITS(8) + PITCH_DELAY_ADDR_BITS(9)@
type PitchEdgeBits = 23

-- | @3 + VOLUME_OVERSAMPLING(1) + VOLUME_COUNTER_BITS(8) + VOLUME_DELAY_ADDR_BITS(9)@
type VolumeEdgeBits = 21

-- | Delay buffer address width for both axes (512 half-cycles).
type DelayAddrBits = 9

-- | Inputs, with the ISERDES front end replaced by its output signals.
data SensorIn = SensorIn
  { spReset        :: Bit
  , spPitchEdge    :: Bit                        -- ^ @CHANGE_EDGE@, toggles per edge
  , spPitchEdgePos :: BitVector PitchEdgeBits    -- ^ @EDGE_POSITION@
  , spVolEdge      :: Bit
  , spVolEdgePos   :: BitVector VolumeEdgeBits
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Outputs. Each is 32 bits with a toggling flag in bit 31, as in the SV.
data SensorOut = SensorOut
  { soPitchPulsePosition :: BitVector 32
  , soVolPulsePosition   :: BitVector 32
  , soPitchPeriodStage1  :: BitVector 32
  , soVolPeriodStage1    :: BitVector 32
  , soPitchPeriodStage2  :: BitVector 32
  , soVolPeriodStage2    :: BitVector 32
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Pack a value into 32 bits with a flag in the MSB and zero padding
-- between, matching @{ flag, {(32-1-BITS){1'b0}}, value }@.
packWithFlag ::
  forall n. (KnownNat n, n <= 31) =>
  Bit -> BitVector n -> BitVector 32
packWithFlag flag value = pack flag ++# (resize value :: BitVector 31)

-- | The sensor datapath, from edge stream to filtered periods.
sensorPeriodMeasure ::
  forall dom.
  HiddenClockResetEnable dom =>
  Signal dom SensorIn ->
  Signal dom SensorOut
sensorPeriodMeasure inp = SensorOut
  <$> (packWithFlag <$> pitchPulseType <*> pitchPulsePos)
  <*> (packWithFlag <$> volPulseType   <*> volPulsePos)
  <*> (packWithFlag <$> pitchS1Changed <*> pitchS1)
  <*> (packWithFlag <$> volS1Changed   <*> volS1)
  <*> (trim36 <$> pitchS2)
  <*> (trim30 <$> volS2)
 where
  rst = spReset <$> inp

  -- ---- pulse centres (includes the CDC from the edge-detector clock) ----
  pitchE2P = edgeToPulsePosition
    (E2PIn <$> rst <*> (spPitchEdge <$> inp) <*> (spPitchEdgePos <$> inp))
  volE2P = edgeToPulsePosition
    (E2PIn <$> rst <*> (spVolEdge <$> inp) <*> (spVolEdgePos <$> inp))

  pitchPulseType = eoPulseType <$> pitchE2P
  volPulseType   = eoPulseType <$> volE2P

  -- The SV declares pulse_position at EDGE_POSITION_BITS but the converter
  -- outputs EDGE_POSITION_BITS+1, so the top bit is dropped on connection.
  -- Reproduced here rather than silently widened. See README.
  pitchPulsePos = truncateB . eoPulsePosition <$> pitchE2P
                    :: Signal dom (BitVector PitchEdgeBits)
  volPulsePos   = truncateB . eoPulsePosition <$> volE2P
                    :: Signal dom (BitVector VolumeEdgeBits)

  -- ---- stage 1: boxcar difference over 512 pulses ----
  pitchDdf = delayDiffFilter @DelayAddrBits 0
    (DdfIn <$> rst <*> pitchPulsePos <*> (eoChanged <$> pitchE2P))
  volDdf = delayDiffFilter @DelayAddrBits 0
    (DdfIn <$> rst <*> volPulsePos <*> (eoChanged <$> volE2P))

  pitchS1        = doDiff <$> pitchDdf
  volS1          = doDiff <$> volDdf
  pitchS1Changed = doChanged <$> pitchDdf
  volS1Changed   = doChanged <$> volDdf

  -- ---- stage 2: time-multiplexed IIR, input left-aligned into the wider
  -- filter word (@{ value, zeroes }@) ----
  iirParams = IirParams { ipCycleCount = 4, ipStageCount = 4 }

  pitchS2 = iir (SNat @8) iirParams rst
              ((`shiftL` (36 - natToNum @PitchEdgeBits)) . zeroExtend <$> pitchS1)
  volS2   = iir (SNat @8) iirParams rst
              ((`shiftL` (30 - natToNum @VolumeEdgeBits)) . zeroExtend <$> volS1)

  -- Both stage-2 widths are >= 32, so the SV takes the top 32 bits.
  trim36 :: BitVector 36 -> BitVector 32
  trim36 = truncateB . (`shiftR` 4)

  trim30 :: BitVector 30 -> BitVector 32
  trim30 = (`shiftL` 2) . zeroExtend

-- | Synthesis root for area/timing measurement on the ECP5.
topEntity ::
  Clock System ->
  Signal System SensorIn ->
  Signal System SensorOut
topEntity clk inp =
  withClockResetEnable clk resetGen enableGen (sensorPeriodMeasure inp)
{-# ANN topEntity
  (Synthesize
    { t_name = "theremin_sensor_period_measure"
    , t_inputs = [PortName "CLK", PortName "IN"]
    , t_output = PortName "OUT"
    }) #-}
{-# NOINLINE topEntity #-}
