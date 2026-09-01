-- Text-console renderer testbench.
--
--     Run:  cabal test render-test --test-show-details=direct
--
-- Simulates `textConsole` on the tiny `sim48x32` record (6 cols x 2 rows
-- of 8x16 characters; 64x40 = 2560 clocks per frame), writes "PM" at
-- character (row 0, col 0)/(row 0, col 1) through the CPU write port,
-- renders one complete post-write frame into a Haskell frame buffer, and
-- asserts:
--
--   * the frame has exactly 48x32 DE pixels, 48 per active line, none on
--     blanking lines
--   * pixel-exact equality of the whole frame against the font table:
--     the 'P' glyph at pixels x 0-7, 'M' at x 8-15 (y 0-15), everything
--     else background
--   * the 'P' and 'M' glyph rows against HARD-CODED byte patterns
--     (0xFC / 0xFE rows of the IBM VGA font), so a blank or shifted
--     font table cannot self-validate
--   * every lit pixel lies inside the two character cells, and the lit
--     count equals the two glyphs' popcount
--   * pipeline alignment: the first DE pixel of every line equals
--     column 0, glyph pixel 0 of that line's character row, and the
--     whole DE/HSYNC/VSYNC/strobe stream equals the raw timing
--     generator's output delayed by exactly 2 cycles
--   * the cursor register reads back what was written (iTFT contract)

module Main (main) where

import Prelude
import Data.Bits (popCount, testBit)
import Data.Maybe (fromMaybe)
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (BitVector, Unsigned)

import PM.Video.Timing
import PM.Video.Font (glyphRow)
import PM.Video.TextConsole

vt :: VideoTiming
vt = sim48x32

hT, vT, hA, vA, frameLen :: Int
hT = fromIntegral (hTotal vt)
vT = fromIntegral (vTotal vt)
hA = fromIntegral (hActive vt)
vA = fromIntegral (vActive vt)
frameLen = hT * vT

nTotal :: Int
nTotal = 4 * frameLen

-- CPU stimulus: write 'P' (0,0) and 'M' (0,1) on cycles 1-2, set the
-- cursor to (1,5), then idle.
writes :: [Maybe CharWrite]
writes = [ Nothing
         , Just (CharWrite 0 0 0x50)   -- 'P'
         , Just (CharWrite 0 1 0x4D)   -- 'M'
         , Just (CharWrite 31 200 0x58)  -- out-of-range row: must be ignored
         ] ++ repeat Nothing

cursorSets :: [Maybe (Unsigned 5, Unsigned 8)]
cursorSets = [Nothing, Just (1, 5)] ++ repeat Nothing

samples :: [(PixelOut, (Unsigned 5, Unsigned 8), TimingOut)]
samples = C.sampleN @C.System nTotal sig
  where
    sig :: C.HiddenClockResetEnable C.System
        => C.Signal C.System (PixelOut, (Unsigned 5, Unsigned 8), TimingOut)
    sig = C.bundle (pix, cur, timingGen vt)
      where (pix, cur) = textConsole vt (C.fromList writes) (C.fromList cursorSets)

pixs :: [PixelOut]
pixs = [ p | (p, _, _) <- samples ]

-- The frame between the 2nd and 3rd (2-cycle-delayed) frame strobes:
-- fully after the CPU writes have landed.
frame :: [PixelOut]
frame = case [ i | (i, p) <- zip [0 ..] pixs, poFrame p ] of
  (_ : f1 : f2 : _) -> take (f2 - f1) (drop f1 pixs)
  _                 -> error "fewer than 3 frame strobes seen"

-- Expected pixel from the font table: what character cell (x,y) falls in.
charAt :: Int -> Int -> BitVector 8
charAt row col | row == 0 && col == 0 = 0x50
               | row == 0 && col == 1 = 0x4D
               | otherwise            = 0x20
expected :: Int -> Int -> Bool
expected x y = testBit row (7 - (x `mod` 8))
  where row = glyphRow (charAt (y `div` 16) (x `div` 8)) (fromIntegral (y `mod` 16))

-- Frame buffer: DE pixels of each line, split on the line strobes.
frameLines :: [[Bool]]
frameLines = [ [ poPixel p | p <- ln, poDe p ] | ln <- chunksOf hT frame ]

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = let (h, t) = splitAt n xs in h : chunksOf n t

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

render :: [Bool] -> String
render = map (\b -> if b then '#' else '.')

