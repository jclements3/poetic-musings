{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
-- PM.UdpTx — letter-N variable-length UDP/IPv4/Ethernet transmitter on RMII:
-- the datagram byte stream from PM.Records (DgByte: data + first/last flags,
-- <= 1400 bytes per datagram) goes out as one Ethernet frame per datagram.
-- This is the "real" TX that PM.Records.beaconGoAdapter was standing in for;
-- PM.Net.beaconTx keeps its fixed 16-byte beacon.
--
--     Test:     cabal test udptx-test --test-show-details=direct
--     Verilog:  cabal run clash -- -isrc PM.UdpTx --verilog
--
-- Buffering: the IP total length and UDP length sit in the headers, ahead of
-- the payload, and dbLast is only known at the END of a datagram, so a
-- datagram is buffered whole before its frame starts.  Two 2048-byte banks in
-- one 4096 x 8 blockRam double-buffer it: the packer fills bank w (one byte
-- per clock, no handshake — it cannot be stalled) while bank r drains onto
-- the wire (one byte per 4 clocks).  A datagram whose first byte arrives
-- while both banks are full is dropped WHOLE and counted in `utDrops`
-- (never-drop-silently); `utRoom` tells the caller whether a new datagram
-- would be accepted.
--
-- Headers come from the UdpCfg register block (src/dst MAC, src/dst IP,
-- ports), sampled once at the start of each frame:
--
--     0..7     preamble 7x55 + SFD D5             (not covered by FCS)
--     8..21    Ethernet: dst, src, type 0800
--     22..41   IPv4: 45 00, total 28+L, ID 0, DF, TTL 64, proto 17,
--              header checksum, src, dst      (checksum: PM.Net.ipChecksum)
--     42..49   UDP: src port, dst port, len 8+L, checksum
--     50..     payload L bytes (the datagram: 16-bit seq + records)
--     ..67     zero pad while 50+L < 68 (Ethernet 46-byte minimum payload)
--     +4       FCS, CRC-32 over bytes 8..end-of-pad (PM.Net.crc32Dibit)
--
-- UDP checksum IS computed (RFC 768): while a datagram fills, the one's-
-- complement sum of its big-endian 16-bit words accumulates in a 32-bit
-- register (an odd trailing byte pads with 0 as the low byte); at frame
-- start the pseudo-header (src IP, dst IP, 0x0011, UDP length), the UDP
-- header words and the folded payload sum go through the same ipChecksum
-- fold, and an all-zero result is sent as 0xFFFF (0 means "no checksum").
-- IP ID stays 0 with DF set (RFC 6864: ID is meaningless for atomic
-- datagrams), so the IP header is a function of L alone.
--
-- Wire timing: 4 clocks per byte at 50 MHz RMII (TXD0 the earlier bit, byte
-- LSB-first, exactly as PM.Net), then 48 clocks (96 bit times) of TX_EN low
-- before the next frame can start; the idle cycle that re-arms adds one
-- more.  Clock domain: the DgByte input and the RMII output are in the SAME
-- domain here (the record path runs at the RMII clock); a CDC FIFO in front
-- is the caller's problem if that ever changes.
module PM.UdpTx where

import Clash.Prelude
import PM.Net (Byte, Rmii50, pmSrcMac, crc32Init, crc32Dibit, ipChecksum)
import PM.Records (DgByte(..))

-- ---------------------------------------------------------------------------
-- Configuration register block.

data UdpCfg = UdpCfg
  { ucSrcMac  :: !(BitVector 48)    -- first octet in bits 47:40
  , ucDstMac  :: !(BitVector 48)
  , ucSrcIp   :: !(BitVector 32)    -- first octet in bits 31:24
  , ucDstIp   :: !(BitVector 32)
  , ucSrcPort :: !(BitVector 16)
  , ucDstPort :: !(BitVector 16)
  } deriving (Generic, NFDataX, Show, Eq)

-- The beacon's identity, limited broadcast, port 20557 ("PM") both ends.
defaultUdpCfg :: UdpCfg
defaultUdpCfg = UdpCfg
  { ucSrcMac = pack pmSrcMac, ucDstMac = 0xFFFF_FFFF_FFFF
  , ucSrcIp = 0x0A00_004D, ucDstIp = 0xFFFF_FFFF
  , ucSrcPort = 0x504D, ucDstPort = 0x504D }

-- ---------------------------------------------------------------------------
-- Header image (42 bytes) for a payload of `len` bytes whose big-endian
-- 16-bit-word sum is `paySum`.

type BufLen = Unsigned 11      -- payload length, <= 1400
type Pos    = Unsigned 12      -- byte position in the frame, max 50+1400+3

-- Two end-around carry folds bring a 32-bit one's-complement partial sum to 16 bits.
fold16 :: BitVector 32 -> BitVector 16
fold16 x = truncateB (f (f x))
 where f y = (y .&. 0xFFFF) + shiftR y 16

be16 :: BitVector 16 -> Vec 2 Byte
be16 w = slice d15 d8 w :> slice d7 d0 w :> Nil

udpHeader :: UdpCfg -> BufLen -> BitVector 32 -> Vec 42 Byte
udpHeader UdpCfg{..} len paySum =
     unpack ucDstMac ++ unpack ucSrcMac ++ (0x08 :> 0x00 :> Nil)
  ++ concatMap be16 ipWs ++ concatMap be16 udpWs
 where
  udpLen = 8 + zeroExtend (pack len) :: BitVector 16
  ipLen  = 20 + udpLen
  srcH = slice d31 d16 ucSrcIp; srcL = slice d15 d0 ucSrcIp
  dstH = slice d31 d16 ucDstIp; dstL = slice d15 d0 ucDstIp
  ipWs0 = 0x4500 :> ipLen  :> 0x0000 :> 0x4000   -- ver/IHL,TOS | total | ID 0 | DF
       :> 0x4011 :> 0x0000                        -- TTL 64, UDP | checksum slot
       :> srcH :> srcL :> dstH :> dstL :> Nil
  ipWs  = replace (5 :: Index 10) (ipChecksum ipWs0) ipWs0
  udpCk0 = ipChecksum (srcH :> srcL :> dstH :> dstL :> 0x0011 :> udpLen
                       :> ucSrcPort :> ucDstPort :> udpLen :> fold16 paySum :> Nil)
  udpCk = if udpCk0 == 0 then 0xFFFF else udpCk0
  udpWs = ucSrcPort :> ucDstPort :> udpLen :> udpCk :> Nil

-- ---------------------------------------------------------------------------
-- State: fill side (bank w) and transmit side (bank r).

data TPhase = TIdle | TSend | TIfg
  deriving (Generic, NFDataX, Eq, Show)

data USt = USt
  { wBank   :: !(Index 2)
  , wPos    :: !BufLen              -- next write offset in the filling bank
  , wActive :: !Bool                -- a datagram is being accepted
  , wSum    :: !(BitVector 32)      -- running payload word sum
  , bLen    :: !(Vec 2 BufLen)
  , bSum    :: !(Vec 2 (BitVector 32))
  , bFull   :: !(Vec 2 Bool)        -- bank holds a complete, unsent datagram
  , uDrops  :: !(Unsigned 16)
  , uSent   :: !(Unsigned 16)
  , tPhase  :: !TPhase
  , rBank   :: !(Index 2)
  , tPos    :: !Pos
  , tDib    :: !(Index 4)
  , tCrc    :: !(BitVector 32)
  , tFcs    :: !(BitVector 32)      -- complemented CRC, shifting right
  , tLen    :: !BufLen
  , tSum    :: !(BitVector 32)
  , tCfg    :: !UdpCfg              -- sampled at frame start
  , tIfg    :: !(Index 48)
  } deriving (Generic, NFDataX)

uInit :: USt
uInit = USt 0 0 False 0 (repeat 0) (repeat 0) (repeat False) 0 0
            TIdle 0 0 0 crc32Init 0 0 0 (UdpCfg 0 0 0 0 0 0) 0

data UdpTxOut = UdpTxOut
  { utTxd   :: !(BitVector 2)
  , utTxEn  :: !Bool
  , utBusy  :: !Bool                -- frame or IFG in progress
  , utRoom  :: !Bool                -- a new datagram would be accepted now
  , utDrops :: !(Unsigned 16)       -- datagrams dropped for lack of a bank
  , utSent  :: !(Unsigned 16)       -- frames completed
  } deriving (Generic, NFDataX, Show)

ramAddr :: Index 2 -> BufLen -> Unsigned 12
ramAddr b p = unpack (pack b ++# pack p)

otherBank :: Index 2 -> Index 2
otherBank b = if b == 0 then 1 else 0

-- Inputs: (cfg, datagram byte, blockRam read data).
-- Outputs: (read address, write op, wire/status).
udpT :: USt -> (UdpCfg, Maybe DgByte, Byte) -> (USt, (Unsigned 12, Maybe (Unsigned 12, Byte), UdpTxOut))
udpT s0 (cfg, inp, ro) = (s2, (rdA, wrOp, out))
 where
  -- fill side
  (s1, wrOp) = case inp of
    Just DgByte{..}
      | dbFirst && bFull s0 !! wBank s0 ->
          (s0 { wActive = False, uDrops = satAdd SatBound (uDrops s0) 1 }, Nothing)
      | dbFirst || wActive s0 ->
          let bank = wBank s0
              p    = if dbFirst then 0 else wPos s0
              word = if lsb p == 0 then shiftL (zeroExtend dbData) 8 else zeroExtend dbData
              sum' = (if dbFirst then 0 else wSum s0) + word
              s' | dbLast    = s0 { wActive = False, wBank = otherBank bank
                                  , bLen  = replace bank (p + 1) (bLen s0)
                                  , bSum  = replace bank sum' (bSum s0)
                                  , bFull = replace bank True (bFull s0) }
                 | otherwise = s0 { wActive = True, wPos = p + 1, wSum = sum' }
          in (s', Just (ramAddr bank p, dbData))
    _ -> (s0, Nothing)
  -- transmit side
  (s2, rdA, out) = txStep cfg ro s1

txStep :: UdpCfg -> Byte -> USt -> (USt, Unsigned 12, UdpTxOut)
txStep cfg ro s@USt{..} = case tPhase of
  TIdle
    | bFull !! rBank ->
        ( s { tPhase = TSend, tPos = 0, tDib = 0, tCrc = crc32Init
            , tLen = bLen !! rBank, tSum = bSum !! rBank, tCfg = cfg }
        , ramAddr rBank 0, quiet False )
    | otherwise -> (s, ramAddr rBank 0, quiet False)

  TSend ->
    let payEnd = 50 + resize tLen :: Pos
        preLen = max 68 payEnd               -- first FCS byte position
        inFcs  = tPos >= preLen
        byteNow
          | tPos < 7      = 0x55
          | tPos == 7     = 0xD5
          | tPos < 50     = udpHeader tCfg tLen tSum !! (resize (tPos - 8) :: Unsigned 6)
          | tPos < payEnd = ro
          | otherwise     = 0                -- Ethernet minimum-size pad
        txd | inFcs     = truncateB tFcs
            | otherwise = truncateB (shiftR byteNow (2 * fromIntegral tDib))
        crc'  = if tPos >= 8 && not inFcs then crc32Dibit tCrc txd else tCrc
        fcs'  = if inFcs then shiftR tFcs 2 else tFcs
        s' | tDib /= 3          = s { tDib = tDib + 1, tCrc = crc', tFcs = fcs' }
           | tPos == preLen + 3 = s { tPhase = TIfg, tIfg = 0, tDib = 0
                                    , bFull = replace rBank False bFull
                                    , rBank = otherBank rBank, uSent = uSent + 1 }
           | tPos == preLen - 1 = s { tPos = tPos + 1, tDib = 0, tCrc = crc', tFcs = complement crc' }
           | otherwise          = s { tPos = tPos + 1, tDib = 0, tCrc = crc', tFcs = fcs' }
        -- read address for the byte the NEXT cycle transmits (registered RAM)
        pos'    = if tDib == 3 then tPos + 1 else tPos
        nextIdx = if pos' >= 50 then resize (pos' - 50) else 0 :: BufLen
    in (s', ramAddr rBank nextIdx, UdpTxOut txd True True room uDrops uSent)

  TIfg
    | tIfg == maxBound -> (s { tPhase = TIdle }, ramAddr rBank 0, quiet True)
    | otherwise        -> (s { tIfg = tIfg + 1 }, ramAddr rBank 0, quiet True)
 where
  room = not (bFull !! wBank)
  quiet busy = UdpTxOut 0 False busy room uDrops uSent

udpTx
  :: HiddenClockResetEnable dom
  => Signal dom UdpCfg
  -> Signal dom (Maybe DgByte)      -- datagram byte stream (PM.Records)
  -> Signal dom UdpTxOut
udpTx cfg inp = out
 where
  (rdA, wr, out) = unbundle (mealy udpT uInit (bundle (cfg, inp, ramOut)))
  ramOut = blockRam (replicate (SNat @4096) (0 :: Byte)) rdA wr

-- ---------------------------------------------------------------------------

topEntity
  :: Clock Rmii50 -> Reset Rmii50 -> Enable Rmii50
  -> Signal Rmii50 UdpCfg
  -> Signal Rmii50 (Maybe DgByte)
  -> Signal Rmii50 UdpTxOut
topEntity = exposeClockResetEnable udpTx
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_udp_tx"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "cfg", PortName "dg" ]
    , t_output = PortProduct "" [ PortName "txd", PortName "tx_en", PortName "busy"
                                , PortName "room", PortName "drops", PortName "sent" ]
    }) #-}
