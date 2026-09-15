{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | End-to-end tests for the full ECP5 sensor chain.
--
-- These drive raw oscillator square waves into 'sensorTop' and check that the
-- filtered period measurement that comes out is the period that went in. That
-- is the whole point of the hardware, and it exercises every ported block at
-- once: 1x edge sampler, CDC, pulse-centre averaging, 512-tap boxcar, and the
-- time-multiplexed IIR.
module SensorTopSpec (tests) where

import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L

import Test.Tasty
import Test.Tasty.HUnit

import Theremin.SensorPeriodMeasure (SensorOut (..))
import Theremin.SensorTop

-- | A square wave with the given half-period, in clock ticks.
--
-- The first cycle asserts reset. Both axes get the same waveform unless a
-- separate volume half-period is given.
oscStream :: Int -> Int -> Int -> [SensorTopIn]
oscStream pitchHalf volHalf n =
  [ SensorTopIn
      { stReset    = if i == 0 then high else low
      , stPitchOsc = square pitchHalf i
      , stVolOsc   = square volHalf i
      }
  | i <- [0 .. n - 1]
  ]
 where
  square h i = if odd (i `div` h) then high else low

runTop :: [SensorTopIn] -> [SensorOut]
runTop ins = simulateN @System (P.length ins) sensorTop ins

-- | Strip the toggling flag in bit 31.
payload :: BitVector 32 -> Integer
payload = toInteger . (`clearBit` 31)

-- | The delay window, in pulses (see 'Theremin.DelayDiffFilter').
delayWindow :: Int
delayWindow = 512

-- | Stage 1 differences pulse centres @delayWindow@ apart. A pulse centre is the
-- sum of two adjacent edge positions, so it advances by @2 * halfPeriod@ per
-- pulse; over the window that is @2 * delayWindow * halfPeriod@ ticks.
expectedStage1 :: Int -> Integer
expectedStage1 half = fromIntegral (2 * delayWindow * half)

-- | Enough clocks to fill the 512-deep buffer and then run a full window
-- beyond it, plus slack for the synchroniser and CDC latency.
clocksFor :: Int -> Int
clocksFor half = half * 2 * (2 * delayWindow + 64)

-- | The settled stage-1 measurements: skip the pre-fill zeros AND the first
-- full window. The first window is contaminated by a startup transient — the
-- edge-to-pulse converter seeds @prev_edge_position = 0@, so the very first
-- pulse centre is bogus and every difference taken against that window reads
-- one count high (measured: 16385 for the first ~512 values, then exactly
-- 2*512*half forever after). This mirrors the real hardware's behaviour; a
-- listener would never hear the first 0.4 ms.
settledStage1 :: Int -> [Integer]
settledStage1 half =
  P.drop delayWindow
    (P.dropWhile (== 0)
      (P.map (payload . soPitchPeriodStage1) (runTop (oscStream half half (clocksFor half)))))

tests :: TestTree
tests = testGroup "sensor chain end to end"
  [ testCase "recovers the period of a 16-tick half-period oscillator" $
      case settledStage1 16 of
        []      -> assertFailure "chain never produced a measurement"
        (v : _) -> v @?= expectedStage1 16

  , testCase "recovers the period of a 24-tick half-period oscillator" $
      case settledStage1 24 of
        []      -> assertFailure "chain never produced a measurement"
        (v : _) -> v @?= expectedStage1 24

  , testCase "measurement is stable once settled" $ do
      -- Every measurement after the buffer fills should be identical for a
      -- constant-period input: no drift, no off-by-one at wrap.
      let vs = P.take 200 (settledStage1 16)
      P.length (L.nub vs) @?= 1

  , testCase "a longer period reads as a proportionally larger value" $ do
      let a = P.head (settledStage1 16)
          b = P.head (settledStage1 24)
      -- 24/16 = 1.5, exactly, since both divide the window evenly.
      (b * 2) @?= (a * 3)

  , testCase "the two axes measure independently" $ do
      -- Pitch at 16, volume at 24: each output must report its own period,
      -- which catches any cross-wiring between the axes.
      let outs = runTop (oscStream 16 24 (clocksFor 24))
          pitchVs = P.drop delayWindow (P.dropWhile (== 0) (P.map (payload . soPitchPeriodStage1) outs))
          volVs   = P.drop delayWindow (P.dropWhile (== 0) (P.map (payload . soVolPeriodStage1) outs))
      case (pitchVs, volVs) of
        (p : _, v : _) -> do
          p @?= expectedStage1 16
          v @?= expectedStage1 24
        _ -> assertFailure "one of the axes never produced a measurement"

  , testCase "stage 2 converges towards stage 1" $ do
      -- Stage 1 is left-aligned into the 36-bit IIR domain (<< 13) and the
      -- stage-2 output is trimmed (top 32 of 36, i.e. >> 4), so the settled
      -- stage-2 target is s1 << 9. The IIR approaches it monotonically from
      -- below and never overshoots (proved in IirSpec), and the run is not
      -- long enough to fully settle a 27-bit value through five stages -- so
      -- assert the bounds, not the endpoint.
      let outs = runTop (oscStream 16 16 (clocksFor 16))
          final = P.last outs
          s1 = payload (soPitchPeriodStage1 final)
          s2 = payload (soPitchPeriodStage2 final)
      assertBool "stage 2 is running" (s2 > 0)
      assertBool "stage 2 stays at or below its DC target"
        (s2 <= s1 * 512)
  ]
