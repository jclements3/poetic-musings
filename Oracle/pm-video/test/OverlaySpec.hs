-- Overlay-strip testbench.
--
--     Run:  cabal test overlay-test --test-show-details=direct
--
-- Simulates `overlayStrip` on a 520x140 active / 532x146 total record
-- (big enough to hold the 480x120 strip with a margin on every side),
-- drives the CPU port with a scripted sequence -- clear, a bar, a
-- single pixel, an origin move, a pixel erase, a clear -- and renders
-- each subsequent frame into a Haskell set of lit (x, y), asserting:
--
--   * a bar `OvColumn 10 50` lights exactly 50 pixels, all in column 10,
--     rows 70..119 (bottom-up), and nothing else
--   * `OvPlot 100 5 1` adds exactly that pixel
--   * moving the origin to (20, 10) shifts every lit pixel by (20, 10)
--   * `OvPlot 10 119 0` erases the bottom pixel of the bar
--   * `OvClear` empties the strip
--   * in every frame no pixel outside the strip region is ever on, and
--     nothing is on during blanking
--   * the clear sweep holds busy for exactly 480 cycles, the pixel RMW
--     for 2, and a column write for 0
--   * `ooOn` is aligned 2 cycles after the timing sample (same latency
--     as the text console)

module Main (main) where

import Prelude
import Data.List (sort)
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (Unsigned)

import PM.Video.Timing
import PM.Video.Overlay

vt :: VideoTiming
vt = VideoTiming
  { hActive = 520, hFrontPorch = 2, hSyncWidth = 4, hBackPorch = 6  -- 532
  , vActive = 140, vFrontPorch = 1, vSyncWidth = 2, vBackPorch = 3  -- 146
  , hSyncHigh = False, vSyncHigh = False
  }

hT, hA, vA, frameLen, nFrames, nTotal, lat :: Int
hT = fromIntegral (hTotal vt)
hA = fromIntegral (hActive vt)
vA = fromIntegral (vActive vt)
frameLen = hT * fromIntegral (vTotal vt)
nFrames = 6
lat = 2                        -- pipeline latency, timing sample -> ooOn
nTotal = nFrames * frameLen + lat + 1

-- CPU script, by cycle: the clear at cycle 1, then one op in the
-- vertical blanking of frame k (so frame k+1 shows it whole).
blank :: Int -> Int
blank k = k * frameLen + vA * hT + 5

ops :: [Maybe OverlayOp]
ops = [ at i | i <- [0 .. nTotal - 1] ]
 where
  at i | i == 1       = Just OvClear
       | i == blank 0 = Just (OvColumn 10 50)
       | i == blank 1 = Just (OvPlot 100 5 1)
       | i == blank 3 = Just (OvPlot 10 119 0)
       | i == blank 4 = Just OvClear
       | otherwise    = Nothing

origins :: [Maybe (Unsigned 12, Unsigned 12)]
origins = [ if i == blank 2 then Just (20, 10) else Nothing | i <- [0 .. nTotal - 1] ]

-- origin in force while frame k is scanned
originOf :: Int -> (Int, Int)
originOf k | k >= 3    = (20, 10)
           | otherwise = (0, 0)

-- cycle-indexed (cycle 0 is the reset sample, so timing x=y=0 twice)
rawSamples :: [(TimingOut, OverlayOut)]
rawSamples = C.sampleN @C.System (nTotal + 1) sig
  where
    sig :: C.HiddenClockResetEnable C.System
        => C.Signal C.System (TimingOut, OverlayOut)
    sig = C.bundle (t, overlayStrip (C.fromList ops) (C.fromList origins) t)
      where t = timingGen vt

-- sample i is timing position i within the frame sequence
samples :: [(TimingOut, OverlayOut)]
samples = drop 1 rawSamples

-- ooOn at sample i+lat describes timing sample i.
onAt :: [Bool]
onAt = drop lat (map (ooOn . snd) samples)

-- lit (x, y) of frame k, including any blanking-time assertions as
-- out-of-range coordinates
litIn :: Int -> [(Int, Int)]
litIn k = sort [ (i `mod` hT, (i `div` hT) `mod` fromIntegral (vTotal vt))
               | (i, b) <- zip [k * frameLen .. (k + 1) * frameLen - 1] (drop (k * frameLen) onAt)
               , b ]

inStrip :: (Int, Int) -> (Int, Int) -> Bool
inStrip (ox, oy) (x, y) = x >= ox && x < ox + 480 && y >= oy && y < oy + 120
                          && x < hA && y < vA

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

main :: IO ()
main = do
  let bar      = sort [ (10, y) | y <- [70 .. 119] ]
      barPix   = sort ((100, 5) : bar)
      shifted  = sort [ (x + 20, y + 10) | (x, y) <- barPix ]
      erased   = filter (/= (30, 129)) shifted

  putStrLn "== column bar, pixel plot, origin move, erase, clear =="
  r1 <- checkEq "frame 1: OvColumn 10 50 -> exactly the 50 pixels (10, 70..119)" bar (litIn 1)
  r1b <- checkEq "frame 1: lit count" (50 :: Int) (length (litIn 1))
  r2 <- checkEq "frame 2: + OvPlot 100 5 1" barPix (litIn 2)
  r3 <- checkEq "frame 3: origin (20,10) shifts every pixel" shifted (litIn 3)
  r4 <- checkEq "frame 4: OvPlot 10 119 0 erases the bar's bottom pixel" erased (litIn 4)
  r5 <- checkEq "frame 5: OvClear empties the strip" [] (litIn 5)

  putStrLn "== containment =="
  let outside = [ (k, p) | k <- [1 .. nFrames - 1], p <- litIn k, not (inStrip (originOf k) p) ]
  r6 <- checkEq "pixels outside the strip region / in blanking, frames 1-5" [] (take 10 outside)

  putStrLn "== busy =="
  -- busy rises the cycle after the op is accepted
  let busy = map (ooBusy . snd) rawSamples
      busyRun from = length (takeWhile id (drop from busy))
  r7 <- checkEq "OvClear busy for 480 cycles" 480 (busyRun 2)
  r8 <- checkEq "OvColumn busy for 0 cycles"  0   (busyRun (blank 0 + 1))
  r9 <- checkEq "OvPlot busy for 2 cycles"    2   (busyRun (blank 1 + 1))

  putStrLn "== alignment =="
  -- with a 1-cycle-off pairing the bar would land in column 9 or 11
  let misaligned d = [ () | (i, b) <- zip [frameLen ..] (drop (frameLen + lat + d) (map (ooOn . snd) samples))
                          , b, i `mod` hT /= 10 ]
  r10 <- checkEq "bar column is 10 only under the 2-cycle pairing (mismatches at +1/-1)"
           (False, False) (null (take 1 (misaligned 1)), null (take 1 (misaligned (-1))))

  if and [r1, r1b, r2, r3, r4, r5, r6, r7, r8, r9, r10]
    then putStrLn "\nALL PASS: overlay bar/plot/origin/erase/clear, containment, busy, 2-cycle alignment"
    else putStrLn "\nFAILURES above" >> exitFailure
