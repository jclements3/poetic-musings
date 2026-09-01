-- PM.Zones — slider zone decoder behind the 0x4020 register pair
-- (Oracle/eforth-pm.md section 1: oPanelCtrl / iPanel).
--
--     Build:    cabal build
--     Test:     cabal test zones-test --test-show-details=direct
--     Verilog:  cabal run clash -- -isrc PM.Zones --verilog
--     Output:   verilog/PM.Zones.topEntity/
--
-- The eforth-pm contract: gateware digitizes S2–S4 and compares against zone
-- thresholds *with hysteresis* (a slider parked on a boundary never flickers
-- — PLAN Piano BOM rule); Forth reads clean zone numbers, never raw counts.
-- The SPI ADC sequencing lives with oPanelCtrl elsewhere; this module takes
-- already-sampled 12-bit values, one per detent slider:
--
--     S2  OCTAVE  3 zones  LOW · MID · HIGH          (LAYOUT top view)
--     S3  MODE    6 zones  P · O · E · T · I · C
--     S4          4 zones  OFF · CAL · PLAY · REC
--
-- Zone geometry: full scale 0..4095 divided evenly, boundary i = i*4096/n.
-- Plain decode is (v*n) >> 12 — a constant multiply, no divider.  Hysteresis
-- is a Schmitt rule around the CURRENT zone: the tracked zone changes only
-- when the input sits more than H counts past a boundary of its zone, and it
-- then jumps straight to the plain decode of v (so a fast full-travel throw
-- is never rate-limited).  Noise up to H around a boundary can therefore
-- never flicker the zone, whichever side it settled on.  The Schmitt test is
-- phrased through the decoder itself — "does v, backed off by H, still
-- decode past my zone?" — so no boundary table exists in hardware at all,
-- just three copies of the same constant multiply.
--
-- S3 mode dwell (LAYOUT: "a mode change takes effect after the slider rests
-- ~1 s in the new zone — a bumped slider never yanks a demo"): the
-- post-hysteresis S3 zone must be stable for a full dwell period before the
-- `mode` output updates and `modeChange` pulses for one cycle; any zone
-- change restarts the timer.  eforth-pm's boot flow keeps the same 1 s rule
-- in the Forth dispatch loop — this output is the gateware-side equivalent
-- for consumers that never go through Forth (and drives the iPanel `stable`
-- flag).  Dwell ticks are a parameter so simulation is cheap.
--
-- Register contract implemented (bit layout provisional per eforth-pm; the
-- S3/S4 fields match the clash-h2 SystemUart sim model of 0x4020):
--
--     iPanel (0x4020 read): bits 2:0 S3 zone 0–5 (P=0 … C=5) · bit 3 zero ·
--       bits 5:4 S4 zone (0 OFF · 1 CAL · 2 PLAY · 3 REC) · bits 7:6 S2 zone
--       (0 LOW · 1 MID · 2 HIGH) · bits 14:8 zero · bit 15 `stable` (the S3
--       zone has sat unchanged for a full dwell period)

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.Zones where

import Clash.Prelude
import PM.Ulx25 (Ulx25)

------------------------------------------------------------------------------------------------
-- Hardware constants
------------------------------------------------------------------------------------------------

-- | Hysteresis half-band, ADC counts.  128 ≈ 3 % of travel — far below the
--   narrowest zone (S3: 682 counts) and far above slider/ADC noise.
hwHyst :: Unsigned 12
hwHyst = 128

-- | S3 mode dwell: 1 s at the ULX3S 25 MHz clock.
hwDwellTicks :: Unsigned 32
hwDwellTicks = 25_000_000

------------------------------------------------------------------------------------------------
-- Zone tracking with hysteresis (generic in the zone count)
------------------------------------------------------------------------------------------------

-- | Plain decode: which of the n even zones does v fall in.  (v*n) >> 12 is
--   a constant multiply; the min catches only the all-ones corner case.
zoneOf :: forall n. (KnownNat n, 1 <= n, n <= 16) => Unsigned 12 -> Index n
zoneOf v = fromIntegral
             (min (natToNum @n - 1)
                  (shiftR (resize v * natToNum @n :: Unsigned 16) 12))

-- | Schmitt zone tracker: hold the current zone until the input sits more
--   than H counts past one of its boundaries, then jump to the plain decode.
--   The band test reuses 'zoneOf' on the input backed off by H — v more than
--   H above hi(z) iff (v - H) still decodes above z, and dually below — so
--   the whole tracker is comparators around the one constant multiply.
zoneTrack
  :: forall n dom. (HiddenClockResetEnable dom, KnownNat n, 1 <= n, n <= 16)
  => Unsigned 12                    -- ^ hysteresis half-band H, ADC counts
  -> Signal dom (Unsigned 12)       -- ^ ADC sample
  -> Signal dom (Index n)           -- ^ tracked zone, post-hysteresis
zoneTrack h = moore go id 0
  where
    go z v
      | d == z                                        = z
      | d > z && zoneOf @n (satSub SatBound v h) > z  = d
      | d < z && zoneOf @n (satAdd SatBound v h) < z  = d
      | otherwise                                     = z
      where d = zoneOf @n v

------------------------------------------------------------------------------------------------
-- S3 mode dwell
------------------------------------------------------------------------------------------------

data DwellSt = DwellSt
  { dwMode :: Index 6        -- ^ the dwell-qualified mode (what a demo runs)
  , dwLast :: Index 6        -- ^ last observed post-hysteresis S3 zone
  , dwCnt  :: Unsigned 32    -- ^ ticks the zone has been stable (saturating)
  , dwChg  :: Bool           -- ^ one-cycle pulse: dwMode just updated
  } deriving (Generic, NFDataX, Eq, Show)

dwellStep :: Unsigned 32 -> DwellSt -> Index 6 -> DwellSt
dwellStep dwellT DwellSt{..} z
  | z /= dwLast                   = DwellSt dwMode z 0 False     -- restart the timer
  | cnt' >= dwellT && dwMode /= z = DwellSt z      z cnt' True   -- dwelled: commit, pulse once
  | otherwise                     = DwellSt dwMode z cnt' False
  where cnt' = satSucc SatBound dwCnt

------------------------------------------------------------------------------------------------
-- The decoder
------------------------------------------------------------------------------------------------

data ZonesOut = ZonesOut
  { zoS2         :: Index 3         -- ^ S2 zone, post-hysteresis
  , zoS3         :: Index 6         -- ^ S3 zone, post-hysteresis (pre-dwell)
  , zoS4         :: Index 4         -- ^ S4 zone, post-hysteresis
  , zoStable     :: Bool            -- ^ S3 unchanged for a full dwell period
  , zoMode       :: Index 6         -- ^ dwell-qualified S3 zone
  , zoModeChange :: Bool            -- ^ one-cycle pulse when zoMode updates
  , zoIPanel     :: BitVector 16    -- ^ the packed iPanel word (module header)
  } deriving (Generic, NFDataX, Eq, Show)

-- | Pack the iPanel register word (0x4020 read; layout in the module header).
ipanelWord :: Index 3 -> Index 6 -> Index 4 -> Bool -> BitVector 16
ipanelWord s2 s3 s4 st =
  pack st ++# (0 :: BitVector 7)
          ++# pack s2 ++# pack s4 ++# (0 :: BitVector 1) ++# pack s3

-- | The zone decoder: three already-sampled sliders in, clean zones + the
--   dwell-qualified mode + the packed iPanel word out.
zones
  :: HiddenClockResetEnable dom
  => Unsigned 12                    -- ^ hysteresis half-band (hw: 'hwHyst')
  -> Unsigned 32                    -- ^ dwell ticks (hw: 'hwDwellTicks'; small for sim)
  -> Signal dom (Unsigned 12)       -- ^ S2 sample
  -> Signal dom (Unsigned 12)       -- ^ S3 sample
  -> Signal dom (Unsigned 12)       -- ^ S4 sample
  -> Signal dom ZonesOut
zones h dwellT s2 s3 s4 = mkOut <$> z2 <*> z3 <*> z4 <*> dw
  where
    z2 = zoneTrack @3 h s2
    z3 = zoneTrack @6 h s3
    z4 = zoneTrack @4 h s4
    dw = moore (dwellStep dwellT) id (DwellSt 0 0 0 False) z3
    mkOut a b c DwellSt{..} =
      ZonesOut a b c stable dwMode dwChg (ipanelWord a b c stable)
      where stable = dwCnt >= dwellT

------------------------------------------------------------------------------------------------
-- Top entity — real timing on the ULX3S 25 MHz crystal
------------------------------------------------------------------------------------------------

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 (BitVector 12)    -- ^ S2 ADC sample
  -> Signal Ulx25 (BitVector 12)    -- ^ S3 ADC sample
  -> Signal Ulx25 (BitVector 12)    -- ^ S4 ADC sample
  -> ( Signal Ulx25 (BitVector 16)  -- ^ iPanel register word
     , Signal Ulx25 (BitVector 3)   -- ^ dwell-qualified mode 0–5
     , Signal Ulx25 Bit             -- ^ one-cycle mode-change strobe
     )
topEntity clk rst en s2 s3 s4 = exposeClockResetEnable board clk rst en
  where
    board :: HiddenClockResetEnable Ulx25
          => ( Signal Ulx25 (BitVector 16)
             , Signal Ulx25 (BitVector 3)
             , Signal Ulx25 Bit )
    board = ( zoIPanel <$> out
            , pack . zoMode <$> out
            , boolToBit . zoModeChange <$> out )
      where
        out = zones hwHyst hwDwellTicks (unpack <$> s2) (unpack <$> s3) (unpack <$> s4)
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_zones"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "s2_adc", PortName "s3_adc", PortName "s4_adc" ]
    , t_output = PortProduct "" [ PortName "ipanel", PortName "mode"
                                , PortName "mode_change" ]
    }) #-}
{-# OPAQUE topEntity #-}
