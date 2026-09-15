{-# LANGUAGE RecordWildCards #-}
-- PM.Rhythm — the VL-1 auto-rhythm: pattern ROM, step sequencer, percussion.
--
--   * bassRom/snareRom/hatRom : 10 patterns x 16 steps (16ths of one 4/4
--                bar; WALTZ uses 12 of the 16), bit 15 = step 0. Patterns:
--                0 MARCH 1 WALTZ 2 4-BEAT 3 SWING 4 ROCK-1 5 ROCK-2
--                6 BOSSA 7 SAMBA 8 RHUMBA 9 BEGUINE.
--   * rhythmStep : (pattern, step) -> BitVector 3 = bass:snare:hat.
--   * stepSeq    : 16-step counter advanced by the tempo tick, held at 0
--                  while not running.
--   * rhythmTrig : one-cycle trigger pulses (bass:snare:hat) on each tick
--                  for the current step.
--   * lfsrStep   : 16-bit maximal-length Fibonacci LFSR (x^16+x^14+x^13+x^11+1),
--                  period 65535.
--   * percEnv    : 8-bit decaying envelope: 255 on trigger, -1 every
--                  (rate+1) cycles down to 0.
--   * noiseVoice : LFSR noise burst * percEnv (snare, hat).
--   * bassVoice  : low square (16-bit NCO) * percEnv (bass drum).
--   * rhythmUnit : sequencer + three voices, mixed bass/2+snare/4+hat/4
--                  into a Signed 12 that cannot exceed full scale.
module PM.Rhythm where

import Clash.Prelude

-- ---------------------------------------------------------------------------
-- Pattern ROM.

bassRom, snareRom, hatRom :: Vec 10 (BitVector 16)
bassRom =
     0b1000_0000_1000_0000  -- MARCH
  :> 0b1000_0000_0000_0000  -- WALTZ
  :> 0b1000_1000_1000_1000  -- 4-BEAT
  :> 0b1000_0000_1000_0000  -- SWING
  :> 0b1000_0010_1000_0000  -- ROCK-1
  :> 0b1000_0010_0010_0000  -- ROCK-2
  :> 0b1001_0010_1001_0010  -- BOSSA
  :> 0b1001_1001_1001_1001  -- SAMBA
  :> 0b1000_0010_0010_0000  -- RHUMBA
  :> 0b1000_0001_0010_0000  -- BEGUINE
  :> Nil
snareRom =
     0b0000_1000_0000_1010
  :> 0b0000_1000_1000_0000
  :> 0b0000_1000_0000_1000
  :> 0b0000_1000_0000_1001
  :> 0b0000_1000_0000_1000
  :> 0b0000_1000_0000_1000
  :> 0b1001_0010_0010_0100
  :> 0b0010_0100_1010_0010
  :> 0b0010_0100_1000_1000
  :> 0b0001_0010_0100_1000
  :> Nil
hatRom =
     0b1010_1010_1010_1010
  :> 0b1000_1000_1000_0000
  :> 0b1010_1010_1010_1010
  :> 0b1001_1001_1001_1001
  :> 0b1010_1010_1010_1010
  :> 0b1111_1111_1111_1111
  :> 0b1010_1010_1010_1010
  :> 0b1011_1011_1011_1011
  :> 0b1010_1010_1010_1010
  :> 0b1010_1010_1010_1010
  :> Nil

romBit :: Vec 10 (BitVector 16) -> Index 10 -> Index 16 -> Bit
romBit tbl p s = (tbl !! p) ! (15 - fromIntegral s :: Int)

rhythmStep :: Index 10 -> Index 16 -> BitVector 3
rhythmStep p s = pack (romBit bassRom p s) ++# pack (romBit snareRom p s) ++# pack (romBit hatRom p s)

-- ---------------------------------------------------------------------------
-- Step sequencer and triggers.

stepSeqT :: Index 16 -> (Bool, Bool) -> (Index 16, Index 16)
stepSeqT s (tick, running)
  | not running = (0, s)
  | tick        = (satSucc SatWrap s, s)
  | otherwise   = (s, s)

stepSeq
  :: HiddenClockResetEnable dom
  => Signal dom Bool -> Signal dom Bool -> Signal dom (Index 16)
stepSeq tick running = mealy stepSeqT 0 (bundle (tick, running))

rhythmTrig
  :: HiddenClockResetEnable dom
  => Signal dom (Index 10) -> Signal dom Bool -> Signal dom Bool
  -> Signal dom (BitVector 3)
rhythmTrig pat tick running = gate <$> tick <*> running <*> (rhythmStep <$> pat <*> stepSeq tick running)
 where gate t r b = if t && r then b else 0

-- ---------------------------------------------------------------------------
-- Noise source.

lfsrStep :: BitVector 16 -> BitVector 16
lfsrStep v =
  let fb = v ! (15 :: Int) `xor` v ! (13 :: Int) `xor` v ! (12 :: Int) `xor` v ! (10 :: Int)
  in shiftL v 1 .|. resize (pack fb)

lfsr :: HiddenClockResetEnable dom => Signal dom (BitVector 16)
lfsr = r where r = register 0xACE1 (lfsrStep <$> r)

-- ---------------------------------------------------------------------------
-- Percussion envelope and voices.

data Perc = Perc { pEnv :: !(Unsigned 8), pCnt :: !(Unsigned 16) }
  deriving (Generic, NFDataX)

percEnvT :: Perc -> (Bool, Unsigned 16) -> (Perc, Unsigned 8)
percEnvT p@Perc{..} (trig, rate)
  | trig         = (Perc 255 0, pEnv)
  | pEnv == 0    = (p, 0)
  | pCnt == rate = (Perc (pEnv - 1) 0, pEnv)
  | otherwise    = (p { pCnt = pCnt + 1 }, pEnv)

percEnv
  :: HiddenClockResetEnable dom
  => Signal dom Bool -> Signal dom (Unsigned 16) -> Signal dom (Unsigned 8)
percEnv trig rate = mealy percEnvT (Perc 0 0) (bundle (trig, rate))

-- +/- env*8: at most +/-2040.
polar :: Bool -> Unsigned 8 -> Signed 12
polar hi e = let v = shiftL (fromIntegral e :: Signed 12) 3 in if hi then v else negate v

noiseVoice
  :: HiddenClockResetEnable dom
  => Signal dom Bool -> Signal dom (Unsigned 16) -> Signal dom (Signed 12)
noiseVoice trig rate = polar <$> (msb' <$> lfsr) <*> percEnv trig rate
 where msb' v = msb v == 1

bassVoice
  :: HiddenClockResetEnable dom
  => Signal dom Bool -> Signal dom (Unsigned 16) -> Signal dom (Unsigned 16)
  -> Signal dom (Signed 12)
bassVoice trig rate inc = polar <$> (msb' <$> phase) <*> percEnv trig rate
 where
  phase = register (0 :: Unsigned 16) (phase + inc)
  msb' v = msb v == 1

-- ---------------------------------------------------------------------------
-- Whole rhythm unit.

data PercCfg = PercCfg
  { rBass, rSnare, rHat :: Unsigned 16   -- envelope decay: cycles per step - 1
  , iBass               :: Unsigned 16   -- bass NCO increment (16-bit phase)
  } deriving (Generic, NFDataX)

-- 25 MHz defaults: bass ~100 ms, snare ~150 ms, hat ~40 ms, bass tone ~60 Hz.
defaultPerc :: PercCfg
defaultPerc = PercCfg { rBass = 9800, rSnare = 14700, rHat = 3900, iBass = 157 }

mix3 :: Signed 12 -> Signed 12 -> Signed 12 -> Signed 12
mix3 b s h = shiftR b 1 + shiftR s 2 + shiftR h 2

rhythmUnit
  :: HiddenClockResetEnable dom
  => Signal dom (Index 10)    -- pattern
  -> Signal dom PercCfg
  -> Signal dom Bool          -- tempo tick
  -> Signal dom Bool          -- running
  -> (Signal dom (Index 16), Signal dom (Signed 12))
rhythmUnit pat cfg tick running = (stepSeq tick running, mix3 <$> b <*> s <*> h)
 where
  trig = rhythmTrig pat tick running
  bit' i v = v ! (i :: Int) == 1
  b = bassVoice  (bit' 2 <$> trig) (rBass  <$> cfg) (iBass <$> cfg)
  s = noiseVoice (bit' 1 <$> trig) (rSnare <$> cfg)
  h = noiseVoice (bit' 0 <$> trig) (rHat   <$> cfg)

-- | Synthesis root (area/Fmax measurement).
topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Index 10) -> Signal System PercCfg -> Signal System Bool -> Signal System Bool
  -> (Signal System (Index 16), Signal System (Signed 12))
topEntity = exposeClockResetEnable rhythmUnit
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_rhythm"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "pattern", PortName "cfg", PortName "tick", PortName "running" ]
    , t_output = PortProduct "" [ PortName "step", PortName "sample" ]
    }) #-}
