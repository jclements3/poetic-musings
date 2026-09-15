{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the MAIDEN CIC decimator.
--
-- The reference is the textbook definition computed in plain Haskell at
-- unbounded 'Integer' precision: integrate @n@ times, keep every @r@-th
-- sample, difference @n@ times — equivalently, convolve with the @n@-fold
-- convolution of an @r@-wide boxcar and decimate. Both formulations are
-- used below so the equivalence itself is exercised.
module CicSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Maiden.Cic

-- Default MAIDEN configuration: order 3, R = 4, 12-bit input, 18-bit output.
type N = 3
type R = 4

order, ratio :: Int
order = 3
ratio = 4

-- | The registered integrator chaining delays the textbook response by
-- @order@ input samples (documented in the module header).
structDelay :: Int
structDelay = order

-- | Drive the pure step function and collect the decimated output stream
-- (one entry per 'csValid' strobe).
runCic :: [Signed 12] -> [Integer]
runCic xs =
  [ toInteger (csOut s)
  | s <- P.scanl cicStep (initialCicState :: CicState N R (CicWidth 12 N R)) xs
  , csValid s ]

-- | All per-clock states, for rate checks.
runStates :: [Signed 12] -> [CicState N R (CicWidth 12 N R)]
runStates = P.tail . P.scanl cicStep initialCicState

-- Reference, formulation 1: integrate^n -> ↓r -> diff^n.
refCic :: Int -> Int -> [Integer] -> [Integer]
refCic n r xs = nTimes n diff (everyR (nTimes n integ xs))
 where
  nTimes k f = P.foldr (.) P.id (P.replicate k f)
  integ = P.scanl1 (+)
  diff ys = P.zipWith (-) ys (0 : ys)
  everyR ys = case P.drop (r - 1) ys of
    []       -> []
    (y : t)  -> y : everyR t

-- Reference, formulation 2: convolution with boxcar^n.
conv :: [Integer] -> [Integer] -> [Integer]
conv hs xs =
  [ P.sum [ h * at (k - i) | (i, h) <- P.zip [0 ..] hs ]
  | k <- [0 .. P.length hs + P.length xs - 2] ]
 where
  at i | i < 0 || i >= P.length xs = 0
       | otherwise                 = xs P.!! i

-- | Impulse response of the undecimated CIC: an @r@-wide boxcar convolved
-- with itself @n@ times.
boxcarN :: Int -> Int -> [Integer]
boxcarN n r = P.foldr conv [1] (P.replicate n (boxcar :: [Integer]))
 where boxcar = P.replicate r 1

tests :: TestTree
tests = testGroup "maiden_cic"
  [ testCase "DC gain is exactly R^N" $ do
      -- Settled output of a constant input c is c * r^n, exactly: full bit
      -- growth means no truncation anywhere in the filter.
      let settle c = P.last (runCic (P.replicate 200 c))
      settle 1     @?= 64
      settle 100   @?= 6_400
      settle (-77) @?= (-4_928)

  , testCase "full-scale input does not overflow the 18-bit output" $ do
      let settle c = P.last (runCic (P.replicate 200 c))
      settle 2_047    @?= 2_047 * 64     --  131 008 <  2^17 - 1
      settle (-2_048) @?= (-2_048) * 64  -- -131 072 = -(2^17)

  , testCase "impulse response matches boxcar^N convolution, every phase" $ do
      -- An impulse entering at phase p is delayed structDelay samples by the
      -- registered chaining, then sees the coefficients of boxcar^n at
      -- indices (m+1)*r - 1 - p - structDelay. Across all p the whole
      -- response is covered (p + structDelay walks every residue mod r).
      let h = boxcarN order ratio
          at i | i < 0 || i >= P.length h = 0
               | otherwise                = h P.!! i
          expected p = [ at ((m + 1) * ratio - 1 - p - structDelay)
                       | m <- [0 .. 5] ]
          measured p = P.take 6 (runCic (P.replicate p 0 P.++ [1]
                                         P.++ P.replicate 40 0))
      P.mapM_ (\p -> measured p @?= expected p) [0 .. ratio - 1]
      -- Sanity on the reference itself: coefficients of boxcar^3 at r=4.
      h @?= [1, 3, 6, 10, 12, 12, 10, 6, 3, 1]

  , testCase "valid strobes once every R clocks, starting at clock R" $ do
      let vs = P.map csValid (runStates (P.replicate 40 5))
      vs @?= [ (i `P.mod` ratio) == ratio - 1 | i <- [0 .. 39 :: Int] ]

  , testPropertyNamed "matches the plain-Haskell reference on random input"
      "prop_matches_reference" $ H.property $ do
      xs <- H.forAll (Gen.list (Range.linear 1 400)
                       (Gen.integral (Range.linearFrom 0 (-2_048) 2_047)))
      let hw = runCic (P.map fromInteger xs)
          ref = refCic order ratio (P.replicate structDelay 0 P.++ xs)
      hw === P.take (P.length hw) ref

  , testPropertyNamed "integrate/decimate/diff equals boxcar^N convolution"
      "prop_reference_is_boxcar" $ H.property $ do
      -- The two reference formulations agree, so the impulse test and the
      -- stream test are checking the same filter.
      xs <- H.forAll (Gen.list (Range.linear 1 120)
                       (Gen.integral (Range.linearFrom 0 (-2_048) 2_047)))
      let full = conv (boxcarN order ratio) xs
          everyR ys = case P.drop (ratio - 1) ys of
            []      -> []
            (y : t) -> y : everyR t
          m = P.length (refCic order ratio xs)
      refCic order ratio xs === P.take m (everyR full)

  , testCase "other decimation ratios elaborate: R = 8 gives gain 512" $ do
      -- The audit keeps R generic; prove the type-level sizing tracks it.
      let states = P.scanl cicStep
                     (initialCicState :: CicState 3 8 (CicWidth 12 3 8))
                     (P.replicate 400 (3 :: Signed 12))
          outs = [ toInteger (csOut s) | s <- states, csValid s ]
      P.last outs @?= 3 * 512
  ]
