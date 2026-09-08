-- PM.SleighSpeed proof: decode the serial line with PM.HarpLink.uartRx and
-- assert the (0xA5, speed) frames track pitch, clamp at both ends, and the
-- volume dead-man forces 0. Also pins the cross-clock baud arithmetic:
-- 25 MHz / div 100 == 50 MHz / div 200 (the Cu's receive divisor).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.Maybe as M
import qualified Data.List as L
import PM.SleighSpeed
import PM.HarpLink (uartRx)
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

cfg :: SleighCfg
cfg = SleighCfg { scPitchMin = 1000, scShift = 3, scVolTh = 200
                , scFrameIv = 400, scDiv = 4 }

-- pitch/vol script: ramp up with vol on, then vol off, then low pitch
seg :: Int
seg = 3000
pitchIn, volIn :: [Unsigned 16]
pitchIn = P.concat [ P.replicate seg p | p <- [1200, 1800, 2600] ]
       P.++ P.replicate seg 2600      -- (vol off here)
       P.++ P.replicate seg 500       -- below pitchMin, vol back on
volIn = P.replicate (3*seg) 800 P.++ P.replicate seg 50 P.++ P.replicate seg 800

frames :: [(BitVector 8, BitVector 8)]
frames = pair (M.catMaybes rxBytes)
 where
  n = 5 * seg
  sys :: HiddenClockResetEnable dom => Signal dom (Maybe (BitVector 8))
  sys = uartRx (pure (scDiv cfg))
              (sleighSpeed cfg (fromList (pitchIn P.++ P.repeat 0))
                               (fromList (volIn P.++ P.repeat 0)))
  rxBytes = sampleN @System n sys
  pair (a:b:rest) | a == 0xA5 = (a, b) : pair rest
                  | otherwise = pair (b:rest)   -- resync (shouldn't happen)
  pair _ = []

main :: IO ()
main = do
  let spds = P.map (fromIntegral . snd) frames :: [Int]
  r0 <- check (P.length frames >= 6) ("got frames: " P.++ P.show (P.length frames))
  r1 <- check (P.all (\(s, _) -> s == 0xA5) frames) "every frame syncs with 0xA5"
  -- expected speeds: (1200-1000)>>3=25, (1800-1000)>>3=100, (2600-1000)>>3=200,
  -- then dead-man 0, then clamp-to-1 (pitch below min, vol on)
  let expects = [25, 100, 200, 0, 1]
      hits e = e `P.elem` spds
  r2 <- check (P.all hits expects)
              ("speed sequence covers " P.++ P.show expects P.++ ": " P.++ P.show (L.nub spds))
  let idx v = P.length (P.takeWhile (/= v) spds)
  r3 <- check (idx 25 < idx 100 && idx 100 < idx 200 && idx 200 < idx 0 && idx 0 < idx 1)
              "speeds arrive in script order (ramp, dead-man, clamp)"
  r4 <- check ((25_000_000 `P.div` 100) == (50_000_000 `P.div` (200 :: Int)))
              "baud math: ULX3S div 100 @25MHz == Cu div 200 @50MHz (250 kbaud)"
  if P.and [r0, r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.SleighSpeed" >> exitSuccess else exitFailure
