-- PM.Sleigh — the coil sequencer in the box (Coil/DESIGN.md Rev D, SS-004).
--
-- Port of Coil/SleighGlide/firmware/SleighGlide.hs (the Cu firmware) onto
-- the register bus: the same Moore FSM, dwell table, pacer and PWM stage;
-- the 250 kbaud (0xA5, speed) link and its 250 ms watchdog are replaced by
-- a speed INPUT (from 0x4050 or PM.SleighSpeed.speedOf) and the ribbon's
-- presence line as the dead-man.
--
--   ring     : PARK_A -> GLIDE_FWD -> PARK_B -> GLIDE_REV -> PARK_A ...
--              parks last restMs (2500 ms); a glide dwells dwell[i] ms at
--              coil i (SS-004: 400 250 150 100 100 150 250 400)
--   pacer    : the FSM advances on VIRTUAL ticks fired at speed/256 of the
--              1 ms tick (speed 1..255; 255 = the Rev B timing within 0.4 %,
--              128 = exactly half rate, 0 = never fires => paused)
--   gates    : one active coil, PWM at holdDuty (parked/paused) or runDuty
--              (gliding), 8-bit carrier at the clock rate; every other gate
--              low. Output depends on the STATE only (Moore): the show
--              switch cannot leak to the MOSFETs (the Rev B fix)
--   paused   : enable low, show switch off or speed 0 freezes the machine in
--              place at Hold duty (pacer stalled, no state change)
--   ribbon   : ribbonPresent low (ribbon out) = every gate low within one
--              clock (the gate register's D input is masked — the ONE
--              non-Moore path, a safety mask, and it is still registered)
--              and the FSM falls to the park state of its direction
--              (GLIDE_FWD -> PARK_A, GLIDE_REV -> PARK_B) at its coil
--   manual   : manualPark high finishes the current station's dwell, then
--              parks THERE (state PARK_A if gliding forward, PARK_B if
--              reverse, coil kept); held parks never count down; on
--              release the park rests restMs then resumes in the same
--              direction from that station
--   dwell wr : (index, ms) writes a PENDING table; the FSM copies it into
--              its working table when a park ends, so a write never
--              changes the glide in progress — it takes effect on the next
--              glide. Readback is the pending table.
--
-- Register semantics (Oracle/eforth-pm.md, 0x4050 group). PM.RegFile is not
-- modified here; these helpers are what its 0x4050/0x4052 decode binds:
--
--   0x4050 write  oSleigh       bits 7:0 speed (0 = follow the theremin,
--                               PM.SleighSpeed.speedOf), bit 8 enable,
--                               bit 9 manual park            (decodeSleighCtl)
--   0x4050 read   iSleigh       bits 1:0 state code (0 PARK_A 1 GLIDE_FWD
--                               2 PARK_B 3 GLIDE_REV), 4:2 coil, 5 ribbon
--                               present, 6 show switch, 7 paused,
--                               15:8 effective speed          (encodeSleighStatus)
--   0x4052 write  oSleighDwell  bits 11:0 dwell ms, 14:12 index (decodeDwellWr)
--   0x4052 read   iSleighDwell  same layout, the pending entry at the
--                               last-written index                (encodeDwellRd)

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.Sleigh where

import Clash.Prelude
import Data.Maybe (isJust)
import PM.SleighSpeed (SleighCfg, speedOf)
import PM.Ulx25 (Ulx25)

------------------------------------------------------------------------
-- Timing (all in ms of the 1 ms tick; the pacer scales them)
------------------------------------------------------------------------

type Ms = Unsigned 12                -- up to 4095 ms per station / park

restMs :: Ms
restMs = 2500                        -- pause at each house

-- | SS-004 dwell table: slow at the houses, fast mid-arc (values copied
--   from SleighGlide.hs dwellMs).
dwellTable :: Vec 8 Ms
dwellTable = 400 :> 250 :> 150 :> 100 :> 100 :> 150 :> 250 :> 400 :> Nil

------------------------------------------------------------------------
-- Drive levels (PWM duty, 8-bit)
------------------------------------------------------------------------

data Drive = Off | Hold | Run
  deriving (Generic, NFDataX, Eq, Show)

holdDuty, runDuty :: Unsigned 8
holdDuty = 13                        -- ~5 %   keeps the sleigh parked
runDuty  = 51                        -- ~20 %  start point, tune on bench

------------------------------------------------------------------------
-- Pacer: fire at rate speed/256 of the tick (unchanged from Rev C)
------------------------------------------------------------------------

paceT :: Unsigned 9 -> Unsigned 8 -> (Unsigned 9, Bool)
paceT acc spd =
  let a = acc + resize spd
  in if a >= 256 then (a - 256, True) else (a, False)

------------------------------------------------------------------------
-- Ports
------------------------------------------------------------------------

