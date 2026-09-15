-- PM.UdpTx proof: datagrams fed as DgByte streams (one byte per clock, as the
-- packer emits them) come out as RMII frames that (1) PM.NetRx receives with
-- crc ok, and (2) a plain-Haskell parser takes apart: Ethernet dst/src/type
-- from the config, IPv4 fields with the header checksum summing to 0xFFFF,
-- UDP ports/length and the UDP checksum verifying over the pseudo-header,
-- payload byte-exact, minimum-size pad, FCS against an independent table
-- CRC-32.  Cases: 10-byte (padded to 64), 11-byte (odd UDP checksum byte),
-- 1400-byte (maximum), two datagrams back-to-back (IFG >= 96 bit times),
-- three 1400-byte datagrams back-to-back (the third finds both banks full:
-- dropped whole, counted, the following datagram still transmitted).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Word (Word8, Word32)
import qualified Data.Bits as B
import PM.Records (DgByte(..))
import PM.NetRx
import PM.UdpTx
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- Reference CRC-32 (table-driven, no hardware code shared).
crcTable :: [Word32]
crcTable = [ P.iterate step (P.fromIntegral n) P.!! (8 :: Int) | n <- [0 .. 255 :: Int] ]
 where step x = if B.testBit x 0 then B.shiftR x 1 `B.xor` 0xEDB88320 else B.shiftR x 1

refCrc32 :: [Word8] -> Word32
refCrc32 = B.complement P.. L.foldl' step 0xFFFFFFFF
 where
  step c b = B.shiftR c 8 `B.xor`
             (crcTable P.!! P.fromIntegral ((c `B.xor` P.fromIntegral b) B..&. 0xFF))

cfg :: UdpCfg
cfg = UdpCfg { ucSrcMac = 0x0250_4D00_0001, ucDstMac = 0x0250_4D00_0002
             , ucSrcIp = 0x0A00_004D, ucDstIp = 0x0A00_0001
             , ucSrcPort = 20557, ucDstPort = 20558 }

srcMacB, dstMacB, srcIpB, dstIpB :: [Int]
srcMacB = [0x02, 0x50, 0x4D, 0x00, 0x00, 0x01]
dstMacB = [0x02, 0x50, 0x4D, 0x00, 0x00, 0x02]
srcIpB  = [10, 0, 0, 77]
dstIpB  = [10, 0, 0, 1]

-- A datagram as its DgByte stream, one byte per clock.
dg :: [Int] -> [Maybe DgByte]
dg bs = [ Just (DgByte (P.fromIntegral b) (i P.== 0) (i P.== n P.- 1)) | (i, b) <- P.zip [0 :: Int ..] bs ]
 where n = P.length bs

-- Run TX -> RX loopback (4 idle cycles first, clear of reset); per cycle (tx output, rx output).
run :: Int -> [Maybe DgByte] -> [(UdpTxOut, RxOut)]
run n inp = sampleN @System n
  (withClockResetEnable @System clockGen resetGen enableGen
     (let o  = udpTx (pure cfg) (fromList (P.replicate 4 Nothing P.++ inp P.++ P.repeat Nothing))
          rx = macRx (utTxd <$> o) (utTxEn <$> o) (pure (ucDstMac cfg))
      in bundle (o, rx)))

