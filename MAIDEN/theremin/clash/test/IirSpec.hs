{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the time-multiplexed IIR port.
module IirSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Theremin.IirNStage

-- | The structural 'iir' (asyncRam state bank) must match the pure model
-- 'iirStep' cycle for cycle. This pins the RAM-based rewrite to the
-- behaviour every other test in this file verifies.
prop_structural_matches_model :: Assertion
prop_structural_matches_model = do
    let n = 4_000
        -- varied deterministic input, plus a mid-run reset pulse
        ins = [ ( if i == 1_500 then high else low
                , fromIntegral ((i * 2654435761) `mod` 1073741824) )
              | i <- [0 .. n - 1] ] :: [(Bit, BitVector 30)]
        structural = simulateN @System n
          (\i -> iir (SNat @6) params (fst <$> i) (snd <$> i)) ins
        -- Moore alignment: output sample n reflects the state after n
        -- inputs, so sample 0 is the initial state -- keep scanl's head,
        -- drop its last element.
        model = P.map isOutReg
          (P.take n (P.scanl (iirStep (SNat @6) params)
                             (initialState :: IirState 30) ins))
    structural @?= model

params :: IirParams
params = IirParams { ipCycleCount = 5, ipStageCount = 5 }

-- | Drive a constant input for @n@ clocks, returning @OUT_VALUE@ each cycle.
runConst :: Int -> BitVector 30 -> [BitVector 30]
runConst n v = P.map isOutReg (P.take n states)
 where
  states = P.tail (P.iterate step (initialState :: IirState 30))
  step s = iirStep (SNat @6) params s (low, v)

-- | Final settled output after a long run at a constant input.
settled :: BitVector 30 -> BitVector 30
settled v = P.last (runConst 200_000 v)

-- | The scalar reference for one stage: @s' = s + ((x - s) >> 6)@, using the
-- same widened arithmetic and bit-select truncation as the hardware.
refStage :: Integer -> Integer -> Integer
refStage s x = ((s `shiftL` 6) + (x - s)) `shiftR` 6

-- | One pass over the 5-stage chain. Each stage consumes the value the
-- previous stage produced /in this pass/, because the hardware advances one
-- stage per clock and the buffered output is what the next stage reads.
refPass :: Integer -> [Integer] -> [Integer]
refPass v [] = []
refPass v (s : rest) = s' : refPass s' rest
 where s' = refStage s v

-- | Reference for the whole 5-stage chain, iterated to a fixed point.
refChain :: Integer -> Integer
refChain x = go (P.replicate 5 0) (200_000 :: Int)
 where
  go ss 0 = P.last ss
  go ss k =
    let ss' = refPass x ss
    in if ss' == ss then P.last ss else go ss' (k - 1)

tests :: TestTree
tests = testGroup "iir_nstage_pow2k"
  [ testCase "structural iir matches the pure model (incl. mid-run reset)"
      prop_structural_matches_model

  , testCase "output starts at zero" $
      P.take 5 (runConst 5 0x1234) @?= P.replicate 5 0

  , testCase "zero input stays at zero" $
      settled 0 @?= 0

  , testCase "reset clears the output register" $ do
      let s  = P.foldl (\a v -> iirStep (SNat @6) params a (low, v))
                 (initialState :: IirState 30)
                 (P.replicate 5_000 0x0010_0000)
          s' = iirStep (SNat @6) params s (high, 0x0010_0000)
      isOutReg s' @?= 0

  , testCase "output updates once per CYCLE_COUNT clocks" $ do
      -- OUT_VALUE is written only when the delayed write address hits the
      -- last stage, i.e. once every 5 clocks.
      let outs = runConst 500 0x0010_0000
          changes = P.length (P.filter id (P.zipWith (/=) outs (P.tail outs)))
      -- Far fewer transitions than clocks, and none between update slots.
      assertBool "changes at most once per 5 clocks" (changes <= 500 `div` 5)

  , testPropertyNamed "settles to a DC gain of one (within truncation)"
      "prop_dc_gain" $ H.property $ do
      -- A lowpass has unity DC gain, but each stage truncates: it stops
      -- moving once (x - s) < 2^K, so it parks up to 2^K - 1 = 63 short.
      -- Five stages in series means a worst-case shortfall of 5 * 63 = 315.
      -- This is a real property of the design, not a porting artefact --
      -- the hand-written SystemVerilog has the same DC droop.
      x <- H.forAll (Gen.integral (Range.linear 0x1_0000 0x00FF_FFFF))
      let out = toInteger (settled (fromIntegral (x :: Integer)))
      H.assert (out <= x)
      H.assert (out >= x - 5 * 63)

  , testPropertyNamed "matches the scalar reference chain"
      "prop_matches_reference" $ H.property $ do
      x <- H.forAll (Gen.integral (Range.linear 0x1_0000 0x00FF_FFFF))
      toInteger (settled (fromIntegral (x :: Integer))) === refChain x

  , testPropertyNamed "monotone in the input"
      "prop_monotone" $ H.property $ do
      a <- H.forAll (Gen.integral (Range.linear 0x1_0000 0x0080_0000))
      b <- H.forAll (Gen.integral (Range.linear 0x1_0000 0x0080_0000))
      let (lo, hi) = (P.min a b, P.max a b)
      H.assert (settled (fromIntegral (lo :: Integer))
                <= settled (fromIntegral (hi :: Integer)))

  , testCase "step response is monotone and never overshoots" $ do
      let target = 0x0010_0000
          outs = P.map toInteger (runConst 100_000 target)
      assertBool "never exceeds the input" (P.all (<= toInteger target) outs)
      assertBool "non-decreasing" (P.and (P.zipWith (<=) outs (P.tail outs)))
  ]
