{-# LANGUAGE RecordWildCards #-}
-- | 1-bpp overlay strip framebuffer for the envelope\/spectrum view.
--
-- @vl1-clash-module-tree.md@: a full 1920x480 overlay at 1 bpp would be
-- 115 KB, so the overlay is a 480x120 *strip* (7 KB) positioned anywhere
-- on the screen by an origin register.  The scan side ORs 'ooOn' over
-- the text console's pixel.
--
-- Storage is column-major: one 120-bit word per column, 480 words, in a
-- true dual-port block RAM (port A: CPU, port B: video).  Column-major
-- makes the common operation -- a spectrum bar or envelope sample,
-- @plotColumn x height@ -- a single write, and clearing the strip a
-- 480-cycle sweep.  A single-pixel write is a read-modify-write of its
-- column (3 cycles).  On the ECP5 a 120-bit-wide TDP RAM maps to 7
-- DP16KD blocks at 18 bits\/port; the 'hardware' budget line in the
-- module tree ("7 KB") is met, at more blocks than a byte-wide layout.
--
-- Rows are numbered top-down like the screen (row 0 is the top of the
-- strip, row 119 the bottom); @plotColumn x h@ lights rows
-- @[120-h .. 119]@, i.e. a bar of height @h@ standing on the bottom edge.
--
-- Read side latency is 2 cycles from the timing sample to 'ooOn', the
-- same as 'PM.Video.TextConsole.textConsole', so an overlay fed the same
-- timing stream lines up with the console's pixel with no extra delay.
module PM.Video.Overlay
  ( stripW, stripH
  , OverlayOp(..)
  , OverlayOut(..)
  , columnMask
  , overlayStrip
  ) where

import Clash.Prelude

import PM.Video.Timing

-- | Strip geometry.
stripW, stripH :: Unsigned 12
stripW = 480
stripH = 120

type ColBits = BitVector 120
type ColAddr = Index 480

-- | CPU-side operations.  Ops arriving while 'ooBusy' is high are
-- dropped (the CPU polls busy, as with the text console's VT100 layer).
data OverlayOp
  = OvPlot   (Unsigned 9) (Unsigned 7) Bit   -- ^ x (0..479), y (0..119), bit
  | OvColumn (Unsigned 9) (Unsigned 7)       -- ^ x, height (0..120): bar from the bottom
  | OvClear                                   -- ^ zero the whole strip
  deriving (Show, Eq, Generic, NFDataX)

data OverlayOut = OverlayOut
  { ooOn   :: Bool  -- ^ overlay pixel, aligned 2 cycles after the timing sample
  , ooBusy :: Bool  -- ^ CPU port busy (pixel RMW or clear sweep in progress)
  } deriving (Show, Eq, Generic, NFDataX)

-- | Column word for a bar of height @h@ (0..120) standing on row 119.
-- Bit @i@ of the word is row @i@.
columnMask :: Unsigned 7 -> ColBits
columnMask h
  | h >= 120  = maxBound
  | otherwise = complement (shiftR maxBound (fromIntegral h))

-- | CPU-port state machine.
data CpuSt
  = Idle
  | PlotWait  ColAddr (Unsigned 7) Bit  -- ^ read issued, data next cycle
  | PlotWrite ColAddr (Unsigned 7) Bit  -- ^ data valid, write this cycle
  | Clearing  ColAddr
  deriving (Show, Eq, Generic, NFDataX)

-- | The strip.  Parameters: CPU op port; origin-set port @(x, y)@ in
-- screen pixels (defaults to the top-left corner); the timing stream to
-- render at (the same 'timingGen' the console runs from).
--
-- The RAM has no initial content: the CPU must 'OvClear' the strip
-- before it is shown (in simulation an unwritten column reads as X).
overlayStrip
  :: forall dom
   . HiddenClockResetEnable dom
  => Signal dom (Maybe OverlayOp)
  -> Signal dom (Maybe (Unsigned 12, Unsigned 12))  -- ^ origin set
  -> Signal dom TimingOut
  -> Signal dom OverlayOut
overlayStrip opM originM t = OverlayOut <$> onOut <*> busy
 where
  origin = regMaybe (0, 0) originM

  ---- video read side (port B) ----------------------------------------
  -- stage 0: inside-strip test and column address
  inStrip o (ox, oy) =
    toActive o && toX o >= ox && toX o < ox + stripW
                && toY o >= oy && toY o < oy + stripH
  in0    = inStrip <$> t <*> origin
  colAdr = (\o (ox, _) -> toEnum (fromIntegral (toX o - ox))) <$> t <*> origin
  row0   = (\o (_, oy) -> truncateB (toY o - oy)) <$> t <*> origin
             :: Signal dom (Unsigned 7)
  rdOp   = mux in0 (RamRead <$> colAdr) (pure RamNoOp)

  -- stage 1: column word out; stage 2: bit select
  in1  = register False in0
  row1 = register 0 row0
  on1  = (\i r w -> i && bitToBool (w ! r)) <$> in1 <*> row1 <*> colB
  onOut = register False on1

  ---- CPU side (port A) ------------------------------------------------
  st   = register Idle st'
  st'  = step <$> st <*> opM
  busy = (/= Idle) <$> st

  step :: CpuSt -> Maybe OverlayOp -> CpuSt
  step Idle (Just (OvPlot x y b))
    | x < 480 && y < 120 = PlotWait (toEnum (fromIntegral x)) y b
  step Idle (Just OvClear)       = Clearing 0
  step Idle _                    = Idle
  step (PlotWait a y b) _        = PlotWrite a y b
  step (PlotWrite {}) _          = Idle
  step (Clearing a) _
    | a == maxBound              = Idle
    | otherwise                  = Clearing (a + 1)

  -- Port A op for this cycle, from the *current* state plus the op
  -- being accepted (so a column write or the pixel read costs no
  -- extra cycle).
  cpuOp :: CpuSt -> Maybe OverlayOp -> ColBits -> RamOp 480 ColBits
  cpuOp Idle (Just (OvColumn x h)) _
    | x < 480 = RamWrite (toEnum (fromIntegral x)) (columnMask h)
  cpuOp Idle (Just (OvPlot x y _)) _
    | x < 480 && y < 120 = RamRead (toEnum (fromIntegral x))
  cpuOp Idle (Just OvClear) _      = RamNoOp
  cpuOp Idle _ _                   = RamNoOp
  cpuOp (PlotWait {}) _ _          = RamNoOp
  cpuOp (PlotWrite a y b) _ old    = RamWrite a (replaceBit y b old)
  cpuOp (Clearing a) _ _           = RamWrite a 0
  wrOp = cpuOp <$> st <*> opM <*> colA

  (colA, colB) = trueDualPortBlockRam wrOp rdOp
