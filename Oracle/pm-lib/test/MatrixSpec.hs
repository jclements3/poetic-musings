-- PM.Matrix testbench — the 0x4024 contract in closed-loop simulation.
--
--     Run:  cabal test matrix-test --test-show-details=direct
--
-- The scanner runs against a simulated switch matrix (strobed row's pressed
-- keys pull their columns low, diode-per-switch so any chord is legal) with
-- bounce injected at the raw-switch level.  Scenarios, at sim timing
-- (10 ticks/row -> 80-tick scan pass; debounce threshold 10 passes, the
-- 10 ms norm with 1 pass = 1 ms):
--
--   A  bouncy press + bouncy release of one key -> exactly one down and one
--      up event, correct keycode; row strobes are one-hot active-low,
--      visit all 8 rows, 10 ticks each
--   B  a 5-pass (= 5 ms) glitch -> no event at all
--   C  keycodes per the LAYOUT fold (A0=0, G7=48, P0=49, P9=58) pressed in
--      sequence, then released together -> presses pop in press order; all
--      four releases arrive, and the same-row pair (48, 49) pops in column
--      order.  (Across rows, completion order depends on scan phase at the
--      release instant — a key whose row was sampled just after the edge
--      finishes its 10 samples a pass early.  Real scanner behaviour.)
--   D  three keys with reads held off -> FIFO accumulates 3 events, drains
--      in order with exact iKeys word values (bit15 valid, bit7 press,
--      bits5:0 keycode), then the empty flag stays clear
--   E  scan disabled -> strobes idle high, a held key emits nothing
--   F  oMatrixCtrl FIFO clear empties pending events; no re-emission for a
--      still-held key

module Main (main) where

import Prelude
import Data.List (group, sort)
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (Bit, BitVector, Index, Unsigned, Vec, low, high)

import PM.Matrix

-- Sim timing: one scan pass = 8 rows * 10 ticks
simCfg :: MatrixCfg
simCfg = MatrixCfg 10 10

passT :: Int
passT = 8 * 10

------------------------------------------------------------------------------------------------
-- Switch-matrix model and closed-loop harness
------------------------------------------------------------------------------------------------

