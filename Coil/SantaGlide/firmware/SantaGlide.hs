-- SantaGlide.hs  --  Rev B: pure Moore machine per SS-004
--
-- Fixes vs Rev A:
--   * built with `moore`: output depends on STATE ONLY (no Mealy leak
--     from the showOn input to the MOSFET gates)
--   * showOn is registered into a `paused` flag in the state
--   * output is a Drive level per coil, then PWM-modulated: RUN / HOLD /
--     OFF -- never 100 % continuous on the 0.4 ohm 24 AWG coils
--
-- Target: Alchitry Cu (iCE40 HX8K), 100 MHz System clock

module SantaGlide where

import Clash.Prelude

------------------------------------------------------------------------
-- Timing
------------------------------------------------------------------------

msTicks :: Unsigned 32
msTicks = 100000                     -- 1 ms @ 100 MHz

restMs :: Unsigned 32
restMs = 2500                        -- pause at each house

-- Velocity profile (SS-004 dwell table): slow at houses, fast mid-arc.
dwellMs :: Index 8 -> Unsigned 32
dwellMs i = case min i (maxBound - i) of
  0 -> 400
  1 -> 250
  2 -> 150
  _ -> 100

------------------------------------------------------------------------
-- Drive levels (PWM duty, 8-bit)
------------------------------------------------------------------------

data Drive = Off | Hold | Run
  deriving (Generic, NFDataX, Eq, Show)

holdDuty, runDuty :: Unsigned 8
holdDuty = 13                        -- ~5 %   keeps Santa parked
runDuty  = 51                        -- ~20 %  start point, tune on bench

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

data Phase = ParkA | GlideFwd | ParkB | GlideRev
  deriving (Generic, NFDataX, Eq, Show)

data St = St
  { phase  :: Phase
  , coil   :: Index 8                -- active station i
  , t      :: Unsigned 32            -- ticks in current station
  , rest   :: Unsigned 32            -- ticks remaining at a house
  , paused :: Bool                   -- registered copy of ~showOn
  } deriving (Generic, NFDataX, Show)

initSt :: St
initSt = St ParkA 0 0 (restMs * msTicks) True

------------------------------------------------------------------------
-- Transition function  (s -> i -> s)
------------------------------------------------------------------------

next :: St -> Bool -> St
next s showOn
  | not showOn = s { paused = True }                  -- freeze everything
  | otherwise  = step s { paused = False }

step :: St -> St
step s@St{..} = case phase of

  ParkA
    | rest > 0  -> s { rest = rest - 1 }
    | otherwise -> s { phase = GlideFwd, coil = 0, t = 0 }

  GlideFwd
    | t < dwell         -> s { t = t + 1 }
    | coil < maxBound   -> s { coil = coil + 1, t = 0 }
    | otherwise         -> s { phase = ParkB, rest = restMs * msTicks }

  ParkB
    | rest > 0  -> s { rest = rest - 1 }
    | otherwise -> s { phase = GlideRev, coil = maxBound, t = 0 }

  GlideRev
    | t < dwell         -> s { t = t + 1 }
    | coil > 0          -> s { coil = coil - 1, t = 0 }
    | otherwise         -> s { phase = ParkA, rest = restMs * msTicks }

  where dwell = dwellMs coil * msTicks

------------------------------------------------------------------------
-- Output function  (s -> o)  -- STATE ONLY, this is what makes it Moore
------------------------------------------------------------------------

output :: St -> Vec 8 Drive
output St{..} = replace coil level (repeat Off)
  where
    level
      | paused                          = Hold
      | phase == ParkA || phase == ParkB = Hold
      | otherwise                       = Run

controller :: HiddenClockResetEnable dom
           => Signal dom Bool -> Signal dom (Vec 8 Drive)
controller = moore next output initSt

------------------------------------------------------------------------
-- Debounce for the show switch (10 ms stable)
------------------------------------------------------------------------

debounce :: HiddenClockResetEnable dom => Signal dom Bool -> Signal dom Bool
debounce = moore go snd (0, False)
  where
    go (cnt, stable) raw
      | raw == stable       = (0, stable)
      | cnt >= 10 * msTicks = (0, raw)
      | otherwise           = (cnt + 1, stable)

------------------------------------------------------------------------
-- PWM stage: shared 8-bit carrier (~390 kHz), one comparator per coil
------------------------------------------------------------------------

carrier :: HiddenClockResetEnable dom => Signal dom (Unsigned 8)
carrier = register 0 (carrier + 1)

toGate :: Unsigned 8 -> Drive -> Bit
toGate _ Off  = 0
toGate c Hold = boolToBit (c < holdDuty)
toGate c Run  = boolToBit (c < runDuty)

pwm :: HiddenClockResetEnable dom
    => Signal dom (Vec 8 Drive) -> Signal dom (Vec 8 Bit)
pwm drives = register (repeat 0) (map <$> (toGate <$> carrier) <*> drives)
  -- registered output: gates change only on the clock edge, never glitch

------------------------------------------------------------------------
-- Top entity
------------------------------------------------------------------------

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool            -- ^ show switch (raw)
  -> Signal System (Vec 8 Bit)     -- ^ gates[0..7] -> IRLZ44N, C0 nearest house A
topEntity = exposeClockResetEnable (pwm . controller . debounce)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "santa_glide"
    , t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "show_on"]
    , t_output = PortName "gates"
    }) #-}
