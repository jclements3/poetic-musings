{-# LANGUAGE RecordWildCards #-}
-- PM.Goertzel — single-tone detector for CW decode (UHF/DESIGN.md: the
-- Goertzel tone detector, DSP core).
--
--   Second-order resonator over a block of N samples:
--     s[n] = x[n] + c*s[n-1] - s[n-2],   c = 2*cos(2*pi*f_tone/f_s)
--   and at block end the squared magnitude
--     |X|^2 = s1^2 + s2^2 - c*s1*s2.
--
--   * coefficient c: runtime, Signed 18 in Q16 (range +/-2, so any tone
--     below Nyquist; c = 2 exactly is not representable and is DC anyway).
--   * block length N: runtime, 1..1024 (Unsigned 11; 0 is treated as 1).
--   * audio in: Signed 16 with a sample strobe (32 kS/s or 8 kS/s; the block
--     runs on strobed samples only, so the core can sit on a 65 MHz clock).
--   * state s1,s2: Signed 36 (|s| <= ~N*A*2^0 resonant growth: 2^10 * 2^15 *
--     a few, so 36 bits is generous, never wraps).
--   * power out: Unsigned 48 = |X|^2 / 2^16 (s is pre-shifted right by 8
--     before squaring so the arithmetic stays within 56 bits). For a
--     full-scale tone and N = 1024 that is (N*A/2)^2 / 2^16 = 2^32.
--   * tone flag with hysteresis: asserted when power > threshold, dropped
--     when power < threshold/2 (-3 dB), updated only at block end.
--   * done: one-clock strobe when a block result is published.
module PM.Goertzel
  ( GoertzelCfg (..)
  , GoertzelState (..)
  , initialGoertzelState
  , goertzelStep
  , goertzel
  , goertzelCoeff
  , topEntity
  ) where

import Clash.Prelude
import qualified Prelude as P

data GoertzelCfg = GoertzelCfg
  { gcCoeff     :: Signed 18    -- ^ 2*cos(2*pi*k/N), Q16
  , gcBlockLen  :: Unsigned 11  -- ^ N, 1..1024
  , gcThreshold :: Unsigned 48  -- ^ power threshold (same scale as output)
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

data GoertzelState = GoertzelState
  { gsS1    :: !(Signed 36)
  , gsS2    :: !(Signed 36)
  , gsCount :: !(Unsigned 11)
  , gsPower :: !(Unsigned 48)
  , gsTone  :: !Bool
  , gsDone  :: !Bool
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

initialGoertzelState :: GoertzelState
initialGoertzelState = GoertzelState 0 0 0 0 False False

-- | Elaboration-time helper for tests and constants: the Q16 coefficient for
-- a tone at @fTone@ with sample rate @fs@ (Double in, Signed 18 out).
goertzelCoeff :: P.Double -> P.Double -> Signed 18
goertzelCoeff fTone fs =
  fromInteger (P.round (2 * P.cos (2 * P.pi * fTone / fs) * 65536))

-- | Q16 product c*s, result truncated to Signed 36.
mulQ16 :: Signed 18 -> Signed 36 -> Signed 36
mulQ16 c s = resize ((c `mul` s) `shiftR` 16)

-- | One clock edge: (config, (sample strobe, sample)).
goertzelStep :: GoertzelState -> (GoertzelCfg, (Bool, Signed 16))
             -> GoertzelState
goertzelStep st (GoertzelCfg{..}, (strobe, x))
  | not strobe = st { gsDone = False }
  | lastOne    = GoertzelState
      { gsS1 = 0, gsS2 = 0, gsCount = 0
      , gsPower = power, gsTone = tone', gsDone = True }
  | otherwise  = st { gsS1 = s1', gsS2 = gsS1 st, gsCount = gsCount st + 1
                    , gsDone = False }
 where
  n        = if gcBlockLen == 0 then 1 else gcBlockLen
  lastOne  = gsCount st + 1 >= n
  s1'      = resize x + mulQ16 gcCoeff (gsS1 st) - gsS2 st
  -- block end: fold in the final sample then square (pre-shift 8 bits)
  a        = s1' `shiftR` 8 :: Signed 36
  b        = gsS1 st `shiftR` 8 :: Signed 36
  a28      = resize a :: Signed 28
  b28      = resize b :: Signed 28
  sq       = resize (a28 `mul` a28) + resize (b28 `mul` b28)
               - resize ((mulQ16 gcCoeff (resize a28)) `mul` b28) :: Signed 57
  power    = resize (bitCoerce (if sq < 0 then 0 else sq) :: Unsigned 57)
  tone'    | power > gcThreshold             = True
           | power < (gcThreshold `shiftR` 1) = False
           | otherwise                         = gsTone st

-- | Synchronous detector: (power, tone, done).
goertzel :: HiddenClockResetEnable dom
         => Signal dom GoertzelCfg
         -> Signal dom (Bool, Signed 16)
         -> Signal dom (Unsigned 48, Bool, Bool)
goertzel cfg inp =
  moore goertzelStep (\s -> (gsPower s, gsTone s, gsDone s))
        initialGoertzelState (bundle (cfg, inp))

topEntity :: Clock System -> Reset System -> Enable System
          -> Signal System GoertzelCfg
          -> Signal System (Bool, Signed 16)
          -> Signal System (Unsigned 48, Bool, Bool)
topEntity = exposeClockResetEnable goertzel
{-# NOINLINE topEntity #-}
