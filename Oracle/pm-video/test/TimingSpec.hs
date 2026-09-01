-- Timing-generator testbench.
--
--     Run:  cabal test timing-test --test-show-details=direct
--
-- Simulates `timingGen` and asserts, purely from the parameter record:
--
--   * line length (lineStart spacing) == hTotal, everywhere
--   * frame length (frameStart spacing) == hTotal * vTotal
--   * lines per frame == vTotal
--   * per line: hsync wire is at its asserted level exactly on
--     [hActive+hFrontPorch .. +hSyncWidth-1] and at the idle level
--     everywhere else (width AND polarity AND position)
--   * per frame: vsync wire asserted exactly during its vSyncWidth lines
--     after the vertical front porch
--   * active-area strobe: exactly [0..hActive-1] on lines [0..vActive-1]
--   * toX / toY mirror the sample position within the frame
--
-- for BOTH the real (assumed) panel record `pm1920x480` and the tiny
-- `sim48x12` record -- which deliberately has the opposite hsync
-- polarity, so both wire senses are exercised.

module Main (main) where

import Prelude
import Data.List (foldl')
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import PM.Video.Timing

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

-- collapse adjacent equals: an all-equal list becomes the singleton it should be
dedup :: Eq a => [a] -> [a]
dedup = foldl' (\acc x -> if take 1 (reverse acc) == [x] then acc else acc ++ [x]) []

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = let (h, t) = splitAt n xs in h : chunksOf n t

checkRecord :: String -> VideoTiming -> Int -> IO Bool
checkRecord name vt nFrames = do
  putStrLn ("== " ++ name ++ " ==")
  let hT = fromIntegral (hTotal vt)  :: Int
      vT = fromIntegral (vTotal vt)  :: Int
      hA = fromIntegral (hActive vt) :: Int
      hF = fromIntegral (hFrontPorch vt) :: Int
      hS = fromIntegral (hSyncWidth vt)  :: Int
      vA = fromIntegral (vActive vt) :: Int
      vF = fromIntegral (vFrontPorch vt) :: Int
      vS = fromIntegral (vSyncWidth vt)  :: Int
      total = hT * vT
      n = nFrames * total + hT

      -- sample 0 is dropped: the simulation holds reset for one cycle,
      -- so x=y=0 appears twice before the counters run
      samples = drop 1 (C.sampleN @C.System (n + 1) (timingGen vt))

      -- at reset x=y=0, so sample 0 is a frame start already
      frameIdxs = [ i | (i, s) <- zip [0 :: Int ..] samples, toFrameStart s ]
      lineIdxs  = [ i | (i, s) <- zip [0 :: Int ..] samples, toLineStart s ]
      frame0    = take total samples
      lines0    = chunksOf hT frame0

      hAssertIdx line = [ i | (i, s) <- zip [0 :: Int ..] line
                            , toHSync s == hSyncHigh vt ]
      vAssertIdx      = [ i | (i, s) <- zip [0 :: Int ..] frame0
                            , toVSync s == vSyncHigh vt ]
      activeIdx line  = [ i | (i, s) <- zip [0 :: Int ..] line, toActive s ]

  r1 <- checkEq "frameStart spacing == hTotal*vTotal"
          [total] (dedup (zipWith (-) (tail frameIdxs) frameIdxs))
  r2 <- checkEq "lineStart spacing == hTotal"
          [hT] (dedup (zipWith (-) (tail lineIdxs) lineIdxs))
  r3 <- checkEq "lines per frame == vTotal"
          vT (length lines0)
  r4 <- checkEq "hsync asserted exactly on [hA+hFP .. +hSW-1], every line (position+width+polarity)"
          [[hA + hF .. hA + hF + hS - 1]]
          (dedup (map hAssertIdx lines0))
  r5 <- checkEq "vsync asserted exactly during its lines (position+width+polarity)"
          [(vA + vF) * hT .. (vA + vF + vS) * hT - 1]
          vAssertIdx
  r6 <- checkEq "active strobe == [0..hActive-1] on active lines"
          [[0 .. hA - 1]]
          (dedup (map activeIdx (take vA lines0)))
  r7 <- checkEq "no active strobe on blanking lines"
          [[]]
          (dedup (map activeIdx (drop vA lines0)))
  r8 <- checkEq "toX/toY mirror the sample position (mismatches in frame 0)"
          (0 :: Int)
          (length [ () | (i, s) <- zip [0 :: Int ..] frame0
                       , fromIntegral (toX s) /= i `mod` hT
                         || fromIntegral (toY s) /= i `div` hT ])
  pure (and [r1, r2, r3, r4, r5, r6, r7, r8])

main :: IO ()
main = do
  okSim  <- checkRecord "sim48x12 (60x18 total, hsync active-HIGH, vsync active-LOW)"
              sim48x12 20
  okReal <- checkRecord "pm1920x480 (1950x570 total, syncs active-LOW; ASSUMED panel record)"
              pm1920x480 1
  if okSim && okReal
    then putStrLn "\nALL PASS: line/frame lengths, sync width+position+polarity, active area, counters"
    else putStrLn "\nFAILURES above" >> exitFailure
