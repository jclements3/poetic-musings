-- PM.Audio proofs:
--  1. sigma-delta density: for DC codes, mean(ones) == code/4096 within 1%.
--  2. NCO frequency: zero crossings over N samples match phaseInc prediction
--     within one cycle; amplitude peaks near +/-2047.
--  3. mixer: unity channel passes through, gains shift, saturation clips
--     symmetric, mute zeroes.
import Clash.Prelude
import qualified Prelude as P
import PM.Audio
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok msg = do
  putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ msg)
  P.pure ok

main :: IO ()
main = do
  -- 1. DAC density
  let densOK code =
        let n = 8192 :: Int
            bits = P.drop 64 (sampleN @System (n + 64) (sdDac (pure code)))
            ones = P.length (P.filter (== 1) bits)
            want = P.fromIntegral code / 4096 * P.fromIntegral n :: Double
        in abs (P.fromIntegral ones - want) < 0.01 * 8192 + 2
  r1 <- check (P.all densOK [0x000, 0x400, 0x800, 0xC00, 0xFFF])
              "sigma-delta density tracks code (0..fs, 1%)"
  -- 2. NCO frequency: inc = 2^32/64 -> period 64 samples -> 128 samples = 2 cycles
  let inc = 0x04000000 :: Unsigned 32
      n2 = 6400 :: Int
      ys = P.drop 1 (sampleN @System (n2 + 1) (nco (pure inc)))
      zc = P.length [ () | (a, b) <- P.zip ys (P.drop 1 ys), a < 0, b >= 0 ]
      cyclesWant = n2 `P.div` 64 :: Int
      pk = P.maximum ys
  r2 <- check (abs (zc - cyclesWant) <= 1) ("NCO cycles " P.++ P.show zc P.++ " ~= " P.++ P.show cyclesWant)
  r3 <- check (pk >= 2000) ("NCO peak " P.++ P.show pk P.++ " near full scale")
  -- 3. mixer
  let m ch g = mixer4 ch g False
  r4 <- check (m (1000 :> 0 :> 0 :> 0 :> Nil) (0 :> 7 :> 7 :> 7 :> Nil) == 1000)
              "mixer unity pass-through"
  r5 <- check (m (1000 :> 0 :> 0 :> 0 :> Nil) (2 :> 7 :> 7 :> 7 :> Nil) == 250)
              "mixer -12dB shift"
  r6 <- check (m (2000 :> 2000 :> 0 :> 0 :> Nil) (0 :> 0 :> 7 :> 7 :> Nil) == 2047)
              "mixer saturates high"
  r7 <- check (m ((-2000) :> (-2000) :> 0 :> 0 :> Nil) (0 :> 0 :> 7 :> 7 :> Nil) == -2048)
              "mixer saturates low"
  r8 <- check (mixer4 (2000 :> 2000 :> 2000 :> 2000 :> Nil) (repeat 0) True == 0)
              "mute zeroes"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8]
    then putStrLn "ALL PASS: PM.Audio" >> exitSuccess
    else exitFailure