-- TX_EN bursts: (start cycle, dibits).
bursts :: [(Int, Bool, Bool)] -> [(Int, [Int])]
bursts = go 0
 where
  go _ [] = []
  go i ss =
    let (idle, rest) = L.span (\(_, en, _) -> P.not en) ss
        (hi, rest')  = L.span (\(_, en, _) -> en) rest
        i0           = i P.+ P.length idle
    in if P.null hi then [] else (i0, P.map (\(d, _, _) -> d) hi) : go (i0 P.+ P.length hi) rest'

toBytes :: [Int] -> [Int]
toBytes (w0 : w1 : w2 : w3 : ws) = (w0 B..|. B.shiftL w1 2 B..|. B.shiftL w2 4 B..|. B.shiftL w3 6) : toBytes ws
toBytes _ = []

-- Received frames from NetRx: (bytes dst.., ok).
rxFrames :: [RxOut] -> [([Int], Bool)]
rxFrames = go []
 where
  go _ [] = []
  go acc (o : os)
    | rxEnd o   = (P.reverse acc', rxOk o) : go [] os
    | otherwise = go acc' os
   where acc' = if rxValid o then P.fromIntegral (toInteger (rxByte o)) : acc else acc

-- ---------------------------------------------------------------------------
-- Test-side parser over a NetRx frame (dst.., FCS stripped).

word16 :: [Int] -> Int -> Int
word16 bs i = B.shiftL (bs P.!! i) 8 B..|. bs P.!! (i P.+ 1)

onesSum :: [Int] -> Int
onesSum = P.foldl (\a w -> let s = a P.+ w in (s B..&. 0xFFFF) P.+ B.shiftR s 16) 0

words16 :: [Int] -> [Int]
words16 (a : b : r) = (B.shiftL a 8 B..|. b) : words16 r
words16 [a]         = [B.shiftL a 8]
words16 []          = []

data Parsed = Parsed
  { pDst, pSrc :: [Int], pType :: Int
  , pIpVer, pIpLen, pIpProto :: Int, pIpSum :: Int, pIpSrc, pIpDst :: [Int]
  , pSport, pDport, pUdpLen, pUdpCk :: Int, pUdpSum :: Int
  , pPayload :: [Int], pPad :: [Int]
  } deriving Show

parseFrame :: [Int] -> Parsed
parseFrame bs = Parsed
  { pDst = P.take 6 bs, pSrc = P.take 6 (P.drop 6 bs), pType = word16 bs 12
  , pIpVer = ip P.!! 0, pIpLen = ipLen, pIpProto = ip P.!! 9
  , pIpSum = onesSum (words16 (P.take 20 ip))
  , pIpSrc = P.take 4 (P.drop 12 ip), pIpDst = P.take 4 (P.drop 16 ip)
  , pSport = word16 udp 0, pDport = word16 udp 2, pUdpLen = udpLen, pUdpCk = word16 udp 6
  , pUdpSum = onesSum (words16 (pseudo P.++ P.take udpLen udp))
  , pPayload = P.take (udpLen P.- 8) (P.drop 8 udp)
  , pPad = P.drop ipLen (P.drop 14 bs) }
 where
  ip     = P.drop 14 bs
  ipLen  = word16 ip 2
  udp    = P.take (ipLen P.- 20) (P.drop 20 ip)
  udpLen = word16 udp 4
  pseudo = P.take 8 (P.drop 12 ip) P.++ [0, 17, B.shiftR udpLen 8, udpLen B..&. 0xFF]

-- All header/length/checksum checks for one frame against its expected payload.
frameOk :: [Int] -> ([Int], Bool) -> [(P.String, Bool)]
frameOk expect (bs, ok) =
  [ ("netrx crc ok",            ok)
  , ("dst MAC",                 pDst p P.== dstMacB)
  , ("src MAC",                 pSrc p P.== srcMacB)
  , ("ethertype 0800",          pType p P.== 0x0800)
  , ("IPv4 45, proto 17",       pIpVer p P.== 0x45 P.&& pIpProto p P.== 17)
  , ("IP total length 28+L",    pIpLen p P.== 28 P.+ n)
  , ("IP header checksum FFFF", pIpSum p P.== 0xFFFF)
  , ("IP src/dst",              pIpSrc p P.== srcIpB P.&& pIpDst p P.== dstIpB)
  , ("UDP ports",               pSport p P.== 20557 P.&& pDport p P.== 20558)
  , ("UDP length 8+L",          pUdpLen p P.== 8 P.+ n)
  , ("UDP checksum verifies",   pUdpCk p P./= 0 P.&& pUdpSum p P.== 0xFFFF)
  , ("payload byte-exact",      pPayload p P.== expect)
  , ("frame >= 60 bytes, pad 0", P.length bs P.>= 60 P.&& P.all (P.== 0) (pPad p))
  , ("frame length",            P.length bs P.== P.max 60 (14 P.+ 28 P.+ n))
  ]
 where
  p = parseFrame bs
  n = P.length expect

report :: P.String -> [(P.String, Bool)] -> IO Bool
report tag cs = do
  let bad = [ nm | (nm, False) <- cs ]
  check (P.null bad) (tag P.++ ": " P.++ show (P.length cs) P.++ " checks"
                      P.++ (if P.null bad then "" else " FAILED " P.++ show bad))

-- Wire-level checks on a TX_EN burst: preamble/SFD, FCS vs reference.
wireOk :: [Int] -> [(P.String, Bool)]
wireOk dibits =
  [ ("burst is whole bytes",  P.length dibits `P.mod` 4 P.== 0)
  , ("preamble 7x55 + D5",    P.take 8 bytes P.== P.replicate 7 0x55 P.++ [0xD5])
  , ("FCS = reference CRC32", fcsWire P.== fcsRef)
  ]
 where
  bytes   = toBytes dibits
  body    = P.drop 8 bytes
  fcsRef  = refCrc32 (P.map P.fromIntegral (P.take (P.length body P.- 4) body))
  fcsWire = P.foldr (\b a -> B.shiftL a 8 B..|. P.fromIntegral b) (0 :: Word32) (P.drop (P.length body P.- 4) body)

main :: IO ()
main = do
  let p10   = [0 .. 9]
      p11   = [0x10, 0x20 .. 0xB0]
      p1400 = [ (i P.* 7 P.+ 3) `P.mod` 256 | i <- [0 .. 1399 :: Int] ]
      txs s = [ (P.fromIntegral (toInteger (utTxd o)), utTxEn o, utBusy o) | (o, _) <- s ]
      rxs s = P.map snd s

  -- (1) 10-byte datagram
  let s1 = run 800 (dg p10)
      b1 = bursts (txs s1)
      f1 = rxFrames (rxs s1)
  r1 <- check (P.length b1 P.== 1 P.&& P.length (snd (P.head b1)) P.== 288) "10-byte: one 288-dibit (72-byte) frame"
  r2 <- report "10-byte wire" (wireOk (snd (P.head b1)))
  r3 <- report "10-byte parse" (P.concatMap (frameOk p10) f1 P.++ [("one rx frame", P.length f1 P.== 1)])
  putStrLn ("  10-byte: " P.++ show (P.length (snd (P.head b1)) `P.div` 4) P.++ " wire bytes, IP total "
            P.++ show (pIpLen (parseFrame (fst (P.head f1)))) P.++ ", UDP len " P.++ show (pUdpLen (parseFrame (fst (P.head f1)))))

  -- (2) 11-byte datagram: odd UDP checksum byte
  let s2 = run 800 (dg p11)
      f2 = rxFrames (rxs s2)
  r4 <- report "11-byte parse" (P.concatMap (frameOk p11) f2 P.++ [("one rx frame", P.length f2 P.== 1)])

  -- (3) 1400-byte datagram
  let s3 = run 8000 (dg p1400)
      b3 = bursts (txs s3)
      f3 = rxFrames (rxs s3)
  r5 <- check (P.length b3 P.== 1 P.&& P.length (snd (P.head b3)) P.== 5816) "1400-byte: one 5816-dibit (1454-byte) frame"
  r6 <- report "1400-byte wire" (wireOk (snd (P.head b3)))
  r7 <- report "1400-byte parse" (P.concatMap (frameOk p1400) f3 P.++ [("one rx frame", P.length f3 P.== 1)])
  putStrLn ("  1400-byte: " P.++ show (P.length (snd (P.head b3)) `P.div` 4) P.++ " wire bytes, IP total "
            P.++ show (pIpLen (parseFrame (fst (P.head f3)))) P.++ ", UDP len " P.++ show (pUdpLen (parseFrame (fst (P.head f3)))))

  -- (4) back-to-back: 1400 then 10 with no gap in the byte stream
  let s4 = run 9000 (dg p1400 P.++ dg p10)
      b4 = bursts (txs s4)
      f4 = rxFrames (rxs s4)
      gap = case b4 of
        ((s, ds) : (s', _) : _) -> s' P.- (s P.+ P.length ds)
        _                       -> 0
  r8 <- check (P.length b4 P.== 2 P.&& gap P.>= 48) ("back-to-back: two frames, IFG " P.++ show gap P.++ " clocks >= 48")
  r9 <- report "back-to-back parse"
          (case f4 of
             [a, b] -> frameOk p1400 a P.++ frameOk p10 b
             _      -> [("two rx frames", False)])
  r10 <- check (utDrops (fst (P.last s4)) P.== 0 P.&& utSent (fst (P.last s4)) P.== 2) "back-to-back: 0 drops, 2 sent"

  -- (5) three 1400-byte datagrams back-to-back: the third is dropped whole;
  --     a 10-byte one after a gap (first frame off the wire) still goes out.
  let s5 = run 16000 (dg p1400 P.++ dg p1400 P.++ dg p1400 P.++ P.replicate 6000 Nothing P.++ dg p10)
      b5 = bursts (txs s5)
      f5 = rxFrames (rxs s5)
      e5 = fst (P.last s5)
  r11 <- check (P.length b5 P.== 3 P.&& utDrops e5 P.== 1 P.&& utSent e5 P.== 3)
                ("overflow: 3 frames sent, 1 datagram dropped (drops=" P.++ show (utDrops e5) P.++ ")")
  r12 <- report "overflow parse"
           (case f5 of
              [a, b, c] -> frameOk p1400 a P.++ frameOk p1400 b P.++ frameOk p10 c
              _         -> [("three rx frames", False)])
  r13 <- check (rxBad (snd (P.last s5)) P.== 0 P.&& rxGood (snd (P.last s5)) P.== 3) "overflow: rxGood 3, rxBad 0"

  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13]
    then putStrLn "ALL PASS: PM.UdpTx" >> exitSuccess
    else exitFailure
