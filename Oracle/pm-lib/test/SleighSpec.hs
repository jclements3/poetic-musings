-- PM.Sleigh proof: the SleighSim.hs assertions re-run against the in-box
-- block (ribbon sense in place of UART rx), plus Rev D's additions.
--   1. pure FSM walk: coils 0->7->0 with the SS-004 dwells, parks 2500
--   2. pacer fire counts are exact (255: N*255/256, 128: N/2, 0: none)
--   3. full block at speed 255 walks 0..7 then 7..0 in ring order
--   4. speed 128 halves the rate EXACTLY (every station 2x the clocks)
--   5. ribbonPresent low: all gates 0 the next clock, state parked
--   6. show switch off freezes: no state change, active coil at Hold duty,
--      no other gate ever high (Moore, no leak)
--   7. manualPark parks at the next station and resumes on release
--   8. dwell write during a glide lands on the NEXT glide only
--   9. register helpers round-trip; theremin follow calls speedOf
{-# LANGUAGE BangPatterns #-}
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Sleigh
import PM.SleighSpeed (SleighCfg (..), speedOf)
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- default input: enabled, show on, ribbon in, tick every clock
inp :: Unsigned 8 -> SleighIn
inp sp = SleighIn True sp True True False True Nothing

-- run-length encode a trajectory
segs :: P.Eq a => [a] -> [(a, Int)]
segs = P.map (\g -> (P.head g, P.length g)) . L.group

run :: Int -> [SleighIn] -> [SleighOut]
run n is = sampleN @System n (sleigh (fromList (is P.++ P.repeat (inp 0))))

runDrv :: Int -> [SleighIn] -> [Vec 8 Drive]
runDrv n is = sampleN @System n
  ((\(d, _, _, _) -> d) <$> sleighCore (fromList (is P.++ P.repeat (inp 0))))

-- pure walk: fire every step, everything nominal
pureWalk :: Int -> [(Unsigned 2, Index 8)]
pureWalk n = P.take n (P.map (\s -> (phaseCode (phase s), coil s))
                        (P.iterate (\s -> next s (True, True, False, True, dwellTable)) initSt))

-- one full ring, as (state, coil, virtual ticks): park 2500+1, dwell+1
ringExpect :: [((Unsigned 2, Index 8), Int)]
ringExpect = [((0, 0), 2501)]
  P.++ [((1, i), fromIntegral (dwellTable !! i) + 1) | i <- [0 .. 7]]
  P.++ [((2, 7), 2501)]
  P.++ [((3, i), fromIntegral (dwellTable !! i) + 1) | i <- P.reverse [0 .. 7]]

ringLen :: Int
ringLen = P.sum (P.map P.snd ringExpect)

ones :: BitVector 8 -> Int
ones = popCount

main :: IO ()
main = do
  -- 1. pure FSM walk, two rings
  let w = segs (pureWalk (2 * ringLen + 1))
  r1 <- check (P.take (P.length ringExpect * 2) w == ringExpect P.++ ringExpect)
              "FSM walks PARK_A, coils 0..7, PARK_B, 7..0 with the SS-004 dwells"
  -- 2. pacer exact rates
  let fires sp = P.length (P.filter P.id (P.tail (P.map P.snd
        (P.scanl (\(a, _) _ -> paceT a sp) (0, False) (P.replicate 65536 ())))))
  r2 <- check (fires 255 == 65280 && fires 128 == 32768 && fires 0 == 0)
              ("pacer fires/65536 at 255/128/0 = " P.++ P.show (fires 255, fires 128, fires 0))
  -- 3. full block at speed 255: ring order (the pacer skips 1 in 256 ticks,
  --    so lengths are ~256/255 of the pure walk; order and coils exact)
  let n255 = 3 * ringLen
      o255 = run n255 (P.replicate n255 (inp 255))
      s255 = segs (P.map (\o -> (soState o, soCoil o)) o255)
  r3 <- check (P.map P.fst (P.take 18 s255) == P.map P.fst ringExpect)
              "block @255: state/coil sequence is the ring"
  -- 4. speed 128: every interior station exactly twice the pure length
  let n128 = 2 * 2 * ringLen + 8
      o128 = run n128 (P.replicate n128 (inp 128))
      s128 = segs (P.map (\o -> (soState o, soCoil o)) o128)
      inner = P.take 16 (P.drop 1 s128)
      exp128 = P.map (\(k, l) -> (k, 2 * l)) (P.take 16 (P.drop 1 ringExpect))
  r4 <- check (inner == exp128)
              ("block @128: 16 stations at exactly 2x virtual length: " P.++ P.show (P.take 3 inner))
  -- 5. ribbon out mid-glide: gates 0 next clock, state park (Moore lost)
  let k = 2700                              -- inside GLIDE_FWD
      isRib = [inp 255 | _ <- [1 .. k]] P.++ P.repeat (inp 255) { siRibbon = False }
      oRib = run (k + 300) (P.take (k + 300) isRib)
      before = oRib P.!! (k - 1)
      after  = P.drop (k + 1) oRib           -- gates registered: one clock
  r5 <- check (soState before == 1
               && P.all ((== 0) . soGates) after
               && P.all (\o -> soState o == 0 && soPaused o) (P.drop 2 after))
              "ribbon out: all gates 0 within one clock, state PARK_A, paused"
  -- 6. show off mid-glide: freeze, Hold duty on the active coil only
  let isShow = [inp 255 | _ <- [1 .. k]] P.++ P.repeat (inp 255) { siShow = False }
      oShow = run (k + 2000) (P.take (k + 2000) isShow)
      frozen = P.drop (k + 2) oShow
      sc = soCoil (P.head frozen)
      win = P.take 256 (P.drop 256 frozen)   -- one full carrier period
      onesAct = P.sum [ones (soGates o .&. bit (fromIntegral sc)) | o <- win]
      leak = P.any (\o -> soGates o .&. complement (bit (fromIntegral sc)) /= 0) frozen
  r6 <- check (P.all (\o -> soState o == 1 && soCoil o == sc && soPaused o) frozen
               && onesAct == fromIntegral holdDuty && not leak)
              ("show off: frozen at coil " P.++ P.show sc P.++ ", Hold duty "
               P.++ P.show onesAct P.++ "/256, no other gate")
  -- 7. manual park during coil 1's dwell: finish it, park there, resume
  let kp = 2501 + 401 + 100                 -- 100 ticks into coil 1
      hold = 3000
      isPark = [inp 255 | _ <- [1 .. kp]] P.++ P.replicate hold (inp 255) { siPark = True }
               P.++ P.repeat (inp 255)
      oPark = run (kp + hold + 4000) (P.take (kp + hold + 4000) isPark)
      dPark = runDrv (kp + hold + 4000) (P.take (kp + hold + 4000) isPark)
      sPark = segs (P.map (\o -> (soState o, soCoil o)) oPark)
      atHold = oPark P.!! (kp + hold - 1)
      drvHold = dPark P.!! (kp + hold - 1)
  r7 <- check (soState atHold == 0 && soCoil atHold == 1 && not (soPaused atHold)
               && drvHold == replace (1 :: Index 8) Hold (repeat Off)
               && P.map P.fst (P.take 6 sPark) == [(0,0),(1,0),(1,1),(0,1),(1,1),(1,2)])
              ("manual park: parks at station 1 at Hold, resumes forward: " P.++ P.show (P.take 6 sPark))
  -- 8. dwell write mid-glide: current glide unchanged, next glide uses it
  let kw = 2501 + 401 + 50 :: Int                 -- during coil 1 (fwd)
      nw = 3 * ringLen
      isW = [inp 255 | _ <- [1 .. kw]] P.++ [(inp 255) { siDwellWr = Just (5, 999) }]
            P.++ P.repeat (inp 255)
      oW = segs (P.map (\o -> (soState o, soCoil o)) (run nw (P.take nw isW)))
      len key = [l | (kk, l) <- oW, kk == key]
      near a b = abs (a - (b * 256) `P.div` 255) <= 2   -- pacer skips 1/256
  r8 <- check (near (P.head (len (1, 5))) 151 && near (P.head (len (3, 5))) 1000
               && near (len (1, 5) P.!! 1) 1000)
              ("dwell! 5 999: fwd coil 5 = " P.++ P.show (len (1, 5)) P.++ ", rev = " P.++ P.show (len (3, 5)))
  -- 9. register helpers
  let ctl = decodeSleighCtl 0x0300                 -- enable+park, speed 0
      cfg = SleighCfg 1000 3 200 400 4
      st = SleighOut 0xFF 3 5 True
  r9 <- check (ctl == SleighCtl True True 0
               && effectiveSpeed ctl 77 == 77
               && effectiveSpeed (decodeSleighCtl 0x0120) 77 == 0x20
               && sleighSpeedFrom cfg ctl 1800 800 == speedOf cfg 1800 800
               && speedOf cfg 1800 800 == 100
               && decodeDwellWr 0x33E7 == (3, 999)
               && encodeDwellRd 3 999 == 0x33E7
               && encodeSleighStatus st True False 200
                    == (200 `shiftL` 8) .|. bit 7 .|. bit 5 .|. (5 `shiftL` 2) .|. 3)
              "0x4050/0x4052 helpers round-trip; follow-theremin calls speedOf"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9]
    then putStrLn "ALL PASS: PM.Sleigh" >> exitSuccess else exitFailure
