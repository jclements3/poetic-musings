-- PM.Rhythm proofs:
--  1. step sequencer wraps 0..15 with a tick every cycle.
--  2. triggers over 16 ticks equal the ROM row of the pattern per step;
--     every pattern has a bass hit on step 0.
--  3. LFSR period is maximal (65535) for 16 bits.
--  4. each voice decays to 0 after a trigger (and was nonzero first).
--  5. no voice nor the mix exceeds full scale while patterns run.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Rhythm
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

main :: IO ()
main = do
  -- 1. wrap
  let steps = simulateN @System 40 (\i -> let (t, r) = unbundle i in stepSeq t r)
                (P.replicate 40 (True, True))
  r1 <- check (steps P.== P.map (P.fromIntegral . (`P.mod` 16)) [0 :: Int .. 39]) "16-step wrap"
  -- 2. pattern lookup via triggers (tick every 4 cycles, pattern 6 BOSSA)
  let n = 64
      ins = [ (6 :: Index 10, i `P.mod` 4 == 0, True) | i <- [0 :: Int .. n - 1] ]
      trigs = simulateN @System n (\i -> let (p, t, r) = unbundle i in rhythmTrig p t r) ins
      onTicks = [ tr | (tr, (_, t, _)) <- P.zip trigs ins, t ]
      expect = [ rhythmStep 6 s | s <- [0 .. 15] ]
  r2 <- check (onTicks P.== expect) "triggers match ROM row per step"
  r3 <- check (P.and [ rhythmStep p 0 ! (2 :: Int) == 1 | p <- [0 .. 9] ]) "every pattern has bass on step 0"
  r4 <- check (P.all (== 0) [ tr | (tr, (_, t, _)) <- P.zip trigs ins, not t ]) "triggers are single-cycle pulses"
  -- 3. LFSR
  let seed = 0xACE1 :: BitVector 16
      orbit = P.takeWhile (/= seed) (P.drop 1 (P.iterate lfsrStep seed))
  r5 <- check (P.length orbit == 65534) ("LFSR period " P.++ P.show (P.length orbit + 1) P.++ " = 2^16-1")
  -- 4. decay
  let m = 400
      trg = True : P.replicate (m - 1) False
      sn = simulateN @System m (\i -> let (t, r) = unbundle i in noiseVoice t r) (P.zip trg (P.repeat 0))
      bs = simulateN @System m (\i -> let (t, r, c) = unbundle i in bassVoice t r c) (P.zip3 trg (P.repeat 0) (P.repeat 2000))
      decays xs = P.any (/= 0) xs && P.all (== 0) (P.drop 300 xs)
  r6 <- check (decays sn) "noise voice decays to 0 after trigger"
  r7 <- check (decays bs) "bass voice decays to 0 after trigger"
  -- 5. full scale
  let k = 4000
      rin = [ (p, cfg, i `P.mod` 20 == 0, True) | i <- [0 :: Int .. k - 1], let p = P.fromIntegral ((i `P.div` 400) `P.mod` 10) ]
      cfg = PercCfg { rBass = 1, rSnare = 1, rHat = 0, iBass = 3000 }
      (_, mixo) = P.unzip (simulateN @System k (\i -> let (p, c, t, r) = unbundle i in bundle (rhythmUnit p c t r)) rin)
      inRange xs = P.all (\x -> x >= -2047 && x <= 2047) xs
  r8 <- check (inRange sn && inRange bs && inRange mixo && L.maximum (P.map abs mixo) > 0) "no voice or mix exceeds full scale"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8]
    then putStrLn "ALL PASS: PM.Rhythm" >> exitSuccess
    else exitFailure
