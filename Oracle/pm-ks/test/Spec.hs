-- PM.Ks proofs:
--  1. pitch: loop period within 1 cent of kDelay for 40, 100, 400 samples
--     (zero-crossing period over many cycles, harmonics boxcar-nulled first).
--  2. decay: late amplitude grows monotonically with loop gain.
--  3. fractional delay 0.5 lands between the two integer neighbours, within
--     1 cent of delay + 0.5.
--  4. bank of 4: pluck string 2 only -> 0/1/3 silent, string 2 is bit-exact
--     with ksVoice; pluck all four -> four independent pitches.
--  5. golden: first 64 samples equal golden/ks_model.py (python3).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Ks
import System.Exit (exitFailure, exitSuccess)
import System.Process (readProcess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- One string: tick every clock, pluck with velocity v at tick 0, n samples.
voiceRun :: KsCfg -> Unsigned 8 -> Int -> [Signed 16]
voiceRun cfg v n =
  simulateN @System n
    (\i -> let (t, c, p) = unbundle i in ksVoice t c p)
    (P.zip3 (P.repeat True) (P.repeat cfg) (Just v : P.repeat Nothing))

-- Bank of 4: tick every `sp` clocks, pluck events given per tick, output
-- sampled at the end of each tick slot.
bankRun :: Vec 4 KsCfg -> [Maybe (Index 4, Unsigned 8)] -> Int -> Int -> [Vec 4 (Signed 16)]
bankRun cfgs plucks sp n =
  let ins = P.concat [ (True, cfgs, p) : P.replicate (sp - 1) (False, cfgs, Nothing)
                     | p <- P.take n (plucks P.++ P.repeat Nothing) ]
      outs = simulateN @System (n * sp)
               (\i -> let (t, c, p) = unbundle i in ksBank t c p) ins
  in [ o | (k, o) <- P.zip [0 :: Int ..] outs, k `P.mod` sp == sp - 1 ]

-- Boxcar of length m (linear phase: zero-crossing period is unchanged).
boxcar :: Int -> [Double] -> [Double]
boxcar m xs = [ P.sum w | w <- P.map (P.take m) (L.tails xs), P.length w == m ]

-- Mean period from positive-going zero crossings with linear interpolation.
-- The KS burst has a slow DC term and harmonics as strong as the
-- fundamental, so first remove DC (x - boxcar P / P) and null harmonics
-- 2..6 with boxcars of ~P/2, P/3, P/4, P/5 (7th and up fall below 1e-3).
period :: Double -> [Signed 16] -> Double
period p0 raw =
  let ys = P.map P.fromIntegral raw :: [Double]
      dc = P.zipWith (\x b -> x - b / P.fromIntegral (P.round p0 :: Int)) ys (boxcar (P.round p0) ys)
      xs = P.foldl (\acc k -> boxcar (P.round (p0 / k)) acc) dc [2, 3, 4, 5]
      cr = [ P.fromIntegral i + (-a) / (b - a)
           | (i, (a, b)) <- P.zip [0 :: Int ..] (P.zip xs (P.drop 1 xs)), a < 0, b >= 0 ]
  in if P.length cr < 2 then 0 / 0 else (P.last cr - P.head cr) / P.fromIntegral (P.length cr - 1)

cents :: Double -> Double -> Double
cents measured target = 1200 * logBase 2 (target / measured)

-- Pitch of one string: skip the first 5 periods, measure over `cyc` periods.
pitchOf :: KsCfg -> Int -> Double
pitchOf cfg cyc =
  let p0 = P.fromIntegral (kDelay cfg) + P.fromIntegral (kFrac cfg) / 256 :: Double
      n0 = P.round (5 * p0); n1 = P.round (P.fromIntegral cyc * p0)
  in period p0 (P.take n1 (P.drop n0 (voiceRun cfg 200 (n0 + n1))))

pitchTest :: Unsigned 11 -> Unsigned 8 -> Int -> IO (Bool, Double)
pitchTest d f cyc = do
  let target = P.fromIntegral d + P.fromIntegral f / 256 :: Double
      meas = pitchOf (KsCfg d f 255) cyc
      c = cents meas target
  ok <- check (abs c < 1)
          ("delay " P.++ P.show d P.++ "+" P.++ P.show f P.++ "/256: period "
           P.++ P.show meas P.++ " (" P.++ P.show c P.++ " cents)")
  P.pure (ok, meas)

main :: IO ()
main = do
  -- 1. pitch
  (r1, _) <- pitchTest 40 0 200
  (r2, _) <- pitchTest 100 0 150
  (r3, _) <- pitchTest 400 0 50
  -- 2. decay: peak |y| in ticks 4000..4400 grows with gain
  let late g = P.maximum (P.map (abs . P.fromIntegral) (P.take 400 (P.drop 4000 (voiceRun (KsCfg 100 0 g) 200 4400)))) :: Int
      gains = [128, 192, 224, 240, 248, 255] :: [Unsigned 8]
      amps = P.map late gains
  r4 <- check (P.and (P.zipWith (<) amps (P.drop 1 amps)))
          ("decay tracks gain: late amplitudes " P.++ P.show (P.zip gains amps))
  -- 3. fractional delay
  (r5, pHalf) <- pitchTest 100 128 150
  let pLo = pitchOf (KsCfg 100 0 255) 150
      pHi = pitchOf (KsCfg 101 0 255) 150
  r6 <- check (pLo < pHalf && pHalf < pHi)
          ("frac 0.5 between neighbours: " P.++ P.show (pLo, pHalf, pHi))
  -- 4. bank
  let cfgs = KsCfg 40 0 255 :> KsCfg 60 0 255 :> KsCfg 100 0 255 :> KsCfg 150 0 255 :> Nil
      nB = 3000
      one = bankRun cfgs [Just (2, 200)] 8 nB
      s :: Index 4 -> [Signed 16]
      s i = P.map (!! i) one
      solo = voiceRun (KsCfg 100 0 255) 200 nB
  r7 <- check (P.all (P.all (== 0)) [s 0, s 1, s 3]) "bank: strings 0/1/3 silent when 2 is plucked"
  r8 <- check (s 2 == solo) "bank: string 2 bit-exact with ksVoice"
  let allP = bankRun cfgs [Just (0, 200), Just (1, 200), Just (2, 200), Just (3, 200)] 8 nB
      per :: Index 4 -> Double
      per i = let p0 = P.fromIntegral (kDelay (cfgs !! i)) :: Double
                  ys = P.map (!! i) allP
              in cents (period p0 (P.take 2000 (P.drop (P.round (8 * p0)) ys))) p0
      cs = P.map per [0, 1, 2, 3]
  r9 <- check (P.all ((< 1) . abs) cs) ("bank: four independent pitches, cents " P.++ P.show cs)
  -- 5. golden model
  py <- readProcess "python3" ["golden/ks_model.py", "100", "64", "250", "200", "64"] ""
  let golden = P.map P.read (P.words py) :: [Int]
      hw = P.map P.fromIntegral (voiceRun (KsCfg 100 64 250) 200 64) :: [Int]
      maxErr = P.maximum (P.zipWith (\a b -> abs (a - b)) golden hw)
  r10 <- check (P.length golden == 64 && maxErr <= 3)
           ("golden model: 64 samples, max |err| = " P.++ P.show maxErr P.++ " LSB")
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10]
    then putStrLn "ALL PASS: PM.Ks" >> exitSuccess
    else exitFailure
