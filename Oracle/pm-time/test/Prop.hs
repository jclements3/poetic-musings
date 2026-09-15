-- Hedgehog properties: PM.StrobeLatch and PM.PpsDiscipline against pure
-- reference models written from the VHDL semantics (strobe_latch.vhd,
-- pps_discipline.vhd — sequential last-assignment-wins, quirks Q1-Q4 of
-- PM.PpsDiscipline's header included). LIBRARY.md porting rule, Lesson 09
-- check 1; the cycle-exact equivalence (check 2) is what these compare.
--
-- Clash `simulate` output k is the state after inputs 0..k-1 (output 0 = the
-- initial state), the same shape as `scanl` over the model.
{-# LANGUAGE RecordWildCards, OverloadedStrings #-}
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Control.Monad (unless)
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import PM.StrobeLatch
import PM.PpsDiscipline
import System.Exit (exitFailure)

------------------------------------------------------------ StrobeLatch model
data RS = RS { rs0, rs1, rs2 :: Bool, fifo :: [(Integer, Integer)], rseq :: Integer, rovf :: Bool }

rsInit :: RS
rsInit = RS False False False [] 0 False

rsStep :: RS -> (Bool, Integer, Bool) -> RS
rsStep RS{..} (strobe, rtcV, rdEn) = RS
  { rs0 = strobe, rs1 = rs0, rs2 = rs1
  , fifo = (if pop then P.tail fifo else fifo) P.++ [(rtcV, rseq) | write]
  , rseq = if push then (rseq + 1) `mod` 65536 else rseq
  , rovf = rovf || (push && not room) }
 where
  push = rs1 && not rs2
  pop = rdEn && not (P.null fifo)
  room = P.length fifo < 16 || pop
  write = push && room

-- (rd_valid, head (only meaningful when valid), count, overflow)
rsOut :: RS -> (Bool, Maybe (Integer, Integer), Int, Bool)
rsOut RS{..} = (not (P.null fifo), if P.null fifo then Nothing else Just (P.head fifo), P.length fifo, rovf)

viewStrobe :: StrobeOut -> (Bool, Maybe (Integer, Integer), Int, Bool)
viewStrobe StrobeOut{..} =
  (rdValid, if rdValid then Just (toInteger rdRtc, toInteger rdSeq) else Nothing, P.fromIntegral count, overflow)

genStrobeIn :: Gen [(Bool, Integer, Bool)]
genStrobeIn = do
  runs <- Gen.list (Range.linear 0 60) $
            (,) <$> Gen.bool <*> Gen.frequency [(6, Gen.int (Range.linear 1 6)), (1, Gen.int (Range.linear 1 40))]
  let levels = P.concatMap (\(l, n) -> P.replicate n l) runs
  rds <- Gen.list (Range.singleton (P.length levels)) (Gen.frequency [(3, P.pure False), (1, P.pure True)])
  rtcs <- Gen.list (Range.singleton (P.length levels)) (Gen.integral (Range.linear 0 (2 P.^ (48 :: Int) - 1)))
  P.pure (P.zip3 levels rtcs rds)

propStrobe :: Property
propStrobe = withTests 300 . property $ do
  ins <- forAll genStrobeIn
  let n = P.length ins
      clashIns = P.map (\(s, r, p) -> (s, P.fromInteger r, p)) (ins P.++ [(False, 0, False)])
      dut = P.take (n + 1) (simulate @System (\i -> let (s, r, p) = unbundle i in strobeLatch s r p) clashIns)
      ref = P.map rsOut (P.scanl rsStep rsInit ins)
  P.map viewStrobe dut === ref

------------------------------------------------------------ PpsDiscipline model
-- Integer state; one function = one rising edge of the VHDL process. Every
-- signal gets a "next" variable that the branches overwrite in source order.
data PS = PS { prtc, pppsRtc, poff :: Integer, plocked, pstb, p0', p1', p2', phave :: Bool
             , pgood, pwdog :: Integer }

psInit :: PS
psInit = PS 0 0 0 False False False False False False 0 0

psStep :: Integer -> Integer -> PS -> Bool -> PS
psStep rtcHz tol PS{..} ppsIn =
  let wdogLimit = rtcHz + rtcHz `div` 2
      offMax = 2 P.^ (19 :: Int) - 1 :: Integer
      -- rtc_q <= rtc_q + 1; stb_q <= '0'; sync chain
      rtc1 = (prtc + 1) `mod` 2 P.^ (48 :: Int)
      stb1 = False
      -- watchdog branch (Q4: saturates, holdover every clock while there)
      (wdog1, locked1, good1)
        | pwdog < wdogLimit = (pwdog + 1, plocked, pgood)
        | otherwise = (pwdog, False, 0)                     -- Q1: runs first
      edge = p1' && not p2'
      -- edge branch overrides
      (stb2, ppsRtc2, wdog2, off2, locked2, good2, have2)
        | not edge = (stb1, pppsRtc, wdog1, poff, locked1, good1, phave)
        | not phave = (True, prtc, 0, poff, locked1, good1, True)
        | otherwise =
            let interval = prtc - pppsRtc                    -- Q2: stale pppsRtc after holdover
                dev = interval - rtcHz
                good = abs dev <= tol
                off | dev > offMax = offMax                  -- Q3: symmetric clamp
                    | dev < negate offMax = negate offMax
                    | otherwise = dev
                (lk, gc) | not good = (False, 0)
                         | pgood == 3 = (True, good1)         -- Q1: good_cnt not assigned here
                         | otherwise = (pgood == 2 || locked1, pgood + 1)
            in (True, prtc, 0, off, lk, gc, True)
  in PS rtc1 ppsRtc2 off2 locked2 stb2 ppsIn p0' p1' have2 good2 wdog2

psOut :: PS -> (Integer, Integer, Bool, Integer, Bool)
psOut PS{..} = (prtc, pppsRtc, pstb, poff, plocked)

viewPps :: PpsOut -> (Integer, Integer, Bool, Integer, Bool)
viewPps PpsOut{..} = (toInteger rtc, toInteger ppsRtc, ppsStb, toInteger offset, locked)

-- Small RTC_HZ so a "second" is 200 clocks: intervals are drawn around it
-- (good, slightly bad, wild, longer than the 1.5 s watchdog) plus glitches.
rtcHzP, tolP :: Integer
rtcHzP = 200
tolP = 3

genPpsIn :: Gen [Bool]
genPpsIn = do
  segs <- Gen.list (Range.linear 1 30) $ do
    period <- Gen.frequency
      [ (6, Gen.integral (Range.linear (rtcHzP - tolP) (rtcHzP + tolP)))
      , (2, Gen.integral (Range.linear (rtcHzP - 12) (rtcHzP + 12)))
      , (1, Gen.integral (Range.linear 2 40))
      , (1, Gen.integral (Range.linear (rtcHzP + rtcHzP `div` 2 - 2) (2 * rtcHzP + 20))) ]
    high <- Gen.integral (Range.linear 1 (max 1 (period `div` 2)))
    P.pure (P.replicate (P.fromInteger high) True P.++ P.replicate (P.fromInteger (period - high)) False)
  P.pure (P.concat segs)

propPps :: Property
propPps = withTests 300 . property $ do
  ins <- forAll genPpsIn
  let n = P.length ins
      dut = P.take (n + 1) (simulate @System (ppsDiscipline (P.fromInteger rtcHzP) (P.fromInteger tolP)) (ins P.++ [False]))
      ref = P.map psOut (P.scanl (psStep rtcHzP tolP) psInit ins)
  P.map viewPps dut === ref
  -- the scenarios must actually exercise lock and holdover somewhere
  cover 30 "locked" (P.any (\(_, _, _, _, l) -> l) ref)
  cover 10 "watchdog-length gap" (P.any ((>= rtcHzP + rtcHzP `div` 2) . toInteger . P.length) (P.filter (not . P.head) (L.group ins)))

main :: IO ()
main = do
  ok <- checkParallel $ Group "pm-time reference models"
          [ ("StrobeLatch == FIFO/seq/overflow model", propStrobe)
          , ("PpsDiscipline == interval/offset/lock/watchdog model", propPps) ]
  unless ok exitFailure
