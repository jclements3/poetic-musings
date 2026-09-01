{-# LANGUAGE RecordWildCards #-}
-- | Video timing generator for the PM's V0 bar TFT (and anything else).
--
-- Everything is driven by a parameter record, 'VideoTiming': the module
-- knows nothing about 1920x480 in particular.  A line is laid out
--
-- >  0 .. hActive-1                : active pixels
-- >  .. +hFrontPorch               : front porch
-- >  .. +hSyncWidth                : sync pulse (level set by hSyncHigh)
-- >  .. +hBackPorch                : back porch          (= hTotal-1)
--
-- and a frame is the same shape vertically, in lines.  The sync outputs
-- are wire levels with polarity already applied; 'toActive' is the
-- active-area strobe; 'toLineStart' / 'toFrameStart' are one-cycle
-- strobes at the first pixel of each line / frame.
module PM.Video.Timing
  ( VideoTiming(..)
  , hTotal, vTotal
  , TimingOut(..)
  , timingIdle
  , timingGen
  , pm1920x480
  , sim48x12
  , sim48x32
  ) where

import Clash.Prelude

-- | Static timing parameter record.  Counts are in pixel clocks
-- (horizontal) and lines (vertical).  This is an elaboration-time
-- parameter: fields become constants in the generated HDL.
data VideoTiming = VideoTiming
  { hActive     :: Unsigned 12
  , hFrontPorch :: Unsigned 12
  , hSyncWidth  :: Unsigned 12
  , hBackPorch  :: Unsigned 12
  , vActive     :: Unsigned 12
  , vFrontPorch :: Unsigned 12
  , vSyncWidth  :: Unsigned 12
  , vBackPorch  :: Unsigned 12
  , hSyncHigh   :: Bool  -- ^ True: hsync pulse is driven high (else low)
  , vSyncHigh   :: Bool  -- ^ True: vsync pulse is driven high (else low)
  } deriving (Show, Eq, Generic, NFDataX)

hTotal :: VideoTiming -> Unsigned 12
hTotal VideoTiming{..} = hActive + hFrontPorch + hSyncWidth + hBackPorch

vTotal :: VideoTiming -> Unsigned 12
vTotal VideoTiming{..} = vActive + vFrontPorch + vSyncWidth + vBackPorch

-- | V0: HSD088IPW1-A00 8.8\" 1920x480 bar TFT, landscape.
--
-- ASSUMED pending the panel datasheet.  Provenance: the Waveshare
-- \"8.8inch Side Monitor\" (same 8.8\" 1920x480 HSD088IPW1-class panel,
-- driven portrait through an HDMI-to-MIPI board) documents
--
-- >  hdmi_timings=480 0 30 30 30 1920 0 18 6 6 0 0 0 60 0 66280000 3
--
-- i.e. native portrait 480x1920: h 480\/30\/30\/30 (570 total),
-- v 1920\/18\/6\/6 (1950 total), 66.28 MHz, sync active low.  This record
-- is that timing transposed to the landscape scan our HDMI driver board
-- kit presents: 1950 x 570 = 1,111,500 clocks\/frame, 66.69 MHz for
-- exactly 60 Hz (66.28 MHz gives 59.63 Hz).  See README for the CVT-RB
-- alternative if the driver board wants a standard mode.
pm1920x480 :: VideoTiming
pm1920x480 = VideoTiming
  { hActive = 1920, hFrontPorch = 18, hSyncWidth =  6, hBackPorch =  6  -- 1950
  , vActive =  480, vFrontPorch = 30, vSyncWidth = 30, vBackPorch = 30  --  570
  , hSyncHigh = False, vSyncHigh = False
  }

-- | Tiny record for fast simulation of the raw timing generator:
-- 60 x 18 = 1080 clocks per frame.  Deliberately opposite sync
-- polarities so the testbench exercises both.
sim48x12 :: VideoTiming
sim48x12 = VideoTiming
  { hActive = 48, hFrontPorch = 2, hSyncWidth = 4, hBackPorch = 6  -- 60
  , vActive = 12, vFrontPorch = 1, vSyncWidth = 2, vBackPorch = 3  -- 18
  , hSyncHigh = True, vSyncHigh = False
  }

-- | Tiny record for the text-console testbench: 6 columns x 2 rows of
-- 8x16 characters (the glyph is 16 lines tall, so the 12-line record
-- above cannot show a full character row).  64 x 40 = 2560 clocks/frame.
sim48x32 :: VideoTiming
sim48x32 = VideoTiming
  { hActive = 48, hFrontPorch = 4, hSyncWidth = 6, hBackPorch = 6  -- 64
  , vActive = 32, vFrontPorch = 2, vSyncWidth = 3, vBackPorch = 3  -- 40
  , hSyncHigh = False, vSyncHigh = True
  }

data TimingOut = TimingOut
  { toX          :: Unsigned 12  -- ^ horizontal count, 0..hTotal-1
  , toY          :: Unsigned 12  -- ^ vertical count (line), 0..vTotal-1
  , toActive     :: Bool         -- ^ inside the active area
  , toHSync      :: Bool         -- ^ hsync wire level, polarity applied
  , toVSync      :: Bool         -- ^ vsync wire level, polarity applied
  , toLineStart  :: Bool         -- ^ strobe: first clock of every line
  , toFrameStart :: Bool         -- ^ strobe: first clock of every frame
  } deriving (Show, Eq, Generic, NFDataX)

-- | Quiescent value (syncs deasserted) for pipeline registers.
timingIdle :: VideoTiming -> TimingOut
timingIdle vt = TimingOut 0 0 False (not (hSyncHigh vt)) (not (vSyncHigh vt)) False False

timingGen
  :: forall dom
   . HiddenClockResetEnable dom
  => VideoTiming
  -> Signal dom TimingOut
timingGen vt = mk <$> x <*> y
 where
  hMax = hTotal vt - 1
  vMax = vTotal vt - 1

  x, y :: Signal dom (Unsigned 12)
  x = register 0 (mux hEnd 0 (x + 1))
  hEnd = (== hMax) <$> x
  y = regEn 0 hEnd (mux ((== vMax) <$> y) 0 (y + 1))

  mk px py = TimingOut
    { toX          = px
    , toY          = py
    , toActive     = px < hActive vt && py < vActive vt
    , toHSync      = inH == hSyncHigh vt
    , toVSync      = inV == vSyncHigh vt
    , toLineStart  = px == 0
    , toFrameStart = px == 0 && py == 0
    }
   where
    hs0 = hActive vt + hFrontPorch vt
    vs0 = vActive vt + vFrontPorch vt
    inH = px >= hs0 && px < hs0 + hSyncWidth vt
    inV = py >= vs0 && py < vs0 + vSyncWidth vt
