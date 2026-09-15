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
Clash port of @edge_to_pulse_position.sv@ from fpga-theremin.

Turns a stream of alternating rising/falling edge positions into a stream of
/pulse centres/, by summing each edge position with the previous one. The sum
is @(rising + falling)@, i.e. twice the midpoint — which is why the output is
one bit wider than the input and the SV comment describes it as
@((raising + falling) / 2) << 1@.

Averaging adjacent edges this way cancels PWM modulation on the oscillator
signal: whatever the duty cycle, the centre of the pulse tracks the period.

A new input is signalled not by a strobe but by @EDGE_TYPE@ /toggling/. The
module registers @EDGE_TYPE@ twice and compares the two, which doubles as the
clock-domain crossing — the edge detector runs on @CLK_PARALLEL@ while this
runs on the output clock @CLK@.
-}
module Theremin.EdgeToPulsePosition
  ( E2PIn (..)
  , E2POut (..)
  , E2PState (..)
  , initialState
  , e2pStep
  , edgeToPulsePosition
  ) where

import Clash.Prelude

-- | Input ports.
data E2PIn n = E2PIn
  { eiReset        :: Bit           -- ^ @RESET@, synchronous active high
  , eiEdgeType     :: Bit           -- ^ @EDGE_TYPE@, toggles per new edge
  , eiEdgePosition :: BitVector n   -- ^ @EDGE_POSITION@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Output ports.
data E2POut n = E2POut
  { eoPulseType     :: Bit               -- ^ @PULSE_TYPE@
  , eoChanged       :: Bit               -- ^ @CHANGED@, one cycle per value
  , eoPulsePosition :: BitVector (n + 1) -- ^ @PULSE_POSITION@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Every register in the module.
data E2PState n = E2PState
  { esPulsePosition   :: BitVector (n + 1)
  , esPulseType       :: Bit
  , esChanged         :: Bit
  , esPrevEdgePos     :: BitVector n
  , esPrevEdgeType    :: Bit  -- ^ @prev_edge_type@, first CDC stage
  , esPrevEdgeTypeD1  :: Bit  -- ^ @prev_edge_type_delay1@, second CDC stage
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | All registers reset to zero.
initialState :: KnownNat n => E2PState n
initialState = E2PState 0 0 0 0 0 0

-- | One clock edge.
e2pStep :: KnownNat n => E2PState n -> E2PIn n -> E2PState n
e2pStep s E2PIn{..}
  | eiReset == high = initialState
  | otherwise = base
      { esPrevEdgeTypeD1 = esPrevEdgeType s
      , esPrevEdgeType   = eiEdgeType
      }
 where
  -- A toggle between the two synchroniser stages means a new edge arrived.
  newEdge = esPrevEdgeTypeD1 s /= esPrevEdgeType s

  base
    | newEdge = s
        { esPulsePosition = add (esPrevEdgePos s) eiEdgePosition
          -- widening add: prev + current, so no carry is lost
        , esPulseType     = esPrevEdgeType s
        , esPrevEdgePos   = eiEdgePosition
        , esChanged       = high
        }
    | otherwise = s { esChanged = low }

-- | Synchronous edge-to-pulse-position converter.
edgeToPulsePosition ::
  (HiddenClockResetEnable dom, KnownNat n) =>
  Signal dom (E2PIn n) ->
  Signal dom (E2POut n)
edgeToPulsePosition = moore e2pStep out initialState
 where
  out s = E2POut
    { eoPulseType     = esPulseType s
    , eoChanged       = esChanged s
    , eoPulsePosition = esPulsePosition s
    }
