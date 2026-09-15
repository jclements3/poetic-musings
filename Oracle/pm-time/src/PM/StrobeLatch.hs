{-# LANGUAGE RecordWildCards #-}
-- PM.StrobeLatch — camera-strobe timestamp capture.
-- Port of MAIDEN/firmware/timebase/rtl/strobe_latch.vhd (DEPTH = 16).
--
--   async strobe -> 2-FF synchroniser -> rising-edge detect -> push
--   (rtc :: Unsigned 48, seq :: Unsigned 16) into a 16-deep FIFO that the
--   CPU / recorder link pops one entry per rdEn.
--
-- Overflow is LOUD: a push against a full FIFO drops the stamp but sets a
-- sticky `overflow` flag (clears only on reset). `seq` still increments on
-- every strobe, dropped or not, so a gap is countable offline — this is the
-- STROBE_STAMP contract in Imaging/DESIGN.md ("seq counts every frame
-- including dropped stamps").
--
-- Synchroniser: the VHDL uses a same-clock s0/s1/s2 chain (s0,s1 are the
-- 2 flops; s2 is the edge-detect delay) with the push on s1 && !s2. pm-lib's
-- PM.Cdc.bitSync is a two-clock primitive, so the chain is written locally
-- here to keep the upstream 2-clk latency exactly (SYS-006 T4 timing).
module PM.StrobeLatch where

import Clash.Prelude

-- Outputs are all functions of the state (Moore).
data StrobeOut = StrobeOut
  { rdValid  :: !Bool            -- FIFO non-empty
  , rdRtc    :: !(Unsigned 48)   -- head entry
  , rdSeq    :: !(Unsigned 16)
  , count    :: !(Unsigned 5)    -- entries held, 0..16
  , overflow :: !Bool            -- sticky
  } deriving (Show, Generic, NFDataX)

data StrobeSt = StrobeSt
  { rtcMem :: !(Vec 16 (Unsigned 48))
  , seqMem :: !(Vec 16 (Unsigned 16))
  , s0, s1, s2 :: !Bool
  , wrPtr  :: !(Unsigned 4)
  , rdPtr  :: !(Unsigned 4)
  , fill   :: !(Unsigned 5)
  , seqQ   :: !(Unsigned 16)
  , ovfQ   :: !Bool
  } deriving (Show, Generic, NFDataX)

strobeInit :: StrobeSt
strobeInit = StrobeSt (repeat 0) (repeat 0) False False False 0 0 0 0 False

-- One clock of the VHDL process (rst = synchronous, handled by `moore`).
-- Inputs: (strobe_in, rtc, rd_en).
strobeStep :: StrobeSt -> (Bool, Unsigned 48, Bool) -> StrobeSt
strobeStep StrobeSt{..} (strobe, rtc, rdEn) = StrobeSt
  { rtcMem = rtcMem', seqMem = seqMem'
  , s0 = strobe, s1 = s0, s2 = s1
  , wrPtr = wrPtr', rdPtr = rdPtr', fill = fill'
  , seqQ = if push then seqQ + 1 else seqQ     -- counts drops too
  , ovfQ = ovfQ || (push && not room)
  }
 where
  push = s1 && not s2
  pop  = rdEn && fill > 0
  -- a push in the same clock as a pop always has a slot (VHDL: fill < DEPTH or pop)
  room = fill < 16 || pop
  write = push && room
  rtcMem' = if write then replace wrPtr rtc  rtcMem else rtcMem
  seqMem' = if write then replace wrPtr seqQ seqMem else seqMem
  wrPtr' = if write then wrPtr + 1 else wrPtr          -- mod 16 by width
  rdPtr' = if pop   then rdPtr + 1 else rdPtr
  fill' | push && pop         = fill
        | push && fill < 16   = fill + 1
        | pop                 = fill - 1
        | otherwise           = fill

strobeOut :: StrobeSt -> StrobeOut
strobeOut StrobeSt{..} = StrobeOut
  { rdValid = fill > 0
  , rdRtc = rtcMem !! rdPtr
  , rdSeq = seqMem !! rdPtr
  , count = fill
  , overflow = ovfQ
  }

strobeLatch
  :: HiddenClockResetEnable dom
  => Signal dom Bool            -- strobe_in (async; synchronised inside)
  -> Signal dom (Unsigned 48)   -- rtc
  -> Signal dom Bool            -- rd_en
  -> Signal dom StrobeOut
strobeLatch strobe rtc rdEn =
  moore strobeStep strobeOut strobeInit (bundle (strobe, rtc, rdEn))

{-# ANN topEntity
  (Synthesize
    { t_name = "strobe_latch"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "strobe_in", PortName "rtc", PortName "rd_en" ]
    , t_output = PortProduct "" [ PortName "rd_valid", PortName "rd_rtc"
                                , PortName "rd_seq", PortName "count"
                                , PortName "overflow" ]
    }) #-}
topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool -> Signal System (Unsigned 48) -> Signal System Bool
  -> Signal System (Bool, Unsigned 48, Unsigned 16, Unsigned 5, Bool)
topEntity clk rst en strobe rtc rdEn = withClockResetEnable clk rst en $
  (\StrobeOut{..} -> (rdValid, rdRtc, rdSeq, count, overflow))
    <$> strobeLatch strobe rtc rdEn
