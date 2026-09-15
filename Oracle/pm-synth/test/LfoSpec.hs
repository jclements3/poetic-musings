-- PM.Lfo proofs:
--  1. period: with rate 3 the output repeats every 256*4 = 1024 cycles.
--  2. peak = depth, trough = -depth once the ramp has settled.
--  3. zero-mean over one period.
--  4. depth ramp: at the first peak the ramped depth (128) is below a
--     200 target, so the first peak is 128, not 200.
--  5. vibrato at depth 0 leaves the increment unchanged; tremolo at depth 0
--     is unity.
import Clash.Prelude
import qualified Prelude as P
import PM.Lfo
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

run :: Int -> Unsigned 16 -> Unsigned 8 -> [Signed 9]
run n rate depth = simulateN @System n
  (\i -> let (r, d, t) = unbundle i in lfo r d t)
  (P.replicate n (rate, depth, False))

main :: IO ()
main = do
  let per = 1024 :: Int
      outs = run (3 * per) 3 100
      settled = P.drop per outs
      one = P.take per settled
  r1 <- check (P.take per settled P.== P.take per (P.drop per settled)) "period = 256*(rate+1) cycles exact"
  r2 <- check (P.maximum one == 100 && P.minimum one == -100) ("peak/trough = +/-depth: " P.++ P.show (P.maximum one, P.minimum one))
  r3 <- check (P.sum (P.map (P.fromIntegral :: Signed 9 -> Int) one) == 0) "zero mean over a period"
  let ramp = run per 3 200
      firstPeak = P.maximum (P.take (129 * 4) ramp)
  r4 <- check (firstPeak == 128) ("depth ramps at one unit per step (first peak " P.++ P.show firstPeak P.++ " of 200)")
  r5 <- check (P.all (\i -> vibrato i 0 == i) [0, 1, 12345678, 0x7fffffff]) "vibrato depth 0 leaves increment unchanged"
  r6 <- check (vibrato 4096000 255 > 4096000 && vibrato 4096000 (-255) < 4096000) "vibrato sign follows modulation"
  r7 <- check (P.all (\s -> tremolo s 0 0 == s) [-2047, -1, 0, 1, 2047]) "tremolo depth 0 is unity"
  r8 <- check (P.all (\m -> abs (tremolo 2047 100 m) <= 2047) [-100 .. 100]) "tremolo never exceeds unity"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8]
    then putStrLn "ALL PASS: PM.Lfo" >> exitSuccess
    else exitFailure
