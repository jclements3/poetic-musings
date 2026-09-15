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
Clash port of @iir_nstage_pow2k.sv@ from fpga-theremin
(@fpga/oversampling_sensor/oversampling_sensor.srcs/sources_1/new/@).

An N-stage single-pole IIR lowpass where the coefficient is a power of two, so
each stage is a shift and an add rather than a multiply:

@
  new_state = prev_state + (in_value - prev_state) >> K
@

The stages are /time-multiplexed/: one adder and one 8-entry state register
bank are reused across @STAGE_COUNT@ stages, one stage per clock, cycling
every @CYCLE_COUNT@ clocks. That is the interesting property for MAIDEN — it
trades throughput for area, the lever that matters when a design is LUT-bound.

Structure of one cycle, matching the SystemVerilog exactly:

* read @states[phase]@ (asynchronous read) as the previous state;
* stage 0 takes @IN_VALUE@, later stages take the previous stage's buffered
  output;
* the computed output is registered, then written back one cycle later to
  @states[phase-1]@;
* when that write targets the last stage, it also updates @OUT_VALUE@.

@filter_en@ holds the buffered output at zero for the first full cycle, which
is how the state bank is initialised without a reset on the RAM.

The shift amount @k@ and value width @v@ are type parameters, because the
sensor top instantiates this at two different widths.
-}
module Theremin.IirNStage
  ( IirParams (..)
  , IirState (..)
  , initialState
  , iirStep
  , iirArith
  , iir
  , topEntity
  ) where

import Clash.Prelude

-- | The state bank is a fixed 8 entries in the SV (@logic [..] states[8]@),
-- addressed by a 3-bit phase counter.
type Depth = 8

