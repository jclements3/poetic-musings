{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}
-- PM.Ddc — the SDR digital down-converter (SDR/DESIGN.md "Signal path"):
--
--   AD9226 (Signed 12 @ 65 MSPS) -> NCO/mixer -> CIC ÷R (order 3) ->
--   FIR compensation (15 taps, Maiden.Fir compCoeffs) -> I/Q Signed 16 + valid
--
-- * NCO: Theremin.Audio.Nco (32-bit accumulator, 0.015 Hz at 65 MHz) and
--   Theremin.Audio.SineLut (quarter-wave 256-entry ROM, Q1.15 sine); cosine
--   is the same table at phase + 90 degrees (top-10-bit index + 256).
-- * Mixer: x * sin/cos, Q15 product truncated back to Signed 12, registered.
--   I = x*cos, Q = -x*sin, so a tone at f_nco lands at DC with I positive.
-- * CIC: Maiden.Cic, order 3, ratio R at the type level; the design's R=512
--   (65 MHz -> 126.95 kS/s) is the default in topEntity, and 'ddc' takes any
--   R the library sizes (width 12 + 3*clog2 R; 39 bits at 512). The 39-bit
--   output is shifted right by cicShift = 3*log2 R - 5 (22 at R=512) so a
--   full-scale DC lands in 18 bits (CIC DC gain R^3 = 2^27 -> 2^5*A/2).
-- * FIR: Maiden.Fir at the decimated rate (enable-gated on the CIC strobe),
--   compCoeffs Q15 (DC gain 20969/32768 = 0.640), 38-bit output >> 15 ->
--   Signed 16. Net DC gain, tone amplitude A (ADC counts) at f_nco:
--   I = A/2 * 2^5 * 0.640 = 10.24*A  (2047 -> 20957, inside Signed 16).
-- * Output valid: one clock per decimated sample, one clock after the FIR
--   registered it (cicValid delayed 1).
module PM.Ddc
  ( ddc
  , mixStep
  , cosLookup
  , firDcGain
  , topEntity
  ) where

import Clash.Prelude
import qualified Prelude as P
import Maiden.Cic (cic, CicWidth)
import Maiden.Fir (fir, compCoeffs)
import Theremin.Audio.Nco (nco, phaseMsbs)
import Theremin.Audio.SineLut (sineLookup)

-- | cos via the sine table: sin(phi + pi/2).
cosLookup :: BitVector 10 -> Signed 16
cosLookup p = sineLookup (p + 256)

-- | Q15 mix, truncated to the ADC width: (x*c) >> 15.
mixStep :: Signed 12 -> Signed 16 -> Signed 12
mixStep x c = resize ((x `mul` c) `shiftR` 15)

-- | DC gain of the compensation FIR (for tests): sum(compCoeffs)/2^15.
firDcGain :: P.Double
firDcGain = P.fromIntegral (P.sum (P.map (P.toInteger) (toList compCoeffs)))
            / 32768

-- | Down-converter with type-level CIC ratio @r@.
--   (freq word, adc) -> (I, Q, valid)
ddc :: forall r w dom.
       ( HiddenClockResetEnable dom, KnownNat r, 1 <= r
       , KnownNat (CLog 2 r), w ~ CicWidth 12 3 r, KnownNat w
       , 12 <= w, 18 <= w )
    => SNat r
    -> Signal dom (Unsigned 32)
    -> Signal dom (Signed 12)
    -> Signal dom (Signed 16, Signed 16, Bool)
ddc r fw adc = bundle (iOut, qOut, vOut)
 where
  phase  = nco fw
  msbs   = phaseMsbs @10 <$> phase
  cosS   = register 0 (cosLookup <$> msbs)
  sinS   = register 0 (sineLookup <$> msbs)
  adcD   = register 0 adc
  iMix   = register 0 (mixStep <$> adcD <*> cosS)
  qMix   = register 0 (mixStep <$> adcD <*> (negate <$> sinS))
  (iCic, v) = unbundle (cic (SNat @3) r iMix)
  (qCic, _) = unbundle (cic (SNat @3) r qMix)
  sh     = 3 * (natToNum @(CLog 2 r) :: Int) - 5
  narrow :: Signed w -> Signed 18
  narrow x = resize (x `shiftR` sh)
  iFir   = andEnable v (fir compCoeffs (narrow <$> iCic))
  qFir   = andEnable v (fir compCoeffs (narrow <$> qCic))
  scale :: Signed 38 -> Signed 16
  scale y = resize (y `shiftR` 15)
  iOut   = scale <$> iFir
  qOut   = scale <$> qFir
  vOut   = register False v

-- | Synthesis root: R = 512 per SDR/DESIGN.md.
topEntity :: Clock System -> Reset System -> Enable System
          -> Signal System (Unsigned 32)
          -> Signal System (Signed 12)
          -> Signal System (Signed 16, Signed 16, Bool)
topEntity = exposeClockResetEnable (ddc (SNat @512))
{-# NOINLINE topEntity #-}
