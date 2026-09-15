{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Behavioural tests for the Clash PWM port.
--
-- These check the /model/, independent of code generation; the generated-VHDL
-- equivalence check against the original SystemVerilog lives in the GHDL
-- co-simulation step (see README).
module Main (main) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Theremin.Pwm
import qualified AudioSpec
import qualified CfarSpec
import qualified CicSpec
import qualified CordicSpec
import qualified FftSpec
import qualified FirSpec
import qualified IirSpec
import qualified NoteMapSpec
import qualified SensorSpec
import qualified SensorTopSpec

-- | Run the pure step function over a constant input for @n@ cycles,
-- collecting the state after each edge.
run :: Int -> PwmIn -> [PwmState]
run n i = P.take n (P.tail (P.iterate (`pwmStep` i) initialState))

steady :: BitVector 8 -> Color -> Color -> PwmIn
steady br c0 c1 = PwmIn { piReset = low
                        , piColor0 = c0
                        , piColor1 = c1
                        , piBrightness = br }

-- | One full period of the shared counter.
period :: Int
period = 65_536

-- | Backlight high-cycles over one full counter period, measured in the
-- /second/ period.
--
-- The first period is not representative: the backlight is switched on by the
-- @high == 0xFF@ comparison, which only fires on the counter wrap at the very
-- end of period 1, so its on-interval falls entirely inside period 2.
backlightDuty :: BitVector 8 -> Int
backlightDuty br =
  P.length (P.filter ((== high) . psPwm)
                     (P.drop period (run (2 * period) (steady br 0 0))))

-- | Red/green/blue high-cycles of LED0 over one full counter period.
led0Duty :: Color -> (Int, Int, Int)
led0Duty c =
  ( count 2, count 1, count 0 )
 where
  states = run period (steady 0 c 0)
  count ix = P.length (P.filter (\s -> (psLed0 s ! (ix :: Int)) == high) states)

tests :: TestTree
tests = testGroup "theremin_pwm"
  [ testCase "reset clears every register" $ do
      let s = P.foldl pwmStep initialState
                [ steady 0x80 0xF0F 0x0F0 | _ <- [1 .. 1000 :: Int] ]
          r = pwmStep s (steady 0x80 0xF0F 0x0F0) { piReset = high }
      r @?= initialState

  , testCase "counter is free-running and wraps" $ do
      let states = run period (steady 0 0 0)
      P.map psCounter states @?= ([1 .. 65_535] P.++ [0])

  , testCase "brightness 0xFF is fully on after the first period" $ do
      -- 0xFF takes the forced-on branch, so it never turns back off.
      let tailStates = P.drop period (run (2 * period) (steady 0xFF 0 0))
      P.all ((== high) . psPwm) tailStates @?= True

  , testCase "brightness 0x00 gives the minimum non-zero duty" $
      -- The level only changes on a low-bits rollover, so even brightness 0
      -- leaves the backlight on for the single 256-cycle sub-step between
      -- the forced-on comparison (high==0xFF) and the off comparison
      -- (high==0). It is not fully dark. Confirmed against the SV semantics.
      backlightDuty 0x00 @?= 256

  , testPropertyNamed "backlight duty tracks brightness"
      "prop_backlight_duty" $ H.property $ do
      br <- H.forAll (Gen.integral (Range.linear 1 0xFE))
      -- Level changes land on low-bits rollovers, at counter k*256-1 where
      -- high==k-1. On fires at high==0xFF (k=256, i.e. the wrap to counter 0)
      -- and off at high==brightness (k=brightness+1). So the on-interval is
      -- [0, (brightness+1)*256).
      backlightDuty (fromIntegral (br :: Int)) === (br + 1) * 256

  , testPropertyNamed "LED channels are independent"
      "prop_led_channels" $ H.property $ do
      r <- H.forAll (Gen.integral (Range.linear 0 15))
      g <- H.forAll (Gen.integral (Range.linear 0 15))
      b <- H.forAll (Gen.integral (Range.linear 0 15))
      let c = fromIntegral ((r `shiftL` 8) + (g `shiftL` 4) + b :: Int)
          -- On fires at rgbHigh==0 (counter 2047, effective 2048), off at
          -- rgbHigh==nibble (effective (n+1)*2048), so the duty is n*2048.
          -- A nibble of 0 hits both comparisons at once and off wins, which
          -- is the SV's two-independent-ifs behaviour: the channel is dark.
          duty n = n * 2048
      led0Duty c === (duty r, duty g, duty b)

  , testPropertyNamed "colour on LED1 does not disturb LED0"
      "prop_led_isolation" $ H.property $ do
      c0 <- H.forAll (fromIntegral <$> Gen.integral (Range.linear 0 (0xFFF :: Int)))
      c1 <- H.forAll (fromIntegral <$> Gen.integral (Range.linear 0 (0xFFF :: Int)))
      let withOther = run period (steady 0 c0 c1)
          alone     = run period (steady 0 c0 0)
      P.map psLed0 withOther === P.map psLed0 alone
  ]

main :: IO ()
main = defaultMain (testGroup "theremin-clash"
  [ tests, IirSpec.tests, SensorSpec.tests, SensorTopSpec.tests
  , FftSpec.tests
  , CicSpec.tests
  , CordicSpec.tests
  , FirSpec.tests
  , CfarSpec.tests
  , AudioSpec.tests
  , NoteMapSpec.tests
  ])
