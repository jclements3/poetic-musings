{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
{-# OPTIONS_GHC -Wno-orphans #-}   -- createDomain necessarily makes an orphan KnownDomain
-- PM.Net — letter-N seed: 100BASE-TX RMII transmit path emitting a fixed
-- UDP/IPv4 status beacon ("the One Box announces itself"; later the same
-- path carries harp/SDR streams).  LIBRARY.md lists RMII MAC/UDP as
-- planned-only for N — MAIDEN has no Ethernet anywhere — so this is new
-- gateware, not a port.  Control-register wiring (0x40xx, per
-- Oracle/eforth-pm.md grouping rules) comes when N gets its address; here
-- go/mode are plain ports.
--
--     Build:    cabal build
--     Test:     cabal test net-test --test-show-details=direct
--     Verilog:  cabal run clash -- -isrc PM.Net --verilog
--     Output:   verilog/PM.Net.topEntity/
--
-- RMII at 100 Mb/s: one 50 MHz clock, TXD[1:0] carries two bits per cycle,
-- TXD0 is the EARLIER bit on the wire.  Ethernet transmits each byte
-- LSB-first, so the dibit stream for a byte b is bits 1:0, then 3:2, 5:4,
-- 7:6 — the FSM below is just an 8-bit right-shift, two bits per clock.
--
-- Frame (72 bytes on the wire = 288 dibits, then 12-byte IFG = 48 clocks
-- of TX_EN low before `ready` returns):
--
--     0..7    preamble 7x55 + SFD D5           (not covered by FCS)
--     8..21   Ethernet: dst ff:ff:ff:ff:ff:ff, src pmSrcMac, type 0800
--     22..41  IPv4: 45 00, len 44, ID 0, no frag, TTL 64, proto 17 UDP,
--             checksum (elaboration-time constant, see ipChecksum),
--             src 10.0.0.77 -> dst 255.255.255.255 (limited broadcast)
--     42..49  UDP: port 20557 ("PM") -> 20557, len 24, checksum 0
--             (transmitted 0 = "not computed" — legal over IPv4)
--     50..65  payload 16 bytes: "PM-ONEBOX" tag, mode byte, 16-bit seq
--             (network order), 4 zero bytes
--     66..67  2 zero pad bytes: IP total is 44 < the 46-byte Ethernet
--             minimum payload, so the MAC pads (FCS covers the pad, IP
--             length does not) — frame is exactly the 64-byte minimum
--     68..71  FCS (CRC-32, computed on the fly, appended LSByte first)
--
-- CRC choice: bit-serial reflected CRC-32 (poly 0xEDB88320, init/final-xor
-- 0xFFFFFFFF), unrolled x2 so it consumes one dibit per 50 MHz clock — the
-- reflected form eats bits exactly in wire order, so the FCS is just the
-- complemented register shifted out LSB-first for 16 more clocks.  Cost is
-- two XOR/mux layers on a 32-bit register (a few tens of LUT4); a
-- byte-at-a-time table CRC would need a 256x32 ROM (BRAM or ~1k LUT4) and
-- buys nothing at 2 bits/clock.
--
-- ID fixed 0 keeps the IPv4 header fully static, so its checksum is a
-- Haskell constant folded at elaboration — no adder in hardware.  seq
-- increments internally per completed frame (free-running beacon counter);
-- mode is sampled at the accepting `go`.
module PM.Net where

import Clash.Prelude

-- 50 MHz RMII reference clock (20 ns).
createDomain vSystem{vName="Rmii50", vPeriod=20000}

type Byte = BitVector 8

-- ---------------------------------------------------------------------------
-- CRC-32 (Ethernet FCS), reflected, bit-serial.

crc32Init :: BitVector 32
crc32Init = 0xFFFF_FFFF

-- One wire bit (transmission order = LSB-first within each byte).
crc32Bit :: BitVector 32 -> Bit -> BitVector 32
crc32Bit c b = if (b `xor` lsb c) == 1 then sh `xor` 0xEDB8_8320 else sh
 where sh = shiftR c 1

-- One RMII dibit per clock: bit 0 is the earlier wire bit (TXD0).
crc32Dibit :: BitVector 32 -> BitVector 2 -> BitVector 32
crc32Dibit c d = crc32Bit (crc32Bit c (d ! (0 :: Int))) (d ! (1 :: Int))

-- ---------------------------------------------------------------------------
-- IPv4 header checksum: one's-complement of the one's-complement sum of the
-- header's big-endian 16-bit words (checksum field taken as 0).  Two
-- end-around carry folds cover any n < 2^16 words.  Applied below to a
-- constant header, so it costs zero gates.

ipChecksum :: KnownNat n => Vec n (BitVector 16) -> BitVector 16
ipChecksum ws = complement (truncateB (fold' (fold' s)))
 where
  s :: BitVector 32
  s = foldl (\a w -> a + zeroExtend w) 0 ws
  fold' x = (x .&. 0xFFFF) + shiftR x 16

-- ---------------------------------------------------------------------------
-- The static frame image (mode/seq bytes patched at readout).

-- Locally-administered src MAC, "PM" in the OUI bytes; a build-time constant
-- by design — the beacon identifies the box, not a NIC.
pmSrcMac :: Vec 6 Byte
pmSrcMac = 0x02 :> 0x50 :> 0x4D :> 0x00 :> 0x00 :> 0x01 :> Nil

-- IPv4 header words, checksum slot 0; ID fixed 0 (never reassembled — DF is
-- not even needed at 44 bytes) keeps every word constant.
ipWords :: Vec 10 (BitVector 16)
ipWords = replace (5 :: Index 10) (ipChecksum ws) ws
 where
  ws = 0x4500 :> 0x002C   -- ver/IHL, TOS | total length 44
    :> 0x0000 :> 0x0000   -- ID 0        | flags/frag 0
    :> 0x4011 :> 0x0000   -- TTL 64, UDP | checksum (slot)
    :> 0x0A00 :> 0x004D   -- src 10.0.0.77
    :> 0xFFFF :> 0xFFFF   -- dst 255.255.255.255
    :> Nil

-- Full 68-byte pre-FCS image: preamble+SFD, headers, payload template
-- (mode/seq zeroed), Ethernet minimum-size pad.
frameImage :: Vec 68 Byte
frameImage =
     replicate d7 0x55 ++ (0xD5 :> Nil)
  ++ replicate d6 0xFF ++ pmSrcMac ++ (0x08 :> 0x00 :> Nil)
  ++ concatMap (\w -> slice d15 d8 w :> slice d7 d0 w :> Nil) ipWords
  ++ (0x50 :> 0x4D :> 0x50 :> 0x4D :> 0x00 :> 0x18 :> 0x00 :> 0x00 :> Nil)
  ++ map charByte ('P' :> 'M' :> '-' :> 'O' :> 'N' :> 'E' :> 'B' :> 'O' :> 'X' :> Nil)
  ++ replicate d7 0    -- mode, seqHi, seqLo, 4 payload zeros
  ++ replicate d2 0    -- Ethernet pad to 46-byte payload
 where charByte = fromIntegral . fromEnum

-- Byte fetch with the three live positions patched in.
frameByte :: Byte -> Unsigned 16 -> Index 68 -> Byte
frameByte m sq i
  | i == 59   = m                       -- payload mode byte
  | i == 60   = slice d15 d8 (pack sq)  -- seq, network order
  | i == 61   = slice d7 d0 (pack sq)
  | otherwise = frameImage !! i

-- ---------------------------------------------------------------------------
-- Beacon transmitter FSM.  Byte counter runs 0..71 (68 image bytes + 4 FCS
-- bytes shifted from the complemented CRC register); dibit counter 0..3
-- within each byte; then 48 clocks of enforced IFG.

data BPhase = PIdle | PSend | PIfg
  deriving (Generic, NFDataX, Eq, Show)

data BSt = BSt
  { bPhase :: !BPhase
  , bByte  :: !(Index 72)         -- 0..67 image, 68..71 FCS
  , bDib   :: !(Index 4)
  , bSh    :: !Byte               -- current image byte, shifting right
  , bCrc   :: !(BitVector 32)
  , bFcs   :: !(BitVector 32)     -- complemented CRC, shifting right
  , bMode  :: !Byte               -- latched at the accepting go
  , bSeq   :: !(Unsigned 16)      -- free-running, +1 per completed frame
  , bIfg   :: !(Index 48)
  } deriving (Generic, NFDataX)

bInit :: BSt
bInit = BSt PIdle 0 0 0 crc32Init 0 0 0 0

-- Outputs: (TXD[1:0], TX_EN, ready).  ready is high exactly while idle; a
-- go pulse outside idle is ignored.
beaconT :: BSt -> (Bool, Byte) -> (BSt, (BitVector 2, Bool, Bool))
beaconT s@BSt{..} (go, m) = case bPhase of
  PIdle
    | go        -> ( s { bPhase = PSend, bByte = 0, bDib = 0
                       , bSh = frameImage !! (0 :: Index 68)
                       , bCrc = crc32Init, bMode = m }
                   , (0, False, True) )
    | otherwise -> (s, (0, False, True))

  PSend ->
    let inData = bByte <= 67
        txd    = if inData then truncateB bSh else truncateB bFcs
        -- preamble/SFD (bytes 0..7) are outside the FCS
        crc'   = if inData && bByte >= 8 then crc32Dibit bCrc txd else bCrc
        s1     = s { bCrc = crc'
                   , bSh  = shiftR bSh 2
                   , bFcs = if inData then bFcs else shiftR bFcs 2 }
        s' | bDib /= 3   = s1 { bDib = bDib + 1 }
           | bByte == 71 = s  { bPhase = PIfg, bIfg = 0 }
           | bByte == 67 = s1 { bByte = 68, bDib = 0, bFcs = complement crc' }
           | otherwise   = s1 { bByte = bByte + 1, bDib = 0
                              , bSh = if bByte < 67   -- FCS region keeps shifting bFcs
                                        then frameByte bMode bSeq (resize (bByte + 1))
                                        else bSh }
    in (s', (txd, True, False))

  PIfg
    | bIfg == maxBound -> (s { bPhase = PIdle, bSeq = bSeq + 1 }, (0, False, False))
    | otherwise        -> (s { bIfg = bIfg + 1 }, (0, False, False))

beaconTx
  :: HiddenClockResetEnable dom
  => Signal dom Bool              -- go (pulse; accepted only when ready)
  -> Signal dom Byte              -- payload mode byte
  -> Signal dom (BitVector 2, Bool, Bool)   -- (TXD, TX_EN, ready)
beaconTx go m = mealy beaconT bInit (bundle (go, m))

-- ---------------------------------------------------------------------------

topEntity
  :: Clock Rmii50 -> Reset Rmii50 -> Enable Rmii50
  -> Signal Rmii50 Bool
  -> Signal Rmii50 Byte
  -> Signal Rmii50 (BitVector 2, Bool, Bool)
topEntity = exposeClockResetEnable beaconTx
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_net_beacon"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "go", PortName "mode" ]
    , t_output = PortProduct "" [ PortName "txd", PortName "tx_en", PortName "ready" ]
    }) #-}
