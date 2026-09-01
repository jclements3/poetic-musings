{-# LANGUAGE RecordWildCards #-}
-- PM.Audio — the One Box audio path (consumers: O sidetone, T theremin,
-- P synth, E harp voices; register contract: eforth-pm.md 0x402C mixer).
--
--   * sdDac  : first-order sigma-delta, Unsigned 12 -> Bit. The single output
--              pin drives the RC lowpass -> amp per LAYOUT; density of ones
--              equals the input code.
--   * nco    : phase-accumulator sine, 32-bit phase, 64-entry quarter-wave
--              table expanded to full wave. freq = phaseInc * fclk / 2^32.
--   * mixer  : four signed channels, per-channel 3-bit right-shift gains,
--              saturating sum, hardware mute (the GPIO amp-mute stays a
--              separate pin; this mute silences the digital path).
module PM.Audio where

import Clash.Prelude
import qualified Prelude

-- ---------------------------------------------------------------------------
-- First-order sigma-delta DAC.

sdDacT :: Unsigned 13 -> Unsigned 12 -> (Unsigned 13, Bit)
sdDacT acc x =
  let s = acc + resize x
      bit_ = if testBit s 12 then 1 else 0
      acc' = clearBit s 12
  in (acc', bit_)

sdDac
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 12) -> Signal dom Bit
sdDac = mealy sdDacT 0

-- ---------------------------------------------------------------------------
-- NCO: quarter-wave sine table, 64 entries, Signed 12 output.

quarterSine :: Vec 64 (Signed 12)
quarterSine = $(listToVecTH
  [ fromInteger (round (2047 * Prelude.sin (Prelude.pi / 2 * ((Prelude.fromIntegral i :: Prelude.Double) + 0.5) / 64))) :: Signed 12
  | i <- [0 :: Integer .. 63] ])

sineLookup :: Unsigned 8 -> Signed 12
sineLookup ph =
  let quad = slice d7 d6 ph
      idx6 = unpack (slice d5 d0 ph) :: Index 64
      idxR = maxBound - idx6
      mag rev = quarterSine !! (if rev then idxR else idx6)
  in case quad of
       0b00 -> mag False
       0b01 -> mag True
       0b10 -> negate (mag False)
       _    -> negate (mag True)

nco
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 32)               -- phase increment
  -> Signal dom (Signed 12)
nco inc = sineLookup . msb8 <$> phase
 where
  phase = register 0 (phase + inc)
  msb8 = unpack . slice d31 d24

-- ---------------------------------------------------------------------------
-- Mixer: 4 channels, shift gains (0 = unity .. 7 = -42 dB), saturating.

mixer4
  :: Vec 4 (Signed 12)      -- channel samples
  -> Vec 4 (Unsigned 3)     -- per-channel right-shift gain
  -> Bool                   -- digital mute
  -> Signed 12
mixer4 xs gs mute_
  | mute_ = 0
  | otherwise =
      let scaled = zipWith (\x g -> shiftR (resize x :: Signed 14) (fromIntegral g)) xs gs
          s = sum scaled
      in satCast s
 where
  satCast :: Signed 14 -> Signed 12
  satCast v
    | v > 2047  = 2047
    | v < -2048 = -2048
    | otherwise = resize v

-- offset-binary conversion for the DAC (Signed 12 audio -> Unsigned 12 code)
toDacCode :: Signed 12 -> Unsigned 12
toDacCode v = bitCoerce (v + 2048 - 2048) `xor` 0x800

-- ---------------------------------------------------------------------------
-- Top: sidetone NCO on ch0 gated by the key line, three external channels,
-- mixed into the sigma-delta pin. This is the whole speaker path of LAYOUT.

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 32)                    -- sidetone phase inc
  -> Signal System Bool                             -- key line (sidetone gate)
  -> Signal System (Vec 3 (Signed 12))              -- synth/theremin/harp channels
  -> Signal System (Vec 4 (Unsigned 3))             -- gains
  -> Signal System Bool                             -- digital mute
  -> Signal System Bit                              -- to RC lowpass -> amp
topEntity = exposeClockResetEnable $ \inc key chans gains mute_ ->
  let side = (\k s -> if k then s else 0) <$> key <*> nco inc
      mixed = mixer4 <$> ((:>) <$> side <*> chans) <*> gains <*> mute_
  in sdDac (toDacCode <$> mixed)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_audio"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "sidetone_inc", PortName "key_line"
                 , PortName "ch_in", PortName "gains", PortName "mute" ]
    , t_output = PortName "dac_out"
    }) #-}
