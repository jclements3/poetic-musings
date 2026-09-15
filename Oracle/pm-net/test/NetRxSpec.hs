-- PM.NetRx proof: the RMII receiver fed (1) the beacon transmitter's own
-- dibit stream (TX -> RX loopback: bytes 8..67 of the frame come back
-- byte-exact, FCS stripped, crc ok, rxGood = 1); (2) the same stream with
-- one wire bit flipped (crc bad, rxBad = 1); (3) unicast frames built in
-- plain Haskell with an independent table CRC — to our MAC accepted, to
-- another MAC dropped without any output or count, broadcast accepted;
-- (4) two frames back-to-back with a 96-bit IFG both received; (5) a 30-byte
-- runt with a correct FCS rejected as bad.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Word (Word8, Word32)
import qualified Data.Bits as B
import PM.Net (beaconTx)
import PM.NetRx
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

-- Bytes -> RMII dibits, bits 1:0 first.
toDibits :: [Word8] -> [BitVector 2]
toDibits = P.concatMap (\b -> [ P.fromIntegral (B.shiftR b (2 P.* k) B..&. 3) | k <- [0 .. 3] ])

-- A complete wire frame: preamble+SFD, dst, src, payload (type onward), FCS.
wireFrame :: [Word8] -> [Word8] -> [Word8] -> [Word8]
wireFrame dst src body = P.replicate 7 0x55 P.++ [0xD5] P.++ mac P.++ fcs
 where
  mac = dst P.++ src P.++ body
  c   = refCrc32 mac
  fcs = [ P.fromIntegral (B.shiftR c (8 P.* k)) | k <- [0 .. 3] ]

-- Wire samples (dibit, CRS_DV): frames separated by idle clocks.
stream :: [[Word8]] -> Int -> [(BitVector 2, Bool)]
stream fs gap = P.replicate 5 (0, False)
  P.++ P.concatMap (\f -> P.map (\d -> (d, True)) (toDibits f) P.++ P.replicate gap (0, False)) fs
  P.++ P.replicate 40 (0, False)

runRx :: BitVector 48 -> [(BitVector 2, Bool)] -> [RxOut]
runRx mac ws = sampleN @System (P.length ws P.+ 20)
  (withClockResetEnable @System clockGen resetGen enableGen
     (macRx (fromList (P.map fst ws P.++ P.repeat 0))
            (fromList (P.map snd ws P.++ P.repeat False))
            (pure mac)))

-- Received frames: (bytes, start seen on byte 0 only, ok flag at end).
frames :: [RxOut] -> [([Int], Bool, Bool)]
frames = go [] []
 where
  go _ _ [] = []
  go acc starts (o : os)
    | rxEnd o   = (P.reverse acc', startOk starts', rxOk o) : go [] [] os
    | otherwise = go acc' starts' os
   where
    acc'    = if rxValid o then P.fromIntegral (toInteger (rxByte o)) : acc else acc
    starts' = if rxValid o then starts P.++ [rxStart o] else starts
    startOk (True : rest) = P.not (P.or rest)
    startOk _             = False

ourMac :: BitVector 48
ourMac = 0x0250_4D00_0001      -- the beacon's own source MAC, reused as "us"

ourMacBytes, otherMac, bcast :: [Word8]
ourMacBytes = [0x02, 0x50, 0x4D, 0x00, 0x00, 0x01]
otherMac    = [0x02, 0x50, 0x4D, 0x00, 0x00, 0x02]
bcast       = P.replicate 6 0xFF

body60 :: [Word8]          -- type + 46 bytes: dst 6 + src 6 + 48 + FCS 4 = 64, the minimum
body60 = [0x08, 0x00] P.++ P.take 46 [1 ..]

