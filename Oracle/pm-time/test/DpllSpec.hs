-- PM.Dpll proofs — GPS/DESIGN.md "Verification" item 1, on the composed
-- PpsDiscipline (measurement layer) + Dpll (steered layer).
--
-- SCALING: clk_sys = 500 kHz, out = 100 kHz (hardware 100 MHz / 10 MHz);
-- ppm relationships are rate-invariant. A +30 ppm crystal is modelled as a
-- PPS period of SYS + 15 clocks. Gains kp = 2, ki = 5, slew 4096 ppb/s,
-- lock after 8 in-threshold (2 us) seconds. Timeline (s):
--    0..50  PPS at +30 ppm: PpsDiscipline locks ~4 s, DPLL acquires
--   50..60  PPS gone: holdover, trim frozen
--   60..80  PPS back: relock
--
--   C1  trim within +/-100 ppb (0.1 ppm) of -30000 ppb by 30 s, stays there
--   C2  dpllLocked by 30 s
--   C3  output at OUT: ticks over 10 PPS seconds (40..50 s) == 10 x OUT
--       (+/-1, i.e. <= 1 ppm at this scale) and |phase error| <= 100 ns/s (0.1 ppm) at 50 s
--   C4  holdover: trim at 60 s == trim at 52 s; holdover flag; lock dropped
--   C5  relock by 80 s, trim still within 100 ppb
--   C6  tick spacing always in {4,5,6} and never jumps by more than 1
--       (phase step <= one system clock), over the entire run
--   C7  PPS out: one pulse per OUT ticks while locked, coincident with a tick
--   C8  RTC layer unchanged: PpsDiscipline offset = +15 counts, rtc +1/clock
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.PpsDiscipline hiding (ppsOut)
import PM.Dpll
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

sysHz, outHz, err30 :: Int
sysHz = 500_000
outHz = 100_000
err30 = 15                                -- +30 ppm x 500 kHz

consts :: DpllConsts
consts = dpllConsts (P.fromIntegral sysHz) (P.fromIntegral outHz) 4096 8

cfg :: DpllCfg
cfg = DpllCfg { kp = 2, ki = 5, lockThr = 2000, forceHold = False }

ppsPulse :: Int -> [Bool]
ppsPulse period = P.replicate (sysHz `div` 1000) True
             P.++ P.replicate (period - sysHz `div` 1000) False

system :: HiddenClockResetEnable dom => Signal dom Bool -> Signal dom (PpsOut, DpllOut)
system ppsIn = bundle (po, d)
 where
  po = ppsDiscipline (P.fromIntegral sysHz) 25 ppsIn
  d = dpll consts (pure cfg) (ppsStb <$> po) (locked <$> po)

-- Streaming fold state: checkpoints + spacing + tick/pps statistics.
data Acc = Acc
  { ckpts :: ![(Int, (PpsOut, DpllOut))]
  , lastTick :: !Int, lastGap :: !Int, minGap :: !Int, maxGap :: !Int, jump :: !Int
  , ticks40 :: !Int, pps40 :: !Int, ppsOffTick :: !Int
  , trimOk :: !Bool, lockOk :: !Bool, trimHold :: !Bool
  }

