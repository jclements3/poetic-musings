{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
-- PM.NetRx — letter-N RMII 100BASE-TX MAC receiver, the RX half of the
-- Network/DESIGN.md "minimal 100 Mb RMII" MAC: preamble/SFD hunt, dibit ->
-- byte reassembly, destination filter (our MAC from a register, plus
-- broadcast), CRC-32 check, runt rejection.  ARP/ICMP/UDP parsing sits
-- ABOVE this block (out of scope here); it consumes the byte stream.
--
--     Test:     cabal test netrx-test --test-show-details=direct
--     Verilog:  cabal run clash -- -isrc PM.NetRx --verilog
--
-- Wire side (50 MHz RMII ref clock): RXD[1:0] one dibit per clock, RXD0 the
-- EARLIER bit — the same ordering PM.Net transmits, so bytes reassemble by an
-- 8-bit right shift with the new dibit entering at the top.  CRS_DV is taken
-- as plain "data valid": high from carrier sense to the last dibit.  (Real
-- PHYs toggle CRS_DV at 25 MHz in the tail when CRS drops before DV; that
-- de-glitch, and the 10 Mb/s mode, are not implemented — 100BASE-TX only.)
--
-- Hunt: while CRS_DV is high, dibit 01 is preamble (0x55 = 01 01 01 01),
-- dibit 11 is the SFD's last dibit (0xD5 = 01 01 01 11) -> data starts on
-- the next clock.  Anything else keeps hunting, so leading 00 dibits from
-- the PHY are tolerated.
--
-- Filter: the destination is the first 6 data bytes; the frame is accepted
-- if every byte equals the `ourMac` register (network byte order, first
-- octet in bits 47:40) or every byte is 0xFF.  Rejected frames produce no
-- output and touch no counter.
--
-- Output stream (accepted frames only): `rxByte` with `rxValid`, `rxStart`
-- on the first byte (dst octet 0), FCS STRIPPED; `rxEnd` pulses once after
-- the last byte with `rxOk` = (CRC residue good) && (>= 64 bytes dst..FCS)
-- && (whole bytes only).  Stripping the FCS needs a 6-byte delay line
-- (bytes leave 6 byte-times late, which also lets the dst decision settle
-- before byte 0 leaves); at CRS_DV fall the two oldest line bytes flush on
-- consecutive clocks, followed by rxEnd.  `rxGood`/`rxBad` count accepted
-- frames by that verdict (wrapping 16-bit, for the status registers).
--
-- CRC: the same dibit-serial reflected CRC-32 as the transmitter
-- (PM.Net.crc32Dibit), run over dst..FCS inclusive; after a correct FCS the
-- register holds the constant residue 0xDEBB20E3.
module PM.NetRx where

import Clash.Prelude
import PM.Net (Byte, Rmii50, crc32Init, crc32Dibit)

-- CRC-32 register value after a message and its correct (LSByte-first) FCS.
crc32Residue :: BitVector 32
crc32Residue = 0xDEBB_20E3

data RPhase = RIdle | RHunt | RData | RFlush
  deriving (Generic, NFDataX, Eq, Show)

data RSt = RSt
  { rPhase   :: !RPhase
  , rDib     :: !(Index 4)          -- dibit within the byte being assembled
  , rSh      :: !Byte               -- assembly register, shifting right
  , rCount   :: !(Unsigned 12)      -- completed data bytes (saturating)
  , rCrc     :: !(BitVector 32)
  , rLine    :: !(Vec 6 Byte)       -- delay line, head newest
  , rOurOk   :: !Bool               -- dst so far == ourMac
  , rBcOk    :: !Bool               -- dst so far == ff:ff:ff:ff:ff:ff
  , rStarted :: !Bool               -- rxStart already issued this frame
  , rFlush   :: !(Index 2)
  , rOk      :: !Bool               -- verdict, latched at CRS_DV fall
  , rGood    :: !(Unsigned 16)
  , rBad     :: !(Unsigned 16)
  } deriving (Generic, NFDataX)

rInit :: RSt
rInit = RSt RIdle 0 0 0 crc32Init (repeat 0) True True False 0 False 0 0

data RxOut = RxOut
  { rxByte  :: Byte
  , rxValid :: Bool
  , rxStart :: Bool
  , rxEnd   :: Bool
  , rxOk    :: Bool
  , rxGood  :: Unsigned 16
  , rxBad   :: Unsigned 16
  } deriving (Generic, NFDataX, Show)

-- Inputs: (RXD[1:0], CRS_DV, ourMac).
macRxT :: RSt -> (BitVector 2, Bool, BitVector 48) -> (RSt, RxOut)
macRxT s@RSt{..} (rxd, crsDv, ourMac) = (s', out)
 where
  quiet = RxOut 0 False False False False rGood rBad
  frameStart = s { rPhase = RHunt, rDib = 0, rCount = 0, rCrc = crc32Init
                 , rOurOk = True, rBcOk = True, rStarted = False }
  (s', out) = case rPhase of
    RIdle
      | crsDv     -> (frameStart, quiet)
      | otherwise -> (s, quiet)

    RHunt
      | not crsDv  -> (s { rPhase = RIdle }, quiet)
      | rxd == 0b11 -> (s { rPhase = RData }, quiet)
      | otherwise  -> (s, quiet)

    RData
      | not crsDv ->
          -- frame over: verdict, then flush (accepted) or drop (filtered)
          let ok = rDib == 0 && rCount >= 64 && rCrc == crc32Residue
          in if accepted
               then (s { rPhase = RFlush, rFlush = 0, rOk = ok }, quiet)
               else (s { rPhase = RIdle }, quiet)
      | otherwise ->
          let sh'   = (rxd ++# slice d7 d2 rSh)
                        -- new dibit enters at the top, byte completes LSB-first
              crc'  = crc32Dibit rCrc rxd
              done  = rDib == 3
              macV  = unpack ourMac :: Vec 6 Byte
              inDst = rCount < 6
              dstIx = truncateB rCount :: Unsigned 3   -- only consulted while inDst
              ourOk = rOurOk && (not inDst || sh' == macV !! dstIx)
              bcOk  = rBcOk  && (not inDst || sh' == 0xFF)
              emit  = done && accepted && rCount >= 6
              s1 = s { rDib = if done then 0 else rDib + 1, rSh = sh', rCrc = crc' }
              s2 | done      = s1 { rCount = if rCount == maxBound then rCount else rCount + 1
                                  , rLine = sh' +>> rLine
                                  , rOurOk = ourOk, rBcOk = bcOk
                                  , rStarted = rStarted || emit }
                 | otherwise = s1
          in ( s2
             , quiet { rxByte = last rLine, rxValid = emit
                     , rxStart = emit && not rStarted } )

    RFlush ->
      let lastOne = rFlush == 1
          emit    = rCount >= 6
          s1 = s { rLine = 0 +>> rLine, rStarted = rStarted || emit }
          s2 | lastOne   = s1 { rPhase = RIdle
                              , rGood = if rOk then rGood + 1 else rGood
                              , rBad  = if rOk then rBad else rBad + 1 }
             | otherwise = s1 { rFlush = 1 }
      in ( s2
         , quiet { rxByte = last rLine, rxValid = emit
                 , rxStart = emit && not rStarted
                 , rxEnd = lastOne, rxOk = lastOne && rOk } )
   where accepted = rOurOk || rBcOk

macRx
  :: HiddenClockResetEnable dom
  => Signal dom (BitVector 2)     -- RXD[1:0]
  -> Signal dom Bool              -- CRS_DV
  -> Signal dom (BitVector 48)    -- our MAC (register), first octet in 47:40
  -> Signal dom RxOut
macRx rxd crsDv ourMac = mealy macRxT rInit (bundle (rxd, crsDv, ourMac))

-- ---------------------------------------------------------------------------

topEntity
  :: Clock Rmii50 -> Reset Rmii50 -> Enable Rmii50
  -> Signal Rmii50 (BitVector 2)
  -> Signal Rmii50 Bool
  -> Signal Rmii50 (BitVector 48)
  -> Signal Rmii50 RxOut
topEntity = exposeClockResetEnable macRx
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_net_rx"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "rxd", PortName "crs_dv", PortName "our_mac" ]
    , t_output = PortProduct "" [ PortName "rx_byte", PortName "rx_valid"
                                , PortName "rx_start", PortName "rx_end"
                                , PortName "rx_ok", PortName "rx_good", PortName "rx_bad" ]
    }) #-}
