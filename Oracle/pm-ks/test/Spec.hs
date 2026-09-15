-- PM.Ks proofs:
--  1. pitch: loop period within 1 cent of kDelay for 40, 100, 400 samples
--     (zero-crossing period over many cycles, harmonics boxcar-nulled first).
--  2. decay: late amplitude grows monotonically with loop gain.
--  3. fractional delay 0.5 lands between the two integer neighbours, within
--     1 cent of delay + 0.5.
--  4. bank of 4: pluck string 2 only -> 0/1/3 silent, string 2 is bit-exact
--     with ksVoice; pluck all four -> four independent pitches.
--  5. golden: first 64 samples equal golden/ks_model.py (python3).
--  6. Erard 49: packed allocation sums to ErardWords (39260) and every
--     region holds its natural period; pluck A0, C4, G7 at real pitches
--     -> each within 1 cent of 96000/f, the other 46 strings stay silent.
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

-- Bank of n: load the configs (one write per clock), then tick every `sp`
-- clocks with the pluck events given per tick; output sampled at the end of
-- each tick slot.
bankRunN
  :: forall w n. (KnownNat n, 1 <= n, KnownNat w, 1 <= w)
  => SNat w -> Vec n (Unsigned 12) -> Vec n KsCfg
  -> [Maybe (Index n, Unsigned 8)] -> Int -> Int -> [Vec n (Signed 16)]
bankRunN w maxD cfgs plucks sp n =
  let nc   = P.length (toList cfgs)
      load = [ (False, Just (i, c), Nothing) | (i, c) <- P.zip [0 ..] (toList cfgs) ]
      ins  = load P.++ P.concat
               [ (True, Nothing, p) : P.replicate (sp - 1) (False, Nothing, Nothing)
               | p <- P.take n (plucks P.++ P.repeat Nothing) ]
      outs = P.drop nc (simulateN @System (nc + n * sp)
               (\i -> let (t, c, p) = unbundle i in ksBankVec w maxD t c p) ins)
  in [ o | (k, o) <- P.zip [0 :: Int ..] outs, k `P.mod` sp == sp - 1 ]

bankRun :: Vec 4 KsCfg -> [Maybe (Index 4, Unsigned 8)] -> Int -> Int -> [Vec 4 (Signed 16)]
bankRun = bankRunN (SNat @8192) (repeat 2048)

-- Same drive on the raw ksBank stream, de-multiplexed per string (one
-- sample per string per tick); cheaper to simulate for the 49-string bank.
bankStream
  :: forall w n. (KnownNat n, 1 <= n, KnownNat w, 1 <= w)
  => SNat w -> Vec n (Unsigned 12) -> Vec n KsCfg
  -> [Maybe (Index n, Unsigned 8)] -> Int -> Int -> Index n -> [Signed 16]
bankStream w maxD cfgs plucks sp n =
  let load = [ (False, Just (i, c), Nothing) | (i, c) <- P.zip [0 ..] (toList cfgs) ]
      ins  = load P.++ P.concat
               [ (True, Nothing, p) : P.replicate (sp - 1) (False, Nothing, Nothing)
               | p <- P.take n (plucks P.++ P.repeat Nothing) ]
      outs = simulateN @System (P.length load + n * sp)
               (\i -> let (t, c, p) = unbundle i in ksBank w maxD t c p) ins
  in \i -> [ y | Just (j, y) <- outs, j == i ]

-- Running-sum boxcar (same values as boxcar up to float rounding; O(n)).
boxcarFast :: Int -> [Double] -> [Double]
boxcarFast m xs =
  let ps = P.scanl (+) 0 xs
  in P.zipWith (-) (P.drop m ps) ps

-- period with the fast boxcar, for the long Erard strings.
periodFast :: Double -> [Signed 16] -> Double
periodFast p0 raw =
  let ys = P.map P.fromIntegral raw :: [Double]
      dc = P.zipWith (\x b -> x - b / P.fromIntegral (P.round p0 :: Int)) ys (boxcarFast (P.round p0) ys)
      xs = P.foldl (\acc k -> boxcarFast (P.round (p0 / k)) acc) dc [2, 3, 4, 5]
      cr = [ P.fromIntegral i + (-a) / (b - a)
           | (i, (a, b)) <- P.zip [0 :: Int ..] (P.zip xs (P.drop 1 xs)), a < 0, b >= 0 ]
  in if P.length cr < 2 then 0 / 0 else (P.last cr - P.head cr) / P.fromIntegral (P.length cr - 1)

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

pitchTest :: Unsigned 12 -> Unsigned 8 -> Int -> IO (Bool, Double)
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
  -- 6. Erard 49
  let words49 = bankWords erardMaxDelay
      fits = P.and (toList (zipWith (\c d -> kDelay c + 1 <= d) erardCfg erardMaxDelay))
      mn = P.minimum (toList erardMaxDelay); mx = P.maximum (toList erardMaxDelay)
  r11 <- check (words49 == natToNum @ErardWords && fits)
           ("erard: 49 packed regions " P.++ P.show mn P.++ " .. " P.++ P.show mx
            P.++ " words, total " P.++ P.show words49 P.++ " (ErardWords), each >= kDelay + 1")
  let a0 = 48; c4 = 25; g7 = 0 :: Index 49
      hz i = [3136, 2793.8, 2637, 2349.3, 2093, 1975.5, 1760, 1568, 1396.9, 1318.5, 1174.7
             , 1046.5, 987.77, 880, 783.99, 698.46, 659.26, 587.33, 523.25, 493.88, 440
             , 392, 349.23, 329.63, 293.66, 261.63, 246.94, 220, 196, 174.61, 164.81
             , 146.83, 130.81, 123.47, 110, 97.99, 87.31, 82.41, 73.42, 65.41, 61.74, 55
             , 49, 43.65, 41.2, 36.71, 32.7, 30.868, 27.5] P.!! P.fromIntegral i :: Double
      nE = 12 * 3491 + 8
      col = bankStream (SNat @ErardWords) erardMaxDelay erardCfg
              [Just (a0, 200), Just (c4, 200), Just (g7, 200)] 52 nE
      centsOf i cyc =
        let p0 = 96000 / hz i
            n0 = P.round (4 * p0); n1 = P.round (cyc * p0)
        in cents (periodFast p0 (P.take n1 (P.drop n0 (col i)))) p0
      cA = centsOf a0 8; cC = centsOf c4 100; cG = centsOf g7 400
      quiet = P.and [ P.all (== 0) (col i) | i <- [minBound .. maxBound], i `P.notElem` [a0, c4, g7] ]
  r12 <- check (abs cA < 1) ("erard: A0 27.5 Hz within 1 cent (" P.++ P.show cA P.++ " cents)")
  r13 <- check (abs cC < 1) ("erard: C4 261.63 Hz within 1 cent (" P.++ P.show cC P.++ " cents)")
  r14 <- check (abs cG < 1) ("erard: G7 3136 Hz within 1 cent (" P.++ P.show cG P.++ " cents)")
  r15 <- check quiet "erard: the other 46 strings stay silent (no cross-talk)"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15]
    then putStrLn "ALL PASS: PM.Ks" >> exitSuccess
    else exitFailure
