-- PM.Dvp / PM.Blob proofs:
--  1. Dvp: a synthetic 640x400 frame (VSYNC pulse, 400 HREF lines of 640 px,
--     2-cycle line gaps) yields exactly 256000 pixels, x/y in raster order,
--     one sof, 400 eol, one eof; the sequence counter advances once per frame.
--  2. threshold hysteresis: a value between thr-hyst and thr keeps the previous
--     pixel's state, below thr-hyst always off, at/above thr always on.
--  3. Blob: the frames of golden/vectors.txt (written by golden/blob_model.py)
--     are rendered as Dvp pixel streams and labelled; the records (sorted by
--     bbox) must match the golden ones in count and bbox, with centroids within
--     0.25 px (4 Q4 units):  (a) one disc  (b) five discs  (c) a 2-px speck
--     below min area is rejected  (d) two discs touching diagonally merge.
--  4. two frames back to back: the second frame's records are still right
--     (state reset at sof, line buffer not cleared but ignored on y = 0).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Maybe (catMaybes)
import PM.Dvp
import PM.Blob
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- ---------------------------------------------------------------------------
-- DVP stimulus: a frame as a pixel predicate.

type Frame = [(Int, Int)]                 -- foreground pixels (x, y)
type Golden = (Int, Int, Int, Int, Int, Int, Int)   -- count cx cy x0 x1 y0 y1

-- | Bus samples for one frame: VSYNC 3 cycles, then 400 lines of 640 HREF
-- samples separated by 2 idle cycles.
dvpFrame :: (Int -> Int -> Unsigned 8) -> [DvpIn]
dvpFrame val =
  P.replicate 3 (DvpIn False True 0) P.++
  P.concat [ [ DvpIn True False (val x y) | x <- [0 .. 639] ] P.++ P.replicate 2 (DvpIn False False 0)
           | y <- [0 .. 399] ]

-- | Rows of the frame as sorted x lists, for an O(1)-ish membership test.
rowSets :: Frame -> Int -> Int -> Unsigned 8
rowSets fg = \x y -> if P.any (== x) (rowsOf y) then 255 else 0
 where
  rows = L.foldl' (\m (x, y) -> P.take y m P.++ [x : (m P.!! y)] P.++ P.drop (y + 1) m)
                  (P.replicate 400 []) fg
  rowsOf y = rows P.!! y

-- | Run capture + labeller over a bus sample list; returns pixels and blob outputs.
runPipeline :: BlobCfg -> [DvpIn] -> ([Maybe Pix], [BlobOut])
runPipeline cfg ins = (pixs, outs)
 where
  n = P.length ins P.+ 1500          -- eof phases: <= 1088 cycles
  pad = ins P.++ P.repeat (DvpIn False False 0)
  pixs = P.take n (simulate @System (fst . dvpCapture) pad)
  outs = simulateN @System n (\i -> let (c, p) = unbundle i in blobLabel c p)
           (P.zip (P.repeat cfg) pixs)

records :: [BlobOut] -> [BlobRec]
records = catMaybes . P.map boRec

toTuple :: BlobRec -> Golden
toTuple r = ( fromIntegral (bCount r), fromIntegral (bCx r), fromIntegral (bCy r)
            , fromIntegral (bX0 r), fromIntegral (bX1 r), fromIntegral (bY0 r), fromIntegral (bY1 r) )

sortRecs :: [Golden] -> [Golden]
sortRecs = L.sortOn (\(_, _, _, x0, _, y0, _) -> (y0, x0))

