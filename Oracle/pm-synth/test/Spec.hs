-- PM.Synth proofs:
--  1. tuning: A4 (semitone 45: C1=0 -> A4 = 3*12+9) phase inc corresponds to
--     440 Hz at 25 MHz within 0.5 cent; octaves are exact right-shifts.
--  2. pattern 0 is a square: equal high/low time over a full phase cycle.
--  3. ADSSR: attack rises monotonically to max, decays to sustain-1, slopes
--     to sustain-2 and holds; release after gate-off reaches 0 and idles.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Synth
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

main :: IO ()
main = do
  -- 1. tuning
  let incA4 = noteInc 45
      fA4 = P.fromIntegral incA4 * 25.0e6 / 4294967296.0 :: Double
      cents = 1200 * logBase 2 (fA4 / 440.0)
  r1 <- check (abs cents < 0.5) ("A4 = " P.++ P.show fA4 P.++ " Hz (" P.++ P.show cents P.++ " cents)")
  r2 <- check (noteInc 12 == shiftL (noteInc 0) 1) "octave doubling exact (C1->C2)"
  -- 2. square pattern duty over one 8-step cycle
  let duty = P.length [ () | s <- [0 :: Int .. 7]
                      , pulseOsc 0 (fromIntegral s `shiftL` 29) > 0 ]
  r3 <- check (duty == 4) ("pattern 0 duty " P.++ P.show duty P.++ "/8")
  -- 3. envelope: fast rates for sim
  let cfg = EnvCfg { rA = 0, rD = 0, rSl = 0, rR = 0
                   , lS1 = 200, lS2 = 120, tS1 = 50 }
      n = 2000
      gates = P.replicate 1200 True P.++ P.replicate (n - 1200) False
      lvls = simulateN @System n
               (\i -> let (c, g) = unbundle i in adssr c g)
               (P.zip (P.repeat cfg) gates)
      pre = P.take 1200 lvls
      atkEnd = L.findIndex (== 255) pre
      s1Reached = L.findIndex (== 200) (P.drop (maybe 0 id atkEnd) pre)
      s2Zone = P.drop 800 pre
      tailZ = P.drop 1700 lvls
  r4 <- check (atkEnd /= Nothing) "attack reaches full scale"
  r5 <- check (s1Reached /= Nothing) "decay reaches sustain-1 (200)"
  r6 <- check (P.all (== 120) (P.take 100 (P.reverse s2Zone))) "slope settles at sustain-2 (120)"
  r7 <- check (P.all (== 0) (P.take 100 (P.reverse tailZ))) "release reaches silence"
  -- monotonic attack
  let atk = P.takeWhile (/= 255) (P.dropWhile (== 0) pre) P.++ [255]
  r8 <- check (P.and (P.zipWith (<=) atk (P.drop 1 atk))) "attack monotonic"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8]
    then putStrLn "ALL PASS: PM.Synth" >> exitSuccess
    else exitFailure
