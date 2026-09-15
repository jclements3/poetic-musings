-- End-to-end chain (PLAN Phase 11's gap-free-track gate, in simulation):
--
--   synthetic 640x400 DVP frames, 3 discs drifting frame to frame
--     -> PM.Dvp.dvpCapture -> PM.Blob.blobLabel (centroids per frame)
--     -> CENTROID records, plus one STROBE_STAMP per frame from
--        PM.StrobeLatch (strobe = VSYNC, stamped with a free-running RTC)
--     -> PM.Records.recordPath4 (ports -> mux -> FIFO -> datagram packer)
--     -> PM.UdpTx -> RMII dibits -> PM.NetRx
--     -> test-side Ethernet/IP/UDP parse -> PROTOCOL.md record parse.
--
-- Asserted over 5 frames: every frame's 3 centroids arrive with the values a
-- plain-Haskell model of the labeller gives (round(16*sum/count), ties up),
-- each frame's STROBE_STAMP (seq = frame number) precedes its centroids,
-- per-type record SEQ and datagram SEQ have no gaps, and nothing is dropped
-- anywhere (record ports, UdpTx banks, NetRx crc).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import qualified Data.Bits as B
import Data.Maybe (isJust)
import PM.Dvp
import PM.Blob (BlobCfg(..), BlobOut(..), BlobRec(..), blobLabel)
import PM.StrobeLatch
import PM.Records
import PM.UdpTx
import PM.Net (Byte)
import PM.NetRx
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- ---------------------------------------------------------------------------
-- Scene: three discs (radius^2 <= 20), moving a few pixels per frame.

nFrames :: Int
nFrames = 5

discs :: Int -> [(Int, Int)]
discs f = [(100 P.+ 8 P.* f, 100 P.+ 4 P.* f), (320, 200 P.- 3 P.* f), (540 P.- 8 P.* f, 300 P.+ 2 P.* f)]

inDisc :: (Int, Int) -> Int -> Int -> Bool
inDisc (cx, cy) x y = (x P.- cx) P.* (x P.- cx) P.+ (y P.- cy) P.* (y P.- cy) P.<= 20

pixVal :: Int -> Int -> Int -> Unsigned 8
pixVal f x y = if P.any (\c -> inDisc c x y) (discs f) then 255 else 0

-- Expected (cx_q4, cy_q4, count) per disc, exactly the labeller's rounding.
expectDisc :: (Int, Int) -> (Int, Int, Int)
expectDisc c@(cx, cy) = (q sx, q sy, n)
 where
  ps = [ (x, y) | y <- [cy P.- 5 .. cy P.+ 5], x <- [cx P.- 5 .. cx P.+ 5], inDisc c x y ]
  n  = P.length ps
  sx = P.sum (P.map fst ps)
  sy = P.sum (P.map snd ps)
  q s = (16 P.* s P.+ n `P.div` 2) `P.div` n

-- Bus samples for one frame: VSYNC 3 cycles, 400 lines of 640 HREF samples
-- with 2 idle cycles each, then vertical blanking for the labeller's eof
-- phases (<= 1088 cycles).
vBlank, frameCycles :: Int
vBlank      = 1500
frameCycles = 3 P.+ 400 P.* 642 P.+ vBlank

dvpFrame :: Int -> [DvpIn]
dvpFrame f =
  P.replicate 3 (DvpIn False True 0)
  P.++ P.concat [ [ DvpIn True False (pixVal f x y) | x <- [0 .. 639] ] P.++ P.replicate 2 (DvpIn False False 0)
                | y <- [0 .. 399] ]
  P.++ P.replicate vBlank (DvpIn False False 0)

-- ---------------------------------------------------------------------------
-- The chain.

cfgNet :: UdpCfg
cfgNet = UdpCfg { ucSrcMac = 0x0250_4D00_0001, ucDstMac = 0x0250_4D00_0010
                , ucSrcIp = 0x0A00_004D, ucDstIp = 0x0A00_0010
                , ucSrcPort = 20557, ucDstPort = 20557 }

blobCfg :: BlobCfg
blobCfg = BlobCfg 128 0 20 200

-- Per-cycle observation: (rx byte if valid, rxEnd, rxOk, port drops, udp drops, blob dropped/overflow).
type Obs = (Maybe Byte, Bool, Bool, Vec 4 (Unsigned 16), Unsigned 16, Bool)

chain :: HiddenClockResetEnable dom => Signal dom DvpIn -> Signal dom Obs
chain dvp = bundle (byteOut, rxEnd <$> rx, rxOk <$> rx, bundle drops, utDrops <$> ut, blobBad)
 where
  rtc      = register (0 :: Unsigned 48) (rtc + 1)
  (pix, _) = dvpCapture dvp
  blob     = blobLabel (pure blobCfg) pix
  blobBad  = (\b -> boDropped b || boOverflow b) <$> blob
  -- strobe stamp: VSYNC is the strobe; pop one entry at a time
  so       = strobeLatch (dVsync <$> dvp) rtc rdEn
  rdEn     = (\v prev -> v && not prev) <$> (rdValid <$> so) <*> register False rdEn
  ssFire   = (\en o -> if en then Just (StrobeStamp (rdRtc o) (rdSeq o) (overflow o)) else Nothing) <$> rdEn <*> so
  curSeq   = regEn 0 rdEn (rdSeq <$> so)
  ceFire   = (\mr r sq -> fmap (\b -> Centroid r sq (pack (bLabel b)) (bCx b) (bCy b) (bCount b) 0) mr)
               <$> (boRec <$> blob) <*> rtc <*> curSeq
  tick     = (\r -> (r .&. 0x7FF) == 0x7FF) <$> rtc          -- flush every 2048 clocks
  (dg, _, _, drops) = recordPath4 (pure Nothing) (pure Nothing) ssFire ceFire tick
  ut       = udpTx (pure cfgNet) dg
  rx       = macRx (utTxd <$> ut) (utTxEn <$> ut) (pure (ucDstMac cfgNet))
  byteOut  = (\o -> if rxValid o then Just (rxByte o) else Nothing) <$> rx

-- ---------------------------------------------------------------------------
-- Single-pass fold over the observations (memory stays bounded).

data Acc = Acc
  { aCur    :: ![Int]              -- current frame bytes, reversed
  , aFrames :: ![([Int], Bool)]    -- completed frames, reversed
  , aDrops  :: ![Int]
  , aUdp    :: !Int
  , aBlob   :: !Bool
  }

step :: Acc -> Obs -> Acc
step a (mb, end, ok, ds, ud, bb) =
  let cur' = case mb of Just b -> P.fromIntegral (toInteger b) : aCur a; Nothing -> aCur a
      a1   = a { aCur = cur', aDrops = P.map (P.fromIntegral . toInteger) (toList ds)
               , aUdp = P.fromIntegral (toInteger ud), aBlob = aBlob a P.|| bb }
  in if end then a1 { aCur = [], aFrames = (P.reverse cur', ok) : aFrames a } else a1

-- ---------------------------------------------------------------------------
-- Test-side parsers.

word16 :: [Int] -> Int -> Int
word16 bs i = B.shiftL (bs P.!! i) 8 B..|. bs P.!! (i P.+ 1)

onesSum :: [Int] -> Int
onesSum = P.foldl (\a w -> let s = a P.+ w in (s B..&. 0xFFFF) P.+ B.shiftR s 16) 0

words16 :: [Int] -> [Int]
words16 (a : b : r) = (B.shiftL a 8 B..|. b) : words16 r
words16 [a]         = [B.shiftL a 8]
words16 []          = []

-- UDP payload of a NetRx frame (dst.., FCS stripped), if the headers check out.
udpPayload :: [Int] -> Maybe [Int]
udpPayload bs
  | P.length bs P.>= 42, word16 bs 12 P.== 0x0800, ip P.!! 0 P.== 0x45, ip P.!! 9 P.== 17
  , onesSum (words16 (P.take 20 ip)) P.== 0xFFFF
  , ipLen P.== 20 P.+ udpLen, P.length udp P.== udpLen
  , onesSum (words16 (pseudo P.++ udp)) P.== 0xFFFF
  , word16 udp 2 P.== 20557
  = Just (P.drop 8 udp)
  | otherwise = Nothing
 where
  ip     = P.drop 14 bs
  ipLen  = word16 ip 2
  udp    = P.take (ipLen P.- 20) (P.drop 20 ip)
  udpLen = word16 udp 4
  pseudo = P.take 8 (P.drop 12 ip) P.++ [0, 17, B.shiftR udpLen 8, udpLen B..&. 0xFF]

payloadLen :: Int -> Maybe Int
payloadLen t = P.lookup t [(0x10, 4), (0x11, 10), (0x12, 9), (0x20, 16)]

parseRecords :: [Int] -> Maybe [(Int, Int, [Int])]
parseRecords [] = Just []
parseRecords (0xA5 : t : sq : rest) = do
  n <- payloadLen t
  let (p, rest') = P.splitAt n rest
  case rest' of
    (ck : rest'')
      | P.length p P.== n, (0xA5 P.+ t P.+ sq P.+ P.sum p P.+ ck) `P.mod` 256 P.== 0
      -> ((t, sq, p) :) P.<$> parseRecords rest''
    _ -> Nothing
parseRecords _ = Nothing

leInt :: [Int] -> Int
leInt = P.foldr (\b a -> a P.* 256 P.+ b) 0

-- A decoded record in arrival order.
data R = RStamp Int Int            -- frame seq, rtc
       | RCent Int Int Int Int Int -- frame seq, cx, cy, count, rtc
  deriving (Show, Eq)

decode :: (Int, Int, [Int]) -> Maybe R
decode (0x12, _, p) = Just (RStamp (leInt (P.take 2 (P.drop 6 p))) (leInt (P.take 6 p)))
decode (0x20, _, p) = Just (RCent (leInt (P.take 2 (P.drop 6 p))) (leInt (P.take 2 (P.drop 9 p)))
                                  (leInt (P.take 2 (P.drop 11 p))) (leInt (P.take 2 (P.drop 13 p)))
                                  (leInt (P.take 6 p)))
decode _ = Nothing

main :: IO ()
main = do
  let nCyc  = nFrames P.* frameCycles P.+ 12000
      ins   = P.concatMap dvpFrame [0 .. nFrames P.- 1] P.++ P.repeat (DvpIn False False 0)
      obs   = simulateN @System nCyc chain ins
      acc   = L.foldl' step (Acc [] [] [0, 0, 0, 0] 0 False) obs
      frs   = P.reverse (aFrames acc)
      pays  = P.map (udpPayload . fst) frs
      dgs   = [ (word16 p 0, parseRecords (P.drop 2 p)) | Just p <- pays ]
      recs  = P.concat [ rs | (_, Just rs) <- dgs ]
      decs  = [ r | Just r <- P.map decode recs ]
      seqsOf t = [ sq | (t', sq, _) <- recs, t' P.== t ]
      contiguous xs = P.and (P.zipWith (\a b -> b P.== (a P.+ 1) `P.mod` 256) xs (P.tail xs))
                      P.&& (P.null xs P.|| P.head xs P.== 0)
      stampsOf f = [ (f', r) | RStamp f' r <- decs, f' P.== f ]
      centsOf f  = L.sort [ (cx, cy, n) | RCent f' cx cy n _ <- decs, f' P.== f ]
      expected f = L.sort (P.map expectDisc (discs f))
      -- ordering: index of the stamp vs the indices of that frame's centroids
      idxOf p = [ i | (i, r) <- P.zip [0 :: Int ..] decs, p r ]
      stampBefore f = case (idxOf (\r -> case r of RStamp f' _ -> f' P.== f; _ -> False),
                            idxOf (\r -> case r of RCent f' _ _ _ _ -> f' P.== f; _ -> False)) of
        ([s], cs@(_ : _)) -> P.all (P.> s) cs
        _                 -> False
      rtcMono = let rs = [ r | RStamp _ r <- decs ] in P.and (P.zipWith (P.<) rs (P.tail rs))
      totalBytes = P.sum (P.map (P.length . fst) frs)

  putStrLn ("cycles " P.++ show nCyc P.++ ", frames rx " P.++ show (P.length frs)
            P.++ " (" P.++ show totalBytes P.++ " bytes dst..pad), datagrams parsed "
            P.++ show (P.length [ () | (_, Just _) <- dgs ]) P.++ "/" P.++ show (P.length dgs)
            P.++ ", records " P.++ show (P.length recs)
            P.++ ", port drops " P.++ show (aDrops acc) P.++ ", udp drops " P.++ show (aUdp acc))
  P.mapM_ (\f -> putStrLn ("  frame " P.++ show f P.++ ": expect " P.++ show (expected f)
                           P.++ " got " P.++ show (centsOf f))) [0 .. nFrames P.- 1]

  rs <- P.sequence
    [ check (P.not (P.null frs) P.&& P.all snd frs)          "every Ethernet frame received crc ok"
    , check (P.all isJust pays)                              "every frame parses as UDP (IP/UDP checksums verify)"
    , check (P.all (isJust . snd) dgs)                       "every datagram parses to whole records"
    , check (P.map fst dgs P.== [0 .. P.length dgs P.- 1])   "datagram SEQ contiguous from 0"
    , check (contiguous (seqsOf 0x12))                       "STROBE_STAMP SEQ contiguous"
    , check (contiguous (seqsOf 0x20))                       "CENTROID SEQ contiguous"
    , check (P.length (seqsOf 0x12) P.== nFrames)            "one STROBE_STAMP per frame"
    , check (P.length (seqsOf 0x20) P.== 3 P.* nFrames)      "three CENTROIDs per frame"
    , check (P.all (\f -> P.map fst (stampsOf f) P.== [f]) [0 .. nFrames P.- 1]) "stamp seq = frame number 0..4"
    , check (P.all (\f -> centsOf f P.== expected f) [0 .. nFrames P.- 1]) "centroids (cx_q4, cy_q4, count) exact for all 5 frames"
    , check (P.all stampBefore [0 .. nFrames P.- 1])         "each frame's STROBE_STAMP precedes its centroids"
    , check rtcMono                                          "stamp RTC strictly increasing"
    , check (aDrops acc P.== [0, 0, 0, 0])                   "record ports: zero drops"
    , check (aUdp acc P.== 0)                                "UdpTx: zero dropped datagrams"
    , check (P.not (aBlob acc))                              "labeller: no dropped pixels, no label overflow"
    ]
  if P.and rs
    then putStrLn "ALL PASS: chain Dvp->Blob->Records->UdpTx->NetRx" >> exitSuccess
    else exitFailure
