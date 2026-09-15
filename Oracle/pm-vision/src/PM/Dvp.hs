{-# LANGUAGE RecordWildCards #-}
-- PM.Dvp — parallel (DVP) camera capture for the OV9281 (Imaging/DESIGN.md,
-- Architecture: "sensor DVP (PCLK/HREF/VSYNC + D[7:0]) -> capture").
--
--   * The pixel bus arrives already in the system domain: a 2-flop
--     synchroniser (or the capture CDC FIFO) upstream presents one DvpIn
--     sample per system cycle: HREF, VSYNC and D[7:0].  A pixel is a cycle
--     with HREF high.  Pixels within a line may be spaced by idle cycles
--     (HREF low with no VSYNC) *only if* the upstream FIFO drops HREF between
--     them — the raw bus never does; the capture counts x per HREF-high cycle
--     and a line ends on the HREF falling edge.
--   * VSYNC high (the OV9281's active-high frame pulse) resets x and y; the
--     first HREF line after VSYNC is y = 0.
--   * dvpCapture emits Just Pix for every HREF-high cycle, tagged with
--     x :: Unsigned 10, y :: Unsigned 9, the 8-bit value, and the frame
--     markers sof (x=0,y=0), eol (x=639), eof (x=639,y=399) for the fixed
--     640 x 400 raster.  Lines longer than 640 px or frames taller than 400
--     lines are clipped (extra pixels dropped); shorter ones never raise eol/eof
--     — the sequence counter then does not advance, which iImgStat can show.
--   * The frame sequence counter (iImgSeq, 0x4062) increments on each eof.
module PM.Dvp where

import Clash.Prelude

-- | Frame geometry of the OV9281 in its 640 x 400 mode.
frameW :: Unsigned 10
frameW = 640

frameH :: Unsigned 9
frameH = 400

-- | One system-clock sample of the synchronised parallel bus.
data DvpIn = DvpIn
  { dHref  :: !Bool
  , dVsync :: !Bool
  , dData  :: !(Unsigned 8)
  } deriving (Generic, NFDataX, Eq, Show)

-- | A captured pixel with its raster position and frame markers.
data Pix = Pix
  { pX   :: !(Unsigned 10)
  , pY   :: !(Unsigned 9)
  , pVal :: !(Unsigned 8)
  , pSof :: !Bool        -- first pixel of the frame
  , pEol :: !Bool        -- last pixel of the line (x = 639)
  , pEof :: !Bool        -- last pixel of the frame (x = 639, y = 399)
  } deriving (Generic, NFDataX, Eq, Show)

data DvpSt = DvpSt
  { sX        :: !(Unsigned 10)
  , sY        :: !(Unsigned 9)
  , sHrefPrev :: !Bool
  , sSeq      :: !(Unsigned 16)
  } deriving (Generic, NFDataX)

dvpInit :: DvpSt
dvpInit = DvpSt 0 0 False 0

dvpT :: DvpSt -> DvpIn -> (DvpSt, (Maybe Pix, Unsigned 16))
dvpT DvpSt{..} DvpIn{..}
  | dVsync    = (DvpSt 0 0 False sSeq, (Nothing, sSeq))
  | dHref     = let inRange = sX < frameW && sY < frameH
                    eol = sX == frameW - 1
                    eof = eol && sY == frameH - 1
                    pix = Pix { pX = sX, pY = sY, pVal = dData
                              , pSof = sX == 0 && sY == 0, pEol = eol, pEof = eof }
                    x'  = if sX == maxBound then sX else sX + 1
                    seq' = if eof then sSeq + 1 else sSeq
                in (DvpSt x' sY True seq', (if inRange then Just pix else Nothing, sSeq))
  | sHrefPrev = -- HREF falling edge: next line
                (DvpSt 0 (if sY == maxBound then sY else sY + 1) False sSeq, (Nothing, sSeq))
  | otherwise = (DvpSt sX sY False sSeq, (Nothing, sSeq))

-- | Capture: synchronised bus in, tagged pixel stream and frame sequence out.
dvpCapture
  :: HiddenClockResetEnable dom
  => Signal dom DvpIn
  -> (Signal dom (Maybe Pix), Signal dom (Unsigned 16))
dvpCapture = unbundle . mealy dvpT dvpInit

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System DvpIn
  -> (Signal System (Maybe Pix), Signal System (Unsigned 16))
topEntity = exposeClockResetEnable dvpCapture
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_dvp"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en", PortName "dvp" ]
    , t_output = PortProduct "" [ PortName "pix", PortName "seq" ]
    }) #-}
