-- | Synthesis top for the V0 bar TFT console at the real 1920x480
-- timing ('pm1920x480', ~66.7 MHz pixel clock).
--
-- Outputs are parallel RGB + syncs + DE in the pixel-clock domain.
-- TMDS/GPDI serialization is deliberately *not* here: on the ULX3S that
-- is a thin ECP5-primitive shim (clk_25_shift PLL + @ODDRX1F@ DDR
-- serializers, e.g. the fpga_pacman/ulx3s-misc @fake_differential@ +
-- @vga2dvid@ pattern) that cannot be simulated from Clash anyway.  See
-- README "TMDS plan".
--
-- Colors: green-phosphor console (the LAYOUT.html V0 mock), background
-- black.  One bit of luminance for V0; attributes arrive with the VT100
-- layer.
{-# OPTIONS_GHC -Wno-orphans #-}  -- createDomain's KnownDomain instance
module PM.Video.Top
  ( PixelDom
  , vPixelDom
  , PmVideoOut(..)
  , pmVideo
  , topEntity
  ) where

import Clash.Prelude

import PM.Video.Timing
import PM.Video.TextConsole

-- ~66.7 MHz pixel clock (60.0 Hz at the 1950x570 total of 'pm1920x480').
createDomain vSystem{vName="PixelDom", vPeriod=14993}

data PmVideoOut = PmVideoOut
  { pvRed    :: BitVector 8
  , pvGreen  :: BitVector 8
  , pvBlue   :: BitVector 8
  , pvDe     :: Bool
  , pvHSync  :: Bool
  , pvVSync  :: Bool
  , pvCurRow :: Unsigned 5   -- ^ iTFT cursor readback
  , pvCurCol :: Unsigned 8
  } deriving (Generic, NFDataX)

pmVideo
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe CharWrite)
  -> Signal dom (Maybe (Unsigned 5, Unsigned 8))
  -> Signal dom PmVideoOut
pmVideo wrM curM = mk <$> pix <*> cur
 where
  (pix, cur) = textConsole pm1920x480 wrM curM
  mk p (cr, cc) = PmVideoOut
    { pvRed    = if poPixel p then 0x9f else 0x00
    , pvGreen  = if poPixel p then 0xff else 0x00
    , pvBlue   = if poPixel p then 0x8a else 0x00
    , pvDe     = poDe p
    , pvHSync  = poHSync p
    , pvVSync  = poVSync p
    , pvCurRow = cr
    , pvCurCol = cc
    }

topEntity
  :: Clock PixelDom
  -> Reset PixelDom
  -> Enable PixelDom
  -> Signal PixelDom Bool            -- ^ character write enable
  -> Signal PixelDom (Unsigned 5)    -- ^ write row
  -> Signal PixelDom (Unsigned 8)    -- ^ write column
  -> Signal PixelDom (BitVector 8)   -- ^ character
  -> Signal PixelDom Bool            -- ^ cursor write enable
  -> Signal PixelDom (Unsigned 5)    -- ^ cursor row
  -> Signal PixelDom (Unsigned 8)    -- ^ cursor column
  -> Signal PixelDom PmVideoOut
topEntity clk rst en we wrow wcol wchar cwe crow ccol =
  exposeClockResetEnable pmVideo clk rst en wrM curM
 where
  wrM  = mux we  (Just <$> (CharWrite <$> wrow <*> wcol <*> wchar)) (pure Nothing)
  curM = mux cwe (Just <$> bundle (crow, ccol)) (pure Nothing)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_video"
    , t_inputs =
        [ PortName "pixel_clk", PortName "rst", PortName "en"
        , PortName "wr_en", PortName "wr_row", PortName "wr_col", PortName "wr_char"
        , PortName "cur_we", PortName "cur_row", PortName "cur_col"
        ]
    , t_output = PortProduct "vid"
        [ PortName "r", PortName "g", PortName "b"
        , PortName "de", PortName "hsync", PortName "vsync"
        , PortName "cursor_row", PortName "cursor_col"
        ]
    }) #-}
