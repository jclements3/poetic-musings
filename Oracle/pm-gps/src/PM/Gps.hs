{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
-- PM.Gps — NMEA time source for the 0x4040 TOD-set block (letter G,
-- GPS/DESIGN.md register table; eforth-pm.md 0x4034 IRIG status group).
--
-- A byte-at-a-time $GxRMC parser: the GPS module's UART stream in, the
-- Irig core's BCD set request out. Any talker is accepted (GP, GN, GL,
-- GA, GB — only the leading 'G' and the 'RMC' formatter are matched);
-- every other sentence ($GPGGA, ...) is ignored. The `*hh` XOR checksum
-- is verified over everything between '$' and '*'; a sentence that fails
-- it, or that is missing any of time/status/date, updates nothing.
--
-- Output words are exactly the Irig topEntity set-interface stub
-- (IRIG/clash/src/Irig.hs — "the register file packs/unpacks its word
-- formats; the core takes BCD digits directly, so it needs no /60 and
-- /3600 dividers"):
--
--     tod_ssmm  [15:12] ss tens  [11:8] ss ones  [7:4] mm tens  [3:0] mm ones
--     tod_hhdl  [15:12] hh tens  [11:8] hh ones  [7:4] doy tens [3:0] doy ones
--     tod_dh    [3:0]   doy hundreds
--     tod_set   one-cycle strobe; the words above are stable while it is high
--
-- so this block replaces the H2 sim's TOD stub (clash-h2 SystemUart.hs)
-- with no conversion layer: SystemUart's binary->BCD div/mod is sim-only
-- code, and with GPS as the source the digits are BCD end to end — the
-- incoming ASCII digits ARE the BCD values (low nibble / subtract 0x30).
-- The only arithmetic here is the day-of-year fold: a BCD cumulative
-- month table + BCD add of the day (+1 for March onward in a leap year,
-- yy mod 4 — exact for 2000-2099). No division, no multiplication wider
-- than the 4-bit month decode, no floating point, no String.
--
-- Validity policy (documented choice): a V-flag (void) sentence still
-- carries the receiver's best time estimate, so it DOES update the TOD
-- words and fire tod_set — but `locked` reports low. Lock is a level,
-- per iGpsStat {locked, holdover, ...}; whether an unlocked label may
-- strobe the rtc is the consumer's call (Forth gates oTodSet anyway).
--
-- Front end: input is a Maybe Byte strobe, not a serial line — pm-lib's
-- PM.HarpLink uartRx produces exactly this shape. Caveat for 9600 Bd
-- GPS modules: uartRx's divisor is Unsigned 8 (built for the 3 Mbaud
-- harp link); 25 MHz / 9600 = 2604 ticks needs that divisor widened (or
-- a /16 prescaler in front). The parser itself is rate-agnostic and
-- accepts back-to-back bytes.
module PM.Gps where

import Clash.Prelude
import Data.Maybe (isJust)

type Byte = BitVector 8

-- | One BCD digit (Irig.hs convention).
type Digit = Unsigned 4

-- | A validated fix: (status == 'A', hhmmss digits, ddmmyy digits).
type Fix = (Bool, Vec 6 Digit, Vec 6 Digit)

-- | The held TOD-set words (formats in the module header).
data Tod = Tod
  { todSsmm   :: !(BitVector 16)
  , todHhdl   :: !(BitVector 16)
  , todDh     :: !(BitVector 8)
  , todLocked :: !Bool
  } deriving (Generic, NFDataX, Eq, Show)

-- Boot value: day 000, 00:00:00, unlocked. Invalid as IRIG time, but
-- tod_set has never fired so nothing may consume it yet.
todInit :: Tod
todInit = Tod 0 0 0 False

-- ---------------------------------------------------------------------------
-- Sentence parser: one mealy FSM, self-synchronizing on '$'.

data Phase
  = PHunt            -- waiting for '$'
  | PAddr !(Index 5) -- matching the G?RMC address field
  | PField           -- inside the comma-separated fields
  | PCk1 | PCk2      -- the two checksum hex digits after '*'
  deriving (Generic, NFDataX, Eq, Show)