main :: IO ()
main = do
  -- (1) TX -> RX loopback with the real beacon transmitter
  let goSig   = fromList [ i == (10 :: Int) | i <- [0 ..] ]
      txOut   = withClockResetEnable @System clockGen resetGen enableGen
                  (beaconTx goSig (pure 0x42))
      tx      = sampleN @System 420 txOut
      wire    = [ (d, en) | (d, en, _) <- tx ]
      txBytes = fromDibits [ P.fromIntegral (toInteger d) | (d, en, _) <- tx, en ]
      fromDibits (a : b : c : d : r) = (a B..|. B.shiftL b 2 B..|. B.shiftL c 4 B..|. B.shiftL d 6) : fromDibits r
      fromDibits _ = []
      rx1 = runRx ourMac wire
      f1  = frames rx1
      end1 = P.last rx1
  r1 <- check (P.length f1 P.== 1) "loopback: exactly one frame received"
  r2 <- check (case f1 of [(bs, st, ok)] -> bs P.== P.take 60 (P.drop 8 txBytes) P.&& st P.&& ok
                          _              -> False)
              "loopback: bytes 8..67 byte-exact, start on byte 0, crc ok"
  r3 <- check (rxGood end1 P.== 1 P.&& rxBad end1 P.== 0) "loopback: rxGood 1, rxBad 0"

  -- (2) one wire bit flipped inside the payload
  let flipAt = 10 P.+ 4 P.* 30 P.+ 1      -- go at 10, ~byte 30 of the frame
      wire2  = [ if i P.== flipAt then (d `xor` 0b10, en) else (d, en) | (i, (d, en)) <- P.zip [0 :: Int ..] wire ]
      rx2    = runRx ourMac wire2
      end2   = P.last rx2
  r4 <- check (case frames rx2 of [(_, _, ok)] -> P.not ok; _ -> False) "corrupt bit: frame ends with crc bad"
  r5 <- check (rxGood end2 P.== 0 P.&& rxBad end2 P.== 1) "corrupt bit: rxBad 1, rxGood 0"

  -- (3) destination filter
  let toUs    = wireFrame ourMacBytes otherMac body60
      toOther = wireFrame otherMac ourMacBytes body60
      toAll   = wireFrame bcast otherMac body60
      rx3a = runRx ourMac (stream [toUs] 48)
      rx3b = runRx ourMac (stream [toOther] 48)
      rx3c = runRx ourMac (stream [toAll] 48)
      expectUs  = P.map P.fromIntegral (P.take 60 (P.drop 8 toUs))
      expectAll = P.map P.fromIntegral (P.take 60 (P.drop 8 toAll))
  r6 <- check (frames rx3a P.== [(expectUs, True, True)]) "filter: unicast to our MAC accepted"
  r7 <- check (P.null (frames rx3b) P.&& P.not (P.any rxValid rx3b)
               P.&& rxGood (P.last rx3b) P.== 0 P.&& rxBad (P.last rx3b) P.== 0)
              "filter: unicast to another MAC dropped, no output, no count"
  r8 <- check (frames rx3c P.== [(expectAll, True, True)]) "filter: broadcast accepted"

  -- (4) two back-to-back frames, 96-bit (48-clock) IFG
  let rx4  = runRx ourMac (stream [toUs, toAll] 48)
      end4 = P.last rx4
  r9 <- check (frames rx4 P.== [(expectUs, True, True), (expectAll, True, True)])
              "back-to-back: both frames received across a 96-bit IFG"
  r10 <- check (rxGood end4 P.== 2 P.&& rxBad end4 P.== 0) "back-to-back: rxGood 2"

  -- (5) runt: 30 bytes dst..FCS with a correct FCS
  let runt = wireFrame ourMacBytes otherMac (P.take 14 [0x08, 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
      rx5  = runRx ourMac (stream [runt] 48)
      end5 = P.last rx5
  r11 <- check (P.length runt P.== 8 P.+ 30) "runt: test frame is 30 bytes dst..FCS"
  r12 <- check (case frames rx5 of [(_, _, ok)] -> P.not ok; _ -> False) "runt: rejected (rxOk false)"
  r13 <- check (rxGood end5 P.== 0 P.&& rxBad end5 P.== 1) "runt: rxBad 1"

  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13]
    then putStrLn "ALL PASS: PM.NetRx" >> exitSuccess
    else exitFailure
