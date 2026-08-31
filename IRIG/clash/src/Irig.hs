-- IRIG-B timecode generator (Phase 2 of PLAN.md) — see IRIG/DESIGN.md.
--
--     Build:    cabal build
--     Test:     cabal test                 (frame/cell/rollover/set assertions in test/Spec.hs)
--     Verilog:  cabal exec -- clash -isrc Irig --verilog
--     Output:   verilog/Irig.topEntity/
--
-- Module map (names per DESIGN.md / vl1-clash-module-tree conventions):
--
--     tick1k    25 MHz sys -> 1 kHz cell-phase enable + 1 kHz carrier phase
--     rtc       BCD clock ss:mm:hh + day-of-year, settable, applied at next P_r
--     framer    100-cell frame mux: cell index -> {ZERO, ONE, MARK} from rtc BCD
--     pwmcell   cell class -> 2/5/8 ms high within the 10 ms cell
--     irigb     top: dcOut :: Bit, amOut :: Signed 8 (to the audio DAC path)
--
-- The whole design runs from one timing parameter, `SNat k` = clock ticks per 0.1 ms
-- (the finest phase anything here needs: the AM carrier is a 1 kHz sine sampled 10 times
-- per cycle, i.e. every 0.1 ms). Ticks per 1 ms cell-phase is therefore 10*k:
--
--     k = 2500  ->  25 000 ticks/ms   real timing on the ULX3S 25 MHz crystal
--     k = 1     ->      10 ticks/ms   simulation: a full 1 s frame in 10 000 ticks
--
--         ┌────────┐ msTick(1kHz) ┌──────────┐ cellIx ┌────────┐ CellClass ┌─────────┐
--     clk─▶ tick1k ├──────────────▶ framePos ├────────▶ framer ├───────────▶ pwmcell ├─▶ dcOut
--         └───┬────┘              └────┬─────┘   ┌────▶        │      ┌────▶         │
--             │carrIx                  │frameRef │    └────────┘      │msIx└─────────┘
--             │                   ┌────▼─────┐   │                   │          │envelope
--             │          set ────▶│   rtc    ├───┘ (BCD + SBS)       │          ▼
--             │                   └──────────┘                       │     ┌─────────┐
--             └──────────────────────────────────────────────────────┼────▶│ am mod  ├─▶ amOut
--                                                                    └────▶└─────────┘

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
{-# OPTIONS_GHC -Wno-orphans #-}   -- createDomain necessarily makes an orphan KnownDomain

module Irig where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------------------------

-- | One BCD digit, 0..9 (tens digits use only the low bits they need).
type Digit = Unsigned 4

-- | What a 10 ms bit cell carries: pulse widths 2 / 5 / 8 ms.
data CellClass = CellZero | CellOne | CellMark
  deriving (Generic, NFDataX, Eq, Show)

-- | Set request for the rtc, as (tens, ones) BCD digit pairs; day-of-year is
--   (hundreds, tens, ones). Latched by @set_strobe@, applied at the next frame reference.
data SetVal = SetVal
  { setSs  :: (Digit, Digit)
  , setMm  :: (Digit, Digit)
  , setHh  :: (Digit, Digit)
  , setDoy :: (Digit, Digit, Digit)
  } deriving (Generic, NFDataX, Eq, Show)

-- | The clock registers the framer serializes. @sbs@ is the straight-binary-seconds-of-day
--   field (0..86399, 17 bits), kept in step with the BCD digits.
data Rtc = Rtc
  { sOnes, sTens :: Digit
  , mOnes, mTens :: Digit
  , hOnes, hTens :: Digit
  , dOnes, dTens, dHund :: Digit
  , sbs :: Unsigned 17
  } deriving (Generic, NFDataX, Eq, Show)

-- | Boot time per DESIGN.md: day 001, 00:00:00 — the scope check doesn't need wall time.
rtcBoot :: Rtc
rtcBoot = Rtc 0 0 0 0 0 0 1 0 0 0

------------------------------------------------------------------------------------------------
-- tick1k: the timebase
------------------------------------------------------------------------------------------------
--
-- One prescaler counts k ticks per 0.1 ms; a mod-10 counter on top of it is simultaneously
-- the carrier-phase index (10 samples per 1 kHz sine cycle) and the divide-to-1ms stage.
-- The 1 kHz cell-phase enable pulses on the LAST tick of each ms, so everything clocked by
-- it changes state on the ms boundary exactly.
--
-- (DESIGN.md's fractional-divider CAL trim is not implemented yet — see Status.)

tick1k ::
  forall k dom.
  (HiddenClockResetEnable dom, KnownNat k, 1 <= k) =>
  SNat k ->                                     -- ^ ticks per 0.1 ms (2500 real, 1 sim)
  (Signal dom Bool, Signal dom (Index 10))      -- ^ (msTick 1 kHz enable, carrier phase)
tick1k _ = (msT, ph)
  where
    pre  = register (0 :: Index k) (satSucc SatWrap <$> pre)
    subT = pre .==. pure maxBound                -- 10 kHz enable: last tick of each 0.1 ms
    ph   = regEn (0 :: Index 10) subT (satSucc SatWrap <$> ph)
    msT  = subT .&&. ph .==. pure maxBound       -- 1 kHz enable: last tick of each 1 ms

------------------------------------------------------------------------------------------------
-- framePos: where in the frame are we
------------------------------------------------------------------------------------------------

framePos ::
  HiddenClockResetEnable dom =>
  Signal dom Bool ->                            -- ^ msTick
  ( Signal dom (Index 100)                      -- ^ cell index within the frame
  , Signal dom (Index 10)                       -- ^ ms index within the cell
  , Signal dom Bool )                           -- ^ frame reference: pulses entering cell 0
framePos msT = (cellIx, msIx, frameRef)
  where
    msIx     = regEn (0 :: Index 10) msT (satSucc SatWrap <$> msIx)
    cellEnd  = msT .&&. msIx .==. pure maxBound
    cellIx   = regEn (0 :: Index 100) cellEnd (satSucc SatWrap <$> cellIx)
    frameRef = cellEnd .&&. cellIx .==. pure maxBound

------------------------------------------------------------------------------------------------
-- rtc: the settable BCD clock
------------------------------------------------------------------------------------------------
--
-- Advances once per frame reference (once per second). A set_strobe latches the request into
-- a pending register; the NEXT frame reference loads it instead of incrementing, so the frame
-- that starts at that P_r encodes exactly the set time. Day-of-year wraps 366 -> 001
-- (leap-agnostic; G disciplines calendars in Phase 7, not us).

rtcTick :: Rtc -> Rtc
rtcTick Rtc{..} = Rtc sO sT mO mT hO hT dO dT dH sbs'
  where
    sbs' = if sbs == 86399 then 0 else sbs + 1
    bump lim d = if d == lim then (0, True) else (d + 1, False)
    (sO, c1) = bump 9 sOnes
    (sT, c2) = if c1 then bump 5 sTens else (sTens, False)
    (mO, c3) = if c2 then bump 9 mOnes else (mOnes, False)
    (mT, c4) = if c3 then bump 5 mTens else (mTens, False)
    (hO, hT, c5)
      | not c4                       = (hOnes, hTens, False)
      | hTens == 2 && hOnes == 3     = (0, 0, True)
      | hOnes == 9                   = (0, hTens + 1, False)
      | otherwise                    = (hOnes + 1, hTens, False)
    (dO, dT, dH)
      | not c5                                   = (dOnes, dTens, dHund)
      | dHund == 3 && dTens == 6 && dOnes == 6   = (1, 0, 0)          -- 366 -> 001
      | dOnes == 9 && dTens == 9                 = (0, 0, dHund + 1)
      | dOnes == 9                               = (0, dTens + 1, dHund)
      | otherwise                                = (dOnes + 1, dTens, dHund)

rtcFromSet :: SetVal -> Rtc
rtcFromSet SetVal{..} =
  Rtc (snd setSs) (fst setSs) (snd setMm) (fst setMm) (snd setHh) (fst setHh)
      dO dT dH sbsOf
  where
    (dH, dT, dO) = setDoy
    bin2 :: (Digit, Digit) -> Unsigned 17
    bin2 (t, o) = 10 * resize t + resize o
    sbsOf = (bin2 setHh * 60 + bin2 setMm) * 60 + bin2 setSs

rtc ::
  HiddenClockResetEnable dom =>
  Signal dom Bool ->                            -- ^ frame reference
  Signal dom Bool ->                            -- ^ set_strobe
  Signal dom SetVal ->
  Signal dom Rtc
rtc frameRef strobe setv = st
  where
    pend = register (Nothing :: Maybe SetVal) (upd <$> strobe <*> setv <*> frameRef <*> pend)
    upd s v fr p | s         = Just v           -- latch (a strobe on the P_r tick itself
                 | fr        = Nothing          --  waits for the NEXT reference)
                 | otherwise = p
    st = regEn rtcBoot frameRef (apply <$> pend <*> st)
    apply (Just v) _ = rtcFromSet v
    apply Nothing  t = rtcTick t

------------------------------------------------------------------------------------------------
-- framer: cell index -> cell class
------------------------------------------------------------------------------------------------
--
-- IRIG-B frame, 100 cells, BCD fields LSB first, position marker every 10th cell. P0 at
-- cell 99 back-to-back with the next frame's P_r at cell 0 is the frame reference
-- double-marker.
--
--     cell   0      P_r                 cell  50-58  zeros (year/ctrl unused)
--     cells  1-8    seconds  1 2 4 8 · 10 20 40      59     P6
--     cell   9      P1                 cells 60-68  zeros   69 P7
--     cells 10-18   minutes  (as seconds) · 0        cells 70-78  zeros   79 P8
--     cell  19      P2                 cells 80-88  SBS bits 0-8
--     cells 20-28   hours    1 2 4 8 · 10 20 · 0 0   cell  89     P9
--     cell  29      P3                 cells 90-97  SBS bits 9-16
--     cells 30-38   doy      1 2 4 8 · 10 20 40 80   cell  98     zero
--     cell  39      P4                 cell  99     P0
--     cells 40-48   doy 100 200 · zeros (0.1 s unused)
--     cell  49      P5

bitCell :: Bool -> CellClass
bitCell b = if b then CellOne else CellZero

digBits :: forall n. KnownNat n => Digit -> Vec n CellClass
digBits d = map (\i -> bitCell (testBit d (fromIntegral i))) (indicesI @n)

frameVec :: Rtc -> Vec 100 CellClass
frameVec Rtc{..} =
       mk                                                              --  0      P_r
    ++ digBits @4 sOnes ++ z1 ++ digBits @3 sTens ++ mk                --  1-9    sec, P1
    ++ digBits @4 mOnes ++ z1 ++ digBits @3 mTens ++ z1 ++ mk          -- 10-19   min, P2
    ++ digBits @4 hOnes ++ z1 ++ digBits @2 hTens ++ zs @2 ++ mk       -- 20-29   hr,  P3
    ++ digBits @4 dOnes ++ z1 ++ digBits @4 dTens ++ mk                -- 30-39   doy, P4
    ++ digBits @2 dHund ++ zs @7 ++ mk                                 -- 40-49   doy, P5
    ++ zs @9 ++ mk                                                     -- 50-59   P6
    ++ zs @9 ++ mk                                                     -- 60-69   P7
    ++ zs @9 ++ mk                                                     -- 70-79   P8
    ++ take (SNat @9) sbsC ++ mk                                       -- 80-89   SBS, P9
    ++ drop (SNat @9) sbsC ++ z1 ++ mk                                 -- 90-99   SBS, P0
  where
    mk = CellMark :> Nil
    z1 = CellZero :> Nil
    zs :: forall n. KnownNat n => Vec n CellClass
    zs = repeat CellZero
    sbsC :: Vec 17 CellClass
    sbsC = map (\i -> bitCell (testBit sbs (fromIntegral i))) (indicesI @17)

framer :: Signal dom Rtc -> Signal dom (Index 100) -> Signal dom CellClass
framer t ix = (!!) <$> (frameVec <$> t) <*> ix

------------------------------------------------------------------------------------------------
-- pwmcell: cell class -> envelope
------------------------------------------------------------------------------------------------

cellWidthMs :: CellClass -> Index 10
cellWidthMs CellZero = 2
cellWidthMs CellOne  = 5
cellWidthMs CellMark = 8

pwmcell :: Signal dom CellClass -> Signal dom (Index 10) -> Signal dom Bit
pwmcell cls msIx = boolToBit <$> ((<) <$> msIx <*> (cellWidthMs <$> cls))

------------------------------------------------------------------------------------------------
-- The modulated output: 1 kHz sine, mark:space 10:3
------------------------------------------------------------------------------------------------
--
-- 10 samples per cycle from a pair of quarter-scaled ROMs; the envelope picks the amplitude.
-- Peak 95/29 out of Signed 8 leaves headroom into the audio ΣΔ/PWM path.

sinHi, sinLo :: Vec 10 (Signed 8)
sinHi = 0 :> 59 :> 95 :> 95 :> 59 :> 0 :> (-59) :> (-95) :> (-95) :> (-59) :> Nil
sinLo = 0 :> 18 :> 29 :> 29 :> 18 :> 0 :> (-18) :> (-29) :> (-29) :> (-18) :> Nil

------------------------------------------------------------------------------------------------
-- irigb: the top
------------------------------------------------------------------------------------------------

irigb ::
  forall k dom.
  (HiddenClockResetEnable dom, KnownNat k, 1 <= k) =>
  SNat k ->                                     -- ^ ticks per 0.1 ms (2500 real, 1 sim)
  Signal dom Bool ->                            -- ^ set_strobe
  Signal dom SetVal ->
  ( Signal dom Bit                              -- ^ dcOut: DC-level-shift IRIG-B00x
  , Signal dom (Signed 8)                       -- ^ amOut: modulated IRIG-B12x
  , Signal dom (Index 100) )                    -- ^ frame phase (for the status register)
irigb k strobe setv = (dcOut, amOut, cellIx)
  where
    (msT, carrIx)            = tick1k k
    (cellIx, msIx, frameRef) = framePos msT
    time    = rtc frameRef strobe setv
    cls     = framer time cellIx
    dcOut   = pwmcell cls msIx
    amOut   = mux (bitToBool <$> dcOut) (romAt sinHi) (romAt sinLo)
    romAt v = (v !!) <$> carrIx

------------------------------------------------------------------------------------------------
-- Synthesis top: real timing on the ULX3S 25 MHz crystal
------------------------------------------------------------------------------------------------
--
-- Set-interface stub. Register addresses moved to the 0x4040 block (GPS/DESIGN.md) after the
-- 0x4036 oHarp collision; status stays at 0x4034. Until O exists these are plain ports the
-- future register file will drive (the register file packs/unpacks its word formats — the
-- core takes BCD digits directly, so it needs no /60 and /3600 dividers):
--
--     set_ssmm  [15:12] ss tens  [11:8] ss ones  [7:4] mm tens  [3:0] mm ones
--     set_hhdl  [15:12] hh tens  [11:8] hh ones  [7:4] doy tens [3:0] doy ones
--     set_dh    [3:0]   doy hundreds; upper nibble reserved
--     set_strobe latches all three; applied at the next frame reference (oTodSet semantics)

createDomain vSystem{vName="Ulx25", vPeriod=40000}   -- 25 MHz, 40 ns

topEntity ::
  Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25 ->
  Signal Ulx25 Bit ->
  Signal Ulx25 (BitVector 16) ->
  Signal Ulx25 (BitVector 16) ->
  Signal Ulx25 (BitVector 8) ->
  (Signal Ulx25 Bit, Signal Ulx25 (Signed 8))
topEntity clk rst en strobe ssmm hhdl dh =
    exposeClockResetEnable board clk rst en
  where
    board :: HiddenClockResetEnable Ulx25 => (Signal Ulx25 Bit, Signal Ulx25 (Signed 8))
    board = let (d, a, _) = irigb (SNat @2500) (bitToBool <$> strobe) setv in (d, a)
    setv  = mkSet <$> ssmm <*> hhdl <*> dh
    mkSet :: BitVector 16 -> BitVector 16 -> BitVector 8 -> SetVal
    mkSet a b c = SetVal
      { setSs  = (unpack (slice d15 d12 a), unpack (slice d11 d8 a))
      , setMm  = (unpack (slice d7  d4  a), unpack (slice d3  d0 a))
      , setHh  = (unpack (slice d15 d12 b), unpack (slice d11 d8 b))
      , setDoy = ( unpack (slice d3 d0 c)
                 , unpack (slice d7 d4 b)
                 , unpack (slice d3 d0 b) )
      }
{-# ANN topEntity
  (Synthesize
    { t_name   = "irigb"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "set_strobe", PortName "set_ssmm"
                 , PortName "set_hhdl", PortName "set_dh" ]
    , t_output = PortProduct "" [PortName "dc_out", PortName "am_out"]
    }) #-}
{-# OPAQUE topEntity #-}
