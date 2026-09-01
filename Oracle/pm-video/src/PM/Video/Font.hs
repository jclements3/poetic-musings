-- | 8x16 font ROM (one block RAM, 2 KB) plus pure lookups for testbenches.
--
-- Glyph data provenance: see "PM.Video.FontData" (classic IBM VGA ROM
-- 8x16 font via the Debian console-setup @Uni2-VGA16@ PSF; public
-- domain bitmap glyphs).
module PM.Video.Font
  ( fontRom
  , fontData
  , glyphRow
  , fontAddr
  ) where

import Clash.Prelude
import PM.Video.FontData (fontList)

-- | 128 glyphs x 16 rows; address = @glyph[6:0] # row[3:0]@, MSB of the
-- data byte is the leftmost pixel.
fontData :: Vec 2048 (BitVector 8)
fontData = $(listToVecTH fontList)

-- | ROM address for (character, glyph row).  Characters >= 0x80 alias
-- into 0x00-0x7F (bit 7 is reserved for attributes later).
fontAddr :: BitVector 8 -> Unsigned 4 -> Unsigned 11
fontAddr c y = unpack (slice d6 d0 c ++# pack y)

-- | Pure glyph-row lookup, for testbench golden references.
glyphRow :: BitVector 8 -> Unsigned 4 -> BitVector 8
glyphRow c y = fontData !! fontAddr c y

-- | Synchronous font ROM: one-cycle read latency, maps to block RAM.
fontRom
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 11)
  -> Signal dom (BitVector 8)
fontRom = romPow2 fontData
