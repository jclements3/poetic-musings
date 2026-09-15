{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The musical pitch map ("Theremin.Audio.NoteMap") against its own
-- 'Double' reference and against upstream's numbers.
module NoteMapSpec (tests) where

import Clash.Prelude hiding (assert)
import qualified Prelude as P

import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

import Theremin.Audio.NoteMap
import Theremin.Audio.NoteTables (defaultAmpTable, defaultNoteTable, defaultPhaseTable)

ps :: NoteMapParams
ps = defaultNoteMapParams

-- | The combinational map, stage by stage, on one reading.
wordAt :: Integer -> Integer
wordAt p = toInteger (noteToFreqWord defaultPhaseTable note)
 where
  (i, f) = periodToIndex ps (fromInteger p)
  -- Index as Int: @i + 1@ in 'Unsigned 10' would wrap 1023 to 0.
  n0 = defaultNoteTable !! (fromIntegral i :: Int)
  n1 = defaultNoteTable !! (fromIntegral i + 1 :: Int)
  note = interpNote n0 n1 f

hzAt :: Integer -> Double
hzAt p = fromIntegral (wordAt p) * nmClockHz ps / 4_294_967_296

cents :: Double -> Double -> Double
cents a b = 1200 * logBase 2 (a / b)

far, near :: Integer
far  = toInteger (nmFar ps)
near = toInteger (nmNear ps)

aps :: AmpMapParams
aps = defaultAmpMapParams

afar, anear :: Integer
afar  = toInteger (amFar aps)
anear = toInteger (amNear aps)

ampAt :: Integer -> Integer
ampAt p = toInteger (interpAmp a0 a1 f)
 where
  (i, f) = periodToIndexWith (amFar aps) (ampIndexShift aps) (fromInteger p)
  a0 = defaultAmpTable !! (fromIntegral i :: Int)
  a1 = defaultAmpTable !! (fromIntegral i + 1 :: Int)

tests :: TestTree
tests = testGroup "musical maps (upstream port)" [pitchTests, volumeTests]

volumeTests :: TestTree
volumeTests = testGroup "volume map"
  [ testCase "hand away from the loop is full volume" $
      ampAt afar @?= 4095

  , testCase "hand on the loop is silent" $ do
      ampAt anear @?= 0
      ampAt (anear - 1_000_000) @?= 0

  , testCase "upstream's curve: (1 - linear)^2, so mid-travel is already quiet" $ do
      let u = 0.5 :: Double
          linear = log (1 + u * (exp 4.5 - 1)) / 4.5
          want = (1 - linear) * (1 - linear) * 4095
          p = afar - P.round (u * fromIntegral (afar - anear))
      assertBool (show (want, ampAt p)) (P.abs (fromIntegral (ampAt p) - want) < 4)

  , testCase "table steps fit the 9-bit interpolation datapath" $
      let t = P.map toInteger (ampTableList aps)
          steps = P.zipWith (-) t (P.tail t)
      in assertBool (show (P.maximum steps, P.minimum steps)) (P.maximum steps < 512 && P.minimum steps >= 0)

  , testPropertyNamed "within 1/256 full scale of the Double reference"
      "prop_amp_accuracy" $ H.property $ do
      p <- H.forAll (Gen.integral (Range.linear (anear - 200_000) (afar + 200_000)))
      let want = 4095 * ampModel aps (fromIntegral p)
      H.annotateShow (p, want, ampAt p)
      H.assert (P.abs (fromIntegral (ampAt p) - want) < 16)

  , testPropertyNamed "monotone: closer to the loop is never louder"
      "prop_amp_monotone" $ H.property $ do
      a <- H.forAll (Gen.integral (Range.linear (anear - 200_000) (afar + 200_000)))
      b <- H.forAll (Gen.integral (Range.linear (anear - 200_000) (afar + 200_000)))
      H.assert (ampAt (P.min a b) <= ampAt (P.max a b))

  , testPropertyNamed "ampScale is sample * amp / 4096, and the pipeline matches"
      "prop_amp_scale" $ H.property $ do
      s <- H.forAll (Gen.integral (Range.linearFrom 0 (-32_768) 32_767))
      a <- H.forAll (Gen.integral (Range.linear 0 4095))
      let want = (s * a) `P.div` 4096 :: Integer   -- floor, like the arithmetic shift
          got  = toInteger (ampScale (fromInteger s) (fromInteger a))
          piped = simulateN @System 4 (\i -> ampScaleP (fst <$> i) (snd <$> i))
                    (P.replicate 4 (fromInteger s, fromInteger a))
      got H.=== want
      toInteger (P.last piped) H.=== want

  , testCase "the registered amp pipeline agrees with the combinational stages" $ do
      let p = afar - (afar - anear) `P.div` 5
          outs = simulateN @System 8 (ampMap aps defaultAmpTable) (P.replicate 8 (fromInteger p))
      toInteger (P.last outs) @?= ampAt p
  ]

pitchTests :: TestTree
pitchTests = testGroup "pitch map"
  [ testCase "hand away plays A0 = 27.5 Hz" $
      assertBool (show (hzAt far)) (P.abs (cents (hzAt far) 27.5) < 1)

  , testCase "beyond far still plays A0 (clamped, like upstream's table[0])" $
      assertBool (show (hzAt (far + 10_000_000))) (P.abs (cents (hzAt (far + 10_000_000)) 27.5) < 1)

  , testCase "closest approach plays G7 = 3135.96 Hz" $
      assertBool (show (hzAt near)) (P.abs (cents (hzAt near) 3135.96) < 1)

  , testCase "past near is clamped at G7" $
      assertBool (show (hzAt (near - 1_000_000))) (P.abs (cents (hzAt (near - 1_000_000)) 3135.96) < 1)

  , testCase "the exponential linearisation: half travel is NOT the middle note" $ do
      -- Upstream's curve with k = 4.5: at u = 0.5, linear = ln(1 + 0.5(e^4.5 - 1))/4.5
      let u = 0.5 :: Double
          linear = log (1 + u * (exp 4.5 - 1)) / 4.5
          expectMidi = 21 + 82 * linear
          p = far - P.round (u * fromIntegral (far - near))
          gotMidi = 69 + 12 * logBase 2 (hzAt p / 440)
      assertBool (show (linear, expectMidi, gotMidi))
                 (P.abs (gotMidi - expectMidi) < 0.03 && linear > 0.8)

  , testCase "table interpolation differences fit the 11-bit datapath" $
      let t = P.map toInteger (noteTableList ps)
          diffs = P.zipWith (-) (P.tail t) t
      in assertBool (show (P.maximum diffs)) (P.maximum diffs < 2048 && P.minimum diffs >= 0)

  , testCase "phase table: one octave is exactly x2, and MIDI 69 lands on 440 Hz" $ do
      let t = P.map toInteger (phaseTableList ps)
      assertBool (show (P.head t, P.last t)) (P.abs (P.last t - 2 * P.head t) <= 2)
      let a4 = fromIntegral (toInteger (noteToFreqWord defaultPhaseTable (69 * 256)))
               * nmClockHz ps / 4_294_967_296
      assertBool (show a4) (P.abs (cents a4 440) < 0.1)

  , testPropertyNamed "within 3 cents of the Double reference across the whole travel"
      "prop_note_map_accuracy" $ H.property $ do
      p <- H.forAll (Gen.integral (Range.linear (near - 200_000) (far + 200_000)))
      let want = noteMapModel ps (fromIntegral p)
          got  = hzAt p
      H.annotateShow (p, want, got, cents got want)
      H.assert (P.abs (cents got want) < 3)

  , testPropertyNamed "monotone: a shorter period never lowers the pitch"
      "prop_note_map_monotone" $ H.property $ do
      a <- H.forAll (Gen.integral (Range.linear (near - 200_000) (far + 200_000)))
      b <- H.forAll (Gen.integral (Range.linear (near - 200_000) (far + 200_000)))
      H.assert (wordAt (P.min a b) >= wordAt (P.max a b))

  , testCase "the registered pipeline agrees with the combinational stages" $ do
      let p = far - (far - near) `P.div` 3
          outs = simulateN @System 16 (noteMap ps defaultNoteTable defaultPhaseTable)
                   (P.replicate 16 (fromInteger p))
      P.last outs @?= fromInteger (wordAt p)
  ]
