{-# LANGUAGE RecordWildCards #-}
-- PM.Lfo — vibrato / tremolo low-frequency oscillators for the VL-1 voice.
--
--   * tri      : 256-step triangle, phase Unsigned 8 -> Signed 9 in
--                [-128, +128]; exactly zero-mean over one cycle.
--   * scaleMod : triangle * depth / 128, rounded symmetrically (magnitude
--                first, then sign) so +/- halves stay mirror images and the
--                cycle keeps a zero mean. Peak = depth exactly.
--   * lfo      : the LFO. Runtime rate = clock cycles per phase step minus
--                one (period = 256 * (rate + 1) cycles); runtime depth
--                (Unsigned 8). The effective depth ramps toward the target
--                by one unit per phase step (constant slope, as the VL-1's
--                delayed vibrato swells in) and resets to 0 on retrig.
--   * vibrato  : apply a modulation value to a 32-bit NCO phase increment:
--                inc * (1 + mod / 2^12), i.e. +/- ~6 % (about a semitone)
--                at full depth. Depth 0 leaves the increment untouched.
--   * tremolo  : apply to a Signed 12 sample: gain (256 - depth + mod)/256,
--                unity at depth 0, dipping to (256 - 2*depth)/256 (floored
--                at 0) at the trough; never exceeds unity.
module PM.Lfo where

import Clash.Prelude

-- ---------------------------------------------------------------------------
-- Triangle: p<128 -> 2p-128 (rising -128..126), else 384-2p (falling 128..-126).

tri :: Unsigned 8 -> Signed 9
tri p =
  let q = fromIntegral p :: Signed 10
      v = if p < 128 then 2 * q - 128 else 384 - 2 * q
  in resize v

scaleMod :: Signed 9 -> Unsigned 8 -> Signed 9
scaleMod t d =
  let m  = fromIntegral (abs t) :: Unsigned 8          -- |t| <= 128
      pr = (resize m :: Unsigned 16) * resize d        -- <= 128*255
      mg = fromIntegral (shiftR pr 7) :: Signed 9      -- <= 255
  in if t < 0 then negate mg else mg

-- ---------------------------------------------------------------------------
-- LFO state machine.

data Lfo = Lfo
  { lCnt :: !(Unsigned 16)   -- cycles since last phase step
  , lPh  :: !(Unsigned 8)    -- triangle phase
  , lDep :: !(Unsigned 8)    -- ramped (effective) depth
  } deriving (Generic, NFDataX)

lfoT :: Lfo -> (Unsigned 16, Unsigned 8, Bool) -> (Lfo, Signed 9)
lfoT l@Lfo{..} (rate, depth, retrig)
  | retrig       = (Lfo 0 0 0, 0)
  | lCnt == rate = (Lfo 0 (lPh + 1) dep', out)
  | otherwise    = (l { lCnt = lCnt + 1 }, out)
 where
  dep' | lDep < depth = lDep + 1
       | lDep > depth = lDep - 1
       | otherwise    = lDep
  out = scaleMod (tri lPh) lDep

lfo
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 16)   -- rate: cycles per phase step - 1
  -> Signal dom (Unsigned 8)    -- depth target
  -> Signal dom Bool            -- retrig: restart phase and depth ramp
  -> Signal dom (Signed 9)
lfo rate depth retrig = mealy lfoT (Lfo 0 0 0) (bundle (rate, depth, retrig))

-- ---------------------------------------------------------------------------
-- Applying the modulation.

vibrato :: Unsigned 32 -> Signed 9 -> Unsigned 32
vibrato inc m =
  let i = fromIntegral inc :: Signed 42
      d = shiftR (i * resize m) 12          -- |i*m| < 2^41
  in fromIntegral (i + d)

tremolo :: Signed 12 -> Unsigned 8 -> Signed 9 -> Signed 12
tremolo s depth m =
  let g  = 256 - fromIntegral depth + resize m :: Signed 10
      g' = if g < 0 then 0 else g
      p  = (resize s :: Signed 22) * resize g'   -- |s*g'| <= 2047*256
  in resize (shiftR p 8)

-- | Synthesis root (area/Fmax measurement).
topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 16) -> Signal System (Unsigned 8) -> Signal System Bool
  -> Signal System (Signed 9)
topEntity = exposeClockResetEnable lfo
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_lfo"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "rate", PortName "depth", PortName "retrig" ]
    , t_output = PortName "mod"
    }) #-}