data PSt = PSt
  { pPhase :: !Phase
  , pCsum  :: !Byte          -- running XOR, '$'-exclusive to '*'-exclusive
  , pField :: !(Unsigned 4)  -- field number = comma count (saturating)
  , pDigs  :: !(Unsigned 3)  -- digits captured in the current time/date field
  , pTime  :: !(Vec 6 Digit) -- h h m m s s
  , pDate  :: !(Vec 6 Digit) -- d d m m y y
  , pStat  :: !Bool          -- status field was 'A'
  , pGotT  :: !Bool          -- field 1 delivered all 6 time digits
  , pGotS  :: !Bool          -- field 2 delivered A or V
  , pGotD  :: !Bool          -- field 9 delivered all 6 date digits
  } deriving (Generic, NFDataX)

pInit :: PSt
pInit = PSt PHunt 0 0 0 (repeat 0) (repeat 0) False False False False

-- G?RMC: any talker second letter — GP, GN, GL, GA, GB all label the
-- same UTC second.
addrOk :: Index 5 -> Byte -> Bool
addrOk 0 b = b == 0x47   -- 'G'
addrOk 1 _ = True
addrOk 2 b = b == 0x52   -- 'R'
addrOk 3 b = b == 0x4D   -- 'M'
addrOk _ b = b == 0x43   -- 'C'

hexVal :: Byte -> Maybe (BitVector 4)
hexVal b
  | b >= 0x30 && b <= 0x39 = Just (truncateB (b - 0x30))   -- '0'-'9'
  | b >= 0x41 && b <= 0x46 = Just (truncateB (b - 0x37))   -- 'A'-'F'
  | b >= 0x61 && b <= 0x66 = Just (truncateB (b - 0x57))   -- 'a'-'f'
  | otherwise              = Nothing

-- Field-close bookkeeping (at ',' and '*'): a time/date field counts only
-- when all 6 digits arrived — "hhmmss.sss" stops capturing at 6, so the
-- fraction and a variant without one both pass; an empty field fails.
closeF :: PSt -> PSt
closeF s@PSt{..} = s { pGotT = pGotT || (pField == 1 && pDigs == 6)
                     , pGotD = pGotD || (pField == 9 && pDigs == 6) }

gpsT :: PSt -> Maybe Byte -> (PSt, Maybe Fix)
gpsT s Nothing = (s, Nothing)
gpsT s@PSt{..} (Just b)
  | b == 0x24 = (pInit { pPhase = PAddr 0 }, Nothing)  -- '$' resyncs from anywhere
  | otherwise = case pPhase of
      PHunt -> (s, Nothing)
      PAddr i
        | not (addrOk i b) -> (s { pPhase = PHunt }, Nothing)   -- not G?RMC: drop
        | i == maxBound    -> (s { pPhase = PField, pCsum = cs }, Nothing)
        | otherwise        -> (s { pPhase = PAddr (i + 1), pCsum = cs }, Nothing)
      PField
        | b == 0x2A ->                                 -- '*': not xored
            ((closeF s) { pPhase = PCk1 }, Nothing)
        | b == 0x2C ->                                 -- ',': field boundary
            ((closeF s) { pField = satAdd SatBound pField 1
                        , pDigs = 0, pCsum = cs }, Nothing)
        | digit, pField == 1, pDigs < 6 ->
            (s { pTime = replace pDigs dig pTime, pDigs = pDigs + 1, pCsum = cs }, Nothing)
        | digit, pField == 9, pDigs < 6 ->
            (s { pDate = replace pDigs dig pDate, pDigs = pDigs + 1, pCsum = cs }, Nothing)
        | pField == 2, b == 0x41 ->                    -- 'A': valid fix
            (s { pStat = True, pGotS = True, pCsum = cs }, Nothing)
        | pField == 2, b == 0x56 ->                    -- 'V': void (header policy)
            (s { pStat = False, pGotS = True, pCsum = cs }, Nothing)
        | otherwise -> (s { pCsum = cs }, Nothing)     -- '.', sign, N/E/W, mode, ...
      PCk1 -> case hexVal b of
        Just h | h == slice d7 d4 pCsum -> (s { pPhase = PCk2 }, Nothing)
        _                               -> (s { pPhase = PHunt }, Nothing)
      PCk2 -> case hexVal b of
        Just h | h == slice d3 d0 pCsum, pGotT, pGotS, pGotD
          -> (pInit, Just (pStat, pTime, pDate))
        _ -> (pInit, Nothing)
  where
    cs    = pCsum `xor` b
    digit = b >= 0x30 && b <= 0x39
    dig   = unpack (slice d3 d0 b) :: Digit   -- ASCII low nibble IS the BCD digit

