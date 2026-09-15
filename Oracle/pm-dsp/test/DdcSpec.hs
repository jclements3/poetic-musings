-- PM.Ddc proofs (65 MHz ADC clock, R = 512 -> 126.95 kS/s):
--  1. 1.000 MHz tone (A = 1000), NCO at 1.000 MHz -> I settles to DC of
--     10.24*A within 10%, |Q| near zero (< 5% of I).
--  2. tone at 1.005 MHz, NCO at 1.000 MHz -> I/Q rotate at 5 kHz: period of
--     I zero crossings = 126953/5000 = 25.39 decimated samples (±3%).
import Clash.Prelude
import qualified Prelude as P
import PM.Ddc
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

fclk :: Double
fclk = 65.0e6

freqWord :: Double -> Unsigned 32
freqWord f = fromInteger (P.round (f * 4294967296 / fclk))

adcTone :: Double -> Double -> Int -> [Signed 12]
adcTone f a n = [ fromInteger (P.round (a * cos (2 * pi * f * P.fromIntegral i / fclk)))
                | i <- [0 .. n - 1] ]

runDdc :: Double -> [Signed 12] -> [(Signed 16, Signed 16)]
runDdc fnco xs =
  let n = P.length xs
      out = simulateN @System n
              (\i -> let (fw, x) = unbundle i in ddc (SNat @512) fw x)
              (P.zip (P.repeat (freqWord fnco)) xs)
  in [ (i, q) | (i, q, v) <- out, v ]

main :: IO ()
main = do
  let a = 1000 :: Double
      n1 = 512 * 60
      o1 = P.drop 30 (runDdc 1.0e6 (adcTone 1.0e6 a n1))
      iAvg = P.sum (P.map (P.fromIntegral . fst) o1) / P.fromIntegral (P.length o1) :: Double
      qMax = P.maximum (P.map (abs . P.fromIntegral . snd) o1) :: Double
      expI = a / 2 * 32 * firDcGain
  r1 <- check (abs (iAvg / expI - 1) < 0.1)
          ("DC I = " P.++ P.show iAvg P.++ " (expected " P.++ P.show expI P.++ ")")
  r2 <- check (qMax < 0.05 * expI) ("|Q| max = " P.++ P.show qMax)
  let n2 = 512 * 200
      o2 = P.drop 30 (runDdc 1.0e6 (adcTone 1.005e6 a n2))
      is = P.map (P.fromIntegral . fst) o2 :: [Double]
      rises = [ k | (k, (p, q)) <- P.zip [0 :: Int ..] (P.zip is (P.drop 1 is)), p < 0, q >= 0 ]
      period = P.fromIntegral (P.last rises - P.head rises) / P.fromIntegral (P.length rises - 1) :: Double
      expP = (fclk / 512) / 5000
      peak = P.maximum is
  r3 <- check (P.length rises > 3 && abs (period / expP - 1) < 0.03)
          ("5 kHz offset: I period " P.++ P.show period P.++ " samples (expected " P.++ P.show expP P.++ ")")
  r4 <- check (abs (peak / expI - 1) < 0.15) ("rotation amplitude " P.++ P.show peak)
  if P.and [r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.Ddc" >> exitSuccess
    else exitFailure
