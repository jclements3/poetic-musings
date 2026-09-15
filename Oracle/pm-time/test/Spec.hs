-- PM.PpsDiscipline / PM.StrobeLatch proofs — the SYS-006 cases of
-- MAIDEN/firmware/timebase/tb/timebase_tb.vhd, same pass criteria.
--
-- SCALING: the GHDL TB runs RTC_HZ = 1_000_000; here RTC_HZ = 100_000 so a
-- "second" is 100k clocks (a ~30 s scenario is ~3M simulated clocks).
-- LOCK_TOL scales with it (50 ppm -> 5 counts) and +30 ppm -> +3 counts;
-- all ppm relationships are rate-invariant, as the TB header argues.
--
--   T1/T2  nominal PPS -> locked within 3 intervals, |offset| <= 2
--   T5/T6  +30 ppm -> locked, offset = +30 ppm x RTC_HZ (+/-2); -30 ppm likewise
--   J      +/-2 count alternating jitter -> still locked, |offset| <= 2
--   T7     PPS loss -> still locked at 1.4 s, lock dropped by 1.6 s (1.5 s wdog)
--   T9     PPS return -> relocked within 4.5 s
--   T11-13 12 strobes at ~30 Hz with jitter: count 12, no overflow, drain in
--          FIFO order with monotone rtc and contiguous seq
--   L      3 strobes -> 3 records, monotone seq
--   T14/15 17-burst without pops -> overflow sticky, fill 16, seq counts the
--          drop (next record after draining carries seq 17)
import Clash.Prelude
import qualified Prelude as P
import PM.PpsDiscipline
import PM.StrobeLatch
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

rtcHz, lockTol, ppm30 :: Int
rtcHz = 100_000
lockTol = 5
ppm30 = 3

-- Streaming sampler: outputs at the given ascending indices, without
-- retaining the list head (clash-sim-space-leaks memory).
sampleAt :: [Int] -> [a] -> [a]
sampleAt = go 0
 where
  go _ [] _ = []
  go _ _ [] = []
  go !i (n:ns) (x:xs)
    | i == n = x : go (i + 1) ns xs
    | otherwise = go (i + 1) (n:ns) xs

-- PPS pulse block: 100 us high (SEC/1000), then low to fill `period`.
ppsPulse :: Int -> [Bool]
ppsPulse period = P.replicate (rtcHz `div` 1000) True
             P.++ P.replicate (period - rtcHz `div` 1000) False

