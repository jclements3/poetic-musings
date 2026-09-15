{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

{-|
512-point streaming FFT — radix-2 single-delay-feedback (R2SDF).

== Why this exists

`hardware/BOM.md` Note A records a behavioural 512-point FFT synthesising to
~139k LUT4s. The ECP5 LFE5U-85F has 83,640, and it is the largest part in the
family — so on that number MAIDEN does not fit any ECP5, and the board choice
would have to leave the family entirely.

That 139k is the signature of a *fully unrolled* FFT: every butterfly
instantiated in parallel, which is what synthesis produces when a transform is
written behaviourally and flattened. It is a property of the implementation,
not of the transform.

This module is the counter-proposal, built to get a real number rather than an
argument. R2SDF is the standard streaming architecture: one sample in and one
out per clock, @log2 512 = 9@ stages, each holding a delay line and *one*
butterfly. Nine butterflies total instead of 512·log2(512)/2 = 2304.

== Structure

Stage @s@ (counting from the input) has a delay line of @L = N / 2^(s+1)@
complex words: 256, 128, 64, ... , 1. Each clock the stage either

* /fills/ (counter's top bit low): push the input into the delay line, and
  emit the *twiddled* value that falls out the far end (the stored
  differences of the previous half-frame); or
* /butterflies/ (top bit high): emit @(delayed + input) \/ 2@, and push
  @(delayed - input) \/ 2@ back into the delay line.

The delay lines of the seven large stages are 'blockRam', so they land in
@DP16KD@ rather than fabric flops — that is the whole point of the exercise,
since 511 complex words held in registers would be ~16k flip-flops. The two
trivial stages use registers: delay 1's only twiddle is @W^0 = 1@ (no
multiplier at all), and delay 2's are @{1, -i}@, where @-i@ is an exact
swap-and-negate (no multiplier, and no 0.99997 table-gain error either).

The complex multiply is the textbook four-real-multiply form,
@(a+bi)(c+di) = (ac - bd) + (ad + bc)i@, which maps to four @MULT18X18D@ per
stage; seven stages carry a multiplier, so 28 of the 156 DSPs on the part.

== Numerics

* __Fixed point__: samples are Q1.15 per component. Each butterfly output is
  scaled by 1\/2 (computed in 17 bits, then rounded-half-up back to 16), so
  the whole transform computes @X[k] \/ 512@ — the standard divide-by-N
  streaming FFT scaling. With that scaling the complex magnitude of every
  internal value is bounded by the maximum input complex magnitude (plus a
  few LSB of rounding creep), so the pipeline cannot overflow provided
  @|x[n]| <= ~32700@ in complex magnitude. Purely real inputs may therefore
  use the full component range.
* __Twiddles__: Q1.15, W_512^k = exp(-2πik\/512), read through a synchronous
  ROM ('rom') whose one-cycle latency doubles as the multiplier's operand
  register. Products are rounded (add 2^14 before the >>15), not truncated.
* __Output order__: decimation-in-frequency, so the natural-order input frame
  x[0..511] produces X in bit-reversed index order: output slot @n@ carries
  @X[bitreverse9(n)] \/ 512@.
* __Latency__: 511 cycles of data path (the sum of the delay-line lengths)
  plus 'stageLatency' pipeline cycles per stage: the first output of a frame
  appears @511 + 9*stageLatency = 547@ cycles after its first input entered.

== Pipelining (the timing fix)

The original sizing model computed the twiddle multiply *inside* the
delay-line feedback loop, giving a BRAM→4×DSP→32-bit-add→BRAM single-cycle
path and a measured Fmax of 25.5 MHz. Two changes:

1. The multiplier is moved to the forward path: the *raw* difference is fed
   back, and the twiddle is applied as the difference exits the delay line
   toward the next stage, where it can be pipelined freely. The forward path
   is a 4-stage pipeline (twiddle-ROM read \/ operand registers \/ DSP
   product registers \/ final add-and-round register); the sum path and the
   phase select are delayed to match.
2. The @DP16KD@ outputs (both the delay line and the twiddle ROM) are
   registered — an ECP5 EBR in NOREG mode has a ~5.6 ns clock-to-out, which
   by itself limits any path it starts to well under 100 MHz. The delay-line
   BRAM therefore reads /two/ addresses ahead of the write and its output
   register completes the exact 2^d-cycle loop; read and write stay two
   slots apart, which is why the BRAM stages need @d >= 2@ (the delay-2 and
   delay-1 stages hold their words in fabric registers anyway).

Each stage's phase counter is initialised @-stageLatency·(stageIndex-1)@ so
the free-running counters absorb the accumulated pipeline latency of the
stages before them.

== Status

__Numerically verified against a Double-precision reference DFT__ (see
@test\/FftSpec.hs@: impulse, single-bin complex tones, two-tone), within a few
LSB after undoing the bit-reversal and 1\/512 scaling. Functional fixes made
to the original sizing model, each of which was a real bug:

1. __Stage order was reversed.__ @fft512@ composed the stages with @(.)@ in
   the order written, so the delay-1 stage ran *first* and delay-256 *last*.
   DIF R2SDF needs delay 256 first. Fixed by reversing the composition.
2. __Delay-line off-by-one.__ 'blockRam' has one cycle of read latency, and
   reading and writing the *same* address made the loop 2^d+1 cycles long
   (and a same-address read\/write collision every cycle, which is undefined
   for a block RAM). Fixed by reading one address ahead of the write, giving
   an exact 2^d-cycle delay with reads and writes always one slot apart.
3. __Butterfly overflow.__ Q1.15 @cadd@\/@csub@ had no growth headroom.
   Fixed with the per-stage 1\/2 scaling described under /Numerics/.
4. __Twiddle gain on the trivial stages.__ The delay-1 stage multiplied by
   table entry (32767, 0) ≈ 0.99997 instead of exactly 1, and the delay-2
   stage by (0, -32767) ≈ -0.99997i instead of exactly -i; they now use no
   multiplier at all.

Measured on ECP5 LFE5U-85F (yosys @synth_ecp5@ + @nextpnr-ecp5 --85k
--package CABGA381 --freq 100@), this revision: 3,537 LUT4 \/ 3,729 FF \/
28 MULT18X18D \/ 10 DP16KD, Fmax 123.59 MHz — __PASS__ at the 100 MHz
constraint. The unpipelined sizing model measured 4,620 LUT4 \/ 486 FF \/
34 DSP \/ 3 BRAM at Fmax 25.5 MHz (FAIL).
-}
module Theremin.Fft
  ( Cplx
  , stageLatency
  , sdfStage
  , sdfStage2
  , sdfStageLast
  , fft512
  , topEntity
  ) where

import Clash.Prelude

import Theremin.Fft.Twiddle

-- | Complex sample: (real, imaginary), 16-bit signed each, Q1.15.
type Cplx = (Signed 16, Signed 16)

-- | Forward-path pipeline depth of every stage, in cycles.
stageLatency :: Int
stageLatency = 4

-- | @(a + b) \/ 2@ per component, computed in 17 bits with round-half-up, so
-- it cannot overflow: the result of @(x + y + 1) >>> 1@ for 16-bit @x@, @y@
-- always fits back in 16 bits.
caddSh :: Cplx -> Cplx -> Cplx
caddSh (a, b) (c, d) = (halveSum a c, halveSum b d)

-- | @(a - b) \/ 2@ per component, same widened-then-halved scheme.
csubSh :: Cplx -> Cplx -> Cplx
csubSh (a, b) (c, d) = (halveDiff a c, halveDiff b d)

halveSum, halveDiff :: Signed 16 -> Signed 16 -> Signed 16
halveSum x y = halve (add x y)
halveDiff x y = halve (sub x y)

-- | Arithmetic halve with round-half-up of a widened butterfly result.
halve :: Signed 17 -> Signed 16
halve v = truncateB ((v + 1) `shiftR` 1)

-- | Q1.15 complex multiply against a twiddle, split into the two pipeline
-- halves: 'cmulProducts' is the four real multiplies (registered into the
-- DSPs), 'cmulCombine' the two 32-bit add\/subs with rounding.
--
-- Ranges: |product sum| <= 32768·(|c|+|d|) <= 32768·46341 < 2^31, so the
-- 32-bit accumulation cannot overflow; and since |twiddle| <= 1 the rounded
-- result fits back in Q1.15 whenever the input's complex magnitude does.
cmulProducts :: Cplx -> Twiddle -> (Signed 32, Signed 32, Signed 32, Signed 32)
cmulProducts (a, b) (c, d) = (mul16 a c, mul16 b d, mul16 a d, mul16 b c)
 where
  mul16 :: Signed 16 -> Signed 16 -> Signed 32
  mul16 x y = resize x * resize y

cmulCombine :: (Signed 32, Signed 32, Signed 32, Signed 32) -> Cplx
cmulCombine (ac, bd, ad, bc) =
  ( resize ((ac - bd + 16384) `shiftR` 15)
  , resize ((ad + bc + 16384) `shiftR` 15) )

-- | Match the 'stageLatency' pipeline depth: four registers.
del4 :: HiddenClockResetEnable dom => Signal dom Cplx -> Signal dom Cplx
del4 = register (0, 0) . register (0, 0) . register (0, 0) . register (0, 0)

del4b :: HiddenClockResetEnable dom => Signal dom Bool -> Signal dom Bool
del4b = register False . register False . register False . register False

-- | One radix-2 single-delay-feedback stage with a block-RAM delay line.
--
-- @d@ is the log2 of the delay length (@d >= 2@ here; the delay-2 and
-- delay-1 stages are 'sdfStage2' and 'sdfStageLast'), so the stage holds
-- @2^d@ complex words and its phase counter is @d+1@ bits: the top bit
-- selects fill vs butterfly.
--
-- @strideShift@ selects this stage's twiddles out of 'masterTwiddles' —
-- stage delay @L@ uses every @256 \/ L@-th entry.
--
-- @phase0@ is the counter's reset value; 'fft512' uses it to absorb the
-- 'stageLatency' cycles of every preceding stage, so all counters can
-- free-run from reset and still agree on which cycle is sample 0.
--
-- The forward path (both the butterfly sum and the twiddled difference
-- leaving the delay line) is pipelined 'stageLatency' cycles; the feedback
-- loop stays single-cycle but contains only a 17-bit add fed from the
-- delay-line output /register/, never from the raw EBR output.
sdfStage ::
  forall d dom.
  (HiddenClockResetEnable dom, KnownNat d, 2 <= d) =>
  SNat d ->
  Int ->                  -- ^ stride shift into the master twiddle table
  Unsigned (d + 1) ->     -- ^ counter reset phase
  Signal dom Cplx ->
  Signal dom Cplx
sdfStage _ strideShift phase0 din = dout
 where
  -- Phase counter: 0 .. 2L-1. Top bit low = fill, high = butterfly.
  counter :: Signal dom (Unsigned (d + 1))
  counter = register phase0 (counter + 1)

  butterflyPhase = (== 1) . msb <$> counter

  -- Index within the half-period: the delay-line *write* address.
  addr :: Signal dom (Unsigned d)
  addr = truncateB <$> counter

  -- Read two slots ahead of the write: one cycle for the blockRam's
  -- internal read latency, one for the explicit output register that
  -- shields everything downstream from the EBR's slow clock-to-out. The
  -- registered value seen at cycle t is then the one written 2^d cycles
  -- earlier, and the read port always trails the write port by two slots,
  -- so they never collide (this is why @d >= 2@).
  readAddr :: Signal dom (Unsigned d)
  readAddr = truncateB <$> (counter + 2)

  delayed :: Signal dom Cplx
  delayed = register (0, 0) (blockRam (replicate (SNat @(2 ^ d)) (0, 0)) readAddr wr)

  wr = (\a v -> Just (a, v)) <$> addr <*> feedback

  -- Feedback: raw scaled difference during butterfly, passthrough during
  -- fill. No multiplier in this loop — that is the timing fix.
  feedback =
    mux butterflyPhase
        (csubSh <$> delayed <*> din)
        din

  -- Twiddle for the difference currently *exiting* the delay line. It was
  -- stored at butterfly-count n and exits at fill-count n, so the ROM index
  -- is the same addr either way. 'rom' has one cycle of latency and its
  -- output is registered like the delay line's, putting the twiddle in step
  -- with opDelayed at the multiplier's operand registers.
  twAddr :: Signal dom (Unsigned 8)
  twAddr = (\a -> resize a `shiftL` strideShift) <$> addr

  tw :: Signal dom Twiddle
  tw = register (0, 0) (rom masterTwiddles twAddr)

  -- Forward pipeline, 4 cycles (= stageLatency), counted from the aligned
  -- signals delayed[t] / addr[t]:
  --   t+1: EBR-side reads (first opDelayed register / raw twiddle-ROM read)
  --   t+2: operand registers at the multiplier (second register / tw)
  --   t+3: DSP product registers
  --   t+4: rounded 32-bit combine
  opDelayed = register (0, 0) (register (0, 0) delayed)
  prods = register (0, 0, 0, 0) (cmulProducts <$> opDelayed <*> tw)
  twiddled = register (0, 0) (cmulCombine <$> prods)

  -- The sum path and the phase select ride the same 4-cycle delay.
  sumP = del4 (caddSh <$> delayed <*> din)
  bfP = del4b butterflyPhase

  dout = mux bfP sumP twiddled

-- | The delay-2 stage: two fabric registers instead of a BRAM, and no DSPs —
-- its twiddles are @W_4^0 = 1@ and @W_4^1 = -i@, and multiplying by @-i@ is
-- an exact swap-and-negate. Output is pipelined 'stageLatency' cycles to
-- match 'sdfStage'.
sdfStage2 ::
  forall dom.
  HiddenClockResetEnable dom =>
  Unsigned 2 ->           -- ^ counter reset phase
  Signal dom Cplx ->
  Signal dom Cplx
sdfStage2 phase0 din = dout
 where
  counter :: Signal dom (Unsigned 2)
  counter = register phase0 (counter + 1)

  butterflyPhase = (== 1) . msb <$> counter

  addr :: Signal dom (Unsigned 1)
  addr = truncateB <$> counter

  delayed = register (0, 0) (register (0, 0) feedback)

  feedback =
    mux butterflyPhase
        (csubSh <$> delayed <*> din)
        din

  -- The value exiting at fill-count 1 was stored at butterfly-count 1 and
  -- needs W_4^1 = -i: (a+bi)·(-i) = b - ai, exactly.
  exit =
    mux ((== 1) <$> addr)
        ((\(re, im) -> (im, negate re)) <$> delayed)
        delayed

  sumP = del4 (caddSh <$> delayed <*> din)
  outP = del4 exit
  bfP = del4b butterflyPhase

  dout = mux bfP sumP outP

-- | The final stage: delay 1, held in a register, and no multiplier — its
-- only twiddle is @W^0 = 1@. Output is pipelined 'stageLatency' cycles to
-- match 'sdfStage'.
sdfStageLast ::
  forall dom.
  HiddenClockResetEnable dom =>
  Unsigned 1 ->           -- ^ counter reset phase
  Signal dom Cplx ->
  Signal dom Cplx
sdfStageLast phase0 din = dout
 where
  counter :: Signal dom (Unsigned 1)
  counter = register phase0 (counter + 1)

  butterflyPhase = (== 1) . msb <$> counter

  delayed = register (0, 0) feedback

  feedback =
    mux butterflyPhase
        (csubSh <$> delayed <*> din)
        din

  sumP = del4 (caddSh <$> delayed <*> din)
  outP = del4 delayed
  bfP = del4b butterflyPhase

  dout = mux bfP sumP outP

-- | 512-point R2SDF pipeline: nine stages, delays 256 down to 1 — delay 256
-- must run *first* (decimation in frequency; the composition order in the
-- original sizing model was reversed).
--
-- The twiddle stride doubles at each stage as the delay halves. Each stage's
-- counter is reset to @-(stageLatency · stagesBefore)@ so the free-running
-- counters stay aligned with the data, which reaches stage @s@ delayed by
-- the pipeline registers of the @s-1@ stages before it.
fft512 ::
  HiddenClockResetEnable dom =>
  Signal dom Cplx ->
  Signal dom Cplx
fft512 =
    sdfStageLast        (phase 8)
  . sdfStage2           (phase 7)
  . sdfStage (SNat @2) 6 (phase 6)
  . sdfStage (SNat @3) 5 (phase 5)
  . sdfStage (SNat @4) 4 (phase 4)
  . sdfStage (SNat @5) 3 (phase 3)
  . sdfStage (SNat @6) 2 (phase 2)
  . sdfStage (SNat @7) 1 (phase 1)
  . sdfStage (SNat @8) 0 (phase 0)
 where
  -- Counter reset value for the stage with @stagesBefore@ stages upstream.
  phase :: KnownNat n => Int -> Unsigned n
  phase stagesBefore = negate (fromIntegral (stageLatency * stagesBefore))

-- | Synthesis root, for area and timing on the ECP5.
topEntity ::
  Clock System ->
  Reset System ->
  Signal System Cplx ->
  Signal System Cplx
topEntity clk rst din =
  withClockResetEnable clk rst enableGen (fft512 din)
{-# ANN topEntity
  (Synthesize
    { t_name = "fft512_r2sdf"
    , t_inputs = [PortName "CLK", PortName "RESET", PortName "IN"]
    , t_output = PortName "OUT"
    }) #-}
{-# NOINLINE topEntity #-}
