{-# LANGUAGE RecordWildCards #-}
-- PM.PpsDiscipline — free-running 48-bit RTC + PPS interval measurement.
-- Port of MAIDEN/firmware/timebase/rtl/pps_discipline.vhd.
--
-- GPS/DESIGN.md "Design decision": the RTC is NEVER steered. This block
-- measures and reports; RTC->UTC truth is the TIME_MARK record pairing
-- ppsRtc with the absolute second, and lock status rides PPS_STATUS.
--
--   * rtc     : free-running, +1 per clock (this clk IS the 10 MHz RTC domain)
--   * ppsRtc  : RTC latched at the last accepted PPS edge (TIME_MARK pps_rtc)
--   * ppsStb  : 1-clk pulse per accepted edge
--   * offset  : last interval minus rtcHz, clamped to +/-(2^19-1)
--   * locked  : three consecutive intervals within +/-lockTol; dropped by
--               the 1.5 s watchdog (holdover) or by any bad interval
--
-- Generics rtcHz / lockTol are plain arguments (constants at the top).
--
-- Upstream quirks reproduced deliberately (VHDL last-assignment-wins order):
--   Q1. The watchdog branch runs BEFORE the edge branch in the same clock.
--       If an edge lands on the very clock the watchdog fires, the edge's
--       lock verdict overrides (`locked`), but the watchdog's good_cnt := 0
--       is overridden only if the edge branch assigns good_cnt — the
--       good_cnt = 3 "stay locked" path does not, so that clock would leave
--       locked = 1 with good_cnt = 0. Unreachable in practice (an interval
--       >= 1.5 s is never `good`), kept for equivalence.
--   Q2. The first edge after holdover measures against the stale ppsRtc
--       (have_prev is never cleared): a wild interval, classified bad,
--       offset clamped. Relock therefore needs 3 further good intervals.
--   Q3. The clamp is symmetric at +/-(2^19-1); -2^19 is never emitted.
--   Q4. The watchdog counter saturates at WDOG_LIMIT and asserts holdover
--       every clock while there; it only leaves on an edge.
module PM.PpsDiscipline where

import Clash.Prelude

data PpsOut = PpsOut
  { rtc    :: !(Unsigned 48)
  , ppsRtc :: !(Unsigned 48)
  , ppsStb :: !Bool
  , offset :: !(Signed 20)
  , locked :: !Bool
  } deriving (Show, Generic, NFDataX)

data PpsSt = PpsSt
  { rtcQ     :: !(Unsigned 48)
  , ppsRtcQ  :: !(Unsigned 48)
  , offsetQ  :: !(Signed 20)
  , lockedQ  :: !Bool
  , stbQ     :: !Bool
  , p0, p1, p2 :: !Bool            -- 2-FF sync + edge delay, same clock
  , havePrev :: !Bool
  , goodCnt  :: !(Unsigned 2)
  , wdog     :: !(Unsigned 32)
  } deriving (Show, Generic, NFDataX)

ppsInit :: PpsSt
ppsInit = PpsSt 0 0 0 False False False False False False 0 0

offMax :: Signed 49
offMax = 524287                     -- 2^19 - 1

-- One clock of the VHDL process.
ppsStep
  :: Unsigned 32      -- rtcHz  : RTC counts per second
  -> Unsigned 32      -- lockTol: +/- counts to call an interval good
  -> PpsSt -> Bool -> PpsSt
ppsStep rtcHz lockTol PpsSt{..} ppsIn = PpsSt
  { rtcQ = rtcQ + 1                 -- sacred: nothing else touches it
  , ppsRtcQ = if edge then rtcQ else ppsRtcQ
  , offsetQ = if measure then offset' else offsetQ
  , lockedQ = locked'
  , stbQ = edge
  , p0 = ppsIn, p1 = p0, p2 = p1
  , havePrev = havePrev || edge
  , goodCnt = goodCnt'
  , wdog = wdog'
  }
 where
  wdogLimit = rtcHz + rtcHz `div` 2                 -- 1.5 s
  holdover = not (wdog < wdogLimit)                 -- Q4
  edge = p1 && not p2
  measure = edge && havePrev
  wdog' | edge = 0
        | holdover = wdog
        | otherwise = wdog + 1

  u49 :: Unsigned 48 -> Signed 49
  u49 = unpack . zeroExtend . pack
  interval = u49 rtcQ - u49 ppsRtcQ :: Signed 49
  dev = interval - (unpack (zeroExtend (pack rtcHz)) :: Signed 49)
  good = abs dev <= (unpack (zeroExtend (pack lockTol)) :: Signed 49)
  offset' | dev > offMax = resize offMax            -- Q3
          | dev < negate offMax = resize (negate offMax)
          | otherwise = resize dev :: Signed 20

  -- watchdog first, then the edge branch overrides what it assigns (Q1)
  (goodCntW, lockedW)
    | holdover = (0, False)
    | otherwise = (goodCnt, lockedQ)
  (goodCnt', locked')
    | not measure = (goodCntW, lockedW)
    | not good = (0, False)
    | goodCnt == 3 = (goodCntW, True)
    | otherwise = (goodCnt + 1, goodCnt == 2 || lockedW)

ppsOut :: PpsSt -> PpsOut
ppsOut PpsSt{..} = PpsOut rtcQ ppsRtcQ stbQ offsetQ lockedQ

ppsDiscipline
  :: HiddenClockResetEnable dom
  => Unsigned 32                 -- rtcHz
  -> Unsigned 32                 -- lockTol
  -> Signal dom Bool             -- pps_in (async; synchronised inside)
  -> Signal dom PpsOut
ppsDiscipline rtcHz lockTol = moore (ppsStep rtcHz lockTol) ppsOut ppsInit

{-# ANN topEntity
  (Synthesize
    { t_name = "pps_discipline"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en", PortName "pps_in" ]
    , t_output = PortProduct "" [ PortName "rtc", PortName "pps_rtc"
                                , PortName "pps_stb", PortName "offset"
                                , PortName "locked" ]
    }) #-}
-- Hardware generics: 10 MHz RTC, LOCK_TOL 500 counts (50 ppm).
topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool
  -> Signal System (Unsigned 48, Unsigned 48, Bool, Signed 20, Bool)
topEntity clk rst en pps = withClockResetEnable clk rst en $
  (\PpsOut{..} -> (rtc, ppsRtc, ppsStb, offset, locked))
    <$> ppsDiscipline 10_000_000 500 pps