main :: IO ()
main = do
  ---------------------------------------------------------------- PPS
  let sec = rtcHz
      idle = 10                                     -- reset release
      nominal = P.concatMap ppsPulse (P.replicate 6 sec)          -- 0..6 s
      plus30  = P.concatMap ppsPulse (P.replicate 5 (sec + ppm30)) -- 6..11 s
      minus30 = P.concatMap ppsPulse (P.replicate 5 (sec - ppm30))
      jitter  = P.concatMap ppsPulse (P.take 6 (P.cycle [sec + 2, sec - 2]))
      settle  = P.concatMap ppsPulse (P.replicate 4 sec)
      dead    = P.replicate (10 * sec) False        -- PPS gone 10 s
      back    = P.concatMap ppsPulse (P.replicate 6 sec)
      segs = [nominal, plus30, minus30, jitter, settle, dead, back]
      starts = P.scanl (+) idle (P.map P.length segs)  -- absolute segment starts
      seg k = starts P.!! k
      (tNom, tP30, tM30, tJit, tDead, tBack) = (seg 0, seg 1, seg 2, seg 3, seg 5, seg 6)
      stim = P.replicate idle False P.++ P.concat segs P.++ P.replicate 10 False
      outs = simulate @System (ppsDiscipline (fromIntegral rtcHz) (fromIntegral lockTol)) stim
      -- checkpoints (TB waits: 5.5 s after enable, 4.5 s after each change,
      -- 2.5 s after loss, 4.5 s after return)
      cks = [ tNom + 55 * sec `div` 10           -- T1/T2
            , tP30 + 45 * sec `div` 10           -- T5/T6
            , tM30 + 45 * sec `div` 10           -- -30 ppm
            , tJit + 45 * sec `div` 10           -- jitter
            -- last PPS edge is at tDead - sec (start of the final settle pulse)
            , tDead - sec + 14 * sec `div` 10    -- 1.4 s after last edge: still locked
            , tDead - sec + 16 * sec `div` 10    -- 1.6 s: holdover
            , tDead + 25 * sec `div` 10          -- T7 (2.5 s after PPS enable dropped)
            , tBack + 45 * sec `div` 10          -- T9
            ]
      ck = sampleAt cks outs
      (cNom, cP30, cM30, cJit, c14, c16, c25, cBack) =
        (ck P.!! 0, ck P.!! 1, ck P.!! 2, ck P.!! 3, ck P.!! 4, ck P.!! 5, ck P.!! 6, ck P.!! 7)
      offI o = fromIntegral (offset o) :: Int
  r1 <- check (locked cNom) "T1 locked after nominal PPS"
  r2 <- check (abs (offI cNom) <= 2) ("T2 offset ~0 at nominal (" P.++ P.show (offI cNom) P.++ ")")
  r3 <- check (locked cP30) "T5 locked at +30 ppm"
  r4 <- check (abs (offI cP30 - ppm30) <= 2) ("T6 offset ~ +30 ppm x RTC_HZ (" P.++ P.show (offI cP30) P.++ ")")
  r5 <- check (locked cM30 && abs (offI cM30 + ppm30) <= 2) ("locked at -30 ppm, offset " P.++ P.show (offI cM30))
  r6 <- check (locked cJit && abs (offI cJit) <= 2) ("locked through +/-2 count jitter, offset " P.++ P.show (offI cJit))
  r7 <- check (locked c14) "still locked 1.4 s after PPS loss"
  r8 <- check (not (locked c16)) "holdover: lock dropped 1.6 s after PPS loss (1.5 s watchdog)"
  r9 <- check (not (locked c25)) "T7 lock drops in holdover (2.5 s)"
  r10 <- check (locked cBack) "T9 relock after PPS return"
  r11 <- check (rtc cBack - rtc cNom == fromIntegral (P.last cks - P.head cks)) "RTC free-runs: +1 per clock, never steered"
  r12 <- check (ppsRtc cBack < rtc cBack && rtc cBack - ppsRtc cBack < fromIntegral sec) "TIME_MARK pps_rtc latched within the last second"
  ---------------------------------------------------------------- Strobe
  let strobePulse gap = P.replicate 100 True P.++ P.replicate (gap - 100) False
      -- T11: 12 strobes at ~30 Hz with alternating +/- jitter (SEC/1000)
      thirty i = sec `div` 30 + (if even i then sec `div` 1000 else negate (sec `div` 1000))
      twelve = P.concatMap (strobePulse . thirty) [1 .. 12 :: Int]
      pops n = P.concat (P.replicate n [True, False])   -- rd_en 1 clk, then 1 idle
      burst n = P.concat (P.replicate n (P.replicate 20 True P.++ P.replicate 20 False))
      latchSim :: [(Bool, Bool)] -> [StrobeOut]
      latchSim = simulate @System (\i -> let (s, p) = unbundle i
                                             cnt = register 0 (cnt + 1)
                                         in strobeLatch s cnt p)
      quiet n = P.replicate n (False, False)
      -- scenario A: 12 jittered strobes, settle, drain 12 (+2 extra pops on empty)
      sA = quiet 10 P.++ P.map (\s -> (s, False)) twelve P.++ quiet 50
           P.++ P.map (\p -> (False, p)) (pops 14) P.++ quiet 4
      aStart = 10 + P.length twelve + 50
      oA = latchSim sA
      full12 = sampleAt [aStart - 1] oA
      drained = sampleAt [aStart + 2 * k | k <- [0 .. 13]] oA
      recs = P.take 12 drained
  r13 <- check (P.map count full12 == [12] && not (P.any overflow full12)) "T11/T12 FIFO holds 12, no overflow at 30 Hz"
  r14 <- check (P.all rdValid recs && P.map rdSeq recs == [0 .. 11]) "T13 seqs contiguous 0..11 in pop order"
  r15 <- check (P.and (P.zipWith (<) (P.map rdRtc recs) (P.drop 1 (P.map rdRtc recs)))) "T13 stamps monotonic (FIFO order)"
  r16 <- check (not (P.any rdValid (P.drop 12 drained))) "T13 all 12 drained; extra pops on empty are ignored"
  -- scenario L: 3 strobes -> 3 records
  let sL = quiet 10 P.++ P.map (\s -> (s, False)) (burst 3) P.++ quiet 10
           P.++ P.map (\p -> (False, p)) (pops 3) P.++ quiet 4
      lStart = 10 + 120 + 10
      oL = latchSim sL
      cL = P.head (sampleAt [lStart - 1] oL)
      recL = sampleAt [lStart + 2 * k | k <- [0 .. 2]] oL
  r17 <- check (count cL == 3 && P.map rdSeq recL == [0, 1, 2] && P.all rdValid recL) "3 strobes -> 3 records, monotone seq"
  -- scenario B: 17-burst, no pops; then drain 16 and stamp an 18th
  let sB = quiet 10 P.++ P.map (\s -> (s, False)) (burst 17) P.++ quiet 10
           P.++ P.map (\p -> (False, p)) (pops 16) P.++ quiet 4
           P.++ P.map (\s -> (s, False)) (burst 1) P.++ quiet 10
      bStart = 10 + 17 * 40 + 10
      b18 = bStart + 32 + 4 + 40 + 10
      oB = latchSim sB
      cBs = sampleAt [bStart - 1, b18 - 1] oB
      (cB, cB18) = (P.head cBs, cBs P.!! 1)
      recB = sampleAt [bStart + 2 * k | k <- [0 .. 15]] oB
  r18 <- check (overflow cB) "T14 sticky overflow on 17-burst"
  r19 <- check (count cB == 16) "T15 fill capped at DEPTH"
  r20 <- check (P.map rdSeq recB == [0 .. 15]) "burst pops in FIFO order, seq 0..15"
  r21 <- check (overflow cB18 && rdValid cB18 && rdSeq cB18 == 17 && count cB18 == 1)
           "seq counts the dropped strobe (18th record is seq 17); overflow stays sticky"
  let rs = [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21]
  if P.and rs
    then putStrLn "ALL PASS: PM.PpsDiscipline PM.StrobeLatch" >> exitSuccess
    else exitFailure
