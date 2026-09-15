{-# LANGUAGE BangPatterns #-}
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
Plain 1x synchronous edge sampler — the ECP5 replacement for upstream's
@oversampling_edge_detector@.

== Why this exists

The fpga-theremin front end oversamples the oscillator at ~1.2 Gbps using a
Xilinx @ISERDESE2@ (1:8 gearing at a 600 MHz shift clock) plus @IDELAYE2@
calibrated delay lines. Neither has an ECP5 equivalent: ECP5's input gearing
tops out at @IDDRX2F@ (1:4) / @IDDR71B@ (1:7), and @DELAYG@/@DELAYF@ are
uncalibrated.

That front end turns out not to be necessary. Measurement resolution here is
the product of the sample tick /and/ the averaging window, and the downstream
'Theremin.DelayDiffFilter' already averages over 512 half-cycles. At a 600 kHz
oscillator:

@
  front end                    tick      period resolution   in cents
  Xilinx ISERDES 8x @150MHz    0.83 ns   1.6 ps              0.003
  this, 1x @200MHz             5.00 ns   9.8 ps              0.02
@

One cent is 5.8e-4 relative, so plain sampling is still ~50x finer than a cent
and far below the LC tank's own phase noise. Dropping the oversampling costs a
factor of six on a budget already overspent by three orders of magnitude.

== Interface

Deliberately matches the signals @oversampling_edge_detector@ presents to
'Theremin.SensorPeriodMeasure', so it drops into the existing chain:

* @CHANGE_FLAG@ — high for one cycle per detected edge;
* @CHANGE_EDGE@ — 1 on a rising edge, 0 on a falling one. Because edges
  alternate, this signal /toggles/ per edge, which is exactly the "new data"
  handshake 'Theremin.EdgeToPulsePosition' expects;
* @EDGE_POSITION@ — the free-running counter latched at the edge.

The position counter is allowed to wrap. Downstream only ever takes
differences, and modular arithmetic makes those correct as long as the
averaging window is shorter than the wrap period — 23 bits at 200 MHz wraps
every 42 ms against a 0.43 ms window, a 100x margin.

@OSC_IN@ is asynchronous to @CLK@, so it gets a three-FF synchroniser: two to
resolve metastability, and a third to give the edge comparison a stable
previous sample.
-}
module Theremin.EdgeSampler
  ( EsOut (..)
  , EsState (..)
  , initialState
  , edgeSamplerStep
  , edgeSampler
  ) where

import Clash.Prelude

-- | Outputs, mirroring @oversampling_edge_detector@'s.
data EsOut n = EsOut
  { esoChangeFlag   :: Bit          -- ^ @CHANGE_FLAG@
  , esoChangeEdge   :: Bit          -- ^ @CHANGE_EDGE@, toggles per edge
  , esoEdgePosition :: BitVector n  -- ^ @EDGE_POSITION@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Registers: the synchroniser chain, the position counter, and the latched
-- edge.
data EsState n = EsState
  { esSync0    :: Bit  -- ^ first synchroniser stage
  , esSync1    :: Bit  -- ^ second stage; metastability resolved by here
  , esSync2    :: Bit  -- ^ third stage, the previous stable sample
  , esCounter  :: BitVector n
  , esEdgePos  :: BitVector n
  , esEdgeType :: Bit
  , esFlag     :: Bit
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | All registers clear to zero.
initialState :: KnownNat n => EsState n
initialState = EsState 0 0 0 0 0 0 0

-- | One clock edge.
edgeSamplerStep ::
  KnownNat n =>
  EsState n ->
  (Bit, Bit) ->  -- ^ @(RESET, OSC_IN)@
  EsState n
edgeSamplerStep s (rst, oscIn)
  | rst == high = initialState
  | otherwise = EsState
      { esSync0    = oscIn
      , esSync1    = esSync0 s
      , esSync2    = esSync1 s
      , esCounter  = esCounter s + 1
      -- Latch the counter as it stands when the edge is observed.
      , esEdgePos  = if edge then esCounter s else esEdgePos s
      -- esSync1 is the new level, so it is 1 on a rising edge.
      , esEdgeType = if edge then esSync1 s else esEdgeType s
      , esFlag     = if edge then high else low
      }
 where
  -- Compare the two settled stages, never the raw input.
  edge = esSync1 s /= esSync2 s

-- | Synchronous 1x edge sampler.
edgeSampler ::
  (HiddenClockResetEnable dom, KnownNat n) =>
  Signal dom Bit ->  -- ^ @RESET@
  Signal dom Bit ->  -- ^ @OSC_IN@, asynchronous
  Signal dom (EsOut n)
edgeSampler rst oscIn = moore edgeSamplerStep out initialState (bundle (rst, oscIn))
 where
  out s = EsOut
    { esoChangeFlag   = esFlag s
    , esoChangeEdge   = esEdgeType s
    , esoEdgePosition = esEdgePos s
    }
