-- Wire-level proof of the N beacon: capture the RMII dibit stream from two
-- `go` pulses, reassemble bytes (dibit bits 1:0 first = the LSBs — the
-- classic RMII ordering bug this spec exists to catch), then verify the
-- frames with plain Haskell: preamble/SFD, an INDEPENDENT table-driven
-- CRC-32 reference (Data.Word/Data.Bits, no hardware code shared) against
-- the transmitted FCS, IPv4 header checksum summing to 0xFFFF, length
-- consistency, payload tag/mode, >= 96 bit times of TX_EN low before ready,
-- and seq advancing by exactly 1 between frames.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Word (Word8, Word32)
import qualified Data.Bits as B
import PM.Net (beaconTx)
import System.Exit (exitFailure, exitSuccess)

-- ---------------------------------------------------------------------------
-- Reference CRC-32: byte-at-a-time, table-driven, over Word8/Word32 —
-- deliberately a different formulation from the hardware's dibit-serial one.

crcTable :: [Word32]
crcTable = [ P.iterate step (P.fromIntegral n) P.!! (8 :: Int) | n <- [0 .. 255 :: Int] ]
 where step x = if B.testBit x 0 then B.shiftR x 1 `B.xor` 0xEDB88320 else B.shiftR x 1

refCrc32 :: [Word8] -> Word32
refCrc32 = B.complement P.. L.foldl' step 0xFFFFFFFF
 where
  step c b = B.shiftR c 8 `B.xor`
             (crcTable P.!! P.fromIntegral ((c `B.xor` P.fromIntegral b) B..&. 0xFF))

-- ---------------------------------------------------------------------------

testMode :: Integer
testMode = 0x42

main :: IO ()
main = do
  let n = 900
      -- go at 10 (frame 1 done ~347 incl. IFG) and at 450
      goSig   = fromList [ i == (10 :: Int) || i == 450 | i <- [0 ..] ]
      outSig  = withClockResetEnable @System clockGen resetGen enableGen
                  (beaconTx goSig (pure (P.fromIntegral testMode)))
      samples = sampleN @System n outSig
      txs     = [ (P.fromIntegral (toInteger d), en, rdy) | (d, en, rdy) <- samples ]
                  :: [(Int, Bool, Bool)]

      -- carve out the TX_EN-high runs with their start indices
      bursts = frames 0 txs
      frames _ [] = []
      frames i ss =
        let (idle, rest) = L.span (\(_, en, _) -> P.not en) ss
            (hi, rest')  = L.span (\(_, en, _) -> en) rest
            i0           = i P.+ P.length idle
        in if P.null hi then []
           else (i0, P.map (\(d, _, _) -> d) hi) : frames (i0 P.+ P.length hi) rest'

      -- RMII reassembly: dibit k of a byte carries bits 2k+1:2k
      toBytes (w0 : w1 : w2 : w3 : ws) =
        (w0 B..|. B.shiftL w1 2 B..|. B.shiftL w2 4 B..|. B.shiftL w3 6) : toBytes ws
      toBytes _ = []

      ((s1, f1), (s2, f2)) = case bursts of
        (a : b : _) -> (a, b)
        _           -> P.error "expected two frames"
      b1 = toBytes f1 :: [Int]
      b2 = toBytes f2

      e1 = s1 P.+ P.length f1              -- first idle cycle after frame 1
      readyAt = e1 P.+ P.length (L.takeWhile (\(_, _, r) -> P.not r) (P.drop e1 txs))
      idleGap = P.length (L.takeWhile (\(_, en, _) -> P.not en) (P.drop e1 txs))

      word16 bs i = B.shiftL (bs P.!! i) 8 B..|. bs P.!! (i P.+ 1)
      onesSum = P.foldr (\w a -> let s = a P.+ w in (s B..&. 0xFFFF) P.+ B.shiftR s 16) (0 :: Int)
      ipSum bs = onesSum [ word16 bs (22 P.+ 2 P.* k) | k <- [0 .. 9] ]

      fcsRef bs = refCrc32 (P.map P.fromIntegral (P.take 60 (P.drop 8 bs)))
      fcsWire bs = P.foldr (\b a -> B.shiftL a 8 B..|. P.fromIntegral b) (0 :: Word32)
                     (P.drop 68 bs)        -- LSByte transmitted first
      seqOf bs = word16 bs 60
      tag bs = P.map (toEnum :: Int -> Char) (P.take 9 (P.drop 50 bs))

      checks =
        [ ("two frames captured",            P.length bursts P.== 2)
        , ("frame length 288 dibits",        P.all ((P.== 288) P.. P.length) [f1, f2])
        , ("preamble 7x55",                  P.all (P.== 0x55) (P.take 7 b1))
        , ("SFD D5",                         b1 P.!! 7 P.== 0xD5)
        , ("dst broadcast",                  P.all (P.== 0xFF) (P.take 6 (P.drop 8 b1)))
        , ("ethertype 0800",                 word16 b1 20 P.== 0x0800)
        , ("FCS matches reference CRC32",    fcsWire b1 P.== fcsRef b1 P.&& fcsWire b2 P.== fcsRef b2)
        , ("IPv4 checksum verifies (FFFF)",  ipSum b1 P.== 0xFFFF)
        , ("IP total length 44",             word16 b1 24 P.== 44)
        , ("UDP length 24",                  word16 b1 46 P.== 24)
        , ("lengths consistent",             P.length b1 P.== 8 P.+ 14 P.+ 44 P.+ 2 P.+ 4
                                             P.&& word16 b1 24 P.== 20 P.+ word16 b1 46)
        , ("UDP checksum transmitted 0",     word16 b1 48 P.== 0)
        , ("payload tag PM-ONEBOX",          tag b1 P.== "PM-ONEBOX")
        , ("mode byte in payload",           b1 P.!! 59 P.== P.fromIntegral testMode)
        , ("IFG >= 96 bit times",            idleGap P.>= 48 P.&& readyAt P.- e1 P.>= 48)
        , ("no TX_EN inside the IFG",        readyAt P.- e1 P.<= idleGap)
        , ("seq advances by 1",              seqOf b2 P.== seqOf b1 P.+ 1)
        ]

  putStrLn ("frame 1 @" P.++ show s1 P.++ ", frame 2 @" P.++ show s2
            P.++ ", seq " P.++ show (seqOf b1) P.++ " -> " P.++ show (seqOf b2))
  putStrLn ("FCS wire/ref: " P.++ show (fcsWire b1) P.++ " / " P.++ show (fcsRef b1)
            P.++ ", IFG idle clocks before ready: " P.++ show (readyAt P.- e1))
  mapM_ (\(nm, ok) -> putStrLn ((if ok then "  ok  " else "  FAIL ") P.++ nm)) checks
  if P.all snd checks
    then putStrLn "PASS: RMII UDP beacon wire-level checks" >> exitSuccess
    else putStrLn "FAIL" >> exitFailure
