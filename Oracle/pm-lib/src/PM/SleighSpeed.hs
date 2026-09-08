-- PM.SleighSpeed — the theremin drives Santa's sleigh (Coil letter, SS-005).
--
-- Pitch raises/lowers the sleigh's speed; killing the volume stops it. The
-- volume antenna is thereby a DEAD-MAN switch for the coil driver: hand off
-- the volume antenna => speed 0 => the Cu parks Santa at Hold duty.
--
--   pitch, vol : numeric antenna values from the theremin DSP
--                (Theremin/SensorTop; higher pitch value = higher tone)
--   speed      : 0 when vol < scVolTh (dead-man), else
--                clamp [1..255] of (pitch - scPitchMin) >> scShift
--                -- minimum 1 so "any audible pitch" = visible motion
--   wire       : 250 kbaud 8N1 frames (0xA5, speed), one frame every
--                scFrameIv ticks (hw: 20 ms => 50 Hz update; the Cu side
--                fail-safes to 0 after 250 ms without a valid frame)
--
-- The UART is PM.HarpLink's uartTx (same library block as the harp link);
-- at the ULX3S 25 MHz clock, divisor 100 = 250 kbaud. The Cu receives at
-- divisor 200 from its 50 MHz clock — same baud, checked in the spec.

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.SleighSpeed where

import Clash.Prelude
import PM.HarpLink (uartTx)
import PM.Ulx25 (Ulx25)

data SleighCfg = SleighCfg
  { scPitchMin :: Unsigned 16   -- pitch at/below this maps to speed 1
  , scShift    :: Unsigned 4    -- speed = (pitch - min) >> shift
  , scVolTh    :: Unsigned 16   -- vol below this = dead-man stop
  , scFrameIv  :: Unsigned 24   -- ticks between frames
  , scDiv      :: Unsigned 8    -- uartTx divisor (ticks per bit)
  } deriving (Generic, NFDataX)

-- | Hardware config @ 25 MHz: 250 kbaud, 50 frames/s. Pitch window and
--   volume threshold are Gate-1 placeholders — tune at the antennas.
hwSleighCfg :: SleighCfg
hwSleighCfg = SleighCfg 2000 5 300 500_000 100

-- | The mapping, combinational and total.
speedOf :: SleighCfg -> Unsigned 16 -> Unsigned 16 -> Unsigned 8
speedOf SleighCfg{..} pitch vol
  | vol < scVolTh = 0                              -- dead-man
  | otherwise     = resize (max 1 (min 255 stepped))
  where
    stepped = satSub SatBound pitch scPitchMin `shiftR` fromIntegral scShift

-- | 2-byte frame pacer: every scFrameIv ticks, push 0xA5 then the speed
--   sampled AT THE SYNC BYTE (both bytes of a frame are coherent).
data FSt = FSt
  { fTimer :: !(Unsigned 24)
  , fStage :: !(Unsigned 3)     -- 0 idle · 1 sync · 2 sync-busy · 3 speed · 4 speed-busy
  , fHeld  :: !(Unsigned 8)     -- speed latched at the sync byte
  } deriving (Generic, NFDataX)

-- Between the two bytes the framer must SEE the transmitter go busy
-- (stages 2/4): with a registered ready, emitting on stale-True ready
-- offers the second byte to a busy uartTx, which drops it.
framerT :: FSt -> (Bool, Unsigned 8, Unsigned 24)
        -> (FSt, Maybe (BitVector 8))
framerT s@FSt{..} (ready, spd, iv) = case fStage of
  0 | fTimer == 0 -> (s { fStage = 1, fTimer = iv }, Nothing)
    | otherwise   -> (s { fTimer = fTimer - 1 }, Nothing)
  1 | ready       -> (s { fStage = 2, fHeld = spd }, Just 0xA5)
    | otherwise   -> (s, Nothing)
  2 | not ready   -> (s { fStage = 3 }, Nothing)
    | otherwise   -> (s, Nothing)
  3 | ready       -> (s { fStage = 4 }, Just (pack fHeld))
    | otherwise   -> (s, Nothing)
  _ | not ready   -> (s { fStage = 0 }, Nothing)
    | otherwise   -> (s, Nothing)

-- | pitch + volume in, serial line out.
sleighSpeed
  :: HiddenClockResetEnable dom
  => SleighCfg
  -> Signal dom (Unsigned 16)     -- ^ pitch value
  -> Signal dom (Unsigned 16)     -- ^ volume value
  -> Signal dom Bit               -- ^ UART line to the Cu
sleighSpeed cfg pitch vol = line
 where
  spd = speedOf cfg <$> pitch <*> vol
  mb = mealy framerT (FSt (scFrameIv cfg) 0 0)
              (bundle (readyR, spd, pure (scFrameIv cfg)))
  (line, ready) = unbundle (uartTx (pure (scDiv cfg)) mbR)
  -- register both directions of the handshake: no combinational loop, and
  -- uartTx's ready is stable by the time the framer sees it
  readyR = register False ready
  mbR = register Nothing mb

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 (Unsigned 16)
  -> Signal Ulx25 (Unsigned 16)
  -> Signal Ulx25 Bit
topEntity clk rst en = withClockResetEnable clk rst en (sleighSpeed hwSleighCfg)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_sleigh_speed"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "pitch", PortName "vol" ]
    , t_output = PortName "sleigh_tx"
    }) #-}
