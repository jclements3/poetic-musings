-- IRIG-B generator testbench — the Phase 2 simulation gate (DESIGN.md, Verification #1).
--
--     Run:  cabal test irig-test --test-show-details=direct
--
-- Simulates `irigb` at SNat 1 (10 ticks/ms, so a 1 s frame is 10 000 ticks) and asserts,
-- over 8 full frames after a burn-in frame:
--
--   * every cell is exactly 100 ticks; every frame exactly 100 cells / 10 000 ticks
--   * every cell is high-then-low with high time exactly 20/50/80 ticks (2/5/8 ms)
--   * position markers at cells 9,19,..,89, P0 at 99, P_r at 0, and nothing else;
--     P0 + next P_r are back-to-back (the frame-reference double marker)
--   * structurally-unused cells always encode ZERO
--   * BCD time decodes to the expected schedule, including 59 -> 00 seconds rollover
--     carrying into minutes, and the full 23:59:59 day-366 carry chain
--   * SBS (cells 80-88 + 90-97, LSB first) == hh*3600 + mm*60 + ss every frame
--     (same decoder semantics as MAIDEN/firmware/timebase/tb/timebase_tb.vhd)
--   * set_strobe latches SetVal and applies it at the NEXT frame reference
--   * amOut is exactly the 10-sample 1 kHz sine table, high/low per the envelope (10:3)
--
-- Strobe schedule (raw ticks; frames drift by at most the reset length, strobes sit
-- mid-frame so that slack is harmless):
--
--     tick 25000  set 00:00:58 doy 001   -> frames ..58, ..59, 00:01:00 (minute carry)
--     tick 55000  set 23:59:59 doy 365   -> frames 23:59:59/365, 00:00:00/366, 00:00:01/366

module Main (main) where

import Prelude
import Data.Function (on)
import Data.List (groupBy)
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (Bit, Signed)
import Irig

-- Simulation timing: SNat 1 = 10 ticks per ms
ticksPerMs, ticksPerCell, ticksPerFrame :: Int
ticksPerMs    = 10
ticksPerCell  = 10 * ticksPerMs
ticksPerFrame = 100 * ticksPerCell

nTotal :: Int
nTotal = 92000

setA, setB :: SetVal
setA = SetVal { setSs = (5,8), setMm = (0,0), setHh = (0,0), setDoy = (0,0,1) }
setB = SetVal { setSs = (5,9), setMm = (5,9), setHh = (2,3), setDoy = (3,6,5) }

strobeL :: [Bool]
strobeL = [ i == 25000 || i == 55000 | i <- [0 :: Int ..] ]

setL :: [SetVal]
setL = [ if i < 40000 then setA else setB | i <- [0 :: Int ..] ]

-- (ss, mm, hh, doy) expected per post-burn frame
expectedTimes :: [(Int, Int, Int, Int)]
expectedTimes =
  [ ( 1,  0,  0,   1)
  , ( 2,  0,  0,   1)
  , (58,  0,  0,   1)   -- set A applied at this frame's reference
  , (59,  0,  0,   1)
  , ( 0,  1,  0,   1)   -- seconds 59 -> 00 carried into minutes
  , (59, 59, 23, 365)   -- set B applied here
  , ( 0,  0,  0, 366)   -- full carry chain: day increment, SBS wrap
  , ( 1,  0,  0, 366)
  ]

samples :: [(Bit, Signed 8, Int)]
samples =
  [ (d, a, fromIntegral ix)
  | (d, a, ix) <- C.sampleN @C.System nTotal sig ]
  where
    sig :: C.HiddenClockResetEnable C.System
        => C.Signal C.System (Bit, Signed 8, C.Index 100)
    sig = let (d, a, c) = irigb (C.SNat @1) (C.fromList strobeL) (C.fromList setL)
          in C.bundle (d, a, c)

third :: (a, b, c) -> c
third (_, _, c) = c

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = let (h, t) = splitAt n xs in h : chunksOf n t

-- One run of samples per cell: (cell index, samples during that cell)
type Cell = (Int, [(Bit, Signed 8, Int)])

cellsAfterBurn :: [Cell]
cellsAfterBurn = case break ((== 99) . fst) runsAll of
    (_, r99 : rest) | fst r99 == 99 -> rest
    _ -> error "never saw cell 99 — sequencer dead"
  where
    runsAll = map (\g -> (third (head g), g)) (groupBy ((==) `on` third) samples)

frames :: [[Cell]]
frames = take 8 (chunksOf 100 cellsAfterBurn)

classify :: Cell -> CellClass
classify (ix, ticks)
  | not prefixOk = error ("cell " ++ show ix ++ ": envelope is not high-then-low")
  | otherwise = case hi of
      20 -> CellZero
      50 -> CellOne
      80 -> CellMark
      _  -> error ("cell " ++ show ix ++ ": high for " ++ show hi ++ " ticks, not 20/50/80")
  where
    dcs      = [ d | (d, _, _) <- ticks ]
    hi       = length (filter (== C.high) dcs)
    prefixOk = all (== C.high) (take hi dcs) && all (== C.low) (drop hi dcs)

fieldVal :: [CellClass] -> [Int] -> Int
fieldVal cs offs = sum [ 2 ^ i | (i, pos) <- zip [(0 :: Int) ..] offs, cs !! pos == CellOne ]

decodeTime :: [CellClass] -> (Int, Int, Int, Int)
decodeTime f =
  ( fieldVal f [1..4]   + 10 * fieldVal f [6..8]
  , fieldVal f [10..13] + 10 * fieldVal f [15..17]
  , fieldVal f [20..23] + 10 * fieldVal f [25,26]
  , fieldVal f [30..33] + 10 * fieldVal f [35..38] + 100 * fieldVal f [40,41] )

decodeSbs :: [CellClass] -> Int
decodeSbs f = fieldVal f ([80..88] ++ [90..97])

markerCells, alwaysZeroCells :: [Int]
markerCells     = 0 : [ p * 10 + 9 | p <- [0..9] ]
alwaysZeroCells = [5,14,18,24,27,28,34] ++ [42..48] ++ [50..58]
                  ++ [60..68] ++ [70..78] ++ [98]

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

main :: IO ()
main = do
  let classed = map (map classify) frames      -- forces cell-shape errors too

  putStrLn "== structure: cell and frame timing =="
  r1 <- checkEq "frames captured" (8 :: Int) (length frames)
  r2 <- checkEq "cell length (ticks), all cells"
          [ticksPerCell] (dedup [ length ts | f <- frames, (_, ts) <- f ])
  r3 <- checkEq "cells per frame" [100 :: Int] (dedup (map length frames))
  r4 <- checkEq "frame length (ticks)"
          [ticksPerFrame] (dedup [ sum (map (length . snd) f) | f <- frames ])
  r5 <- checkEq "cell index sequence, every frame"
          [[0 .. 99]] (dedup (map (map fst) frames))

  putStrLn "== markers =="
  r6 <- checkEq "marker positions (P_r, P1..P9, P0), every frame"
          [markerCells]
          (dedup [ [ i | (i, c) <- zip [0 ..] f, c == CellMark ] | f <- classed ])
  r7 <- checkEq "frame reference double marker (P0 ++ P_r), consecutive frames"
          (replicate 7 (CellMark, CellMark))
          [ (last f, head g) | (f, g) <- zip classed (tail classed) ]
  r8 <- checkEq "structurally-unused cells are ZERO, every frame"
          [[CellZero]]
          (dedup [ dedup [ f !! i | i <- alwaysZeroCells ] | f <- classed ])

  putStrLn "== time decode: increments, set latch, rollovers =="
  r9 <- checkEq "(ss,mm,hh,doy) schedule over 8 frames"
          expectedTimes (map decodeTime classed)
  r10 <- checkEq "SBS == hh*3600 + mm*60 + ss, every frame"
          [ h * 3600 + m * 60 + s | (s, m, h, _) <- expectedTimes ]
          (map decodeSbs classed)

  putStrLn "== modulated output =="
  let hiL = C.toList sinHi
      loL = C.toList sinLo
      sliceBad s = let dcs = [ d | (d, _, _) <- s ]
                       ams = [ a | (_, a, _) <- s ]
                   in not (all (== head dcs) dcs)
                      || ams /= (if head dcs == C.high then hiL else loL)
  r11 <- checkEq "amOut carrier per 1 ms slice, frame 0 (bad slices)"
          (0 :: Int)
          (length [ () | (_, ts) <- head frames
                       , s <- chunksOf ticksPerMs ts, sliceBad s ])

  if and [r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11]
    then putStrLn "\nALL PASS: IRIG-B frame structure, timing, rollovers, set latch, AM carrier"
    else putStrLn "\nFAILURES above" >> exitFailure

-- collapse adjacent equals: an all-equal list becomes the singleton it should be
dedup :: Eq a => [a] -> [a]
dedup = foldr (\x acc -> if [x] == take 1 acc then acc else x : acc) []