data SleighIn = SleighIn
  { siEnable  :: !Bool              -- ^ oSleigh enable
  , siSpeed   :: !(Unsigned 8)      -- ^ 1..255; 0 pauses
  , siShow    :: !Bool              -- ^ show switch (ribbon, debounced upstream)
  , siRibbon  :: !Bool              -- ^ ribbon sense: False = ribbon out
  , siPark    :: !Bool              -- ^ manual park
  , siTick    :: !Bool              -- ^ 1 ms tick
  , siDwellWr :: !(Maybe (Index 8, Ms))  -- ^ dwell-table write port
  } deriving (Generic, NFDataX)

data SleighOut = SleighOut
  { soGates  :: !(BitVector 8)      -- ^ gates[0..7] -> IRLZ44N, bit 0 nearest house A
  , soState  :: !(Unsigned 2)       -- ^ 0 PARK_A 1 GLIDE_FWD 2 PARK_B 3 GLIDE_REV
  , soCoil   :: !(Index 8)          -- ^ active station
  , soPaused :: !Bool
  } deriving (Generic, NFDataX, Eq, Show)

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

data Phase = ParkA | GlideFwd | ParkB | GlideRev
  deriving (Generic, NFDataX, Eq, Show)

phaseCode :: Phase -> Unsigned 2
phaseCode ParkA    = 0
phaseCode GlideFwd = 1
phaseCode ParkB    = 2
phaseCode GlideRev = 3

data St = St
  { phase  :: !Phase
  , coil   :: !(Index 8)            -- active station i
  , t      :: !Ms                   -- virtual ticks in the current station
  , rest   :: !Ms                   -- virtual ticks remaining at a park
  , paused :: !Bool                 -- registered freeze (show/enable/speed 0)
  , lost   :: !Bool                 -- registered "ribbon out"
  , dwell  :: !(Vec 8 Ms)           -- working dwell table for this glide
  } deriving (Generic, NFDataX, Show)

initSt :: St
initSt = St ParkA 0 0 restMs True False dwellTable

------------------------------------------------------------------------
-- Transition function
------------------------------------------------------------------------

-- | Inputs to the FSM proper: (run, ribbon, park, fire, pending table).
next :: St -> (Bool, Bool, Bool, Bool, Vec 8 Ms) -> St
next s (run, ribbon, park, fire, pend)
  | not ribbon = parkNow s { paused = True, lost = True }
  | not run    = s { paused = True, lost = False }
  | not fire   = s { paused = False, lost = False }   -- hold state this tick
  | otherwise  = step s { paused = False, lost = False } park pend

-- | Fall to the park state of the current direction, coil kept.
parkNow :: St -> St
parkNow s@St{..} = case phase of
  GlideFwd -> s { phase = ParkA, rest = restMs }
  GlideRev -> s { phase = ParkB, rest = restMs }
  _        -> s

step :: St -> Bool -> Vec 8 Ms -> St
step s@St{..} park pend = case phase of

  ParkA
    | park      -> s { rest = restMs }                     -- held park
    | rest > 0  -> s { rest = rest - 1 }
    | otherwise -> s { phase = GlideFwd, t = 0, dwell = pend }

  GlideFwd
    | t < here        -> s { t = t + 1 }
    | park            -> s { phase = ParkA, rest = restMs } -- park at this station
    | coil < maxBound -> s { coil = coil + 1, t = 0 }
    | otherwise       -> s { phase = ParkB, rest = restMs }

  ParkB
    | park      -> s { rest = restMs }
    | rest > 0  -> s { rest = rest - 1 }
    | otherwise -> s { phase = GlideRev, t = 0, dwell = pend }

  GlideRev
    | t < here        -> s { t = t + 1 }
    | park            -> s { phase = ParkB, rest = restMs }
    | coil > 0        -> s { coil = coil - 1, t = 0 }
    | otherwise       -> s { phase = ParkA, rest = restMs }

  where here = dwell !! coil

------------------------------------------------------------------------
-- Output function — STATE ONLY (Moore)
------------------------------------------------------------------------

output :: St -> (Vec 8 Drive, Unsigned 2, Index 8, Bool)
output St{..} = (replace coil level (repeat Off), phaseCode phase, coil, paused)
  where
    level
      | lost                             = Off
      | paused                           = Hold
      | phase == ParkA || phase == ParkB = Hold
      | otherwise                        = Run

------------------------------------------------------------------------
-- PWM stage: shared 8-bit carrier, one comparator per coil
------------------------------------------------------------------------

toGate :: Unsigned 8 -> Drive -> Bit
toGate _ Off  = 0
toGate c Hold = boolToBit (c < holdDuty)
toGate c Run  = boolToBit (c < runDuty)

------------------------------------------------------------------------
-- The block
------------------------------------------------------------------------

