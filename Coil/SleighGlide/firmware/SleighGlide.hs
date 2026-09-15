{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
-- (the clash CLI enables these by default; spelled out so plain GHC tools
-- like the SleighSim runghc harness can load this file too)

-- SleighGlide.hs  --  Rev C: theremin speed control per SS-005
--   (Rev B: pure Moore machine per SS-004)
--
-- Rev C adds the sleigh_rx serial input: the One Box theremin sends
-- (0xA5, speed) frames at 250 kbaud (PM.SleighSpeed). Pitch = speed,
-- volume off = speed 0 = dead-man stop (Hold duty, the sleigh parked).
-- A 250 ms watchdog forces speed 0 when the cable is unplugged. Speed
-- scales the WHOLE dwell table without multipliers: an accumulator
-- passes 'virtual ticks' to the FSM at rate speed/256, so speed 255 is
-- Rev B timing and speed 0 freezes the machine at Hold.
--
-- Fixes vs Rev A:
--   * built with `moore`: output depends on STATE ONLY (no Mealy leak
--     from the showOn input to the MOSFET gates)
--   * showOn is registered into a `paused` flag in the state
--   * output is a Drive level per coil, then PWM-modulated: RUN / HOLD /
--     OFF -- never 100 % continuous on the 0.4 ohm 24 AWG coils
--
-- Target: Alchitry Cu (iCE40 HX8K). The board oscillator is 100 MHz, but
-- the logic runs from a 50 MHz PLL in the board wrapper (cu_top.v): the
-- 32-bit dwell counters close timing at ~72 MHz on the HX fabric, not 100.
-- msTicks below is set for the 50 MHz logic clock.

module SleighGlide where

import Clash.Prelude

------------------------------------------------------------------------
-- Timing
------------------------------------------------------------------------

msTicks :: Unsigned 32
msTicks = 50000                      -- 1 ms @ 50 MHz (PLL clock, see above)

restMs :: Unsigned 32
restMs = 2500                        -- pause at each house

-- Velocity profile (SS-004 dwell table): slow at houses, fast mid-arc.
dwellMs :: Index 8 -> Unsigned 32
dwellMs i = case min i (maxBound - i) of
  0 -> 400
  1 -> 250
  2 -> 150
  _ -> 100

-- Dwell in TICKS. Each alternative is `constant * constant`, so Clash
-- folds it at compile time and the hardware is a 4-way mux of constants.
-- (Writing `dwellMs coil * msTicks` at a runtime `coil` instead infers a
-- real 32-bit multiplier, which was the timing-critical path on the iCE40.)
dwellTicks :: Index 8 -> Unsigned 32
dwellTicks i = case min i (maxBound - i) of
  0 -> 400 * msTicks
  1 -> 250 * msTicks
  2 -> 150 * msTicks
  _ -> 100 * msTicks

------------------------------------------------------------------------
-- Drive levels (PWM duty, 8-bit)
------------------------------------------------------------------------

data Drive = Off | Hold | Run
  deriving (Generic, NFDataX, Eq, Show)

holdDuty, runDuty :: Unsigned 8
holdDuty = 13                        -- ~5 %   keeps the sleigh parked
runDuty  = 51                        -- ~20 %  start point, tune on bench

------------------------------------------------------------------------
-- Rev C: theremin speed link (SS-005) — RX, framing, watchdog, pacer
------------------------------------------------------------------------

rxDiv :: Unsigned 8
rxDiv = 200                          -- 250 kbaud @ 50 MHz (ULX3S: div 100 @ 25 MHz)

divW :: Unsigned 10
divW = resize rxDiv                   -- divisor widened for the 1.5-bit wait

watchdogTicks :: Unsigned 24
watchdogTicks = 12_500_000           -- 250 ms @ 50 MHz

-- 8N1 receiver, explicit timing (the PM.HarpLink receiver, inlined so the
-- Cu firmware stays a single self-contained file for build.sh): start edge
-- after idle, 1.5 bits to mid-data0, 8 samples, true mid-stop check.
-- rCnt is Unsigned 10: the 1.5-bit start wait is 1.5*rxDiv-1 = 299 ticks at
-- divisor 200, which overflows the Unsigned 8 counter HarpLink uses at its
-- 3 Mbaud divisors (a latent width bug at any divisor > 170)
data RxSt = RxSt { rActive :: !Bool, rIdle :: !Bool, rSh :: !(BitVector 8)
                 , rBit :: !(Unsigned 4), rCnt :: !(Unsigned 10) }
  deriving (Generic, NFDataX)

rxT :: RxSt -> Bit -> (RxSt, Maybe (BitVector 8))
rxT s@RxSt{..} l
  | not rActive
  = if l == 1 then (s { rIdle = True }, Nothing)
    else if rIdle
      then (RxSt True False 0 8 (divW + (divW `shiftR` 1) - 1), Nothing)
      else (s, Nothing)
  | rCnt /= 0 = (s { rCnt = rCnt - 1 }, Nothing)
  | rBit /= 0
  = ( s { rSh = pack l ++# slice d7 d1 rSh, rBit = rBit - 1, rCnt = divW - 1 }
    , Nothing )
  | otherwise
  = ( s { rActive = False }
    , if l == 1 then Just rSh else Nothing )

-- (0xA5, speed) parser with the fail-safe watchdog. Any byte after a sync
-- is the speed; anything else re-arms the sync hunt. No frame for 250 ms
-- (cable out, sender dead, noise) => speed 0.
data LinkSt = LinkSt { lSpeed :: !(Unsigned 8), lSync :: !Bool
                     , lWd :: !(Unsigned 24) }
  deriving (Generic, NFDataX)

linkT :: LinkSt -> Maybe (BitVector 8) -> (LinkSt, Unsigned 8)
linkT s mb = (s', lSpeed s')            -- no wildcards: selectors stay usable
 where
  timed = if lWd s == 0 then s { lSpeed = 0 } else s { lWd = lWd s - 1 }
  s' = case mb of
    Nothing -> timed
    Just b
      | lSync s   -> LinkSt (unpack b) False watchdogTicks
      | b == 0xA5 -> timed { lSync = True }
      | otherwise -> timed { lSync = False }

-- Virtual-tick pacer: fire at rate speed/256 of the clock. speed 255 ~
-- Rev B full rate (0.4 % slow, invisible); speed 0 never fires.
paceT :: Unsigned 9 -> Unsigned 8 -> (Unsigned 9, Bool)
paceT acc spd =
  let a = acc + resize spd
  in if a >= 256 then (a - 256, True) else (a, False)

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

-- showOn off OR speed 0 (dead-man / watchdog) => paused: freeze at Hold.
-- Otherwise advance only on pacer fires — that is the speed control.
next :: St -> (Bool, Bool, Bool) -> St
next s (showOn, go, fire)
  | not (showOn && go) = s { paused = True }
  | not fire           = s { paused = False }         -- hold state this tick
  | otherwise          = step s { paused = False }

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

  where dwell = dwellTicks coil

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
           => Signal dom (Bool, Bool, Bool) -> Signal dom (Vec 8 Drive)
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

glide :: HiddenClockResetEnable dom
      => Signal dom Bool -> Signal dom Bit -> Signal dom (Vec 8 Bit)
glide showRaw rxLine = pwm (controller (bundle (showD, go, fire)))
 where
  showD = debounce showRaw
  rxB   = mealy rxT (RxSt False False 0 0 0) (register 1 rxLine)
  spd   = mealy linkT (LinkSt 0 False watchdogTicks) rxB
  go    = (/= 0) <$> spd
  fire  = mealy paceT 0 spd

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool            -- ^ show switch (raw)
  -> Signal System Bit             -- ^ sleigh_rx — theremin speed link (SS-005)
  -> Signal System (Vec 8 Bit)     -- ^ gates[0..7] -> IRLZ44N, C0 nearest house A
topEntity = exposeClockResetEnable glide
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "sleigh_glide"
    , t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "show_on", PortName "sleigh_rx"]
    , t_output = PortName "gates"
    }) #-}