-- | Combinational matrix: a pressed key on the strobed (low) row pulls its
--   column low through its diode; everything else floats high.
modelCols :: Vec 8 Bit -> Vec 64 Bool -> Vec 8 Bit
modelCols rowsN pr = C.map colBit C.indicesI
  where
    colBit c = if or [ rowsN C.!! r == low && pr C.!! keyAt r c
                     | r <- [0 .. 7] :: [Index 8] ]
               then low else high
    keyAt r c = C.bitCoerce (C.pack r C.++# C.pack c) :: Index 64

ctrlOn, ctrlOff, ctrlClear :: MatrixCtrl
ctrlOn    = MatrixCtrl True  False 0
ctrlOff   = MatrixCtrl False False 0
ctrlClear = MatrixCtrl True  True  0

-- | Close the loop: scanner strobes drive the matrix model, whose columns
--   feed the scanner back.  @popL = Nothing@ pops whenever iKeys is valid
--   (each event is then seen exactly once); @Just l@ follows the schedule.
runMatrix :: Int -> [MatrixCtrl] -> Maybe [Bool] -> [Vec 64 Bool]
          -> [(Vec 8 Bit, BitVector 16)]
runMatrix n ctrlL popL presses = C.sampleN @C.System n sig
  where
    sig :: C.HiddenClockResetEnable C.System
        => C.Signal C.System (Vec 8 Bit, BitVector 16)
    sig = C.bundle (rows, ikeys)
      where
        (rows, ikeys) = matrix simCfg ctrlS pop cols
        ctrlS         = C.fromList (ctrlL ++ repeat ctrlOn)
        pop = case popL of
                Nothing -> (`C.testBit` 15) <$> ikeys
                Just l  -> C.fromList (l ++ repeat False)
        cols     = modelCols <$> rows <*> pressedS
        pressedS = C.fromList (presses ++ repeat (C.repeat False))

-- | (down?, keycode) for every cycle the head was valid.
events :: [(Vec 8 Bit, BitVector 16)] -> [(Bool, Unsigned 6)]
events smp = [ (C.testBit w 7, C.unpack (C.slice C.d5 C.d0 w))
             | (_, w) <- smp, C.testBit w 15 ]

-- Stimulus builders (raw switch state per tick)
pv :: [Index 64] -> Vec 64 Bool
pv ks = C.map (`elem` ks) C.indicesI

holdP :: Int -> [Index 64] -> [Vec 64 Bool]
holdP nPass ks = replicate (nPass * passT) (pv ks)

-- | Alternate two raw states one pass at a time — bounce at the rate the
--   sampler can actually see.
bounceP :: Int -> [Index 64] -> [Index 64] -> [Vec 64 Bool]
bounceP nPass a b = concat [ holdP 1 (if even i then a else b) | i <- [0 .. nPass - 1] ]

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

------------------------------------------------------------------------------------------------
-- Scenarios
------------------------------------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "== A: bouncy press/release -> one event each; strobe pattern =="
  let stimA = holdP 5 [] ++ bounceP 4 [5] [] ++ holdP 30 [5]
                         ++ bounceP 4 [] [5] ++ holdP 30 []
      smpA  = runMatrix (length stimA + 2 * passT) [] Nothing stimA
  rA1 <- checkEq "debounced events (down F1=5, up F1=5)"
           [(True, 5), (False, 5)] (events smpA)
  let win    = map fst (take (2 * passT) (drop (5 * passT) smpA))
      lows v = [ i | (i, b) <- zip [0 :: Int ..] (C.toList v), b == low ]
  rA2 <- checkEq "row strobes one-hot active-low, whole window"
           True (all ((== 1) . length . lows) win)
  rA3 <- checkEq "all 8 rows strobed over 2 passes"
           [0 .. 7] (dedupSort (concatMap lows win))
  rA4 <- checkEq "strobe dwell = 10 ticks (interior runs)"
           [10] (dedup (map length (interior (group (map lows win)))))

  putStrLn "== B: 5-pass (5 ms) glitch emits nothing =="
  let stimB = holdP 5 [] ++ holdP 5 [7] ++ holdP 30 []
  rB <- checkEq "events" [] (events (runMatrix (length stimB) [] Nothing stimB))

  putStrLn "== C: LAYOUT keycodes and event order =="
  let stimC = holdP 5 []
           ++ holdP 15 [0]                -- A0
           ++ holdP 15 [0, 48]            -- + G7
           ++ holdP 15 [0, 48, 49]        -- + P0
           ++ holdP 15 [0, 48, 49, 58]    -- + P9
           ++ holdP 30 []                 -- release all together
  let evC = events (runMatrix (length stimC) [] Nothing stimC)
  rC1 <- checkEq "A0=0 G7=48 P0=49 P9=58 presses, in press order"
           [(True, 0), (True, 48), (True, 49), (True, 58)] (take 4 evC)
  rC2 <- checkEq "all four releases arrive (sorted)"
           [(False, 0), (False, 48), (False, 49), (False, 58)]
           (sort (drop 4 evC))
  rC3 <- checkEq "same-row releases (G7 then P0) in column order" True
           (case [ k | (False, k) <- evC, k == 48 || k == 49 ] of
              [a, b] -> a == 48 && b == 49
              _      -> False)

  putStrLn "== D: FIFO accumulates, drains in order, then empty flag =="
  let tDrain = 25 * passT
      nD     = 32 * passT
      stimD  = holdP 5 [] ++ holdP 27 [2, 10, 20]
      smpD   = runMatrix nD [] (Just (replicate tDrain False ++ repeat True)) stimD
      wordsD = [ w | (_, w) <- drop tDrain smpD, C.testBit w 15 ]
  rD1 <- checkEq "held-off head is valid just before the drain"
           True (C.testBit (snd (smpD !! (tDrain - 1))) 15)
  rD2 <- checkEq "drained iKeys words, exact (valid|press|keycode)"
           [0x8082, 0x808A, 0x8094 :: BitVector 16] wordsD
  rD3 <- checkEq "empty flag: no valid head in the last 3 passes"
           [] (events (drop (nD - 3 * passT) smpD))

  putStrLn "== E: scan disabled =="
  let stimE = holdP 20 [12]
      smpE  = runMatrix (length stimE) (repeat ctrlOff) Nothing stimE
  rE1 <- checkEq "row strobes all idle high" True
           (all (all (== high) . C.toList . fst) smpE)
  rE2 <- checkEq "no events" [] (events smpE)

  putStrLn "== F: oMatrixCtrl FIFO clear =="
  let tClr  = 25 * passT
      nF    = 32 * passT
      ctrlF = replicate tClr ctrlOn ++ replicate 5 ctrlClear ++ repeat ctrlOn
      stimF = holdP 5 [] ++ holdP 27 [3]
      smpF  = runMatrix nF ctrlF (Just (replicate nF False)) stimF
  rF1 <- checkEq "event pending before the clear"
           True (C.testBit (snd (smpF !! (tClr - 1))) 15)
  rF2 <- checkEq "nothing pending after the clear (key still held, no re-emit)"
           [] (events (drop (tClr + 6) smpF))

  if and [rA1, rA2, rA3, rA4, rB, rC1, rC2, rC3, rD1, rD2, rD3, rE1, rE2, rF1, rF2]
    then putStrLn "\nALL PASS: scan, debounce, keycode fold, FIFO order, empty flag, ctrl bits"
    else putStrLn "\nFAILURES above" >> exitFailure

-- collapse adjacent equals; and a sorted-unique helper for the row coverage check
dedup :: Eq a => [a] -> [a]
dedup = foldr (\x acc -> if [x] == take 1 acc then acc else x : acc) []

dedupSort :: [Int] -> [Int]
dedupSort = dedup . sort

interior :: [a] -> [a]
interior xs = if length xs < 3 then [] else init (tail xs)