-- | Term-level parameters that the SystemVerilog exposes as module
-- parameters. Kept at the term level because they only select /which/
-- entries of the fixed 8-deep bank are used.
data IirParams = IirParams
  { ipCycleCount :: Index Depth
    -- ^ @CYCLE_COUNT@: output updates once per this many clocks.
  , ipStageCount :: Index Depth
    -- ^ @STAGE_COUNT@: number of IIR stages, must be @<= CYCLE_COUNT@.
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Every register in the module, for a value width of @v@.
data IirState v = IirState
  { isStates      :: Vec Depth (BitVector v)
    -- ^ @states[8]@, the distributed-RAM state bank.
  , isOutBuf      :: BitVector v   -- ^ @filter_out_buffered@
  , isPhase       :: Index Depth   -- ^ @phase_counter@
  , isPhaseDelay1 :: Index Depth   -- ^ @phase_counter_delay1@
  , isFilterEn    :: Bool          -- ^ @filter_en@
  , isOutReg      :: BitVector v   -- ^ @out_reg@, drives @OUT_VALUE@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

-- | Power-up / reset value. The SV gives @states@ no reset — it is RAM — but
-- zero is the value it reaches after the first cycle of @filter_en@ being low.
initialState :: KnownNat v => IirState v
initialState = IirState
  { isStates      = repeat 0
  , isOutBuf      = 0
  , isPhase       = 0
  , isPhaseDelay1 = 0
  , isFilterEn    = False
  , isOutReg      = 0
  }

-- | One clock edge. Pure, so tests can drive it without a simulator.
--
-- Note the ordering: the state-bank write and the output register both
-- consume the /current/ @isOutBuf@, i.e. the value registered on the previous
-- edge, not the value being computed now.
iirStep ::
  forall k v.
  (KnownNat k, KnownNat v) =>
  SNat k ->
  IirParams ->
  IirState v ->
  (Bit, BitVector v) ->
  IirState v
iirStep k IirParams{..} s (rst, inValue)
  | rst == high = (initialState :: IirState v) { isStates = isStates s }
      -- RESET clears the registers but not the RAM, as in the SV.
  | otherwise = IirState
      { isStates      = replace wrAddr wrData (isStates s)
      , isOutBuf      = if isFilterEn s then filterOut else 0
      , isPhase       = phase'
      , isPhaseDelay1 = isPhase s
      , isFilterEn    = filterEn'
      , isOutReg      = if wrAddr == ipStageCount - 1 then wrData else isOutReg s
      }
 where
  phase = isPhase s

  -- Read channel: asynchronous read at the phase counter.
  inState = isStates s !! phase

  -- Stage 0 takes the module input; every later stage chains from the
  -- previous stage's buffered output (@filter_value_mux@).
  value = if phase == 0 then inValue else isOutBuf s

  -- filter_out = filter_sum[VALUE_BITS+K-1 : K] — see 'iirArith'.
  filterOut :: BitVector v
  filterOut = iirArith k inState value

  -- Write channel: one cycle behind the read, always enabled.
  wrAddr = isPhaseDelay1 s
  wrData = isOutBuf s

  wrapping  = phase == ipCycleCount - 1
  phase'    = if wrapping then 0 else phase + 1
  -- filter_en goes high on the first wrap and stays high.
  filterEn' = wrapping || isFilterEn s

-- | The shared per-stage arithmetic:
-- @filter_out = ((in_state << K) + (value - in_state)) >> K@, computed
-- signed and K bits wider so the difference cannot wrap. Factored out so the
-- pure model ('iirStep') and the structural implementation ('iir') cannot
-- drift apart.
iirArith ::
  forall k v.
  (KnownNat k, KnownNat v) =>
  SNat k -> BitVector v -> BitVector v -> BitVector v
iirArith k inState value = truncateB (pack filterSum `shiftR` shiftBy)
 where
  shiftBy = snatToNum k :: Int
  scaledState, diffValue, diffState, filterSum :: Signed (v + k)
  scaledState = unpack (zeroExtend inState `shiftL` shiftBy)
  diffValue   = unpack (zeroExtend value)
  diffState   = unpack (zeroExtend inState)
  filterSum   = scaledState + (diffValue - diffState)

-- | Synchronous time-multiplexed IIR filter.
--
-- Structural implementation: the state bank is 'asyncRam' (asynchronous
-- read, synchronous write), which yosys infers to @TRELLIS_DPR16X4@
-- distributed RAM — matching the hand-written SV. The first version of this
-- function kept the bank in the Moore state instead, and measured 519 LUT4 /
-- 307 FF against the SV's 175 / 67 on the LFE5U-85F: a @Vec@ in register
-- state becomes 240 flip-flops plus mux trees. The behaviour is pinned to
-- the pure model by the equivalence test in @IirSpec@.
iir ::
  forall k v dom.
  (HiddenClockResetEnable dom, KnownNat k, KnownNat v) =>
  SNat k ->
  IirParams ->
  Signal dom Bit ->            -- ^ @RESET@, synchronous active high
  Signal dom (BitVector v) ->  -- ^ @IN_VALUE@
  Signal dom (BitVector v)     -- ^ @OUT_VALUE@
iir k IirParams{..} rst inValue = outReg
 where
  rstB = bitToBool <$> rst

  -- @RESET@ is a synchronous data input, not the domain reset, so every
  -- register muxes back to its initial value on it.
  reg :: NFDataX a => a -> Signal dom a -> Signal dom a
  reg i next = register i (mux rstB (pure i) next)

  phase, phaseD1 :: Signal dom (Index Depth)
  phase   = reg 0 (mux wrapping 0 (phase + 1))
  phaseD1 = reg 0 phase

  wrapping = phase .==. pure (ipCycleCount - 1)

  filterEn :: Signal dom Bool
  filterEn = reg False (wrapping .||. filterEn)

  -- State bank: async read at the phase counter, write one cycle behind.
  -- The model leaves the bank untouched during RESET, so writes are gated.
  inState = asyncRam (SNat @Depth) phase wr
  wr = mux rstB (pure Nothing)
               (Just <$> bundle (phaseD1, outBuf))

  value = mux (phase .==. 0) inValue outBuf

  filterOut = iirArith k <$> inState <*> value

  outBuf :: Signal dom (BitVector v)
  outBuf = reg 0 (mux filterEn filterOut 0)

  atLast = phaseD1 .==. pure (ipStageCount - 1)
  outReg = reg 0 (mux atLast outBuf outReg)

-- | Synthesis root at the standalone parameters (@K = 6@, @VALUE_BITS = 30@,
-- @CYCLE_COUNT = STAGE_COUNT = 5@), for a like-for-like area comparison
-- against the hand-written SystemVerilog.
topEntity ::
  Clock System ->
  Signal System Bit ->
  Signal System (BitVector 30) ->
  Signal System (BitVector 30)
topEntity clk rst inValue =
  withClockResetEnable clk resetGen enableGen $
    iir (SNat @6) (IirParams { ipCycleCount = 5, ipStageCount = 5 }) rst inValue
{-# ANN topEntity
  (Synthesize
    { t_name = "iir_nstage_pow2k"
    , t_inputs = [PortName "CLK", PortName "RESET", PortName "IN_VALUE"]
    , t_output = PortName "OUT_VALUE"
    }) #-}
{-# NOINLINE topEntity #-}
