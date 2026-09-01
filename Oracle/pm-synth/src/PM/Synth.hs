{-# LANGUAGE RecordWildCards #-}
-- PM.Synth — the VL-1 voice core (P2 of PLAN.md; eforth-pm.md 0x402E).
--
--   * noteInc  : semitone -> 32-bit NCO phase increment at 25 MHz. One
--                octave of constants (C8 octave, computed at compile time),
--                shifted right per octave — exact octaves by construction,
--                equal temperament within the table's rounding (<0.1 cent).
--   * pulseOsc : the VL-1 character: an 8-step pattern ROM (10 patterns:
--                voices + rhythm timbres) walked by the phase MSBs.
--                Pattern 0 = square. Output +/- full scale.
--   * adssr    : the VL-1 5-segment envelope — Attack, Decay, Sustain1,
--                Slope (drift to Sustain2), Release — one 8-bit level,
--                per-segment rates as tick periods (bigger = slower).
--   * voice    : pulseOsc * adssr / 256 -> Signed 12 sample.
module PM.Synth where

import Clash.Prelude
import qualified Prelude

-- ---------------------------------------------------------------------------
-- Note table: phase increments for octave 8 (C8..B8) at 25 MHz, 2^32 phase.
-- inc = f * 2^32 / 25e6; C8 = 4186.009 Hz. Lower octaves shift right.

octave8Inc :: Vec 12 (Unsigned 32)
octave8Inc = $(listToVecTH
  [ fromInteger (round (f * 4294967296.0 / 25.0e6)) :: Unsigned 32
  | i <- [0 :: Int .. 11]
  , let f = 4186.0090448064 * (2.0 Prelude.** (Prelude.fromIntegral i / 12.0)) :: Prelude.Double
  ])

-- semitone 0 = C1 .. semitone 83 = B7 (7 octaves of range, C1..B7)
noteInc :: Unsigned 7 -> Unsigned 32
noteInc n =
  let (oct, semi) = n `divMod` 12          -- oct 0 -> C1's octave
      base = octave8Inc !! (unpack (resize (pack semi)) :: Index 12)
  in shiftR base (7 - fromIntegral oct)    -- oct 0 = C8 >> 7 = C1

-- ---------------------------------------------------------------------------
-- Pulse-pattern oscillator: 10 patterns x 8 steps, walked by phase bits.

patterns :: Vec 10 (BitVector 8)
patterns =
     0b11110000   -- 0 square        (piano-ish base)
  :> 0b11000000   -- 1 narrow 25%    (fantasy)
  :> 0b10000000   -- 2 thin 12.5%    (violin edge)
  :> 0b11111100   -- 3 wide 75%      (flute-ish)
  :> 0b10100000   -- 4 double pulse  (guitar)
  :> 0b11001100   -- 5 half-rate square
  :> 0b10101010   -- 6 octave-up square
  :> 0b11100100   -- 7 stair
  :> 0b10010000   -- 8 sparse
  :> 0b11011000   -- 9 syncopated
  :> Nil

pulseOsc :: Index 10 -> Unsigned 32 -> Signed 12
pulseOsc pat phase =
  let step = unpack (slice d31 d29 phase) :: Index 8
      hi = testBit (patterns !! pat) (7 - fromIntegral step)
  in if hi then 2047 else -2047

-- ---------------------------------------------------------------------------
-- ADSSR envelope.

data Seg = SegIdle | SegA | SegD | SegS1 | SegSl | SegR
  deriving (Generic, NFDataX, Eq, Show)

data Env = Env
  { eSeg :: !Seg
  , eLvl :: !(Unsigned 8)
  , eCnt :: !(Unsigned 16)
  } deriving (Generic, NFDataX)

data EnvCfg = EnvCfg
  { rA, rD, rSl, rR :: Unsigned 16   -- ticks per level step in each moving segment
  , lS1, lS2        :: Unsigned 8    -- sustain-1 target, slope target (sustain-2)
  , tS1             :: Unsigned 16   -- ticks to hold sustain-1 before the slope
  } deriving (Generic, NFDataX)

adssrT :: Env -> (EnvCfg, Bool) -> (Env, Unsigned 8)
adssrT e@Env{..} (EnvCfg{..}, gate)
  | not gate, eSeg /= SegIdle, eSeg /= SegR
  = (e { eSeg = SegR, eCnt = rR }, eLvl)                    -- key up: release
  | otherwise = case eSeg of
      SegIdle | gate -> (Env SegA 0 rA, 0)
              | otherwise -> (e, 0)
      SegA | eCnt /= 0 -> (e { eCnt = eCnt - 1 }, eLvl)
           | eLvl == maxBound -> (e { eSeg = SegD, eCnt = rD }, eLvl)
           | otherwise -> (e { eLvl = eLvl + 1, eCnt = rA }, eLvl)
      SegD | eCnt /= 0 -> (e { eCnt = eCnt - 1 }, eLvl)
           | eLvl <= lS1 -> (e { eSeg = SegS1, eCnt = tS1 }, eLvl)
           | otherwise -> (e { eLvl = eLvl - 1, eCnt = rD }, eLvl)
      SegS1 | eCnt /= 0 -> (e { eCnt = eCnt - 1 }, eLvl)
            | otherwise -> (e { eSeg = SegSl, eCnt = rSl }, eLvl)
      SegSl | eCnt /= 0 -> (e { eCnt = eCnt - 1 }, eLvl)
            | eLvl == lS2 -> (e, eLvl)                       -- hold sustain-2
            | eLvl > lS2 -> (e { eLvl = eLvl - 1, eCnt = rSl }, eLvl)
            | otherwise -> (e { eLvl = eLvl + 1, eCnt = rSl }, eLvl)
      SegR | eCnt /= 0 -> (e { eCnt = eCnt - 1 }, eLvl)
           | eLvl == 0 -> (e { eSeg = SegIdle }, 0)
           | otherwise -> (e { eLvl = eLvl - 1, eCnt = rR }, eLvl)

adssr
  :: HiddenClockResetEnable dom
  => Signal dom EnvCfg -> Signal dom Bool -> Signal dom (Unsigned 8)
adssr cfg gate = mealy adssrT (Env SegIdle 0 0) (bundle (cfg, gate))

-- ---------------------------------------------------------------------------
-- One voice: note + pattern + envelope -> sample.

voice
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 7)      -- semitone (C1=0 .. B7=83)
  -> Signal dom (Index 10)        -- pattern select
  -> Signal dom EnvCfg
  -> Signal dom Bool              -- gate
  -> Signal dom (Signed 12)
voice semi pat cfg gate = out
 where
  phase = register 0 (phase + (noteInc <$> semi))
  raw   = pulseOsc <$> pat <*> phase
  env   = adssr cfg gate
  out   = scale <$> raw <*> env
  scale :: Signed 12 -> Unsigned 8 -> Signed 12
  scale s l = resize (shiftR (resize s * fromIntegral l :: Signed 21) 8)

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 7)
  -> Signal System (Index 10)
  -> Signal System EnvCfg
  -> Signal System Bool
  -> Signal System (Signed 12)
topEntity = exposeClockResetEnable voice
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_voice"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "semitone", PortName "pattern"
                 , PortName "env_cfg", PortName "gate" ]
    , t_output = PortName "sample"
    }) #-}
