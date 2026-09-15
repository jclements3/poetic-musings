{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the MAIDEN transposed FIR.
--
-- The filter keeps full precision (no rounding), so every test is exact:
-- impulse response returns the coefficients bit-for-bit, superposition
-- holds bit-for-bit, and the whole stream matches a plain-Haskell direct
-- convolution at 'Integer' precision.
module FirSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Maiden.Fir

coeffs :: [Integer]
coeffs = P.map toInteger (toList compCoeffs)

-- | Drive the pure step function; output k corresponds to input k (the
-- 'moore' wrapper adds one clock of latency on top, pinned in IirSpec-style
-- by construction, not retested here).
runFir :: [Integer] -> [Integer]
runFir xs =
  P.map (toInteger . fsOut)
        (P.tail (P.scanl (firStep compCoeffs) initialFirState
                         (P.map (fromInteger :: Integer -> Signed 18) xs)))

-- | Direct-form convolution reference at unbounded precision.
refConv :: [Integer] -> [Integer]
refConv xs = [ P.sum [ c * at (k - i) | (i, c) <- P.zip [0 ..] coeffs ]
             | k <- [0 .. P.length xs - 1] ]
 where
  at i | i < 0 || i >= P.length xs = 0
       | otherwise                 = xs P.!! i

genXs :: H.Gen [Integer]
genXs = Gen.list (Range.linear 1 120)
                 (Gen.integral (Range.linearFrom 0 (-65_536) 65_535))

tests :: TestTree
tests = testGroup "maiden_fir"
  [ testCase "unit impulse returns the coefficients exactly" $
      runFir (1 : P.replicate 20 0) @?= coeffs P.++ P.replicate 6 0

  , testCase "scaled impulse returns scaled coefficients (homogeneity)" $ do
      let a = -1_931
      runFir (a : P.replicate 20 0) @?= P.map (a *) coeffs P.++ P.replicate 6 0

  , testCase "DC gain is the coefficient sum" $ do
      let c = 1_000
      P.last (runFir (P.replicate 40 c)) @?= c * P.sum coeffs

  , testPropertyNamed "superposition holds bit-for-bit"
      "prop_superposition" $ H.property $ do
      xs <- H.forAll genXs
      ys <- H.forAll genXs
      let n = P.max (P.length xs) (P.length ys)
          pad zs = zs P.++ P.replicate (n - P.length zs) 0
      runFir (P.zipWith (+) (pad xs) (pad ys))
        === P.zipWith (+) (runFir (pad xs)) (runFir (pad ys))

  , testPropertyNamed "matches direct convolution on random streams"
      "prop_matches_convolution" $ H.property $ do
      xs <- H.forAll genXs
      runFir xs === refConv xs

  , testCase "full-scale constant input cannot overflow 38 bits" $ do
      -- Worst case |y| ≤ max|x| · Σ|c_i| = 131 072 · 25 245 < 2^37.
      let worst = P.last (runFir (P.replicate 40 (-131_072)))
      worst @?= (-131_072) * P.sum coeffs
      assertBool "fits Signed 38" (P.abs worst < 2 P.^ (37 :: Int))
  ]
