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
Clash port of @delay_diff_filter.sv@ from fpga-theremin.

@
  OUT_DIFF = IN_VALUE - IN_VALUE delayed by DELAY_CYCLES writes
@

The input is a stream of monotonically increasing latched timer values, so the
difference between a sample and one taken @DELAY_CYCLES@ writes ago is the
time spanned by those cycles — that is, the oscillator period, averaged over
the delay window. It is a boxcar averager built from one subtract and a
circular buffer, rather than an accumulator, which is what keeps it cheap.

@ram_initialized@ suppresses the output until the buffer has been filled once,
so the first window never differences against uninitialised memory.

The SV picks distributed RAM or block RAM by comparing the address width
against @BRAM_ADDR_BITS_THRESHOLD@. That choice only changes read latency
(asynchronous vs synchronous read), so it is a term-level flag here; Clash
emits a memory that yosys infers to the same primitives. At the theremin's
parameters (512-deep) both instances take the BRAM path.
-}
module Theremin.DelayDiffFilter
  ( DdfIn (..)
  , DdfOut (..)
  , DdfState (..)
  , initialState
  , ddfStep
  , delayDiffFilter
  ) where

import Clash.Prelude

-- | Input ports.
data DdfIn v = DdfIn
  { diReset :: Bit          -- ^ @RESET@, synchronous active high
  , diValue :: BitVector v  -- ^ @IN_VALUE@
  , diWr    :: Bit          -- ^ @WR@, one cycle per pushed value
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Output ports.
data DdfOut v = DdfOut
  { doChanged :: Bit          -- ^ @CHANGED@, toggles per new output
  , doDiff    :: BitVector v  -- ^ @OUT_DIFF@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Every register plus the delay buffer.
--
-- @n@ is the address width, so the buffer holds @2^n@ entries.
data DdfState n v = DdfState
  { dsRam         :: Vec (2 ^ n) (BitVector v)
  , dsRamRead     :: BitVector v  -- ^ @ram_read_value@ (BRAM path registers it)
  , dsAddr        :: BitVector n  -- ^ @addr_counter@
  , dsInitialized :: Bool         -- ^ @ram_initialized@
  , dsDiff        :: BitVector v  -- ^ @diff_value@
  , dsChanged     :: Bit          -- ^ @output_changed@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Power-up value. As in the SV, the buffer contents are not reset — the
-- @ram_initialized@ gate is what makes that safe.
initialState :: (KnownNat n, KnownNat v) => DdfState n v
initialState = DdfState
  { dsRam         = repeat 0
  , dsRamRead     = 0
  , dsAddr        = 0
  , dsInitialized = False
  , dsDiff        = 0
  , dsChanged     = 0
  }

-- | One clock edge.
--
-- The @offset@ argument is @DELAY_COUNTER_OFFSET@, i.e.
-- @2^n - DELAY_CYCLES@, which supports delays that are not a power of two.
-- It is zero for both of the theremin's instances.
ddfStep ::
  forall n v.
  (KnownNat n, KnownNat v) =>
  BitVector n ->  -- ^ @DELAY_COUNTER_OFFSET@
  DdfState n v ->
  DdfIn v ->
  DdfState n v
ddfStep offset s DdfIn{..}
  | diReset == high = (initialState :: DdfState n v) { dsRam = dsRam s }
  | diWr == high = s
      { dsRam         = replace (unpack dsAddrIdx :: Index (2 ^ n)) diValue (dsRam s)
        -- BRAM path: synchronous read, one cycle behind the write.
      , dsRamRead     = dsRam s !! (unpack readAddr :: Index (2 ^ n))
      , dsAddr        = dsAddr s + 1
      , dsInitialized = dsInitialized s || addrOverflow
      , dsDiff        = if dsInitialized s then diValue - dsRamRead s else dsDiff s
      , dsChanged     = if dsInitialized s then complement (dsChanged s) else dsChanged s
      }
  | otherwise = s
 where
  dsAddrIdx = dsAddr s
  -- BRAM read address leads the write pointer by one, plus the offset.
  readAddr = dsAddr s + 1 + offset
  addrOverflow = dsAddr s == maxBound

-- | Synchronous delay-difference filter.
--
-- Structural implementation: the delay buffer is 'blockRam', which lands in
-- @DP16KD@ — matching the SV's BRAM path at these parameters. The first
-- version of this function kept the buffer as a @Vec@ in Moore state, which
-- becomes @2^n * v@ fabric flip-flops plus mux forests (~12k FF per 512x24
-- instance) and made the sensor top practically unroutable. Same lesson as
-- the IIR's state bank; see the README.
--
-- The BRAM's synchronous-read output register plays the role of the model's
-- @dsRamRead@ register: the read address is presented so that it is frozen
-- between WR strobes (it only moves when @dsAddr@ moves), so the data out of
-- the RAM during any cycle equals the value the model holds in @dsRamRead@
-- during that cycle. Read and write addresses differ by @1 + offset@ at
-- every write, so the write-first collision behaviour of 'blockRam' is never
-- exercised (offset is 0 in both theremin instances). Behaviour is pinned to
-- 'ddfStep' by the equivalence test in @SensorSpec@.
delayDiffFilter ::
  forall n v dom.
  (HiddenClockResetEnable dom, KnownNat n, KnownNat v, 1 <= 2 ^ n) =>
  BitVector n ->  -- ^ @DELAY_COUNTER_OFFSET@
  Signal dom (DdfIn v) ->
  Signal dom (DdfOut v)
delayDiffFilter offset din = DdfOut <$> changed <*> diff
 where
  rstB = bitToBool . diReset <$> din
  wrB  = bitToBool . diWr <$> din
  value = diValue <$> din

  reg :: NFDataX a => a -> Signal dom a -> Signal dom a
  reg i next = register i (mux rstB (pure i) next)

  -- Registers, updated only on WR (as in the model's guard).
  upd :: NFDataX a => a -> Signal dom a -> Signal dom a
  upd i next = r where r = reg i (mux wrB next r)

  addr :: Signal dom (BitVector n)
  addr = upd 0 (addr + 1)

  initialized :: Signal dom Bool
  initialized = upd False (initialized .||. (addr .==. pure maxBound))

  -- Frozen-between-writes read address: on a WR cycle the *next* slot
  -- (addr+1+offset) is presented so the BRAM captures it at the edge; on
  -- idle cycles addr has already incremented, so addr+offset re-presents the
  -- same physical address and the output register simply holds.
  presentAddr :: Signal dom (Index (2 ^ n))
  presentAddr = unpack . resize <$>
    mux wrB (addr + 1 + pure offset) (addr + pure offset)

  wrPort = mux (rstB .||. fmap not wrB)
               (pure Nothing)
               (Just <$> bundle (unpack . resize <$> addr, value))

  ramOut :: Signal dom (BitVector v)
  ramOut = blockRam (replicate (SNat @(2 ^ n)) 0) presentAddr wrPort

  diff = upd 0 (mux initialized (value - ramOut) diff)
  changed :: Signal dom Bit
  changed = upd 0 (mux initialized (complement <$> changed) changed)
