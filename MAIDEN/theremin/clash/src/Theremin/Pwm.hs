{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BinaryLiterals #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-|
Clash port of @theremin_pwm.sv@ from fpga-theremin
(@fpga/ip_repo/theremin_ip/src/theremin_pwm/hdl/theremin_pwm.sv@).

Two PWM generators sharing one free-running counter:

* /Backlight/ — 8-bit duty from @BACKLIGHT_BRIGHTNESS@, updated on the
  low-8-bits rollover of the counter. Brightness @0xFF@ is forced fully on.
* /RGB LEDs/ — two 12-bit colours (4 bits each of R, G, B), compared against
  the top 5 bits of the counter on its low-11-bits rollover.

The SystemVerilog @RESET@ is a *synchronous, active-high data input*, not an
FPGA reset network, so it stays an explicit port here rather than becoming a
Clash 'Reset'. That keeps the port list identical to the original for
generated-VHDL co-simulation against the SV.
-}
module Theremin.Pwm
  ( Color
  , PwmIn (..)
  , PwmOut (..)
  , PwmState (..)
  , initialState
  , pwmStep
  , pwm
  , topEntity
  ) where

import Clash.Prelude

-- | Width of the shared free-running counter (the @PWM_COUNTER_BITS@
-- parameter; only the default of 16 is instantiated by the hardware).
type CounterBits = 16

-- | Packed RGB colour: 4 bits each of red, green, blue (@[11:8] [7:4] [3:0]@).
type Color = BitVector 12

-- | Input port bundle, mirroring the SystemVerilog port list.
data PwmIn = PwmIn
  { piReset      :: Bit    -- ^ @RESET@, synchronous, active high
  , piColor0     :: Color  -- ^ @RGB_LED_COLOR0@
  , piColor1     :: Color  -- ^ @RGB_LED_COLOR1@
  , piBrightness :: BitVector 8 -- ^ @BACKLIGHT_BRIGHTNESS@, 0 = dark
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX, ShowX)

-- | Output port bundle, mirroring the SystemVerilog port list.
data PwmOut = PwmOut
  { poLed0Pwm       :: BitVector 3 -- ^ @LED0_PWM@, @{r,g,b}@
  , poLed1Pwm       :: BitVector 3 -- ^ @LED1_PWM@, @{r,g,b}@
  , poBacklightPwm  :: Bit         -- ^ @BACKLIGHT_PWM@
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX, ShowX)

-- | The four registers in the original @always @(posedge CLK)@ block.
data PwmState = PwmState
  { psCounter :: BitVector CounterBits
  , psPwm     :: Bit
  , psLed0    :: BitVector 3
  , psLed1    :: BitVector 3
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFDataX, ShowX)

-- | Reset value of every register (all zero, as in the SV reset branch).
initialState :: PwmState
initialState = PwmState 0 0 0 0

-- | One clock edge. Pure, so the property tests can drive it directly.
pwmStep :: PwmState -> PwmIn -> PwmState
pwmStep s PwmIn{..}
  | piReset == high = initialState
  | otherwise = PwmState
      { psCounter = psCounter s + 1
      , psPwm     = pwm'
      , psLed0    = led0'
      , psLed1    = led1'
      }
 where
  cnt = psCounter s

  -- Backlight: low 8 bits are the sub-step, high 8 bits the duty comparison.
  backlightLow  = slice d7  d0 cnt
  backlightHigh = slice d15 d8 cnt

  pwm'
    | backlightLow /= maxBound      = psPwm s
    | backlightHigh == 0xFF         = high    -- brightness 0xFF never turns off
    | backlightHigh == piBrightness = low
    | otherwise                     = psPwm s

  -- RGB LEDs: low 11 bits are the sub-step, high 5 bits the duty comparison.
  rgbLow  = slice d10 d0  cnt
  rgbHigh = slice d15 d11 cnt

  led0' = updateLeds piColor0 (psLed0 s)
  led1' = updateLeds piColor1 (psLed1 s)

  updateLeds :: Color -> BitVector 3 -> BitVector 3
  updateLeds color old
    | rgbLow /= maxBound = old
    | otherwise =
        pack (channel (slice d11 d8 color) (old ! (2 :: Int))
           :> channel (slice d7  d4 color) (old ! (1 :: Int))
           :> channel (slice d3  d0 color) (old ! (0 :: Int))
           :> Nil)

  -- The SV writes the "on" and "off" comparisons as two independent @if@s on
  -- the same nonblocking target, so for a nibble of 0 both fire and the later
  -- (off) assignment wins. Ordering here reproduces that.
  channel :: BitVector 4 -> Bit -> Bit
  channel nibble old
    | rgbHigh == zeroExtend nibble = low
    | rgbHigh == 0                 = high
    | otherwise                    = old

-- | Synchronous PWM generator.
pwm ::
  HiddenClockResetEnable dom =>
  Signal dom PwmIn ->
  Signal dom PwmOut
pwm = moore pwmStep out initialState
 where
  out s = PwmOut
    { poLed0Pwm      = psLed0 s
    , poLed1Pwm      = psLed1 s
    , poBacklightPwm = psPwm s
    }

-- | Synthesis root. Port names match @theremin_pwm.sv@ so the generated VHDL
-- is a drop-in for co-simulation against the original testbench.
topEntity ::
  Clock System ->
  Signal System Bit ->          -- RESET
  Signal System Color ->        -- RGB_LED_COLOR0
  Signal System Color ->        -- RGB_LED_COLOR1
  Signal System (BitVector 8) -> -- BACKLIGHT_BRIGHTNESS
  Signal System (BitVector 3, BitVector 3, Bit)
topEntity clk rst c0 c1 br =
  withClockResetEnable clk resetGen enableGen $
    fmap (\PwmOut{..} -> (poLed0Pwm, poLed1Pwm, poBacklightPwm))
         (pwm (PwmIn <$> rst <*> c0 <*> c1 <*> br))
{-# ANN topEntity
  (Synthesize
    { t_name = "theremin_pwm"
    , t_inputs =
        [ PortName "CLK"
        , PortName "RESET"
        , PortName "RGB_LED_COLOR0"
        , PortName "RGB_LED_COLOR1"
        , PortName "BACKLIGHT_BRIGHTNESS"
        ]
    , t_output =
        PortProduct ""
          [ PortName "LED0_PWM"
          , PortName "LED1_PWM"
          , PortName "BACKLIGHT_PWM"
          ]
    }) #-}
{-# NOINLINE topEntity #-}
