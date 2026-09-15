{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Tests for the audio path: NCO, sine LUT, sigma-delta DAC, pitch\/volume
-- maps, and the composed instrument end to end (oscillator pins to DSM
-- bitstream).
--
-- Every group name contains \"audio\" so the whole path runs selectively with
-- @cabal run spec -- -p \'\/audio\/\'@.
module AudioSpec (tests) where

import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L

import Hedgehog ((===))
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Theremin.Audio.DsmDac
import Theremin.Audio.Nco (ncoStep)
import Theremin.Audio.PitchMap
import Theremin.Audio.SineLut (sineLookup)
import Theremin.SensorTop (SensorTopIn (..))
import Theremin.ThereminTop

-- ---------------------------------------------------------------------------
-- NCO

-- | Phase after @n@ steps from zero, via the pure step function.
ncoRun :: Int -> Unsigned 32 -> [Unsigned 32]
ncoRun n fw = P.take (n + 1) (P.iterate (ncoStep fw) 0)

ncoTests :: TestTree
ncoTests = testGroup "audio nco"
  [ testCase "phase after N cycles is exactly N * word mod 2^32" $
      sequence_
        [ P.last (ncoRun n fw) @?=
            fromIntegral (fromIntegral n * toInteger fw)
        | fw <- [1, 9_449, 12_345_678, 0x8000_0000, 0xDEAD_BEEF]
        , n  <- [1_000, 65_536]
        ]

  , testCase "wrap count over N cycles is exactly floor (N * word / 2^32)" $
      -- Each wrap is one full output period, so this pins the average
      -- frequency to word / 2^32 cycles per clock, exactly.
      sequence_
        [ let phases = ncoRun n fw
              wraps  = P.length
                [ () | (a, b) <- P.zip phases (P.tail phases), b < a ]
          in wraps @?= fromIntegral
               ((fromIntegral n * toInteger fw) `P.div` (2 P.^ (32 :: Int)))
        | fw <- [0, 1, 0x0010_0000, 0x8000_0000, 0xFFFF_FFFF]
        , n  <- [100_000]
        ]
  ]

-- ---------------------------------------------------------------------------
-- Sine LUT

-- | The ideal sample the LUT approximates at 10-bit phase @p@.
idealSine :: Int -> Integer
idealSine p = round (32767 * sin ((2 * fromIntegral p + 1) * pi / 1024 :: Double))

lutAt :: Int -> Integer
lutAt = toInteger . sineLookup . fromIntegral

sineTests :: TestTree
sineTests = testGroup "audio sine lut"
  [ testCase "max error vs Double sine is at most 1 LSB over all 1024 phases" $ do
      let errs = [ abs (lutAt p - idealSine p) | p <- [0 .. 1023] ]
      assertBool ("worst error " P.<> show (P.maximum errs)) (P.maximum errs <= 1)

  , testCase "half-wave symmetry: sin(p) == sin(511 - p)" $
      sequence_ [ lutAt p @?= lutAt (511 - p) | p <- [0 .. 511] ]

  , testCase "odd symmetry: sin(p + 512) == -sin(p)" $
      sequence_ [ lutAt (p + 512) @?= negate (lutAt p) | p <- [0 .. 511] ]

  , testCase "first quadrant is strictly monotone" $
      assertBool "not strictly increasing"
        (P.and [ lutAt (p + 1) > lutAt p | p <- [0 .. 254] ])

  , testCase "output range never touches -32768, so negation is safe" $ do
      let vs = P.map lutAt [0 .. 1023]
      assertBool "range" (P.minimum vs >= -32767 && P.maximum vs <= 32767)
  ]

-- ---------------------------------------------------------------------------
-- Sigma-delta DAC

-- | Output bits over @n@ cycles of a constant input, via the pure step.
dsmBits :: Int -> Signed 16 -> [Bit]
dsmBits n x = P.map dsOut (P.take n (P.tail (P.iterate (`dsmStep` x) initialState)))

ones :: [Bit] -> Integer
ones = fromIntegral . P.length . P.filter (== high)

-- | From a zero accumulator the 1s count over @n@ cycles is exact, not just
-- within tolerance: floor (n * u \/ 65536) for offset-binary input u.
expectedOnes :: Int -> Signed 16 -> Integer
expectedOnes n x = (fromIntegral n * (toInteger x + 32_768)) `P.div` 65_536

dsmTests :: TestTree
dsmTests = testGroup "audio dsm dac"
  [ testCase "1s density is exactly (x + 32768) / 65536 over two full periods" $
      sequence_
        [ ones (dsmBits n x) @?= expectedOnes n x
        | x <- [-32_768, -32_767, -12_345, -1, 0, 1, 300, 12_345, 32_767]
        , let n = 131_072
        ]

  , testCase "full-scale negative input is silent: constant 0, no limit cycle" $
      ones (dsmBits 200_000 (-32_768)) @?= 0

  , testCase "full-scale positive input drops exactly one bit per 65536" $
      ones (dsmBits 131_072 32_767) @?= 131_070

  , testPropertyNamed "density is exact for arbitrary constant inputs"
      "prop_dsm_density" $ H.property $ do
      x <- H.forAll (Gen.integral (Range.linearFrom 0 (-32_768) 32_767))
      let n = 8_192
      ones (dsmBits n (fromIntegral (x :: Int))) === expectedOnes n (fromIntegral x)
  ]

-- ---------------------------------------------------------------------------
-- Pitch and volume maps

-- | Parameters chosen so every clamp region is reachable with small numbers:
-- zero beat at period @16_000_000@, upper clamp active near period 0.
clampParams :: PitchMapParams
clampParams = PitchMapParams
  { pmBase    = 1_000_000
  , pmShift   = 4
  , pmMaxWord = 800_000
  , pmSilence = 50_000_000
  }

fwAt :: PitchMapParams -> Integer -> Integer
fwAt ps = toInteger . pitchToFreqWord ps . fromIntegral

pitchMapTests :: TestTree
pitchMapTests = testGroup "audio pitch map"
  [ testCase "short periods clamp to the maximum tuning word" $ do
      fwAt clampParams 0 @?= 800_000
      fwAt clampParams 1_000_000 @?= 800_000  -- 1M >> 4 = 62_500, still clamped

  , testCase "the linear region subtracts the shifted period" $
      fwAt clampParams 8_000_000 @?= 500_000  -- 1_000_000 - 8M >> 4

  , testCase "periods past the zero-beat point are silent" $ do
      fwAt clampParams 16_000_000 @?= 0       -- exactly at zero beat
      fwAt clampParams 20_000_000 @?= 0

  , testCase "periods at or past the silence threshold are silent" $ do
      fwAt clampParams 50_000_000 @?= 0
      fwAt clampParams 4_000_000_000 @?= 0

  , testCase "default constants map the testbench periods to distinct tones" $ do
      -- Stage-2 readings of the 16- and 24-tick synthetic oscillators.
      fwAt defaultPitchMapParams 8_388_608 @?= 1_048_576
      fwAt defaultPitchMapParams 12_582_912 @?= 524_288

  , testPropertyNamed "the map is monotone non-increasing in the period"
      "prop_pitch_monotone" $ H.property $ do
      a <- H.forAll (Gen.integral (Range.linear 0 (4_294_967_295 :: Integer)))
      b <- H.forAll (Gen.integral (Range.linear 0 (4_294_967_295 :: Integer)))
      let lo = P.min a b
          hi = P.max a b
      H.assert (fwAt clampParams lo >= fwAt clampParams hi)

  , testCase "volume attenuation is clamped at the ceiling" $ do
      let att = toInteger . periodToAttenuation defaultVolMapParams . fromIntegral
      att (2 P.^ (25 :: Int) :: Integer) @?= 2
      att 4_000_000_000 @?= 12

  , testPropertyNamed "volume attenuation is monotone non-decreasing"
      "prop_vol_monotone" $ H.property $ do
      a <- H.forAll (Gen.integral (Range.linear 0 (4_294_967_295 :: Integer)))
      b <- H.forAll (Gen.integral (Range.linear 0 (4_294_967_295 :: Integer)))
      let att = toInteger . periodToAttenuation defaultVolMapParams . fromIntegral
      H.assert (att (P.min a b) <= att (P.max a b))
  ]

-- ---------------------------------------------------------------------------
-- End to end: oscillator pins to DSM bitstream

-- | Square-wave stimulus, as in SensorTopSpec: reset on the first cycle,
-- then a square wave of the given half-period on each axis.
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

-- | Enough clocks for the 512-deep boxcar to fill and settle, as in
-- SensorTopSpec's @clocksFor@; the 24-tick run needs ~52k cycles.
e2eClocks :: Int
e2eClocks = 24 * 2 * (2 * 512 + 64)

runTop :: Int -> [AudioOut]
runTop pitchHalf =
  simulateN @System e2eClocks
    (thereminTop defaultPitchMapParams defaultVolMapParams)
    (oscStream pitchHalf 16 e2eClocks)

-- | Density of 1s in the last @w@ bits of the bitstream.
tailBits :: Int -> [AudioOut] -> [Bit]
tailBits w outs = P.drop (P.length bs - w) bs
 where
  bs = P.map aoAudio1Bit outs

densityWindow :: Int
densityWindow = 16_384

e2eTests :: TestTree
e2eTests = testGroup "audio end to end"
  [ testCase "the DSM bitstream carries signal once the sensor settles" $ do
      let bits = tailBits densityWindow (runTop 16)
          d    = fromIntegral (ones bits) / fromIntegral densityWindow :: Double
      assertBool ("density " P.<> show d) (d > 0.05 && d < 0.95)

  , testCase "changing the pitch oscillator period changes the bitstream" $ do
      let b16 = tailBits densityWindow (runTop 16)
          b24 = tailBits densityWindow (runTop 24)
          d24 = fromIntegral (ones b24) / fromIntegral densityWindow :: Double
      assertBool ("density " P.<> show d24) (d24 > 0.05 && d24 < 0.95)
      assertBool "bitstreams are identical" (b16 P./= b24)

  , testCase "the 4-bit PCM output also carries signal" $ do
      let nibbles = P.map aoAudioPcm4 (runTop 16)
      assertBool "PCM output is constant"
        (P.length (L.nub (P.drop (e2eClocks - densityWindow) nibbles)) > 1)
  ]

tests :: TestTree
tests = testGroup "audio"
  [ ncoTests
  , sineTests
  , dsmTests
  , pitchMapTests
  , e2eTests
  ]
