-- PM.HarpLink — the Erand49 event link (HANDOFF: "3 Mbaud 8-byte event
-- frames"; eforth-pm.md 0x4036 oHarp; framing discipline per MAIDEN
-- recorder PROTOCOL.md: sync byte + additive checksum, resync on the wire).
--
-- Frame (8 bytes): A5 | type | string# | velHi | velLo | angle | seq | cksum
--   cksum = low byte of the sum of bytes 0..6. type: 01 pluck, 02 damp,
--   03 cal, 04 heartbeat. string# 0..48, angle = pluck-vector angle / 256.
--
--   * uartTx / uartRx : 8N1 at a programmable divisor (25 MHz / 3 M ~ 8.33:
--                       divisor 8 gives 3.125 Mbaud, within UART tolerance;
--                       the divisor is a port so the bench can pick).
--   * frameTx         : Maybe Frame -> serial line (busy handshake).
--   * frameRx         : serial line -> Maybe Frame, checksum-checked,
--                       resynchronizes on A5 after corruption.
module PM.HarpLink where

import Clash.Prelude

type Byte = BitVector 8

data HFrame = HFrame
  { hType :: !Byte, hString :: !Byte, hVelHi :: !Byte
  , hVelLo :: !Byte, hAngle :: !Byte, hSeq :: !Byte
  } deriving (Generic, NFDataX, Eq, Show)

frameBytes :: HFrame -> Vec 8 Byte
frameBytes HFrame{..} = bs :< cks
 where
  bs = 0xA5 :> hType :> hString :> hVelHi :> hVelLo :> hAngle :> hSeq :> Nil
  cks = foldl (+) 0 bs

parseFrame :: Vec 8 Byte -> Maybe HFrame
parseFrame v =
  let (bs, cks) = (init v, last v)
  in if head bs == 0xA5 && foldl (+) 0 bs == cks
       then Just (HFrame (bs !! (1 :: Index 7)) (bs !! (2 :: Index 7))
                         (bs !! (3 :: Index 7)) (bs !! (4 :: Index 7))
                         (bs !! (5 :: Index 7)) (bs !! (6 :: Index 7)))
       else Nothing

-- ---------------------------------------------------------------------------
-- 8N1 UART, programmable divisor (ticks per bit).

data TxSt = TxSt { tActive :: !Bool, tSh :: !(BitVector 10)
                 , tBit :: !(Unsigned 4), tCnt :: !(Unsigned 8) }
  deriving (Generic, NFDataX)