-- ---------------------------------------------------------------------------
-- ddmmyy -> BCD day-of-year, all-BCD arithmetic.

-- Cumulative days before each month (non-leap), stored as BCD digits so
-- the fold below is pure digit adds with decimal carries — no dividers.
cumDays :: Vec 12 (Digit, Digit, Digit)
cumDays =    (0,0,0) :> (0,3,1) :> (0,5,9) :> (0,9,0)
          :> (1,2,0) :> (1,5,1) :> (1,8,1) :> (2,1,2)
          :> (2,4,3) :> (2,7,3) :> (3,0,4) :> (3,3,4) :> Nil

-- 3-digit BCD + 2-digit BCD (+1), decimal ripple carry. Max per stage is
-- 9+9+1 = 19: one compare, one subtract-10.
bcdAdd :: (Digit, Digit, Digit) -> (Digit, Digit) -> Bool -> (Digit, Digit, Digit)
bcdAdd (ch, ct, co) (bt, bo) inc = (h, t, o)
  where
    (c0, o) = digAdd co bo (if inc then 1 else 0)
    (c1, t) = digAdd ct bt c0
    (_,  h) = digAdd ch 0  c1
    digAdd :: Digit -> Digit -> Digit -> (Digit, Digit)   -- (carry, digit)
    digAdd x y c =
      let sm = resize x + resize y + resize c :: Unsigned 5
      in if sm > 9 then (1, resize (sm - 10)) else (0, resize sm)

-- Leap: yy mod 4 == 0, i.e. (2*tens + ones) mod 4 — exact for 2000-2099
-- (2000 is a leap year); the +1 applies from March on.
dayOfYear :: (Digit, Digit) -> (Digit, Digit) -> (Digit, Digit) -> (Digit, Digit, Digit)
dayOfYear dd (m10, m1) (y10, y1) = bcdAdd (cumDays !! mIx) dd leapAdj
  where
    month   = 10 * resize m10 + resize m1 :: Unsigned 5
    mIx     = min 11 (satSub SatBound month 1)
    leap    = (2 * resize y10 + resize y1 :: Unsigned 6) .&. 3 == 0
    leapAdj = leap && month >= 3

-- ---------------------------------------------------------------------------
-- Field packing and the register stage.

packFix :: Fix -> Tod
packFix (a, t, d) = Tod ssmm hhdl dh a
  where
    ti i = t !! (i :: Index 6)
    di i = d !! (i :: Index 6)
    (yH, yT, yO) = dayOfYear (di 0, di 1) (di 2, di 3) (di 4, di 5)
    ssmm = pack (ti 4) ++# pack (ti 5) ++# pack (ti 2) ++# pack (ti 3)
    hhdl = pack (ti 0) ++# pack (ti 1) ++# pack yT ++# pack yO
    dh   = (0 :: BitVector 4) ++# pack yH

-- The TOD words are held; tod_set is registered off the same event so it
-- is high exactly one cycle, with the freshly latched words already
-- visible — oTodSet semantics (strobe latches stable registers).
gps
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe Byte)           -- rx byte strobe (uartRx shape)
  -> (Signal dom Tod, Signal dom Bool) -- (held TOD words + lock, tod_set)
gps mb = (tod, pulse)
  where
    fix   = mealy gpsT pInit mb
    good  = isJust <$> fix
    tod   = regEn todInit good (packFix . fromJustX <$> fix)
    pulse = register False good

-- ---------------------------------------------------------------------------
-- Top entity: byte strobe in, TOD-set block out. Wired under O's register
-- file as {iGpsStat.locked, oTodSecs/oTodDay/oTodSet payload}; until then,
-- plain ports (PM.Keyer convention).

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Maybe Byte)               -- rx byte strobe
  -> Signal System (BitVector 16, BitVector 16, BitVector 8, Bool, Bool)
     -- (tod_ssmm, tod_hhdl, tod_dh, locked, tod_set)
topEntity = exposeClockResetEnable $ \mb ->
  let (tod, pulse) = gps mb
  in bundle ( todSsmm <$> tod, todHhdl <$> tod, todDh <$> tod
            , todLocked <$> tod, pulse )
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_gps"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "rx_byte" ]
    , t_output = PortName "out"
    }) #-}
