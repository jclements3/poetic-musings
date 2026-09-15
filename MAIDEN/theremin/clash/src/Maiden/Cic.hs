{-|
MAIDEN CW-Doppler front-end decimator: an order-@n@ CIC (Hogenauer) filter
with a type-level decimation ratio @r@.

Position in the chain (docs\/D6, revised by
@results/design-notes/decimation-audit.md@):

@
  MCP3202 ADC (12-bit I\/Q at 48 kS\/s) -> CIC ↓R -> FIR compensate -> 512-pt FFT
@

The decimation ratio is a /generic/, per the audit's finding of record: a
fixed ↓8 aliases pattern-speed targets at 24.125 GHz, so the default build is
@R = 4@ (↓8 remains acceptable only if VT-05 selects the 10.525 GHz HB100).
This module takes @r@ as a type parameter with the default instantiated in
'topEntity'.

== Structure

Classic two-section CIC with unit differential delay (@M = 1@):

* @n@ integrators at the /input/ rate, one adder per stage with
  /registered/ chaining: stage 0 accumulates the input, each later stage
  accumulates the previous stage's register
  (@y_k[t] = y_k[t-1] + y_{k-1}[t-1]@). No two adders are ever chained
  combinationally — an early ripple-chained version of this file measured
  77 MHz on the LFE5U-85 because the whole integrator + comb ripple landed
  in one cycle; the registered form clears 100 MHz.
* @n@ combs at the /output/ rate: every @r@-th input clock the last
  integrator /register/ is sampled and differenced @n@ times
  (@c_k[m] = c_{k-1}[m] - c_{k-1}[m-1]@), all in the same enable slot.

The registered chaining inserts one extra input-rate delay per stage
boundary plus one at the sampling point: the output is the textbook CIC
response of the input delayed by @n@ samples (3 at the default order).
Delay changes nothing about gain or shape — but it does shift which input
phase lands on which decimated sample, and the tests pin that alignment
exactly.

Two's-complement wraparound in the integrators is not a bug — it is the
standard Hogenauer trick. It is exact as long as the internal width covers
the worst-case DC gain, which is @r^n@, i.e. @n * log2(r)@ bits of growth.
'CicWidth' sizes that with type-level arithmetic: @w = inW + n * CLog 2 r@
(for non-power-of-two @r@ the ceiling log over-provisions, which is safe).
For the default @inW = 12@, @n = 3@, @r = 4@: @w = 12 + 3*2 = 18@.

== Interface

One channel is 'cic'. 'topEntity' instantiates it /twice/ (I and Q), because
MAIDEN's chain is quadrature and the resource measurement must reflect the
real cost, not half of it. Output 'csValid' is high for exactly one input
clock per decimated sample.
-}
module Maiden.Cic
  ( CicWidth
  , CicState (..)
  , initialCicState
  , cicStep
  , cic
  , topEntity
  ) where

import Clash.Prelude

-- | Internal (and output) width of an order-@n@, ratio-@r@ CIC on an
-- @inW@-bit input: full bit growth, no pruning.
type CicWidth inW n r = inW + n * CLog 2 r

-- | Every register in one CIC channel.
data CicState n r w = CicState
  { csInts  :: Vec n (Signed w)
    -- ^ Integrator registers, stage 0 first.
  , csPhase :: Index r
    -- ^ Decimation phase; the comb section fires on the wrap.
  , csCombs :: Vec n (Signed w)
    -- ^ Comb delay registers (@M = 1@), stage 0 first.
  , csOut   :: Signed w
    -- ^ Registered decimated output.
  , csValid :: Bool
    -- ^ True for the one input clock on which 'csOut' was refreshed.
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

initialCicState ::
  (KnownNat n, KnownNat r, KnownNat w, 1 <= r) =>
  CicState n r w
initialCicState = CicState
  { csInts  = repeat 0
  , csPhase = 0
  , csCombs = repeat 0
  , csOut   = 0
  , csValid = False
  }

-- | One input-rate clock edge. Pure, so tests drive it without a simulator.
cicStep ::
  forall inW n r.
  ( KnownNat inW, KnownNat n, KnownNat r
  , 1 <= r, 1 <= n, inW <= CicWidth inW n r ) =>
  CicState n r (CicWidth inW n r) ->
  Signed inW ->
  CicState n r (CicWidth inW n r)
cicStep s x = CicState
  { csInts  = ints'
  , csPhase = if wrap then 0 else csPhase s + 1
  , csCombs = if wrap then combs' else csCombs s
  , csOut   = if wrap then combOut else csOut s
  , csValid = wrap
  }
 where
  -- Integrator cascade with registered chaining: each stage adds the
  -- /previous/ value of the stage before it, so the critical path is one
  -- adder. (x +>> ints) is (x, i_0, .., i_{n-2}): stage k's addend.
  ints' :: Vec n (Signed (CicWidth inW n r))
  ints' = zipWith (+) (csInts s) (resize x +>> csInts s)

  wrap = csPhase s == maxBound

  -- Comb cascade in the decimation slot, fed from the last integrator
  -- register (not this cycle's sum — that keeps the adder chains apart).
  -- Each stage outputs (input - delayed input) and refreshes its delay.
  -- (!! maxBound rather than 'last': it only needs @1 <= n@, not @n ~ m+1@.)
  (combOut, combs') =
    mapAccumL (\v d -> (v - d, v))
              (csInts s !! (maxBound :: Index n))
              (csCombs s)

-- | One synchronous CIC channel.
cic ::
  forall inW n r dom.
  ( HiddenClockResetEnable dom
  , KnownNat inW, KnownNat n, KnownNat r
  , 1 <= r, 1 <= n, inW <= CicWidth inW n r ) =>
  SNat n ->
  SNat r ->
  Signal dom (Signed inW) ->
  Signal dom (Signed (CicWidth inW n r), Bool)
cic SNat SNat =
  moore cicStep
        (\s -> (csOut s, csValid s))
        (initialCicState :: CicState n r (CicWidth inW n r))

-- | Synthesis root at the MAIDEN defaults: order 3, R = 4 (decimation
-- audit), 12-bit MCP3202 samples, two channels for quadrature I\/Q.
-- Output is 18 bits per channel with a shared-timing valid strobe (the
-- two channels advance in lockstep, so one strobe is reported).
topEntity ::
  Clock System ->
  Signal System (Signed 12) ->
  Signal System (Signed 12) ->
  Signal System (Signed 18, Signed 18, Bool)
topEntity clk iIn qIn =
  withClockResetEnable clk resetGen enableGen $
    let iOut = cic (SNat @3) (SNat @4) iIn
        qOut = cic (SNat @3) (SNat @4) qIn
    in  (\(i, v) (q, _) -> (i, q, v)) <$> iOut <*> qOut
{-# ANN topEntity
  (Synthesize
    { t_name = "maiden_cic"
    , t_inputs = [PortName "CLK", PortName "I_IN", PortName "Q_IN"]
    , t_output = PortProduct "" [PortName "I_OUT", PortName "Q_OUT", PortName "VALID"]
    }) #-}
{-# NOINLINE topEntity #-}
