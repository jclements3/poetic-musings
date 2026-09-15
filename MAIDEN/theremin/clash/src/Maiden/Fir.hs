{-# LANGUAGE NumericUnderscores #-}
{-|
MAIDEN CIC droop compensator: a 15-tap transposed-form (systolic MAC) FIR.

Position in the chain: runs at the /decimated/ rate on the CIC output
(18-bit per the full-growth sizing in "Maiden.Cic"), flattening the CIC's
sinc³ passband droop ahead of the 512-pt FFT so bin amplitudes are
comparable across the Doppler span.

== Structure

Transposed direct form: the input is broadcast to all taps, each tap is a
multiply feeding an adder\/register chain that carries partial sums toward
the output:

@
  y[t]       = c_0·x[t] + r_1[t]
  r_i[t+1]   = c_i·x[t] + r_{i+1}[t]      (i = 1 .. taps-2)
  r_14[t+1]  = c_14·x[t]
@

This is the systolic-friendly form: no adder tree, one add per stage, and
the input fan-out is the only broadcast. Each @c_i·x@ product is an 18×16
multiply — one ECP5 @MULT18X18D@ per tap expected, /except/ that symmetric
(linear-phase) coefficient sets let synthesis share products between
mirrored taps, which is a legitimate saving, not a measurement artefact.
The measured number is reported either way.

== Precision

No rounding anywhere: 18-bit input × 16-bit coefficients → 34-bit products,
plus @clog2 15 = 4@ bits of accumulation growth → 38-bit output. The filter
is therefore /exactly/ linear (superposition holds bit-for-bit), which the
tests exploit. Scaling back down (e.g. @>> 15@ for Q15 coefficients) is the
consumer's choice and is kept out of this block.

The output is registered ('moore'), so the combinational path is one
multiply plus one add regardless of tap count. Tap count is carried as
@n + 1@ at the type level (a FIR with zero taps is not a thing), which is
also what gives 'head'\/'tail' their non-empty vectors.
-}
module Maiden.Fir
  ( FirOut
  , FirState (..)
  , initialFirState
  , firStep
  , fir
  , compCoeffs
  , topEntity
  ) where

import Clash.Prelude

-- | Full-precision output width for @taps@ taps of @cW@-bit coefficients
-- on @iW@-bit samples.
type FirOut iW cW taps = iW + cW + CLog 2 taps

-- | Carry-chain registers plus the registered output, for @n + 1@ taps.
data FirState n w = FirState
  { fsChain :: Vec n (Signed w)
    -- ^ @r_1 .. r_n@, partial sums marching toward the output.
  , fsOut   :: Signed w
    -- ^ Registered @y@.
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

initialFirState :: (KnownNat n, KnownNat w) => FirState n w
initialFirState = FirState { fsChain = repeat 0, fsOut = 0 }

-- | One clock edge at the sample rate. Pure, so tests drive it directly.
firStep ::
  forall n iW cW.
  (KnownNat n, KnownNat iW, KnownNat cW) =>
  Vec (n + 1) (Signed cW) ->
  FirState n (FirOut iW cW (n + 1)) ->
  Signed iW ->
  FirState n (FirOut iW cW (n + 1))
firStep coeffs s x = FirState
  { fsChain = tail sums
  , fsOut   = head sums
  }
 where
  products :: Vec (n + 1) (Signed (FirOut iW cW (n + 1)))
  products = map (\c -> resize (x `mul` c)) coeffs

  -- Pairing p_i with (r_1 .. r_n, 0): element 0 is y = p_0 + r_1, and
  -- element i >= 1 is the next r_i = p_i + r_{i+1} (0 past the far end).
  sums :: Vec (n + 1) (Signed (FirOut iW cW (n + 1)))
  sums = zipWith (+) products (fsChain s :< 0)

-- | Synchronous transposed FIR with the coefficients as a 'Vec' parameter.
fir ::
  forall n iW cW dom.
  ( HiddenClockResetEnable dom
  , KnownNat n, KnownNat iW, KnownNat cW ) =>
  Vec (n + 1) (Signed cW) ->
  Signal dom (Signed iW) ->
  Signal dom (Signed (FirOut iW cW (n + 1)))
fir coeffs =
  moore (firStep coeffs) fsOut
        (initialFirState :: FirState n (FirOut iW cW (n + 1)))

-- | The synthesis coefficient set: a 15-tap linear-phase inverse-sinc³
-- compensator shape in Q15 (large positive centre tap, alternating-sign
-- skirt). The values are representative of the class of filter this slot
-- holds; the final taps get fitted once VT-05 fixes the band (R = 4 vs 8
-- changes the droop curve).
compCoeffs :: Vec 15 (Signed 16)
compCoeffs =
  (-12) :> 33 :> (-74) :> 145 :> (-260) :> 442 :> (-723) :> 21_867 :>
  (-723) :> 442 :> (-260) :> 145 :> (-74) :> 33 :> (-12) :> Nil

-- | Synthesis root: 18-bit CIC samples in, full-precision 38-bit out.
topEntity ::
  Clock System ->
  Signal System (Signed 18) ->
  Signal System (Signed 38)
topEntity clk x =
  withClockResetEnable clk resetGen enableGen (fir compCoeffs x)
{-# ANN topEntity
  (Synthesize
    { t_name = "maiden_fir"
    , t_inputs = [PortName "CLK", PortName "X"]
    , t_output = PortName "Y"
    }) #-}
{-# NOINLINE topEntity #-}
