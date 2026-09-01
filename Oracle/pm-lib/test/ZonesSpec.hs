-- PM.Zones testbench — the 0x4020 contract in simulation.
--
--     Run:  cabal test zones-test --test-show-details=direct
--
-- Sim parameters: hysteresis half-band H = 64 counts, S3 dwell = 50 ticks
-- (the 1 s dwell scaled down; the rule under test is identical).  Scenarios:
--
--   Z1  full S2 sweep up and back -> zone sequence exactly 0,1,2,1,0
--       (one transition per crossing, no chatter)
--   Z2  park at the S2 LOW/MID boundary (1365) with ±63 alternating noise,
--       approached from below and from above -> zone never moves either way
--   Z3  step past the boundary by less than H -> no change; past H -> change
--   Z4  full S4 sweep -> 0,1,2,3,2,1,0 (OFF·CAL·PLAY·REC geometry)
--   Z5  S3 mode dwell: settle in P, jump to T(=zone 3) with noise -> the
--       modeChange strobe fires exactly once, ~dwell after the jump; a
--       10-tick bump into zone 4 never fires (a bumped slider never yanks a
--       demo); a real move to C(=5) fires exactly once more; `stable` is low
--       during the dwell and high after
--   Z6  iPanel packing: S2=HIGH, S3=C, S4=CAL, settled ->
--       word == 0x8095 (bit15 stable | s2 bits7:6 | s4 bits5:4 | s3 bits2:0)

module Main (main) where

import Prelude
import System.Exit (exitFailure)

import qualified Clash.Prelude as C
import Clash.Prelude (BitVector, Unsigned)

import PM.Zones

simH :: Unsigned 12
simH = 64

simDwell :: Unsigned 32
simDwell = 50

runZ :: Int -> [Unsigned 12] -> [Unsigned 12] -> [Unsigned 12] -> [ZonesOut]
runZ n s2L s3L s4L = C.sampleN @C.System n sig
  where
    sig :: C.HiddenClockResetEnable C.System => C.Signal C.System ZonesOut
    sig = zones simH simDwell (mk s2L) (mk s3L) (mk s4L)
    mk l = C.fromList (l ++ repeat (if null l then 0 else last l))

checkEq :: (Eq a, Show a) => String -> a -> a -> IO Bool
checkEq name want got
  | want == got = putStrLn ("  PASS  " ++ name ++ " = " ++ show got) >> pure True
  | otherwise   = putStrLn ("  FAIL  " ++ name ++ ": expected " ++ show want
                            ++ ", got " ++ show got) >> pure False

noise :: Int -> Unsigned 12 -> Unsigned 12 -> [Unsigned 12]
noise n lo hi = concat (replicate n [lo, hi])

main :: IO ()
main = do
  putStrLn "== Z1: S2 sweep, one transition per crossing =="
  let sweep = [0, 8 .. 4095] ++ [4095] ++ reverse [0, 8 .. 4095]
  r1 <- checkEq "zone sequence (deduped)" [0, 1, 2, 1, 0]
          (dedup (map zoS2 (runZ (length sweep) sweep [] [])))

  putStrLn "== Z2: parked on the boundary with +/-63 noise, no flicker =="
  let parkLo = replicate 20 600  ++ noise 300 1302 1428
      parkHi = replicate 20 2000 ++ noise 300 1302 1428
  -- drop 10: the tracker resets in zone 0 and locks to the parked value in
  -- ~2 ticks — the check is about flicker at the boundary, not power-on
  r2a <- checkEq "approached from below stays LOW" [0]
           (dedup (drop 10 (map zoS2 (runZ (length parkLo) parkLo [] []))))
  r2b <- checkEq "approached from above stays MID" [1]
           (dedup (drop 10 (map zoS2 (runZ (length parkHi) parkHi [] []))))

  putStrLn "== Z3: crossing needs the full hysteresis band =="
  let cross = replicate 20 600 ++ replicate 100 1400 ++ replicate 50 1500
      smp3  = map zoS2 (runZ (length cross) cross [] [])
  r3a <- checkEq "40 counts past the boundary: still LOW" 0 (smp3 !! 100)
  r3b <- checkEq "past boundary+H: MID; exactly one transition" [0, 1] (dedup smp3)

  putStrLn "== Z4: S4 sweep OFF-CAL-PLAY-REC and back =="
  r4 <- checkEq "zone sequence (deduped)" [0, 1, 2, 3, 2, 1, 0]
          (dedup (map zoS4 (runZ (length sweep) [] [] sweep)))

  putStrLn "== Z5: S3 mode dwell =="
  let stim5 = replicate 120 300            -- settle in P (zone 0)
           ++ noise 100 2326 2452          -- jump to T-side zone 3, +/-63 noise
           ++ replicate 10 3100            -- 10-tick bump into zone 4
           ++ noise 100 2326 2452          -- back to zone 3
           ++ replicate 100 3800           -- real move to C (zone 5)
      n5     = length stim5 + 10
      smp5   = runZ n5 [] stim5 []
      pulses = [ i | (i, o) <- zip [0 :: Int ..] smp5, zoModeChange o ]
  r5a <- checkEq "modeChange fires exactly twice in the whole run" 2 (length pulses)
  r5b <- checkEq "first pulse ~dwell after the jump (tick window 168..180)"
           True (case pulses of (p : _) -> p >= 168 && p <= 180; _ -> False)
  r5c <- checkEq "second pulse ~dwell after the move to C (tick window 578..592)"
           True (case pulses of (_ : q : _) -> q >= 578 && q <= 592; _ -> False)
  r5d <- checkEq "mode still P during the new-zone dwell" 0 (zoMode (smp5 !! 160))
  r5e <- checkEq "mode T-side zone after the first pulse" 3 (zoMode (smp5 !! 200))
  r5f <- checkEq "10-tick bump never changed mode" 3 (zoMode (smp5 !! 350))
  r5g <- checkEq "mode C at the end" 5 (zoMode (last smp5))
  r5h <- checkEq "stable low during the dwell" False (zoStable (smp5 !! 160))
  r5i <- checkEq "stable high once dwelled" True (zoStable (smp5 !! 250))

  putStrLn "== Z6: iPanel word packing =="
  r6a <- checkEq "ipanelWord 2 5 1 True" (0x8095 :: BitVector 16)
           (ipanelWord 2 5 1 True)
  let smp6 = runZ 120 (replicate 120 3500) (replicate 120 3900) (replicate 120 1300)
  r6b <- checkEq "settled register value (S2=HIGH S3=C S4=CAL, stable)"
           (0x8095 :: BitVector 16) (zoIPanel (last smp6))

  if and [r1, r2a, r2b, r3a, r3b, r4, r5a, r5b, r5c, r5d, r5e, r5f, r5g, r5h, r5i, r6a, r6b]
    then putStrLn "\nALL PASS: hysteresis, no-flicker parking, sweeps, S3 dwell, iPanel packing"
    else putStrLn "\nFAILURES above" >> exitFailure

-- collapse adjacent equals: an all-equal list becomes the singleton it should be
dedup :: Eq a => [a] -> [a]
dedup = foldr (\x acc -> if [x] == take 1 acc then acc else x : acc) []