-- | Compare hardware records with golden: same count/bbox, centroid within 4 Q4.
matchRecs :: [Golden] -> [Golden] -> (Bool, [(Int, Int)])
matchRecs hw gold = (P.length hw == P.length gold && P.and oks, errs)
 where
  pairs = P.zip (sortRecs hw) (sortRecs gold)
  cmp (n, cx, cy, x0, x1, y0, y1) (n', cx', cy', x0', x1', y0', y1') =
    ( n == n' && (x0, x1, y0, y1) == (x0', x1', y0', y1')
      && abs (cx - cx') <= 4 && abs (cy - cy') <= 4
    , (cx - cx', cy - cy') )
  (oks, errs) = P.unzip (P.map (P.uncurry cmp) pairs)

-- ---------------------------------------------------------------------------
-- golden/vectors.txt parser

parseVectors :: P.String -> [(P.String, Int, Int, Frame, [Golden])]
parseVectors = go . P.map P.words . P.lines
 where
  go [] = []
  go (("frame" : name : mn : mx : _) : rest) =
    let (body, rest') = P.break (== ["end"]) rest
        px = [ (P.read a, P.read b) | ["px", a, b] <- body ]
        rs = [ (P.read n, P.read cx, P.read cy, P.read x0, P.read x1, P.read y0, P.read y1)
             | ["rec", n, cx, cy, x0, x1, y0, y1] <- body ]
    in (name, P.read mn, P.read mx, px, rs) : go (P.drop 1 rest')
  go (_ : rest) = go rest

main :: IO ()
main = do
  -- 1. DVP capture on an all-zero frame
  let ins1 = dvpFrame (\_ _ -> 0)
      pixs1 = catMaybes (P.take (P.length ins1) (simulate @System (fst . dvpCapture) (ins1 P.++ P.repeat (DvpIn False False 0))))
      seqs = P.take (P.length ins1 P.* 2) (simulate @System (snd . dvpCapture) (ins1 P.++ ins1 P.++ P.repeat (DvpIn False False 0)))
      expectXY = [ (fromIntegral x, fromIntegral y) | y <- [0 :: Int .. 399], x <- [0 :: Int .. 639] ]
  r1 <- check (P.length pixs1 == 256000) ("dvp: 256000 pixels (" P.++ P.show (P.length pixs1) P.++ ")")
  r2 <- check (P.map (\p -> (pX p, pY p)) pixs1 == expectXY) "dvp: x/y in raster order"
  r3 <- check (P.length (P.filter pSof pixs1) == 1 && P.length (P.filter pEof pixs1) == 1
               && P.length (P.filter pEol pixs1) == 400) "dvp: one sof, one eof, 400 eol"
  r4 <- check (P.last seqs == 2 && P.head seqs == 0) ("dvp: sequence counter 0 -> 2 over two frames (" P.++ P.show (P.last seqs) P.++ ")")
  -- 2. hysteresis
  let th = (100, 10, 95)
  r5 <- check (thresholdT True th && not (thresholdT False th)) "threshold: band keeps previous state"
  r6 <- check (not (thresholdT True (100, 10, 89)) && thresholdT False (100, 10, 100)) "threshold: below band off, at thr on"
  -- 3. golden frames
  txt <- P.readFile "golden/vectors.txt"
  let vecs = parseVectors txt
  rs <- P.mapM (\(name, mn, mx, fg, gold) -> do
          let cfg = BlobCfg 128 0 (fromIntegral mn) (fromIntegral mx)
              (_, outs) = runPipeline cfg (dvpFrame (rowSets fg))
              hw = P.map toTuple (records outs)
              (ok, errs) = matchRecs hw gold
              maxErr = if P.null errs then 0 else P.maximum (P.map (\(a, b) -> max (abs a) (abs b)) errs)
              dones = P.length (P.filter boFrameDone outs)
          check (ok && dones == 1 && not (P.any boOverflow outs) && not (P.any boDropped outs))
                ("blob " P.++ name P.++ ": " P.++ P.show (P.length hw) P.++ "/" P.++ P.show (P.length gold)
                 P.++ " records, max centroid error " P.++ P.show maxErr P.++ "/16 px, frame_done="
                 P.++ P.show dones P.++ (if ok then "" else " hw=" P.++ P.show (sortRecs hw) P.++ " gold=" P.++ P.show (sortRecs gold))))
        vecs
  -- 4. two frames back to back (frame b then frame a)
  let (_, _, _, fgA, goldA) = P.head [ v | v@("a", _, _, _, _) <- vecs ]
      (_, _, _, fgB, _)     = P.head [ v | v@("b", _, _, _, _) <- vecs ]
      cfg = BlobCfg 128 0 20 200
      (_, outs2) = runPipeline cfg (dvpFrame (rowSets fgB) P.++ P.replicate 1200 (DvpIn False False 0) P.++ dvpFrame (rowSets fgA))
      recs2 = P.map toTuple (records outs2)
      second = P.drop 5 recs2
  r7 <- check (P.length recs2 == 6 && fst (matchRecs second goldA) && not (P.any boDropped outs2))
          ("blob: second frame after a five-disc frame (" P.++ P.show (P.length recs2) P.++ " records total)")
  if P.and ([r1, r2, r3, r4, r5, r6, r7] P.++ rs)
    then putStrLn "ALL PASS: PM.Dvp PM.Blob" >> exitSuccess
    else exitFailure
