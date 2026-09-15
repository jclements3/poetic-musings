{-# LANGUAGE RecordWildCards #-}
-- PM.AmDemod — AM envelope demodulator on the DDC's I/Q output
-- (SDR/DESIGN.md "AM/CW demod -> oAudio SDR source").
--
--   envelope = |I + jQ|          Maiden.Cordic vectoring mode, 17-clock
--                                pipeline, gain G = 1.6468, Unsigned 18
--   lpf:  y  += (env - y) >> kLpf     first-order IIR, shift-based (runtime
--                                     shift 0..7; 1 -> fc ~ fs/12)
--   dc:   dc += (y - dc) >> 10        DC tracker, fc ~ fs/6400 (5 Hz @ 32k)
--   audio = (y - dc) >> 2 -> Signed 16 (envelope is <= 2^18 so /4 fits)
--
-- Samples arrive with a valid strobe at the decimated rate (32 kS/s); the
-- CORDIC pipeline and both filters advance only on the strobe (enable
-- gating), so the whole block runs on the 65 MHz DSP clock. Output audio is
-- valid on the strobe delayed by the 17-clock CORDIC latency + 1 (amValid).
module PM.AmDemod
  ( AmState (..)
  , initialAmState
  , amStep
  , amDemod
  , cordicGain
  , topEntity
  ) where

import Clash.Prelude
import qualified Prelude as P
import Maiden.Cordic (cordic)

-- | CORDIC magnitude gain (Maiden.Cordic), for test expectations.
cordicGain :: P.Double
cordicGain = 1.6467603

data AmState = AmState
  { asLpf :: !(Signed 20)   -- ^ low-passed envelope
  , asDc  :: !(Signed 30)   -- ^ DC tracker, Q10 (extra fraction bits)
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX)

initialAmState :: AmState
initialAmState = AmState 0 0

-- | One strobed sample: (shift, envelope) -> new state.
amStep :: AmState -> (Unsigned 3, Unsigned 18) -> AmState
amStep AmState{..} (k, env) = AmState lpf' dc'
 where
  e    = bitCoerce (resize env :: Unsigned 20) :: Signed 20
  lpf' = asLpf + ((e - asLpf) `shiftR` fromEnum k)
  -- Q10 tracker: dc += (y*2^10 - dc) >> 10  ==  dc += y - dc/2^10
  dc'  = asDc + ((resize lpf' `shiftL` 10) - asDc) `shiftR` 10

audioOut :: AmState -> Signed 16
audioOut AmState{..} = resize ((asLpf - resize (asDc `shiftR` 10)) `shiftR` 2)

-- | (lpf shift, (valid, (i, q))) -> (audio, dc level (envelope units), valid)
amDemod :: HiddenClockResetEnable dom
        => Signal dom (Unsigned 3)
        -> Signal dom (Bool, (Signed 16, Signed 16))
        -> Signal dom (Signed 16, Unsigned 18, Bool)
amDemod k inp = bundle (audio, dcLvl, vOut)
 where
  (v, iq)  = unbundle inp
  mag      = fst <$> andEnable v (cordic iq)
  -- strobe delayed by the 17-clock CORDIC latency (same enable gating)
  vDel     = andEnable v (foldl (\s _ -> register False s) v (replicate d17 ()))
  vOut     = register False (v .&&. vDel)
  st       = andEnable v $
               register initialAmState
                 (mux vDel (amStep <$> st <*> bundle (k, mag)) st)
  audio    = audioOut <$> st
  dcLvl    = dcOut <$> st

dcOut :: AmState -> Unsigned 18
dcOut s = bitCoerce (resize (asDc s `shiftR` 10) :: Signed 18)

topEntity :: Clock System -> Reset System -> Enable System
          -> Signal System (Unsigned 3)
          -> Signal System (Bool, (Signed 16, Signed 16))
          -> Signal System (Signed 16, Unsigned 18, Bool)
topEntity = exposeClockResetEnable amDemod
{-# NOINLINE topEntity #-}
