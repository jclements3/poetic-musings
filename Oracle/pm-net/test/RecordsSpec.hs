-- PM.Records proof: (1) framer bytes against hand-computed PROTOCOL.md
-- vectors for 0x10/0x11/0x12/0x20; (2) the whole N=4 path (ports -> mux ->
-- BRAM FIFO -> datagram packer) driven with bursts of simultaneous fires,
-- its DgByte stream carved into datagrams by first/last flags and every
-- datagram parsed back into records in plain Haskell (SYNC, TYPE-implied
-- length, checksum sums to 0) — intact records prove the mux never
-- interleaves, per-type SEQ must be +1 monotone, every fired payload must
-- come back byte-exact and in order, and datagrams must end (a) at the size
-- limit, (b) on a timeout tick, (c) on a TIME_MARK.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Maybe (isJust, mapMaybe)
import PM.Records
import System.Exit (exitFailure, exitSuccess)

-- ---------------------------------------------------------------------------

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ name)
  P.return ok

bytes :: KnownNat n => Vec n (BitVector 8) -> [Int]
bytes = P.map (P.fromIntegral . toInteger) . toList

-- Independent record parser: returns (type, seq, payload) list or Nothing on
-- any framing/checksum error or trailing garbage.  Lengths per PROTOCOL.md.
payloadLen :: Int -> Maybe Int
payloadLen t = P.lookup t [(0x01, 9), (0x04, 12), (0x10, 4), (0x11, 10), (0x12, 9), (0x20, 16)]

