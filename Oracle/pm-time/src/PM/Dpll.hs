{-# LANGUAGE RecordWildCards #-}
-- PM.Dpll — PPS-locked 10 MHz DPLL: the second, *physical* layer of
-- GPS/DESIGN.md ("measure-and-report AND steer — two layers").
--
-- PM.PpsDiscipline stays the unsteered measurement layer (its RTC is never
-- touched). This block sits beside it on clk_sys and produces the steered
-- 10 MHz enable/output plus a 1 PPS aligned to it:
--
--   clk_sys ─► frac-N NCO (32-bit accumulator, fcw = outHz/sysHz·2^32) ─► tick
--                 ▲                                                       │
--     trim (ppb) ─┘ PI loop ◄─ phase detector ◄─ NCO phase latched at ppsStb
--
-- Phase detector: at every accepted PPS edge (PpsDiscipline's ppsStb) the NCO
-- phase (tick count ++ 12 fraction bits of the accumulator, unit q = 2^-12
-- tick) is latched; the difference to the previous edge minus outHz ticks is
-- the interval error, converted to ns (1 ppb·s = 1 ns) by one constant
-- multiply. PPS-in validity is PpsDiscipline's `locked`: a bad interval or
-- the 1.5 s watchdog (holdover) gates the update off, so a wild PPS cannot
-- yank the output (DESIGN: slew-limited; trim moves at most slewMax ppb per
-- second in any case).
--
-- Loop (one update per accepted edge, 3-clock pipeline: latch, multiply,
-- update):
--   acquisition (not locked): frequency step — trim -= eNs/2 (phase register
--     re-referenced each second, so no phase built up during the slew ramp
--     has to be unwound later);
--   tracking (locked): type-II — phi += eNs; integ -= phi >> ki;
--     trim = integ - phi >> kp; the integrator is held while the slew limit
--     is active (anti-windup). Gains are runtime (DpllCfg), shift-based.
--   lock detector: |phi| <= lockThr ns for lockN consecutive updates; drops
--     at once when PPS validity drops (holdover) or the threshold is missed.
--   holdover: no update runs (PPS gone -> no ppsStb; bad -> gated), so the
--     integrator and trim freeze at the best-known crystal trim.
--
-- Trim: Signed 20, LSB = 1 ppb (ppm = trim / 1000), range +/-524 ppm;
-- applied as fcw = fcwNom + (trim * fcwK) >> 16 with fcwK = fcwNom·1e-9·2^16.
-- The accumulator is never slammed: the tick spacing only ever changes by one
-- system clock (test: spacing in {n-1, n, n+1}, consecutive spacings differ
-- by <= 1).
--
-- 1 PPS out: pulse on the tick that begins each outHz-tick second. While the
-- DPLL is not locked, each accepted PPS edge re-aligns the second counter
-- (PPS-out then lands one second after that edge, at the sync latency of
-- PpsDiscipline: 3 clocks); once locked it free-runs on the disciplined
-- ticks and the loop holds it there.
module PM.Dpll where

import Clash.Prelude

-- Compile-time constants, derived from the clock plan (see dpllConsts).
data DpllConsts = DpllConsts
  { fcwNom  :: !(Unsigned 32)   -- outHz / sysHz * 2^32
  , fcwK    :: !(Unsigned 16)   -- fcwNom * 1e-9 * 2^16  (ppb -> fcw LSB, x2^-16)
  , qK      :: !(Unsigned 32)   -- 1e9 * 2^16 / (4096 * outHz) (q -> ns, x2^-16)
  , outTicks:: !(Unsigned 32)   -- ticks per second (outHz)
  , slewMax :: !(Signed 20)     -- max |trim change| per update, ppb
  , lockN   :: !(Unsigned 8)    -- consecutive in-threshold updates to lock
  } deriving (Show, Generic, NFDataX)

-- | Constants for a system clock of sysHz driving an outHz output.
dpllConsts :: Integer -> Integer -> Signed 20 -> Unsigned 8 -> DpllConsts
dpllConsts sysHz outHz slew n = DpllConsts
  { fcwNom = fromInteger fcw
  , fcwK = fromInteger ((fcw * 65536 + 500_000_000) `div` 1_000_000_000)
  , qK = fromInteger ((1_000_000_000 * 65536 + 2048 * outHz) `div` (4096 * outHz))
  , outTicks = fromInteger outHz
  , slewMax = slew, lockN = n }
 where fcw = (outHz * 4294967296 + sysHz `div` 2) `div` sysHz

-- Runtime configuration (oGpsCtrl in the GPS register block).
data DpllCfg = DpllCfg
  { kp        :: !(Unsigned 4)   -- proportional gain 2^-kp (ns -> ppb)
  , ki        :: !(Unsigned 4)   -- integral gain 2^-ki
  , lockThr   :: !(Unsigned 16)  -- |phase error| threshold, ns
  , forceHold :: !Bool           -- holdover force (test / manual)
  } deriving (Show, Generic, NFDataX)

data DpllOut = DpllOut
  { tick       :: !Bool          -- disciplined outHz enable/output
  , ppsOut     :: !Bool          -- 1 PPS, coincident with a tick
  , trim       :: !(Signed 20)   -- ppb
  , phaseErr   :: !(Signed 24)   -- ns, last update
  , dpllLocked :: !Bool
  , holdover   :: !Bool          -- PPS not valid (PpsDiscipline unlocked / forced)
  } deriving (Show, Generic, NFDataX)

data DpllSt = DpllSt
  { acc     :: !(Unsigned 32)
  , tickQ   :: !Bool
  , tickCnt :: !(Unsigned 32)
  , secCnt  :: !(Unsigned 32)
  , ppsOutQ :: !Bool
  , phPrev  :: !(Unsigned 44)    -- tickCnt ++ acc[31:20]
  , havePh  :: !Bool
  , s1, s2  :: !Bool             -- pipeline stages
  , okL     :: !Bool             -- PPS valid, latched at the edge
  , eQ      :: !(Signed 28)      -- interval error, q
  , eNs     :: !(Signed 24)      -- interval error, ns
  , phi     :: !(Signed 24)      -- phase error, ns
  , integ   :: !(Signed 20)      -- ppb
  , trimQ   :: !(Signed 20)      -- ppb
  , lockCnt :: !(Unsigned 8)
  , lockedQ :: !Bool
  , holdQ   :: !Bool
  } deriving (Show, Generic, NFDataX)

dpllInit :: DpllSt
dpllInit = DpllSt 0 False 0 0 False 0 False False False False 0 0 0 0 0 0 False True

clampTo :: forall n m. (KnownNat n, KnownNat m, n <= m) => Signed m -> Signed n
clampTo x
  | x > resize (maxBound :: Signed n) = maxBound
  | x < resize (minBound :: Signed n) = minBound
  | otherwise = resize x

-- Inputs: (ppsStb, ppsOk, cfg).
dpllStep :: DpllConsts -> DpllSt -> (Bool, Bool, DpllCfg) -> DpllSt
dpllStep DpllConsts{..} DpllSt{..} (ppsStb, ppsOk, DpllCfg{..}) = DpllSt
  { acc = acc', tickQ = tick', tickCnt = if tick' then tickCnt + 1 else tickCnt
  , secCnt = secCnt', ppsOutQ = tick' && not slam && secCnt == outTicks - 1
  , phPrev = if ppsStb then phNow else phPrev
  , havePh = havePh || ppsStb
  , s1 = ppsStb && havePh, s2 = s1
  , okL = if ppsStb then valid else okL
  , eQ = if ppsStb then clampTo eRaw else eQ
  , eNs = if s1 then clampTo (mul eQ qKs `shiftR` 16) else eNs
  , phi = phi', integ = integ', trimQ = trim', lockCnt = lockCnt'
  , lockedQ = lockCnt' >= lockN && valid
  , holdQ = not valid
  }
 where
  valid = ppsOk && not forceHold
  -- NCO
  corr = mul trimQ (unpack (zeroExtend (pack fcwK)) :: Signed 17) `shiftR` 16
  fcw = fcwNom + unpack (pack (resize corr :: Signed 32))
  sum33 = add acc fcw :: Unsigned 33
  tick' = msb sum33 == 1
  acc' = truncateB sum33
  -- 1 PPS out
  slam = ppsStb && not lockedQ
  secCnt' | slam = 0
          | tick' = if secCnt == outTicks - 1 then 0 else secCnt + 1
          | otherwise = secCnt
  -- phase detector (stage 0)
  phNow = unpack (pack tickCnt ++# slice d31 d20 acc) :: Unsigned 44
  diffQ = unpack (pack (phNow - phPrev)) :: Signed 44
  expQ = unpack (zeroExtend (pack outTicks) ++# (0 :: BitVector 12)) :: Signed 44
  eRaw = resize diffQ - resize expQ :: Signed 45
  qKs = unpack (zeroExtend (pack qK)) :: Signed 33
  -- loop update (stage 2)
  update = s2 && okL
  shR :: Signed 24 -> Unsigned 4 -> Signed 24
  shR v k = v `shiftR` fromIntegral k
  phiT = clampTo (resize phi + resize eNs :: Signed 25)      -- tracking
  iNew = clampTo (resize integ - resize (shR phiT ki) :: Signed 25)
  uT = clampTo (resize iNew - resize (shR phiT kp) :: Signed 25)
  uHeld = clampTo (resize integ - resize (shR phiT kp) :: Signed 25)
  slewing = resize uT - resize trimQ > (resize slewMax :: Signed 21)
         || resize uT - resize trimQ < negate (resize slewMax :: Signed 21)
  uA = clampTo (resize trimQ - resize (eNs `shiftR` 1) :: Signed 25) -- acquisition
  (phi', integT, target)
    | not update = (phi, integ, trimQ)
    | lockedQ && slewing = (phiT, integ, uHeld)
    | lockedQ = (phiT, iNew, uT)
    | otherwise = (eNs, integ, uA)
  d = resize target - resize trimQ :: Signed 21
  dLim | d > resize slewMax = slewMax
       | d < negate (resize slewMax) = negate slewMax
       | otherwise = resize d
  trim' = if update then trimQ + dLim else trimQ
  -- acquisition keeps the integrator equal to the (slewed) trim
  integ' = if update && not lockedQ then trim' else integT
  inThr = abs phi' <= (unpack (zeroExtend (pack lockThr)) :: Signed 24)
  lockCnt' | not valid = 0
           | not update = lockCnt
           | inThr = if lockCnt == maxBound then lockCnt else lockCnt + 1
           | otherwise = 0

dpllOut :: DpllSt -> DpllOut
dpllOut DpllSt{..} = DpllOut tickQ ppsOutQ trimQ phi lockedQ holdQ

dpll
  :: HiddenClockResetEnable dom
  => DpllConsts
  -> Signal dom DpllCfg
  -> Signal dom Bool             -- ppsStb  (PM.PpsDiscipline)
  -> Signal dom Bool             -- ppsOk   (PM.PpsDiscipline locked)
  -> Signal dom DpllOut
dpll c cfg stb ok = moore (dpllStep c) dpllOut dpllInit (bundle (stb, ok, cfg))

-- Hardware: clk_sys 100 MHz (ULX3S 25 MHz xtal x PLL), 10 MHz out,
-- slew 4096 ppb/s, lock after 8 consecutive in-threshold seconds.
hwConsts :: DpllConsts
hwConsts = DpllConsts
  { fcwNom = 429496730, fcwK = 28147, qK = 1600, outTicks = 10_000_000
  , slewMax = 4096, lockN = 8 }

{-# ANN topEntity
  (Synthesize
    { t_name = "dpll_10mhz"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortProduct "" [ PortName "kp", PortName "ki"
                                  , PortName "lock_thr", PortName "force_hold" ]
                 , PortName "pps_stb", PortName "pps_ok" ]
    , t_output = PortProduct "" [ PortName "tick", PortName "pps_out"
                                , PortName "trim", PortName "phase_err"
                                , PortName "locked", PortName "holdover" ]
    }) #-}
topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 4, Unsigned 4, Unsigned 16, Bool)
  -> Signal System Bool -> Signal System Bool
  -> Signal System (Bool, Bool, Signed 20, Signed 24, Bool, Bool)
topEntity clk rst en cfg stb ok = withClockResetEnable clk rst en $
  (\DpllOut{..} -> (tick, ppsOut, trim, phaseErr, dpllLocked, holdover))
    <$> dpll hwConsts ((\(a, b, c, d) -> DpllCfg a b c d) <$> cfg) stb ok
