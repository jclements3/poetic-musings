-- PM.Goertzel proofs (8 kHz audio, N = 256, coefficient for 700 Hz):
--  1. 700 Hz tone   -> power above threshold, tone flag true.
--  2. 1200 Hz tone  -> power well below, tone flag false.
--  3. amplitude doubling quadruples the power (quadratic, within 2%).
--  4. hysteresis: a tone at threshold*0.7 keeps the flag once set.
import Clash.Prelude
import qualified Prelude as P
import PM.Goertzel
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

fs :: Double
fs = 8000

tone :: Double -> Double -> Int -> [Signed 16]
tone f a n = [ fromInteger (P.round (a * sin (2 * pi * f * P.fromIntegral i / fs)))
             | i <- [0 .. n - 1] ]

-- run one 256-sample block per clock, return the published power/tone
run :: GoertzelCfg -> [Signed 16] -> [(Unsigned 48, Bool, Bool)]
run cfg xs =
  let n = P.length xs
      out = simulateN @System (n + 2) (\i -> let (c, s) = unbundle i in goertzel c s)
              (P.zip (P.repeat cfg) (P.map (\x -> (True, x)) xs P.++ P.repeat (False, 0)))
  in P.filter (\(_, _, d) -> d) out

main :: IO ()
main = do
  let blk = 256 :: Int
      c700 = goertzelCoeff 700 fs
      -- expected power for amplitude A: (N*A/2)^2 / 2^16
      expP a = (P.fromIntegral blk * a / 2) P.^ (2 :: Int) / 65536 :: Double
      thr = P.round (expP 4000 * 0.25) :: Unsigned 48
      cfg = GoertzelCfg { gcCoeff = c700, gcBlockLen = P.fromIntegral blk, gcThreshold = thr }
      first xs = case xs of { ((p, t, _) : _) -> (p, t); [] -> (0, False) }
      (p700, t700)   = first (run cfg (tone 700 4000 blk))
      (p1200, t1200) = first (run cfg (tone 1200 4000 blk))
      (p8k, _)       = first (run cfg (tone 700 8000 blk))
      ratio = P.fromIntegral p8k / P.fromIntegral p700 :: Double
      rel = P.fromIntegral p700 / expP 4000 :: Double
  r1 <- check (t700 && abs (rel - 1) < 0.1)
          ("700 Hz: power " P.++ P.show p700 P.++ " (expected " P.++ P.show (P.round (expP 4000) :: Integer) P.++ "), tone " P.++ P.show t700)
  r2 <- check (not t1200 && p1200 * 20 < p700)
          ("1200 Hz: power " P.++ P.show p1200 P.++ ", tone " P.++ P.show t1200)
  r3 <- check (abs (ratio - 4) < 0.08) ("amplitude x2 -> power x" P.++ P.show ratio)
  -- hysteresis: blocks at A=4000 (above), then A=2400 (0.36 thr*4 -> between thr/2 and thr)
  let xs = tone 700 4000 blk P.++ tone 700 2400 blk P.++ tone 700 1000 blk
      flags = P.map (\(_, t, _) -> t) (run cfg xs)
  r4 <- check (flags == [True, True, False]) ("hysteresis flags " P.++ P.show flags)
  if P.and [r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.Goertzel" >> exitSuccess
    else exitFailure