parseRecords :: [Int] -> Maybe [(Int, Int, [Int])]
parseRecords [] = Just []
parseRecords (0xA5 : t : sq : rest) = do
  n <- payloadLen t
  let (p, rest') = P.splitAt n rest
  case rest' of
    (ck : rest'')
      | P.length p P.== n
      , (0xA5 P.+ t P.+ sq P.+ P.sum p P.+ ck) `P.mod` 256 P.== 0
      -> ((t, sq, p) :) P.<$> parseRecords rest''
    _ -> Nothing
parseRecords _ = Nothing

-- Stimulus: sparse (cycle, payload) list -> infinite Maybe stream.
evAt :: [(Int, a)] -> [Maybe a]
evAt evs = [ P.lookup i evs | i <- [0 ..] ]

-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  -- Hand-computed vectors (checksum by hand, verified again by parseRecords).
  let vPps = ppsStatusRecord 0x05 (PpsStatus (-3) 0b101)
      ePps = [0xA5, 0x10, 0x05, 0xFD, 0xFF, 0xFF, 0x05, 0x46]
      vTm  = timeMarkRecord 0x7F (TimeMark 0x0123_4567_89AB 86399 365)
      eTm  = [0xA5, 0x11, 0x7F, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, 0x7F, 0x51, 0xDB, 0x02, 0x1A]
      vSs  = strobeStampRecord 0x00 (StrobeStamp 0xFFFF_FFFF_FFFF 0x1234 True)
      eSs  = [0xA5, 0x12, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x34, 0x12, 0x01, 0x08]
      vCe  = centroidRecord 0xFE (Centroid 0x100 2 7 0x1234 0xABCD 0xFF 0x80)
      eCe  = [0xA5, 0x20, 0xFE, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x07
             , 0x34, 0x12, 0xCD, 0xAB, 0xFF, 0x00, 0x80, 0xF6]

  -- Path stimulus.
  let cyc4 = [10, 6500, 6600, 6700]           -- all four ports fire together (ports are one-deep: 55 mux cycles per burst)
      ppsEv = [ (c, PpsStatus (P.fromIntegral c) 1) | c <- cyc4 ] P.++ [(5000, PpsStatus 0 0b111)]
      tmEv  = [ (c, TimeMark (P.fromIntegral c P.* 1000) (P.fromIntegral c) 1) | c <- cyc4 ]
      ssEv  = [ (c, StrobeStamp (P.fromIntegral c) (P.fromIntegral c) False) | c <- cyc4 ]
              P.++ [ (c, StrobeStamp (P.fromIntegral c) (P.fromIntegral c) True) | c <- [7000, 7020 .. 7300] ]
      ceEv  = [ (c, Centroid (P.fromIntegral c) (P.fromIntegral c) 1 2 3 4 5) | c <- cyc4 ]
              P.++ [ (c, Centroid (P.fromIntegral c) (P.fromIntegral k) (P.fromIntegral k) 100 200 300 0)
                   | (k, c) <- P.zip [0 :: Int ..] [100, 130 .. 2470 :: Int] ]
      ticks = [ i `P.elem` [3000, 4500, 6000, 9000 :: Int] | i <- [0 ..] ]
      nCyc  = 10000

      outSig = withClockResetEnable @System clockGen resetGen enableGen
                 (let (o, q, l, ds) = recordPath4 (fromList (evAt ppsEv)) (fromList (evAt tmEv))
                                                  (fromList (evAt ssEv)) (fromList (evAt ceEv))
                                                  (fromList ticks)
                  in bundle (o, q, l, bundle ds))
      samples = sampleN @System nCyc outSig
      stream  = [ (i, db) | (i, (Just db, _, _, _)) <- P.zip [0 :: Int ..] samples ]
      drops   = case P.last samples of (_, _, _, ds) -> P.map (P.fromIntegral . toInteger) (toList ds) :: [Int]

      -- carve datagrams by flags: each starts with dbFirst and ends with dbLast
      carve [] = []
      carve ss = let (dg, rest) = L.break (dbLast . snd) ss
                 in case rest of
                      (l : rest') -> (dg P.++ [l]) : carve rest'
                      []          -> [dg]        -- unterminated tail (should not happen)
      dgs = carve stream
      dgOk dg = P.not (P.null dg) P.&& dbFirst (snd (P.head dg)) P.&& dbLast (snd (P.last dg))
                P.&& P.all (P.not . dbFirst . snd) (P.tail dg)
                P.&& P.all (P.not . dbLast . snd) (P.init dg)
                P.&& P.and (P.zipWith (\(a, _) (b, _) -> b P.== a P.+ 1) dg (P.tail dg))  -- contiguous
      dgBytes dg = P.map (P.fromIntegral . toInteger . dbData . snd) dg :: [Int]
      dgSeq  bs = P.head bs P.* 256 P.+ bs P.!! 1
      dgRecs bs = parseRecords (P.drop 2 bs)
      allBs   = P.map dgBytes dgs
      parsed  = P.map dgRecs allBs
      recs    = P.concat (mapMaybe id parsed)
      lastTy  = P.map (\rs -> if P.null rs then Nothing else Just (let (t, _, _) = P.last rs in t))
                      (mapMaybe id parsed)
      ofType t = [ (sq, p) | (t', sq, p) <- recs, t' P.== t ]
      monotone xs = P.and (P.zipWith (\a b -> b P.== (a P.+ 1) `P.mod` 256) xs (P.tail xs))
                    P.&& (P.null xs P.|| P.head xs P.== 0)
      firedPayloads enc evs = P.map (bytes . enc . snd) (L.sortOn fst evs)

      -- datagrams: the one holding a TIME_MARK must end with it
      tmDgs = [ rs | Just rs <- parsed, P.any (\(t, _, _) -> t P.== 0x11) rs ]
      tmEndsDg = P.all (\rs -> let (t, _, _) = P.last rs in t P.== 0x11) tmDgs
      -- the lone PPS_STATUS at 5000 flushed by the tick at 6000: a 10-byte datagram
      loneDg = P.any (\bs -> P.length bs P.== 10 P.&& bs P.!! 3 P.== 0x10) allBs
      -- size-limit flush: at least one datagram in (1380, 1400]
      bigDg  = P.any (\bs -> P.length bs P.> 1380 P.&& P.length bs P.<= 1400) allBs
      -- ticks at 3000 (latched during the 1395-cycle send) / 4500: a datagram
      -- shorter than the size limit that ends with a centroid
      tickCe = P.any (\bs -> let n = P.length bs in n P.>= 22 P.&& n P.< 1380 P.&& bs P.!! (n P.- 19) P.== 0x20
                               P.&& bs P.!! (n P.- 20) P.== 0xA5) allBs

  putStrLn ("datagrams: " P.++ show (P.length dgs) P.++ " lengths " P.++ show (P.map P.length allBs)
            P.++ ", records " P.++ show (P.length recs) P.++ ", drops " P.++ show drops)
  rs <- P.sequence
    [ check "PPS_STATUS framer bytes"             (bytes vPps P.== ePps)
    , check "TIME_MARK framer bytes"              (bytes vTm  P.== eTm)
    , check "STROBE_STAMP framer bytes"           (bytes vSs  P.== eSs)
    , check "CENTROID framer bytes"               (bytes vCe  P.== eCe)
    , check "vectors parse with checksum 0"       (P.all (isJust . parseRecords) [ePps, eTm, eSs, eCe])
    , check "stream carves into flagged datagrams" (P.not (P.null dgs) P.&& P.all dgOk dgs)
    , check "datagram seq prefix monotone from 0" (P.map dgSeq allBs P.== [0 .. P.length allBs P.- 1])
    , check "datagram payload <= 1400"            (P.all ((P.<= 1400) . P.length) allBs)
    , check "every datagram parses to whole records" (P.all isJust parsed)
    , check "no producer drops"                   (drops P.== [0, 0, 0, 0])
    , check "record count = fires"                (P.length recs P.== P.length ppsEv P.+ P.length tmEv
                                                                     P.+ P.length ssEv P.+ P.length ceEv)
    , check "PPS_STATUS SEQ monotone"             (monotone (P.map fst (ofType 0x10)))
    , check "TIME_MARK SEQ monotone"              (monotone (P.map fst (ofType 0x11)))
    , check "STROBE_STAMP SEQ monotone"           (monotone (P.map fst (ofType 0x12)))
    , check "CENTROID SEQ monotone"               (monotone (P.map fst (ofType 0x20)))
    , check "PPS_STATUS payloads byte-exact, in order"
        (P.map snd (ofType 0x10) P.== firedPayloads ppsStatusPayload ppsEv)
    , check "TIME_MARK payloads byte-exact, in order"
        (P.map snd (ofType 0x11) P.== firedPayloads timeMarkPayload tmEv)
    , check "STROBE_STAMP payloads byte-exact, in order"
        (P.map snd (ofType 0x12) P.== firedPayloads strobeStampPayload ssEv)
    , check "CENTROID payloads byte-exact, in order"
        (P.map snd (ofType 0x20) P.== firedPayloads centroidPayload ceEv)
    , check "flush on TIME_MARK (TM is last in its datagram)" (P.length tmDgs P.== 4 P.&& tmEndsDg)
    , check "flush on timeout (lone 10-byte datagram)" loneDg
    , check "flush on timeout mid-burst (ends on centroid)" tickCe
    , check "flush at size limit (1380 < len <= 1400)" bigDg
    , check "datagram lengths never split a record"  (P.all (\bs -> (P.length bs P.- 2) P.>= 0) allBs P.&& P.all isJust parsed)
    , check "last record type known in every datagram" (P.all isJust lastTy)
    ]
  if P.and rs
    then putStrLn "ALL PASS: PM.Records" >> exitSuccess
    else exitFailure