main :: IO ()
main = do
  let fb = frameLines

  putStrLn "== frame structure =="
  r1 <- checkEq "frame length (clocks)" frameLen (length frame)
  r2 <- checkEq "DE pixels per active line" [hA] (dedup (map length (take vA fb)))
  r3 <- checkEq "DE pixels on blanking lines" [0] (dedup (map length (drop vA fb)))
  r4 <- checkEq "total DE pixels" (hA * vA) (sum (map length fb))

  putStrLn "== glyph pixels: \"PM\" at (0,0), font-table golden =="
  let golden = [ [ expected x y | x <- [0 .. hA - 1] ] | y <- [0 .. vA - 1] ]
      diffs  = [ (x, y) | (y, (gl, rl)) <- zip [0 :: Int ..] (zip golden (take vA fb))
                        , (x, (g, r))   <- zip [0 :: Int ..] (zip gl rl), g /= r ]
  r5 <- checkEq "pixel-exact frame vs font table (mismatching (x,y))" [] (take 20 diffs)

  putStrLn "  rendered 16x16 corner:"
  mapM_ (putStrLn . ("    " ++) . render . take 16) (take 16 fb)

  putStrLn "== hard-coded IBM-VGA glyph rows (font cannot self-validate) =="
  -- 'P' rows 0-15 of the IBM VGA 8x16 font: 00 00 fc 66 66 66 7c 60 60 60 60 f0 00 00 00 00
  -- 'M' rows 0-15:                          00 00 c6 ee fe fe d6 c6 c6 c6 c6 c6 00 00 00 00
  let pWant = [0x00,0x00,0xfc,0x66,0x66,0x66,0x7c,0x60,0x60,0x60,0x60,0xf0,0x00,0x00,0x00,0x00] :: [Int]
      mWant = [0x00,0x00,0xc6,0xee,0xfe,0xfe,0xd6,0xc6,0xc6,0xc6,0xc6,0xc6,0x00,0x00,0x00,0x00] :: [Int]
      rowBits v = [ testBit (v :: Int) (7 - i) | i <- [0 .. 7] ]
  r6 <- checkEq "rendered 'P' cell (x 0-7, y 0-15) == hard-coded bytes"
          (map rowBits pWant)
          [ take 8 ln | ln <- take 16 fb ]
  r7 <- checkEq "rendered 'M' cell (x 8-15, y 0-15) == hard-coded bytes"
          (map rowBits mWant)
          [ take 8 (drop 8 ln) | ln <- take 16 fb ]

  putStrLn "== background =="
  let lit = [ (x, y) | (y, ln) <- zip [0 :: Int ..] fb, (x, b) <- zip [0 :: Int ..] ln, b ]
  r8 <- checkEq "every lit pixel inside the two cells (x<16, y<16)"
          [] (take 20 (filter (\(x, y) -> x >= 16 || y >= 16) lit))
  r9 <- checkEq "lit pixel count == popcount of the two glyphs"
          (sum (map popCount pWant) + sum (map popCount mWant))
          (length lit)

  putStrLn "== pipeline alignment (2-cycle latency) =="
  let firstDe ln = fmap fst (safeHead [ (poPixel p, ()) | p <- ln, poDe p ])
      safeHead (a : _) = Just a
      safeHead []      = Nothing
  r10 <- checkEq "first DE pixel of every active line == column 0, glyph pixel 0"
          [ expected 0 y | y <- [0 .. vA - 1] ]
          [ fromMaybe (error "line without DE") (firstDe ln)
          | ln <- take vA (chunksOf hT frame) ]
  -- Sample-by-sample: every timing field of the pixel stream equals the
  -- bare timing generator's output two cycles earlier.  The first three
  -- samples are skipped: two are the pipeline fill, and sample 2 still
  -- carries the simulation's 1-cycle reset flush of the delay registers.
  let tOuts   = [ t | (_, _, t) <- samples ]
      delayed = replicate 2 (timingIdle vt) ++ tOuts
      mism    = length [ () | (p, t) <- drop 3 (zip pixs delayed)
                            , poDe p /= toActive t || poHSync p /= toHSync t
                              || poVSync p /= toVSync t || poLine p /= toLineStart t
                              || poFrame p /= toFrameStart t ]
  r11 <- checkEq "DE/HSYNC/VSYNC/strobes == timingGen delayed exactly 2 cycles (mismatches)"
          (0 :: Int) mism

  putStrLn "== cursor register (iTFT readback) =="
  let (_, curEnd, _) = last samples
  r12 <- checkEq "cursor reads back (1,5)" (1, 5) curEnd

  if and [r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12]
    then putStrLn "\nALL PASS: frame structure, exact PM glyph pixels, background, 2-cycle alignment, cursor"
    else putStrLn "\nFAILURES above" >> exitFailure

dedup :: Eq a => [a] -> [a]
dedup = foldr (\x acc -> if [x] == take 1 acc then acc else x : acc) []