main :: IO ()
main = do
  let sec = sysHz
      idle = 10
      stim = P.replicate idle False
          P.++ P.concatMap ppsPulse (P.replicate 50 (sec + err30))
          P.++ P.replicate (10 * (sec + err30)) False
          P.++ P.concatMap ppsPulse (P.replicate 20 (sec + err30))
          P.++ P.replicate 10 False
      total = P.length stim
      at s = idle + s * (sec + err30)              -- PPS (true) seconds
      cks = P.map at [30, 40, 50, 52, 60, 80]
      outs = simulate @System system stim
      near t = abs (P.fromIntegral t + 30000 :: Int) <= 100
      step a (i, o@(_, d))
        = let t = P.fromIntegral (trim d) :: Int
              gap = i - lastTick a
              inWin = i >= at 40 && i < at 50
              a1 | tick d = a { lastTick = i, lastGap = if lastTick a < 0 then -1 else gap
                              , minGap = if lastTick a < 0 then minGap a else min (minGap a) gap
                              , maxGap = if lastTick a < 0 then maxGap a else max (maxGap a) gap
                              , jump = if lastTick a < 0 || lastGap a < 0 then jump a else max (jump a) (abs (gap - lastGap a))
                              , ticks40 = if inWin then ticks40 a + 1 else ticks40 a }
                 | otherwise = a
              a2 = a1 { pps40 = if inWin && ppsOut d then pps40 a + 1 else pps40 a
                      , ppsOffTick = if ppsOut d && not (tick d) then ppsOffTick a + 1 else ppsOffTick a
                      , trimOk = trimOk a && (i < at 30 || i >= at 50 || near t)
                      , lockOk = lockOk a && (i < at 30 || i >= at 50 || dpllLocked d)
                      , trimHold = trimHold a && (i <= at 52 || i > at 60 || t == P.fromIntegral (trim (P.snd (ck 52 a))))
                      , ckpts = if i `P.elem` cks then (i, o) : ckpts a else ckpts a }
          in a2
      ck s a = case P.lookup (at s) (ckpts a) of
                 Just o -> o
                 Nothing -> P.error "checkpoint"
      acc0 = Acc [] (-1) (-1) maxBound 0 0 0 0 0 True True True
      acc = L.foldl' step acc0 (P.zip [0 ..] (P.take total outs))
      (p30, d30) = ck 30 acc
      (_, d40) = ck 40 acc
      (_, d50) = ck 50 acc
      (_, d52) = ck 52 acc
      (p60, d60) = ck 60 acc
      (p80, d80) = ck 80 acc
      trimI d = P.fromIntegral (trim d) :: Int
      -- phase over 40..50 s from the tick counts: 10 s x OUT ticks expected
      expTicks = 10 * outHz
      ppmWin = P.fromIntegral (ticks40 acc - expTicks) * 1e6 / P.fromIntegral expTicks :: Double
  putStrLn ("trim (ppb) at 30/40/50/52/60/80 s: " P.++ P.show (P.map trimI [d30, d40, d50, d52, d60, d80]))
  putStrLn ("phase error (ns) at 30/50/80 s: " P.++ P.show (P.map phaseErr [d30, d50, d80]))
  putStrLn ("ticks in 40..50 s: " P.++ P.show (ticks40 acc) P.++ " (" P.++ P.show ppmWin P.++ " ppm)")
  putStrLn ("tick spacing min/max/maxjump: " P.++ P.show (minGap acc, maxGap acc, jump acc))
  r1 <- check (near (trim d30) && trimOk acc) "C1 trim within 0.1 ppm of -30 ppm from 30 s on"
  r2 <- check (dpllLocked d30 && lockOk acc) "C2 DPLL locked from 30 s on (PpsDiscipline lock ~4 s + acquisition)"
  r3 <- check (abs (ticks40 acc - expTicks) <= 1 && abs (P.fromIntegral (phaseErr d50) :: Int) <= 100)
          ("C3 output at OUT over 40..50 s (" P.++ P.show ppmWin P.++ " ppm), |phase err| <= 100 ns/s at 50 s")
  r4 <- check (trimHold acc && holdover d60 && not (dpllLocked d60) && trimI d60 == trimI d52)
          "C4 holdover: trim frozen, holdover flag, lock dropped"
  r5 <- check (not (holdover d50) && not (holdover d80)) "holdover flag clear while PPS valid"
  r6 <- check (dpllLocked d80 && near (trim d80)) "C5 relocked by 20 s after PPS return, trim within 0.1 ppm"
  r7 <- check (minGap acc >= 4 && maxGap acc <= 6 && jump acc <= 1)
          "C6 divider phase step never exceeds one system clock"
  r8 <- check (pps40 acc == 10 && ppsOffTick acc == 0) ("C7 1 PPS out: 10 pulses in 40..50 s, all on ticks (" P.++ P.show (pps40 acc) P.++ ")")
  r9 <- check (P.fromIntegral (offset p30) == err30 && locked p30 && not (locked p60) && locked p80
               && rtc p80 - rtc p30 == P.fromIntegral (50 * (sec + err30)))
          "C8 measurement layer untouched: offset +30 ppm, lock/holdover/relock, RTC +1/clk"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9]
    then putStrLn "ALL PASS: PM.Dpll" >> exitSuccess
    else exitFailure
