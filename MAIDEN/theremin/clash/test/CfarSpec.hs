{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the MAIDEN CA-CFAR detector.
--
-- The block is RAM-based, so it is exercised through 'simulateN' against a
-- plain-Haskell golden model of the window geometry. Zero-initialised RAMs
-- make the hardware behave exactly as if the stream had been all-zero
-- forever, so the golden model extends the input with zeros on both sides
-- and the comparison is cycle-exact, warm-up included.
module CfarSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Maiden.Cfar

-- | α = 5.0 in Q4.4, as instantiated by the top entity.
alphaQ44 :: Integer
alphaQ44 = 80

latency :: Int
latency = 22

-- | Golden verdict for the cell at index @k@ of @xs@ (zero-padded world):
-- reference cells are 3..18 away on each side (2 guards between), and the
-- compare is the divider-free cross-multiplied form with strict >.
goldenAt :: [Integer] -> Int -> (Bool, Integer)
goldenAt xs k = (cut * 512 > alphaQ44 * (lead + lag), cut)
 where
  at i | i < 0 || i >= P.length xs = 0
       | otherwise                 = xs P.!! i
  cut  = at k
  lead = P.sum [ at (k + j) | j <- [3 .. 18] ]
  lag  = P.sum [ at (k - j) | j <- [3 .. 18] ]

-- | Hardware run over a finite stream.
runCfar :: [Integer] -> [(Bool, Integer)]
runCfar xs =
  [ (d, toInteger c)
  | (d, c) <- simulateN @System (P.length xs) (cfar 80)
                        (P.map fromInteger xs) ]

-- | A deterministic pseudo-noise floor around 1000 counts.
floorNoise :: [Integer]
floorNoise = [ 950 + (i * 37) `P.mod` 100 | i <- [0 ..] ]

tests :: TestTree
tests = testGroup "maiden_cfar"
  [ testCase "synthetic target in a noise floor: one detection, right cell" $ do
      let spikeIx = 60
          xs = [ if i == spikeIx then 40_000 else n
               | (i, n) <- P.zip [0 ..] (P.take 120 floorNoise) ]
          outs = runCfar (xs P.++ P.replicate latency 0)
          dets = [ (m, c) | (m, (d, c)) <- P.zip [0 ..] outs, d ]
      dets @?= [(spikeIx + latency, 40_000)]

  , testCase "threshold edge is exact: 5·mean+1 fires, 5·mean does not" $ do
      -- Constant floor 1000: Σref = 32 000, α·Σ = 2 560 000, so a CUT
      -- detects iff cut·512 > 2 560 000 ⇔ cut > 5000.
      let stream v = [ if i == (50 :: Int) then v else 1_000 | i <- [0 .. 99] ]
                       P.++ P.replicate latency 0
          detsFor v = [ m | (m, (d, _)) <- P.zip [0 :: Int ..] (runCfar (stream v)), d ]
      detsFor 5_001 @?= [50 + latency]
      detsFor 5_000 @?= []

  , testCase "all-zero input never detects (strict compare)" $
      P.filter fst (runCfar (P.replicate 120 0)) @?= []

  , testCase "warm-up cycles report (False, 0)" $ do
      let outs = runCfar (P.take 60 floorNoise)
      P.take latency outs @?= P.replicate latency (False, 0)

  , testPropertyNamed "matches the golden model cycle-for-cycle"
      "prop_matches_golden" $ H.property $ do
      xs <- H.forAll (Gen.list (Range.linear 1 150)
                       (Gen.integral (Range.linear 0 262_143)))
      let n = P.length xs P.+ latency
          padded = xs P.++ P.replicate latency 0
          hw = runCfar padded
      hw === [ if m < latency then (False, 0)
               else goldenAt padded (m - latency)
             | m <- [0 .. n - 1] ]
  ]