-- | The Moore machine with its pacer and pending table: drive levels,
--   state code, coil, paused. Shared by the PWM block and the sims.
sleighCore
  :: HiddenClockResetEnable dom
  => Signal dom SleighIn
  -> Signal dom (Vec 8 Drive, Unsigned 2, Index 8, Bool)
sleighCore inp = moore next output initSt (bundle (run, ribbon, park, fire, pend))
 where
  ribbon = siRibbon <$> inp
  park   = siPark <$> inp
  wr     = siDwellWr <$> inp
  spd    = siSpeed <$> inp
  -- pending dwell table: the write port lands here immediately
  pend = regEn dwellTable (isJust <$> wr) (writeEntry <$> pend <*> wr)
  writeEntry tbl (Just (i, ms)) = replace i ms tbl
  writeEntry tbl Nothing        = tbl
  run = (\i -> siEnable i && siShow i && siSpeed i /= 0) <$> inp
  -- the pacer only counts on the 1 ms tick; a paused machine does not
  -- accumulate credit either
  fire = mealy paceStep 0 (bundle (siTick <$> inp, run, spd))
  paceStep acc (tk, r, sp)
    | tk && r   = paceT acc sp
    | otherwise = (acc, False)

sleigh
  :: HiddenClockResetEnable dom
  => Signal dom SleighIn
  -> Signal dom SleighOut
sleigh inp = SleighOut <$> gates <*> code <*> ci <*> pz
 where
  (drives, code, ci, pz) = unbundle (sleighCore inp)
  carrier = register (0 :: Unsigned 8) (carrier + 1)
  -- registered gates: change only on the clock edge; the ribbon mask on
  -- the D input is the dead-man (all low within one clock of ribbon out)
  gates = register 0
            (mask <$> (siRibbon <$> inp)
                  <*> (v2bv . reverse <$> (map <$> (toGate <$> carrier) <*> drives)))
  -- (v2bv puts element 0 at the MSB; reverse so coil 0 is bit 0)
  mask r g = if r then g else 0

------------------------------------------------------------------------
-- 0x4050 / 0x4052 register semantics (decode helpers for PM.RegFile)
------------------------------------------------------------------------

data SleighCtl = SleighCtl
  { scEnable :: !Bool               -- ^ bit 8
  , scPark   :: !Bool               -- ^ bit 9
  , scSpeed  :: !(Unsigned 8)       -- ^ bits 7:0; 0 = follow the theremin
  } deriving (Generic, NFDataX, Eq, Show)

decodeSleighCtl :: BitVector 16 -> SleighCtl
decodeSleighCtl w = SleighCtl (testBit w 8) (testBit w 9) (unpack (slice d7 d0 w))

-- | Effective speed: the register's own value, or the theremin's
--   (PM.SleighSpeed.speedOf) when the register says 0.
effectiveSpeed :: SleighCtl -> Unsigned 8 -> Unsigned 8
effectiveSpeed SleighCtl{..} theremin = if scSpeed == 0 then theremin else scSpeed

-- | The speed the block runs at: the register's, or the theremin's
--   pitch/volume through PM.SleighSpeed.speedOf (volume off = 0 = paused).
sleighSpeedFrom :: SleighCfg -> SleighCtl -> Unsigned 16 -> Unsigned 16 -> Unsigned 8
sleighSpeedFrom cfg ctl pitch vol = effectiveSpeed ctl (speedOf cfg pitch vol)

-- | iSleigh: state, coil, ribbon, show, paused, effective speed.
encodeSleighStatus :: SleighOut -> Bool -> Bool -> Unsigned 8 -> BitVector 16
encodeSleighStatus SleighOut{..} ribbon showSw spd =
  pack spd ++# pack soPaused ++# pack showSw ++# pack ribbon
           ++# pack soCoil ++# pack soState

-- | oSleighDwell: bits 14:12 index, 11:0 ms.
decodeDwellWr :: BitVector 16 -> (Index 8, Ms)
decodeDwellWr w = (unpack (slice d14 d12 w), unpack (slice d11 d0 w))

-- | iSleighDwell readback in the same layout.
encodeDwellRd :: Index 8 -> Ms -> BitVector 16
encodeDwellRd i ms = 0 ++# pack i ++# pack ms

------------------------------------------------------------------------
-- Top entity (ULX3S, 25 MHz)
------------------------------------------------------------------------

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 SleighIn
  -> Signal Ulx25 SleighOut
topEntity clk rst en = withClockResetEnable clk rst en sleigh
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_sleigh"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortProduct "" [ PortName "enable", PortName "speed"
                                  , PortName "show_on", PortName "ribbon"
                                  , PortName "park", PortName "tick_1ms"
                                  , PortName "dwell_wr" ] ]
    , t_output = PortProduct "" [ PortName "gates", PortName "state"
                                , PortName "coil", PortName "paused" ]
    }) #-}
