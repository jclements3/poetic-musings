{-# LANGUAGE RecordWildCards #-}
-- PM.I2s — I²S master transmitter and receiver (24-bit samples in 32-bit
-- slots, stereo, 64 sck per frame). Standard I²S timing: MSB first, data
-- one sck after the ws transition, ws low = left.
--
--   * i2sTx   : master. sck is derived from the system clock by a runtime
--               half-period divider (sck = fclk / (2*div)); for a 96 kHz frame
--               sck = 6.144 MHz. ws and sd change on the sck falling edge.
--               The (L,R) input is latched at frame start (frameStart pulse).
--   * i2sRx   : samples ws/sd on the sck rising edge (own edge detector, so
--               it also works as a slave against an external sck). Emits
--               Just (L,R) one sck after the right slot ends. It waits for a
--               ws transition before shifting, so a mid-frame start yields no
--               garbage frame: the partial frame is dropped, the next is right.
--   * i2sLoop : tx wired to rx for simulation.
module PM.I2s where

import Clash.Prelude
import qualified Prelude as P

type Sample = Signed 24

-- ---------------------------------------------------------------------------
-- Transmitter.

data TxS = TxS
  { tSck  :: !Bit
  , tCnt  :: !(Unsigned 8)     -- half-period counter
  , tPos  :: !(Index 64)       -- bit position within the frame
  , tWord :: !(BitVector 64)   -- the frame being shifted out, MSB first
  } deriving (Generic, NFDataX)

-- 64-bit frame: [pad1][L 24][pad7][pad1][R 24][pad7]; the leading pad is the
-- one-sck delay after the ws transition.
frameWord :: Sample -> Sample -> BitVector 64
frameWord l r = slot l ++# slot r
 where
  slot :: Sample -> BitVector 32
  slot s = (0 :: BitVector 1) ++# pack s ++# (0 :: BitVector 7)

txT :: TxS -> (Unsigned 8, (Sample, Sample)) -> (TxS, (Bit, Bit, Bit, Bool))
txT TxS{..} (dv, (l, r)) =
  let half  = if dv == 0 then 1 else dv
      tick  = tCnt + 1 >= half
      cnt'  = if tick then 0 else tCnt + 1
      fall  = tick && tSck == 1
      sck'  = if tick then complement tSck else tSck
      wrap  = fall && tPos == maxBound
      pos'  | not fall  = tPos
            | wrap      = 0
            | otherwise = tPos + 1
      word' = if wrap then frameWord l r else tWord
      ws    = if tPos >= 32 then 1 else 0
      sd    = (unpack tWord :: Vec 64 Bit) !! tPos
  in (TxS sck' cnt' pos' word', (tSck, ws, sd, wrap))

i2sTx
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 8)               -- sck half-period in system clocks
  -> Signal dom (Sample, Sample)           -- (L,R), latched at frame start
  -> Signal dom (Bit, Bit, Bit, Bool)      -- (sck, ws, sd, frameStart)
i2sTx dv smp = mealy txT (TxS 0 0 0 0) (bundle (dv, smp))

-- ---------------------------------------------------------------------------
-- Receiver.

data RxS = RxS
  { rSck    :: !Bit
  , rWs     :: !Bit
  , rSynced :: !Bool           -- seen a ws transition
  , rHaveL  :: !Bool           -- left slot captured since sync
  , rN      :: !(Index 25)     -- bits shifted in this slot
  , rSh     :: !(BitVector 24)
  , rL      :: !Sample
  } deriving (Generic, NFDataX)

rxT :: RxS -> (Bit, Bit, Bit) -> (RxS, Maybe (Sample, Sample))
rxT RxS{..} (sck, ws, sd) =
  let rise    = sck == 1 && rSck == 0
      change  = rise && ws /= rWs
      shiftIn = rise && not change && rSynced && rN < 24
      sh'   | change  = 0
            | shiftIn = (rSh `shiftL` 1) .|. zeroExtend (pack sd)
            | otherwise = rSh
      n'    | change  = 0
            | shiftIn = rN + 1
            | otherwise = rN
      leftEnd  = change && ws == 1 && rSynced
      rightEnd = change && ws == 0 && rSynced
      l'    = if leftEnd then unpack rSh else rL
      out   = if rightEnd && rHaveL then Just (rL, unpack rSh) else Nothing
      haveL' | leftEnd  = True
             | rightEnd = False
             | otherwise = rHaveL
      s' = RxS sck (if rise then ws else rWs) (rSynced || change) haveL' n' sh' l'
  in (s', out)

i2sRx
  :: HiddenClockResetEnable dom
  => Signal dom Bit -> Signal dom Bit -> Signal dom Bit   -- sck, ws, sd
  -> Signal dom (Maybe (Sample, Sample))                   -- one-cycle pulse
i2sRx sck ws sd = mealy rxT (RxS 0 0 False False 0 0 0) (bundle (sck, ws, sd))

-- ---------------------------------------------------------------------------
-- Loop: tx -> rx, for simulation.

i2sLoop
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 8)
  -> Signal dom (Sample, Sample)
  -> (Signal dom Bool, Signal dom (Maybe (Sample, Sample)))  -- (frameStart, rx out)
i2sLoop dv smp =
  let (sck, ws, sd, fs) = unbundle (i2sTx dv smp)
  in (fs, i2sRx sck ws sd)

-- ---------------------------------------------------------------------------
-- Top: master tx + rx on the same sck (codec DAC out, ADC in).

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 8)               -- sck half-period divider
  -> Signal System (Sample, Sample)           -- to codec
  -> Signal System Bit                        -- sd from codec
  -> Signal System (Bit, Bit, Bit, Bool, Maybe (Sample, Sample))
                                               -- sck, ws, sd out, frameStart, rx
topEntity = exposeClockResetEnable $ \dv smp sdIn ->
  let (sck, ws, sd, fs) = unbundle (i2sTx dv smp)
  in bundle (sck, ws, sd, fs, i2sRx sck ws sdIn)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_i2s"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "sck_div", PortName "tx_sample", PortName "sd_in" ]
    , t_output = PortProduct "" [ PortName "sck", PortName "ws", PortName "sd_out"
                                , PortName "frame_start", PortName "rx_sample" ]
    }) #-}

-- unused-import guard for the qualified Prelude (kept for convention)
_pm_i2s_prelude :: P.Int
_pm_i2s_prelude = 0
