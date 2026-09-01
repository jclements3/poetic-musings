{-# LANGUAGE RecordWildCards #-}
-- | Text-mode renderer: 240x30 character buffer -> 8x16 glyphs -> pixels.
--
-- This is the V0 core behind the @0x4026@ oTFT\/iTFT register pair of
-- @eforth-pm.md@: the CPU side only ever *writes* characters (a
-- @{row, col, char}@ write port) and sets\/reads a cursor register; the
-- scan side reads the buffer at pixel rate.  The VT100 interpreter that
-- turns an oTFT byte stream into these writes (the upstream @vga.vhd@
-- @vt100@ entity's job) sits on top of this module and is *not* part of
-- the V0 core.
--
-- Pipeline (2-cycle latency from the timing counters to the pixel):
--
-- >  cycle 0: timing counters -> char-cell address into the char RAM
-- >  cycle 1: char code out   -> glyph-row address into the font ROM
-- >  cycle 2: glyph row out   -> pixel = row bit selected by x[2:0]
--
-- so the sync\/active strobes are delayed two cycles to stay aligned
-- with the pixel they describe.  The testbench asserts this alignment
-- (first active pixel of a line is column 0, glyph pixel 0).
module PM.Video.TextConsole
  ( CharWrite(..)
  , PixelOut(..)
  , textCols, textRows
  , textConsole
  ) where

import Clash.Prelude

import PM.Video.Timing
import PM.Video.Font

-- | Character-buffer geometry: 240 columns x 30 rows fills 1920x480
-- exactly with 8x16 glyphs.  Smaller timing records simply use the
-- top-left corner of the same buffer.
textCols, textRows :: Unsigned 12
textCols = 240
textRows = 30

-- | One CPU-side character write (the @0x4026@ oTFT write side after
-- VT100 decode).  Out-of-range writes (row >= 30, col >= 240) are
-- ignored.
data CharWrite = CharWrite
  { cwRow  :: Unsigned 5   -- ^ 0..29
  , cwCol  :: Unsigned 8   -- ^ 0..239
  , cwChar :: BitVector 8
  } deriving (Show, Eq, Generic, NFDataX)

-- | Video output, aligned: every field describes the same pixel clock.
data PixelOut = PixelOut
  { poPixel :: Bool  -- ^ glyph luminance; False outside the active area
  , poDe    :: Bool  -- ^ data enable (active area)
  , poHSync :: Bool
  , poVSync :: Bool
  , poLine  :: Bool  -- ^ line-start strobe
  , poFrame :: Bool  -- ^ frame-start strobe
  } deriving (Show, Eq, Generic, NFDataX)

-- | The console.  Parameters: timing record; CPU character-write port;
-- cursor-set port.  Returns the pixel stream and the cursor register
-- (the iTFT @cursor row.col@ readback; V0 does not draw the cursor,
-- the VT100 layer will own that).
textConsole
  :: forall dom
   . HiddenClockResetEnable dom
  => VideoTiming
  -> Signal dom (Maybe CharWrite)
  -> Signal dom (Maybe (Unsigned 5, Unsigned 8))  -- ^ cursor set (row, col)
  -> ( Signal dom PixelOut
     , Signal dom (Unsigned 5, Unsigned 8)        -- ^ cursor readback
     )
textConsole vt wrM curM = (pixOut, cursor)
 where
  t = timingGen vt

  ---- stage 0: character-cell address ---------------------------------
  -- x[2:0] / y[3:0] index inside the glyph, x>>3 / y>>4 the cell.
  bufAddr :: Unsigned 5 -> Unsigned 8 -> Unsigned 13
  bufAddr r c = resize r * resize textCols + resize c

  cell o = ( resize (shiftR (toY o) 4) :: Unsigned 5
           , resize (shiftR (toX o) 3) :: Unsigned 8 )
  -- Clamped to 0 during blanking so the RAM never sees an
  -- out-of-range address.
  rdAddr = (\o -> if toActive o then uncurry bufAddr (cell o) else 0) <$> t

  glyphY0 = (truncateB . toY) <$> t :: Signal dom (Unsigned 4)
  glyphX0 = (truncateB . toX) <$> t :: Signal dom (Unsigned 3)

  ---- CPU write port ---------------------------------------------------
  wr = fmap toWr wrM
  toWr (Just CharWrite{..})
    | resize cwRow < textRows && resize cwCol < textCols
    = Just (bufAddr cwRow cwCol, cwChar)
  toWr _ = Nothing

  ---- stage 1: char RAM (one 7200x8 block RAM), font address ----------
  charD = blockRam (replicate (SNat @7200) 0x20) rdAddr wr

  glyphY1 = register 0 glyphY0
  fAddr   = fontAddr <$> charD <*> glyphY1

  ---- stage 2: font ROM, bit select -----------------------------------
  rowD    = fontRom fAddr
  glyphX2 = register 0 (register 0 glyphX0)

  ---- timing delayed 2 cycles to match --------------------------------
  t2 = register (timingIdle vt) (register (timingIdle vt) t)

  pixOut = mk <$> t2 <*> rowD <*> glyphX2
  mk o row gx = PixelOut
    { -- bv2v: head of the Vec is the MSB, so index 0 = leftmost pixel
      poPixel = toActive o && bitToBool (bv2v row !! gx)
    , poDe    = toActive o
    , poHSync = toHSync o
    , poVSync = toVSync o
    , poLine  = toLineStart o
    , poFrame = toFrameStart o
    }

  ---- cursor register (iTFT readback; not drawn in V0) ----------------
  cursor = regMaybe (0, 0) curM
