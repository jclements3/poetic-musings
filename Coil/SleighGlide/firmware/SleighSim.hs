-- SleighSim.hs — simulation proof of SleighGlide Rev C (SS-005).
-- Run from the clash-h2 environment (has clash-prelude on the path):
--   cd Oracle/clash-h2 && cabal exec -- runghc \
--     ../../Coil/SleighGlide/firmware/SleighSim.hs
--
-- Checks, mostly on the PURE transition functions (fast):
--   1. rxT+linkT decode a real 250 kbaud (div 200) waveform of (A5,spd)
--   2. watchdog: 250 ms of idle line drops the speed to 0
--   3. paceT fire-rate is proportional to speed (255 ~ full, 64 ~ 1/4)
--   4. next: speed 0 / show off => paused Hold, fires advance the FSM
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import System.Exit (exitFailure, exitSuccess)
import SleighGlide

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- serialize one 8N1 byte at rxDiv ticks/bit
byteWave :: BitVector 8 -> [Bit]
byteWave b = bits (0 :: Bit) P.++ P.concat [bits (b ! i) | i <- [0 .. 7]]
          P.++ bits 1
  where bits v = P.replicate (fromIntegral rxDiv) v

frameWave :: Unsigned 8 -> [Bit]
frameWave spd = idle P.++ byteWave 0xA5 P.++ idle P.++ byteWave (pack spd)
  where idle = P.replicate (2 * fromIntegral rxDiv) 1

-- strict fold of the pure pipeline over a line waveform:
-- returns (was `target` ever the speed?, final speed)
runLink :: Unsigned 8 -> [Bit] -> (Bool, Unsigned 8)
runLink target = done . L.foldl' stepF (RxSt False False 0 0 0,
                                        LinkSt 0 False watchdogTicks,
                                        False, 0)
  where
    stepF (!rx, !lk, !seen, !_) l =
      let (rx', mb) = rxT rx l
          (lk', spd) = linkT lk mb
      in (rx', lk', seen || spd == target, spd)
    done (_, _, seen, lastS) = (seen, lastS)

main :: IO ()
main = do
  -- 1. decode two frames
  let wave = frameWave 100 P.++ frameWave 200 P.++ P.replicate 4000 1
      (saw100, last1) = runLink 100 wave
  r1 <- check (saw100 && last1 == 200)
              ("rx+link decode 100 then 200: last=" P.++ P.show last1)
  -- 2. watchdog: hold the line idle past 250 ms
  let idleTicks = fromIntegral watchdogTicks + fromIntegral rxDiv * 40
      (saw77, last2) = runLink 77 (frameWave 77 P.++ P.replicate idleTicks 1)
  r2 <- check (saw77 && last2 == 0)
              "watchdog: speed 77 decays to 0 after 250 ms of silence"
  -- 3. pacer proportionality over 65536 ticks
  let fires spd = P.length (P.filter P.id
        (P.tail (P.map P.snd (P.scanl (\(a, _) _ -> paceT a spd) (0, False)
                                      (P.replicate 65536 ())))))
      f255 = fires 255; f64 = fires 64; f0 = fires 0
  r3 <- check (f0 == 0 && f255 == 65280 && f64 == 16384)   -- exact: N*spd/256
              ("pacer: fires/65536 at spd 255/64/0 = "
               P.++ P.show (f255, f64, f0))
  -- 4. FSM semantics (pure `next`)
  let s0 = initSt { phase = GlideFwd, coil = 3, t = 7, rest = 0, paused = False }
      sPause = next s0 (False, True, True)
      sDead  = next s0 (True, False, True)
      sHold  = next s0 (True, True, False)
      sStep  = next s0 (True, True, True)
  r4 <- check (paused sPause && paused sDead && P.not (paused sHold)
               && t sHold == 7 && t sStep == 8)
              "next: show-off & dead-man pause; no-fire holds; fire steps"
  -- 5. output policy: paused => Hold on the active coil only
  let drv = output s0 { paused = True }
  r5 <- check (drv !! (3 :: Index 8) == Hold
               && P.length [d | d <- toList drv, d == Off] == 7)
              "paused output: Hold on the active coil, Off elsewhere"
  if P.and [r1, r2, r3, r4, r5]
    then putStrLn "ALL PASS: SleighGlide Rev C" >> exitSuccess
    else exitFailure
