-- TMDS encoder testbench.
--
--     Run:  cabal test tmds-test --test-show-details=direct
--
--   * transition minimisation: for every byte 0..255 the 9-bit
--     intermediate has <= 5 transitions (in fact <= 4: 3 in the data
--     chain plus the XOR/XNOR flag), and every 10-bit output word has
--     <= 5, for both disparity signs
--   * the four control words are the DVI 1.0 values
--   * running disparity: over 200 000 pseudo-random bytes through the
--     registered `tmdsEncoder`, the accumulated (ones - zeros) of the
--     emitted words stays within +-8, and the encoder's internal counter
--     is exactly that accumulation (checked against the pure step)
--   * invertibility: a decoder written here round-trips 0..255 for every
--     disparity in -8..8
--   * `tmdsShift` emits the word LSB first, bit 0 on the load cycle + 1

module Main (main) where

import Prelude
import Data.Bits (testBit, xor, shiftL, (.&.))
import Data.List (foldl')
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (BitVector, Bit)

import PM.Video.Tmds

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

bits :: Int -> Integer -> [Bool]
bits n v = [ testBit v i | i <- [0 .. n - 1] ]

transitions :: [Bool] -> Int
transitions bs = length (filter id (zipWith (/=) bs (tail bs)))

ones :: [Bool] -> Int
ones = length . filter id

-- Reference decoder (DVI 1.0 §3.2.2 inverted).
decode :: BitVector 10 -> BitVector 8
decode w = fromInteger (foldr (\b acc -> acc `shiftL` 1 + (if b then 1 else 0)) 0 d)
 where
  wb  = bits 10 (toInteger w)
  inv = wb !! 9
  q8  = wb !! 8
  q   = map (/= inv) (take 8 wb)
  d   = head q : [ (q !! i `xor` q !! (i - 1)) /= not q8 | i <- [1 .. 7] ]
  -- q8=1: d[i] = q[i] xor q[i-1]; q8=0: d[i] = not (q[i] xor q[i-1])

lcg :: Int -> [BitVector 8]
lcg = map (\s -> fromIntegral ((s `div` 65536) .&. 0xFF)) . tail . iterate step
  where step s = (s * 1103515245 + 12345) .&. 0x7FFFFFFF

main :: IO ()
main = do
  putStrLn "== transition minimisation =="
  let qms = [ transitions (bits 9 (toInteger (tmdsMinimise d))) | d <- [0 .. 255] ]
  r1 <- checkEq "9-bit intermediate: max transitions over 0..255 (<= 5 required)"
          True (maximum qms <= 5)
  putStrLn ("        (observed max " ++ show (maximum qms) ++ ")")
  let outs = [ transitions (bits 10 (toInteger (fst (tmdsEncodeStep cnt True 0 d))))
             | cnt <- [-8 .. 8], d <- [0 .. 255] ]
  r2 <- checkEq "10-bit word: max transitions, all bytes x disparity -8..8 (<= 5)"
          True (maximum outs <= 5)

  putStrLn "== control words =="
  r3 <- checkEq "control (c1,c0) = 00,01,10,11"
          [0b1101010100, 0b0010101011, 0b0101010100, 0b1011010100]
          (map tmdsControl [0, 1, 2, 3])
  r3b <- checkEq "blanking emits the control word for (vsync,hsync) and zeroes disparity"
          (0b0101010100, 0) (tmdsEncodeStep 5 False 2 0xAB)

  putStrLn "== running disparity, registered encoder, 200 000 random bytes =="
  let n     = 200000
      dat   = take n (lcg 12345)
      des   = replicate 8 False ++ repeat True     -- a short control run first
      -- raw sample 0 is the reset cycle and sample 1 still shows the
      -- reset value, so output sample j+1 encodes input j for j >= 1
      -- (input 0, a control word, is swallowed by the reset)
      words' = drop 2 (C.sampleN @C.System (n + 1)
                 (tmdsEncoder (C.fromList des) (C.fromList (cycle [0, 1, 2, 3]))
                              (C.fromList dat)))
      deWords = drop 7 words'          -- the data-period words
      -- control word 2 is itself unbalanced (4 ones), so the DC
      -- balance is measured over the data period, starting from the
      -- disparity 0 that the control period leaves behind
      disp  = scanl (\acc w -> let b = bits 10 (toInteger w) in acc + ones b - (10 - ones b))
                    (0 :: Int) deWords
      bound = maximum (map abs disp)
  r4 <- checkEq "|accumulated (ones - zeros)| <= 8 over the data stream" True (bound <= 8)
  putStrLn ("        (observed bound " ++ show bound ++ ")")
  -- the pure step, folded, equals the registered encoder
  let pureWords = snd (foldl' (\(cnt, acc) (de, c, d) -> let (w, cnt') = tmdsEncodeStep cnt de c d
                                                           in (cnt', w : acc))
                              (0, []) (drop 1 (zip3 des (cycle [0, 1, 2, 3]) dat)))
  r5 <- checkEq "registered encoder == pure step folded (mismatches)"
          (0 :: Int)
          (length (filter id (zipWith (/=) (reverse pureWords) words')))
  r6 <- checkEq "stream decodes back to the input bytes (mismatches)"
          (0 :: Int)
          (length (filter id (zipWith (/=) (map decode deWords) (drop 8 dat))))

  putStrLn "== invertibility =="
  let bad = [ (cnt, d) | cnt <- [-8 .. 8], d <- [0 .. 255]
                       , decode (fst (tmdsEncodeStep cnt True 0 d)) /= d ]
  r7 <- checkEq "decode . encode == id for 0..255, disparity -8..8" [] (take 10 bad)

  putStrLn "== 10:1 sequencer =="
  let w = 0b1011000101 :: BitVector 10
      loads = [False, True] ++ replicate 9 False ++ [True] ++ repeat False
      ser   = C.sampleN @C.System 14 (tmdsShift (C.fromList loads) (C.pure w)) :: [Bit]
  r8 <- checkEq "bits 2..11 == word LSB first, then reload"
          (map (\b -> if b then 1 else 0) (bits 10 (toInteger w)) ++ [1, 0])
          (drop 2 ser)

  if and [r1, r2, r3, r3b, r4, r5, r6, r7, r8]
    then putStrLn "\nALL PASS: TMDS transitions, control words, disparity bound, invertibility, sequencer"
    else putStrLn "\nFAILURES above" >> exitFailure