uartTxT :: TxSt -> (Unsigned 8, Maybe Byte) -> (TxSt, (Bit, Bool))
uartTxT s@TxSt{..} (dv, mb)
  | not tActive = case mb of
      Just b -> (TxSt True (pack (1 :: Bit) ++# b ++# pack (0 :: Bit)) 10 (dv - 1), (1, False))
      Nothing -> (s, (1, True))
  | tCnt /= 0 = (s { tCnt = tCnt - 1 }, (lsb', False))
  | tBit == 1 = (s { tActive = False }, (lsb', False))
  | otherwise = (s { tSh = shiftR tSh 1, tBit = tBit - 1, tCnt = dv - 1 }, (lsb', False))
 where lsb' = lsb tSh

uartTx :: HiddenClockResetEnable dom
       => Signal dom (Unsigned 8) -> Signal dom (Maybe Byte)
       -> Signal dom (Bit, Bool)                 -- (line, ready)
uartTx dv mb = mealy uartTxT (TxSt False maxBound 0 0) (bundle (dv, mb))

data RxSt = RxSt { rActive :: !Bool, rIdle :: !Bool, rSh :: !(BitVector 8)
                 , rBit :: !(Unsigned 4), rCnt :: !(Unsigned 8) }
  deriving (Generic, NFDataX)

-- Framing-robust: a start bit is only accepted after idle (line high) has
-- been seen, and the stop bit is verified — a byte with a low stop bit is a
-- framing error and is dropped. Combined with the transmitter's inter-frame
-- gap this bounds desync to the corrupted frame.
-- Explicit timing: on the start edge wait 1.5 bit periods (lands mid-data0),
-- sample 8 data bits LSB-first every bit period, then one more period to
-- mid-stop and verify the stop bit before emitting.
uartRxT :: RxSt -> (Unsigned 8, Bit) -> (RxSt, Maybe Byte)
uartRxT s@RxSt{..} (dv, l)
  | not rActive
  = if l == 1 then (s { rIdle = True }, Nothing)
    else if rIdle
      then (RxSt True False 0 8 (dv + (dv `shiftR` 1) - 1), Nothing)
      else (s, Nothing)
  | rCnt /= 0 = (s { rCnt = rCnt - 1 }, Nothing)
  | rBit /= 0
  = ( s { rSh = pack l ++# slice d7 d1 rSh, rBit = rBit - 1, rCnt = dv - 1 }
    , Nothing )
  | otherwise
  = ( s { rActive = False }
    , if l == 1 then Just rSh else Nothing )     -- true stop-bit check


uartRx :: HiddenClockResetEnable dom
       => Signal dom (Unsigned 8) -> Signal dom Bit -> Signal dom (Maybe Byte)
uartRx dv l = mealy uartRxT (RxSt False False 0 0 0) (bundle (dv, l))

-- ---------------------------------------------------------------------------
-- Frame layer.

data FtxSt = FtxSt { fBuf :: !(Vec 8 Byte), fLeft :: !(Index 9)
                   , fGap :: !(Unsigned 12) }
  deriving (Generic, NFDataX)

-- After each frame the line is held idle for ~1.5 byte times: the receiver's
-- resync window (see uartRxT).
frameTxT :: FtxSt -> (Maybe HFrame, Bool, Unsigned 8) -> (FtxSt, (Maybe Byte, Bool))
frameTxT s@FtxSt{..} (mf, txReady, dv)
  | fLeft /= 0, txReady
  = (s { fBuf = fBuf <<+ 0, fLeft = fLeft - 1
       , fGap = if fLeft == 1 then 15 * resize dv else fGap }
    , (Just (head fBuf), False))
  | fLeft /= 0 = (s, (Nothing, False))
  | fGap /= 0 = (s { fGap = fGap - 1 }, (Nothing, False))
  | Just f <- mf = (FtxSt (frameBytes f) 8 0, (Nothing, False))
  | otherwise = (s, (Nothing, True))

frameTx :: HiddenClockResetEnable dom
        => Signal dom (Unsigned 8) -> Signal dom (Maybe HFrame)
        -> Signal dom (Bit, Bool)                -- (line, frame-ready)
frameTx dv mf = bundle (line, fready)
 where
  (mb, fready) = unbundle (mealy frameTxT (FtxSt (repeat 0) 0 0) (bundle (mf, txReady, dv)))
  (line, txReady) = unbundle (uartTx dv mbR)
  mbR = register Nothing mb    -- break the ready feedback loop

data FrxSt = FrxSt { gBuf :: !(Vec 8 Byte), gGot :: !(Index 9) }
  deriving (Generic, NFDataX)

frameRxT :: FrxSt -> Maybe Byte -> (FrxSt, Maybe HFrame)
frameRxT s Nothing = (s, Nothing)
frameRxT s@FrxSt{..} (Just b)
  | gGot == 0, b /= 0xA5 = (s, Nothing)            -- hunt for sync
  | otherwise =
      let buf' = gBuf <<+ b
          got' = gGot + 1
      in if got' == 8
           then case parseFrame buf' of
                  Just f  -> (FrxSt (repeat 0) 0, Just f)
                  Nothing ->
                    -- bad checksum: drop the oldest, re-hunt from within
                    (FrxSt (repeat 0) 0, Nothing)
           else (s { gBuf = buf', gGot = got' }, Nothing)

frameRx :: HiddenClockResetEnable dom
        => Signal dom (Unsigned 8) -> Signal dom Bit -> Signal dom (Maybe HFrame)
frameRx dv l = mealy frameRxT (FrxSt (repeat 0) 0) (uartRx dv l)

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 8)
  -> Signal System (Maybe HFrame)
  -> Signal System Bit
  -> Signal System ((Bit, Bool), Maybe HFrame)
topEntity = exposeClockResetEnable $ \dv mf rxl ->
  bundle (frameTx dv mf, frameRx dv rxl)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_harplink"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "divisor", PortName "tx_frame", PortName "rx_line" ]
    , t_output = PortName "out"
    }) #-}
