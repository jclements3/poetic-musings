-- PM.AmDemod proofs (32 kS/s I/Q, one sample per clock):
--  1. AM signal: carrier 10000 counts at 3 kHz baseband offset, 1 kHz tone,
--     50% modulation -> audio period 32 samples (1 kHz).
--  2. audio amplitude / DC level = 0.5 * lpf gain(1 kHz) within 10%.
--  3. DC level ~= G * carrier within 5%.
import Clash.Prelude
import qualified Prelude as P
import PM.AmDemod
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

main :: IO ()
main = do
  let fs = 32000 :: Double
      n = 24000
      carrier = 10000 :: Double
      iq = [ (fromInteger (P.round (e * cos ph)), fromInteger (P.round (e * sin ph)))
           | k <- [0 .. n - 1]
           , let t = P.fromIntegral k / fs
                 e = carrier * (1 + 0.5 * sin (2 * pi * 1000 * t))
                 ph = 2 * pi * 3000 * t ]
      out = simulateN @System n (\i -> let (k, s) = unbundle i in amDemod k s)
              (P.zip (P.repeat 1) (P.map (\x -> (True, x)) iq))
      valid = [ (a, d) | (a, d, v) <- out, v ]
      settled = P.drop 16000 valid
      audio = P.map (P.fromIntegral . fst) settled :: [Double]
      dcs = P.map (P.fromIntegral . snd) settled :: [Double]
      amp = (P.maximum audio - P.minimum audio) / 2 * 4   -- undo >>2
      dc = P.sum dcs / P.fromIntegral (P.length dcs)
      -- zero crossings (rising) -> period
      rises = [ i | (i, (a, b)) <- P.zip [0 :: Int ..] (P.zip audio (P.drop 1 audio)), a < 0, b >= 0 ]
      period = P.fromIntegral (P.last rises - P.head rises) / P.fromIntegral (P.length rises - 1) :: Double
      -- first-order IIR alpha = 1/2 gain at 1 kHz
      w = 2 * pi * 1000 / fs
      g = 0.5 / sqrt ((1 - 0.5 * cos w) P.^ (2 :: Int) + (0.5 * sin w) P.^ (2 :: Int))
      ratio = amp / dc
      expect = 0.5 * g
  r1 <- check (abs (period - 32) < 0.5) ("audio period " P.++ P.show period P.++ " samples (1 kHz @ 32k = 32)")
  r2 <- check (abs (ratio / expect - 1) < 0.1)
          ("modulation ratio " P.++ P.show ratio P.++ " vs expected " P.++ P.show expect)
  r3 <- check (abs (dc / (cordicGain * carrier) - 1) < 0.05)
          ("DC level " P.++ P.show dc P.++ " vs G*carrier " P.++ P.show (cordicGain * carrier))
  r4 <- check (P.length valid > 20000) ("valid strobes " P.++ P.show (P.length valid))
  if P.and [r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.AmDemod" >> exitSuccess
    else exitFailure
