{-# LANGUAGE NumericUnderscores #-}

-- | Numerical verification of the 512-point R2SDF FFT against a
-- Double-precision reference DFT.
--
-- == What is checked
--
-- 'fft512' is driven through Clash 'simulateN' with an impulse, single-bin
-- complex sinusoids, and a two-tone signal. The streamed outputs are
-- bit-reverse reordered to natural bin order and compared against a direct
-- O(N^2) reference DFT of the /quantised/ input samples, scaled by 1\/512 to
-- match the hardware's per-stage divide-by-2.
--
-- == Alignment
--
-- The stage counters free-run from reset, so the pipeline treats input cycle
-- @t@ as frame sample @(t - r) mod 512@, where @r@ is however many cycles the
-- simulator holds reset. Rather than hard-code Clash's reset behaviour, a
-- calibration pass finds @r@ by scanning an impulse over the first few input
-- offsets and looking for the flat, all-real spectrum an aligned impulse must
-- produce; the same pass measures the input-to-output latency and a test
-- asserts it equals the architectural @511 + 9*stageLatency@ cycles.
--
-- == Tolerance
--
-- Q1.15 with a rounded divide-by-2 at each of the 9 butterfly ranks:
--
-- * Rounding injects <= 0.5 LSB per component per stage; each injection is
--   attenuated by the later stages' 1\/2 scalings, so the accumulated
--   rounding error at any output bin is a few LSB at most (RMS well under
--   1 LSB).
-- * The twiddles themselves are quantised to 15 bits, a relative error of
--   ~3e-5 per stage; over 8 twiddling stages that is ~2.4e-4 of the bin
--   value, i.e. up to ~6 LSB on a near-full-scale bin (A = 23000).
--
-- Measured worst-case component errors on these vectors (ghci, this
-- revision): impulse 0.002 LSB, tone bin 5: 1.11, bin 100: 1.03, bin 383:
-- 5.03, two-tone: 1.05. The tests allow 2 LSB for the impulse (where every
-- bin is exactly representable at 64) and 8 LSB for the large tones —
-- roughly the measured error plus margin, and far too tight to hide a
-- structural bug: any ordering, alignment, or twiddle error shifts whole
-- bins by thousands of LSB.
module FftSpec (tests) where

import Clash.Prelude (Signed, simulateN, System)
import Prelude

import Data.Bits (bit, testBit, (.|.))
import Data.Complex
import Data.List (findIndex)
import Test.Tasty
import Test.Tasty.HUnit

import Theremin.Fft (Cplx, fft512, stageLatency)

fftN :: Int
fftN = 512

-- | Architectural latency: sum of the delay lines (511) plus the forward
-- pipeline of each of the 9 stages.
expectedLatency :: Int
expectedLatency = 511 + 9 * stageLatency

-- | Simulate one 512-sample frame injected after @p@ idle cycles, returning
-- the raw output stream.
rawSim :: Int -> [Cplx] -> [Cplx]
rawSim p frame = simulateN @System len fft512 ins
 where
  len = p + expectedLatency + fftN + 16
  ins = replicate p (0, 0) ++ frame ++ repeat (0, 0)

-- | The impulse used for calibration: full-scale real spike at sample 0, so
-- every output bin must be 32767\/512 ~ 64, purely real, only when the frame
-- is aligned with the stage counters.
impulseFrame :: [Cplx]
impulseFrame = (32767, 0) : replicate (fftN - 1) (0, 0)

-- | @(inputPhase, measuredLatency)@: the input offset at which the pipeline
-- sees the frame as aligned (equal to however long simulate holds reset),
-- and the observed first-input-to-first-output latency at that offset.
calibration :: (Int, Int)
calibration =
  head
    [ (p, f - p)
    | p <- [0 .. 8]
    , Just f <- [firstLoud (rawSim p impulseFrame)]
    , flatReal (take fftN (drop f (rawSim p impulseFrame)))
    ]
 where
  firstLoud outs = findIndex (\(re, im) -> abs re > 16 || abs im > 16) outs
  flatReal w =
    length w == fftN
      && all (\(re, im) -> abs (re - 64) <= 6 && abs im <= 6) w

inputPhase :: Int
inputPhase = fst calibration

-- | Run one frame through the pipeline, returning the 512 outputs reordered
-- from the stream's bit-reversed index order to natural bin order.
runFft :: [Cplx] -> [Cplx]
runFft frame =
  [ windowed !! bitrev9 k | k <- [0 .. fftN - 1] ]
 where
  windowed =
    take fftN (drop (inputPhase + expectedLatency) (rawSim inputPhase frame))

bitrev9 :: Int -> Int
bitrev9 k = foldl (\acc i -> if testBit k i then acc .|. bit (8 - i) else acc) 0 [0 .. 8]

-- Reference ---------------------------------------------------------------

toC :: Cplx -> Complex Double
toC (re, im) = fromIntegral re :+ fromIntegral im

-- | Direct DFT of the quantised samples, scaled by 1\/N to match the
-- hardware's nine divide-by-2 stages.
refDft :: [Cplx] -> [Complex Double]
refDft xs =
  [ sum [ toC x * cis (-2 * pi * fromIntegral (k * m) / nD) | (m, x) <- zip [0 :: Int ..] xs ] / (nD :+ 0)
  | k <- [0 .. fftN - 1]
  ]
 where
  nD = fromIntegral fftN

-- | Worst absolute component error between hardware and reference, in LSB.
maxErr :: [Cplx] -> [Complex Double] -> Double
maxErr hw ref =
  maximum
    [ max (abs (fromIntegral re - realPart r)) (abs (fromIntegral im - imagPart r))
    | ((re, im), r) <- zip hw ref
    ]

checkAgainstRef :: Double -> [Cplx] -> Assertion
checkAgainstRef tol frame = do
  let e = maxErr (runFft frame) (refDft frame)
  assertBool
    ("max component error " ++ show e ++ " LSB exceeds tolerance " ++ show tol)
    (e <= tol)

-- Signal generators -------------------------------------------------------

quantise :: Double -> Signed 16
quantise = fromInteger . round

-- | Complex sinusoid @A·exp(+2πi·k·m\/512)@: all frame energy in bin @k@,
-- so bin @k@ of the scaled DFT is @A@ (real) and every other bin ~0.
-- Amplitude must keep the complex magnitude within Q1.15 (see module header
-- of Theremin.Fft), hence A <= ~32700.
toneFrame :: Int -> Double -> [Cplx]
toneFrame k a =
  [ ( quantise (a * cos (2 * pi * fromIntegral (k * m) / 512))
    , quantise (a * sin (2 * pi * fromIntegral (k * m) / 512)) )
  | m <- [0 .. fftN - 1]
  ]

twoToneFrame :: [Cplx]
twoToneFrame =
  [ ( quantise (a1 * cos (th 3 m) + a2 * cos (th 250 m))
    , quantise (a1 * sin (th 3 m) + a2 * sin (th 250 m)) )
  | m <- [0 .. fftN - 1]
  ]
 where
  a1 = 12_000 :: Double
  a2 = 8_000 :: Double
  th k m = 2 * pi * fromIntegral (k * m) / 512

-- Tests -------------------------------------------------------------------

tests :: TestTree
tests = testGroup "fft512_r2sdf"
  [ testCase "calibration: latency is 511 + 9*stageLatency" $
      snd calibration @?= expectedLatency

  , testCase "impulse: flat all-real spectrum, every bin 32767/512" $
      checkAgainstRef 2 impulseFrame

  , testCase "single tone, bin 5" $
      checkAgainstRef 8 (toneFrame 5 23_000)

  , testCase "single tone, bin 100" $
      checkAgainstRef 8 (toneFrame 100 23_000)

  , testCase "single tone, bin 383 (upper half)" $
      checkAgainstRef 8 (toneFrame 383 23_000)

  , testCase "two-tone, bins 3 and 250" $
      checkAgainstRef 8 twoToneFrame
  ]
