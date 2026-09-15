{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the MAIDEN vectoring CORDIC.
--
-- References are plain 'Double' 'atan2' and 'sqrt'. The asserted error
-- bounds are the ones documented in @Maiden.Cordic@:
--
--   * phase within ±4 BAM LSB of atan2 for ‖v‖ ≥ 8192, ±32 for ‖v‖ ≥ 1024;
--   * magnitude within ±8 counts of G·√(I²+Q²).
module CordicSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Maiden.Cordic

-- | CORDIC gain for 16 iterations.
gain :: Double
gain = P.product [ P.sqrt (1 + 2 P.** (-2 * fromIntegral i))
                 | i <- [0 .. 15 :: Int] ]

-- | Reference phase in BAM counts (Double, un-quantised).
refPhase :: Integer -> Integer -> Double
refPhase i q = P.atan2 (fromInteger q) (fromInteger i) / (2 * P.pi) * 65_536

-- | Reference magnitude in output counts (Double, un-quantised).
refMag :: Integer -> Integer -> Double
refMag i q = gain * P.sqrt (fromInteger (i * i + q * q))

-- | Signed distance between a measured BAM angle and a reference angle,
-- shortest way around the circle.
bamErr :: Signed 16 -> Double -> Double
bamErr meas ref = wrapped
 where
  d = fromIntegral meas - ref
  wrapped | d > 32_768   = d - 65_536
          | d < -32_768  = d + 65_536
          | otherwise    = d

run :: Integer -> Integer -> (Integer, Signed 16)
run i q =
  let (m, p) = cordicModel (fromInteger i, fromInteger q)
  in (toInteger m, p)

checkOne :: Double -> Double -> Integer -> Integer -> H.PropertyT IO ()
checkOne phaseTol magTol i q = do
  let (m, p) = run i q
  H.annotateShow (i, q, m, p, refMag i q, refPhase i q)
  H.assert (P.abs (bamErr p (refPhase i q)) <= phaseTol)
  H.assert (P.abs (fromInteger m - refMag i q) <= magTol)

genCoord :: H.Gen Integer
genCoord = Gen.integral (Range.linearFrom 0 (-32_768) 32_767)

tests :: TestTree
tests = testGroup "maiden_cordic"
  [ testCase "atan table matches its defining formula" $ do
      let ref = [ P.round (P.atan (2 P.** (-(fromIntegral i)) :: Double)
                           / (2 * P.pi) * 65_536)
                | i <- [0 .. 15 :: Int] ] :: [Integer]
      P.map toInteger (toList atanTable) @?= ref

  , testCase "cardinal directions" $ do
      let r = 20_000
          g x = P.round (gain * fromIntegral x) :: Integer
          near (m, p) (m', p') tol = do
            assertBool ("mag " P.<> show m) (P.abs (m - m') <= 8)
            assertBool ("phase " P.<> show p)
                       (P.abs (bamErr p (fromInteger p')) <= tol)
      near (run r 0)          (g r, 0)         4
      near (run 0 r)          (g r, 16_384)    4
      near (run (-r) 0)       (g r, -32_768)   4   -- ±π, one bit pattern
      near (run 0 (-r))       (g r, -16_384)   4
      near (run r r)          (g (P.round (P.sqrt 2 * fromIntegral r :: Double)), 8_192) 4

  , testCase "origin gives zero magnitude (phase undefined there)" $
      -- atan2 0 0 is a convention, not a value; the hardware happily emits
      -- Σ atan(2^-i) for it. Only the magnitude is contractual at the origin.
      fst (run 0 0) @?= 0

  , testCase "full-scale corners do not overflow" $ do
      -- ‖v‖·G·8 at (−32768, −32768) is the datapath maximum; the magnitude
      -- must come back ≈ G·√2·32768, not wrapped.
      let corners = [ (i, q) | i <- [-32_768, 32_767]
                             , q <- [-32_768, 32_767] ] :: [(Integer, Integer)]
      P.mapM_ (\(i, q) -> do
        let (m, _) = run i q
        assertBool (show ((i, q), m))
                   (P.abs (fromInteger m - refMag i q) <= (8 :: Double)))
        corners

  , testPropertyNamed "phase within ±4 BAM LSB at quarter scale and up"
      "prop_phase_tight" $ H.property $ do
      i <- H.forAll genCoord
      q <- H.forAll genCoord
      let r2 = i * i + q * q
      if r2 >= 8_192 * 8_192
        then checkOne 4 8 i q
        else H.success

  , testPropertyNamed "phase within ±32 BAM LSB down to ‖v‖ = 1024"
      "prop_phase_loose" $ H.property $ do
      i <- H.forAll (Gen.integral (Range.linearFrom 0 (-8_192) 8_191))
      q <- H.forAll (Gen.integral (Range.linearFrom 0 (-8_192) 8_191))
      let r2 = i * i + q * q
      if r2 >= 1_024 * 1_024
        then checkOne 32 8 i q
        else H.success

  , testPropertyNamed "magnitude within ±8 counts everywhere"
      "prop_mag" $ H.property $ do
      i <- H.forAll genCoord
      q <- H.forAll genCoord
      let (m, _) = run i q
      H.annotateShow (i, q, m, refMag i q)
      H.assert (P.abs (fromInteger m - refMag i q) <= (8 :: Double))

  , testCase "pipeline latency is 17 clocks and matches the model" $ do
      let inputs = [ (fromInteger i, fromInteger q)
                   | (i, q) <- [ (12_000, -5_000), (-20_000, 20_000)
                               , (300, 40), (-1, -1), (32_767, -32_768) ] ]
              P.++ P.replicate 20 (0, 0)
          outs = simulateN @System (P.length inputs) cordic inputs
          expected = P.map cordicModel (P.take 5 inputs)
      P.drop 17 (P.take 22 outs) @?= expected
  ]
