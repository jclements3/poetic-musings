{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-|
The musical pitch map: a fixed-point port of the upstream fpga-theremin's
period-to-note pipeline, which there runs in C++ on the Zynq's ARM
(@fpga/theremin_sdk/theremin/src/synth_control_utils.cpp@,
@common/src/noteutil.cpp@). Three stages, as upstream:

1. __period -> linear__ (@SensorConvertor::periodToLinear@). The hand's
   effect on the oscillator period is compressed at arm's length; upstream
   undoes that with an exponential of gain @k@ (default 4.5):

   @
     u      = (far - period) / (far - near)          -- 0 hand away, 1 closest
     linear = ln(1 + u * (e^k - 1)) / k              -- 0..1, even in centimetres
   @

2. __linear -> note__ (@synthControl_setNoteRange@). A straight line from
   @minNote@ to @maxNote@, so equal hand travel is equal intervals. Notes are
   MIDI numbers in 8.8 fixed point (upstream's 16-bit note, less its +84
   offset), 1\/256 semitone = 0.39 cent.

   Stages 1 and 2 are one 1024-entry ROM indexed by the top bits of
   @far - period@, linearly interpolated with the 8 bits below, exactly as
   upstream's @pitchPeriodToNoteTable@ (which is also 1024 entries with
   interpolation).

3. __note -> tuning word__ (@noteToPhaseIncrementFast@). Octave from the
   integer note, then a 48-entry quarter-semitone table of
   @2^(i\/48)@ scaled to the NCO word for MIDI 0 at the audio clock,
   interpolated, then shifted by the octave. Upstream uses a
   quarter-semitone table too. No full-width multiplier anywhere — the
   iCE40 has no DSPs.

The tables are built from 'NoteMapParams' with ordinary 'Double' maths at
/elaboration time/ ('noteTableList', 'phaseTableList'). The 49-entry phase
table is baked in with Template Haskell ("Theremin.Audio.NoteTables"); the
1024-entry note table goes through @romFilePow2@ — a @$readmemb@ file
(@bringup\/notemap_lo.bin@, @notemap_hi.bin@, written by 'writeNoteTableFiles')
— because a 1025-element vector literal takes Clash's normaliser
tens of minutes, the same reason the H2 port loads its memory from
@h2.bin@. 'noteMap' (vector ROMs) is what the tests simulate;
'noteMapFile' is what 'topEntity' synthesises; both share 'noteMapWith'.

== Calibration

@nmFar@ and @nmNear@ are the two bench numbers: the stage-2 period reading
with the hand away and at closest approach. Everything else follows. The
stage-2 reading is @2^18@ times the oscillator period in clock ticks
(measured on the Cu: a 20-tick half-period reads @2^19 * 20@).
-}
module Theremin.Audio.NoteMap
  ( NoteMapParams (..)
  , defaultNoteMapParams
  , NoteTable
  , PhaseTable
  , OctaveTable
  , indexShift
  , noteTableList
  , phaseTableList
  , octaveTable
  , periodToIndex
  , periodToIndexWith
  , interpNote
  , noteToFreqWord
  , noteToFreqWordP
  , noteMapWith
  , noteMap
  , noteMapFile
  , writeNoteTableFiles
  , noteMapModel
  , noteMapModelWord
    -- * Volume (upstream's setVolumeRange)
  , AmpMapParams (..)
  , defaultAmpMapParams
  , AmpTable
  , ampIndexShift
  , ampModel
  , ampTableList
  , interpAmp
  , ampMapWith
  , ampMap
  , ampMapFile
  , writeAmpTableFiles
  , ampScale
  , ampScaleP
  ) where

import Clash.Prelude
import Clash.Explicit.BlockRam.File (memFile)
import qualified Prelude as P

-- | Elaboration-time constants of the musical pitch map.
data NoteMapParams = NoteMapParams
  { nmFar      :: Unsigned 32
    -- ^ Stage-2 pitch reading with the hand away (the /longest/ period).
  , nmNear     :: Unsigned 32
    -- ^ Stage-2 pitch reading at closest approach (the /shortest/ period).
  , nmLinK     :: Double
    -- ^ Upstream's @linearizationK@; 4.5 in their defaults.
  , nmMinNote  :: Int
    -- ^ MIDI note with the hand away. A0 = 21.
  , nmMaxNote  :: Int
    -- ^ MIDI note at closest approach. G7 = 103.
  , nmSilence  :: Unsigned 32
    -- ^ Readings at or beyond this are silent (tuning word 0). Upstream has
    -- no such thing — the volume hand mutes — so the default is never.
  , nmClockHz  :: Double
    -- ^ Audio (NCO) clock, for the note-to-word table.
  }
  deriving stock (Generic, Show)

-- | The synthetic-oscillator bench defaults (the GUI build on the Cu):
-- a 600 kHz-class tank whose period moves from 84 ticks (hand away) to 80
-- ticks (closest) — a 5 % swing, like a real antenna. Range A0..G7 at 50 MHz.
-- Real oscillators get their own @nmFar@\/@nmNear@ from the bench.
defaultNoteMapParams :: NoteMapParams
defaultNoteMapParams = NoteMapParams
  { nmFar     = 84 * 262_144       -- 84 ticks * 2^18
  , nmNear    = 80 * 262_144       -- 80 ticks * 2^18
  , nmLinK    = 4.5
  , nmMinNote = 21                 -- A0, 27.5 Hz
  , nmMaxNote = 103                -- G7, 3136 Hz
  , nmSilence = maxBound
  , nmClockHz = 50.0e6
  }

type NoteTable   = Vec 1025 (Unsigned 16)   -- ^ note (8.8 MIDI) per index, +1 for interpolation
type PhaseTable  = Vec 49   (Unsigned 28)   -- ^ NCO word for MIDI 0 + i/4 semitones, x2^16
type OctaveTable = Vec 128  (Unsigned 4, Unsigned 4)  -- ^ MIDI -> (octave, semitone)

-- | Right shift turning @far - period@ into a 10-bit table index: the table
-- spans the smallest power of two that covers the calibrated range.
indexShift :: NoteMapParams -> Int
indexShift NoteMapParams{..} = indexShiftFor nmFar nmNear

indexShiftFor :: Unsigned 32 -> Unsigned 32 -> Int
indexShiftFor far near = P.max 0 (ceilLog2 - 10)
 where
  -- ceil(log2 range) via a leading-zero count: a Clash primitive that folds
  -- at elaboration (a lazy 'iterate' here blew the specialisation limit).
  range = far - near
  ceilLog2 = 32 - countLeadingZeros (range - 1)

-- | Upstream's period-to-note curve on 'Double's: reading -> MIDI note.
noteModel :: NoteMapParams -> Double -> Double
noteModel NoteMapParams{..} p = fromIntegral nmMinNote + noteSpan * linear
 where
  far   = fromIntegral nmFar
  near  = fromIntegral nmNear
  u     = P.max 0 (P.min 1 ((far - p) / (far - near)))
  linear = log (1 + u * (exp nmLinK - 1)) / nmLinK
  noteSpan = fromIntegral (nmMaxNote - nmMinNote)

-- | The whole map on 'Double's: reading -> Hz. The reference the fixed-point
-- pipeline is tested against.
noteMapModel :: NoteMapParams -> Double -> Double
noteMapModel ps p = 440 * 2 ** ((noteModel ps p - 69) / 12)

-- | ... and as an ideal NCO word.
noteMapModelWord :: NoteMapParams -> Double -> Double
noteMapModelWord ps p = noteMapModel ps p * 4_294_967_296 / nmClockHz ps

-- | Stage 1+2 table, 1025 entries: entry @i@ is the note at
-- @far - i * 2^shift@. Entry 1024 is the interpolation neighbour of index
-- 1023; the model clamps, so it is the top note exactly and the saturated
-- address (1023, 255) lands within 1\/256 of an entry of it.
noteTableList :: NoteMapParams -> [Unsigned 16]
noteTableList ps = [ entry i | i <- [0 .. 1024 :: Int] ]
 where
  s = indexShift ps
  entry i = fromIntegral (P.round (256 * noteModel ps p) :: Integer)
   where
    d = i * 2 P.^ s
    p = fromIntegral (toInteger (nmFar ps) - toInteger d)

-- | Stage 3 table: the NCO word for MIDI note @i/4@ (C-1 = 8.1758 Hz upward,
-- one octave in 48 quarter-semitone steps, 49 entries), times @2^16@ so the
-- lowest octaves keep their precision before the octave shift.
phaseTableList :: NoteMapParams -> [Unsigned 28]
phaseTableList ps = [ entry i | i <- [0 .. 48 :: Int] ]
 where
  f0 = 440 * 2 ** ((0 - 69) / 12) :: Double              -- MIDI 0
  entry i = fromIntegral (P.round (f0 * 2 ** (fromIntegral i / 48)
                                     * 4_294_967_296 / nmClockHz ps * 65_536) :: Integer)

-- | MIDI note -> (octave 0..10, semitone 0..11). Small enough for LUTs.
octaveTable :: OctaveTable
octaveTable = map (\m -> (fromIntegral (m `P.div` 12), fromIntegral (m `P.mod` 12)))
                  (iterateI (+ 1) (0 :: Int))

-- | Stage 1 address arithmetic: reading -> (table index, interpolation
-- fraction). Saturates at both ends: hand past @near@ pins the top entry,
-- period beyond @far@ pins entry 0.
periodToIndex :: NoteMapParams -> BitVector 32 -> (Unsigned 10, Unsigned 8)
periodToIndex ps = periodToIndexWith (nmFar ps) (indexShift ps)

periodToIndexWith :: Unsigned 32 -> Int -> BitVector 32 -> (Unsigned 10, Unsigned 8)
periodToIndexWith far s pv = (truncateB (d18 `shiftR` 8), truncateB d18)
 where
  p = unpack pv :: Unsigned 32
  d = if p >= far then 0 else far - p
  d18raw = if s >= 8 then d `shiftR` (s - 8) else d `shiftL` (8 - s)
  d18 = if d18raw >= 0x3FFFF then 0x3FFFF else d18raw

-- | Stage 2: linear interpolation between neighbouring table entries.
-- The table is monotone non-decreasing, so the difference is unsigned; it
-- is bounded well inside 11 bits (checked in the test suite).
interpNote :: Unsigned 16 -> Unsigned 16 -> Unsigned 8 -> Unsigned 16
interpNote n0 n1 frac = n0 + resize (prod `shiftR` 8)
 where
  diff = truncateB (n1 - n0) :: Unsigned 11
  prod = diff `mul` frac                     -- 19 bits

-- | Stage 3a: 8.8 MIDI note -> (octave, table entry, next entry, fraction).
noteLookup :: PhaseTable -> Unsigned 16 -> (Unsigned 4, Unsigned 28, Unsigned 28, Unsigned 6)
noteLookup tbl note = (oct, asyncRom tbl qi, asyncRom tbl (qi + 1), qf)
 where
  midi = truncateB (note `shiftR` 8) :: Unsigned 7
  nfrac = truncateB note :: Unsigned 8
  (oct, semi) = asyncRomPow2 octaveTable midi
  r = (resize semi `shiftL` 8) .|. resize nfrac :: Unsigned 12   -- 0..3071
  qi = truncateB (r `shiftR` 6) :: Unsigned 6                    -- 0..47
  qf = truncateB r :: Unsigned 6

-- | Stage 3b: the interpolation product, @(w1 - w0) * qf@ (21 x 6 bits).
noteInterpProd :: Unsigned 28 -> Unsigned 28 -> Unsigned 6 -> Unsigned 27
noteInterpProd w0 w1 qf = (truncateB (w1 - w0) :: Unsigned 21) `mul` qf

-- | Stage 3c: add the interpolation and shift by the octave.
noteShift :: Unsigned 4 -> Unsigned 28 -> Unsigned 27 -> Unsigned 32
noteShift oct w0 prod = resize w `shiftR` (16 - fromIntegral oct)
 where
  w = w0 + resize (prod `shiftR` 6) :: Unsigned 28

-- | Stage 3, combinational: 8.8 MIDI note -> 32-bit NCO tuning word.
-- The reference for the tests; 'noteToFreqWordP' is the same three
-- functions with a register between each, which is what synthesises.
noteToFreqWord :: PhaseTable -> Unsigned 16 -> Unsigned 32
noteToFreqWord tbl note = noteShift oct w0 (noteInterpProd w0 w1 qf)
 where
  (oct, w0, w1, qf) = noteLookup tbl note

-- | Stage 3, pipelined: three clocks of latency. The single-cycle version
-- closed at ~32 MHz on the iCE40; the ROM lookups, the multiplier and the
-- barrel shift each get their own cycle here.
noteToFreqWordP ::
  HiddenClockResetEnable dom =>
  PhaseTable -> Signal dom (Unsigned 16) -> Signal dom (Unsigned 32)
noteToFreqWordP tbl note = word
 where
  look  = register (0, 0, 0, 0) (noteLookup tbl <$> note)
  oct1  = (\(o, _, _, _) -> o) <$> look
  w01   = (\(_, w, _, _) -> w) <$> look
  prod  = register 0 ((\(_, w0, w1, qf) -> noteInterpProd w0 w1 qf) <$> look)
  oct2  = register 0 oct1
  w02   = register 0 w01
  word  = register 0 (noteShift <$> oct2 <*> w02 <*> prod)

-- | The registered pipeline: stage-2 pitch reading in, NCO tuning word out,
-- six clocks later. The two ROM read functions (registered reads of the
-- table entries @i@ and @i+1@) are passed in, so the same pipeline runs on
-- vector ROMs in simulation and on @$readmemb@ files in synthesis.
noteMapWith ::
  HiddenClockResetEnable dom =>
  NoteMapParams ->
  (Signal dom (Unsigned 10) -> Signal dom (Unsigned 16)) ->  -- ^ entry i
  (Signal dom (Unsigned 10) -> Signal dom (Unsigned 16)) ->  -- ^ entry i+1
  PhaseTable ->
  Signal dom (BitVector 32) ->
  Signal dom (Unsigned 32)
noteMapWith ps romLo romHi ptbl reading = word
 where
  idxFrac = periodToIndex ps <$> reading
  silent  = register False ((\pv -> (unpack pv :: Unsigned 32) >= nmSilence ps) <$> reading)
  frac1   = register 0 (snd <$> idxFrac)
  n0      = romLo (fst <$> idxFrac)
  n1      = romHi (fst <$> idxFrac)
  note    = register 0 (interpNote <$> n0 <*> n1 <*> frac1)
  -- silence flag delayed to match: idx(1) + rom(1) + note(1) + stage3(3)
  silent6 = register False (register False (register False (register False (register False silent))))
  word    = (\s w -> if s then 0 else w) <$> silent6 <*> noteToFreqWordP ptbl note

-- | Vector-ROM instance, for simulation and the tests.
noteMap ::
  HiddenClockResetEnable dom =>
  NoteMapParams ->
  NoteTable ->
  PhaseTable ->
  Signal dom (BitVector 32) ->
  Signal dom (Unsigned 32)
noteMap ps ntbl = noteMapWith ps (romPow2 (init ntbl)) (romPow2 (tail ntbl))

-- | @$readmemb@ instance, for synthesis: the two files hold entries
-- 0..1023 and 1..1024 of 'noteTableList' (see 'writeNoteTableFiles').
noteMapFile ::
  HiddenClockResetEnable dom =>
  NoteMapParams ->
  FilePath ->    -- ^ entries 0..1023
  FilePath ->    -- ^ entries 1..1024
  PhaseTable ->
  Signal dom (BitVector 32) ->
  Signal dom (Unsigned 32)
noteMapFile ps lo hi =
  noteMapWith ps (fmap unpack . romFilePow2 lo) (fmap unpack . romFilePow2 hi)

-- | Write the two @$readmemb@ files for 'noteMapFile' (one 16-bit binary
-- word per line, Clash's 'memFile' format).
writeNoteTableFiles :: NoteMapParams -> FilePath -> FilePath -> P.IO ()
writeNoteTableFiles ps lo hi = do
  let t = noteTableList ps
  P.writeFile lo (memFile Nothing (P.take 1024 t))
  P.writeFile hi (memFile Nothing (P.drop 1 t))

-- ---------------------------------------------------------------------------
-- Volume: the port of upstream's @synthControl_setVolumeRange@.
--
-- Same shape as the pitch map — the same 'periodToLinear' curve on the
-- volume oscillator — but the table holds an amplitude, not a note:
--
-- @
--   amp = (1 - linear)^2        -- hand away from the loop = 1, on it = 0
-- @
--
-- as a 12-bit unsigned fraction, applied to the sample by 'ampScale'
-- (upstream multiplies a 16-bit amp; 12 bits is 72 dB of range, and the
-- iCE40 has no DSPs, so the multiplier is split into two 16 x 6 halves in
-- 'ampScaleP' to close at 50 MHz).

-- | Elaboration-time constants of the volume map.
data AmpMapParams = AmpMapParams
  { amFar  :: Unsigned 32   -- ^ stage-2 volume reading, hand away (loud)
  , amNear :: Unsigned 32   -- ^ stage-2 volume reading, hand on the loop (mute)
  , amLinK :: Double        -- ^ upstream's @linearizationK@ for the volume axis
  }
  deriving stock (Generic, Show)

-- | Synthetic-bench defaults: a second tank at 92 -> 88 ticks. NB the
-- volume channel's stage-2 reading is @2^20@ times the period in ticks,
-- four times the pitch channel's @2^18@ ('VolumeEdgeBits' is 21 against
-- 'PitchEdgeBits' 23) — confirmed on the Cu by the old shift-based map's
-- attenuation steps.
defaultAmpMapParams :: AmpMapParams
defaultAmpMapParams = AmpMapParams
  { amFar  = 92 * 1_048_576
  , amNear = 88 * 1_048_576
  , amLinK = 4.5
  }

type AmpTable = Vec 1025 (Unsigned 12)

ampIndexShift :: AmpMapParams -> Int
ampIndexShift AmpMapParams{..} = indexShiftFor amFar amNear

-- | Upstream's volume curve on 'Double's: reading -> amplitude 0..1.
ampModel :: AmpMapParams -> Double -> Double
ampModel AmpMapParams{..} p = (1 - linear) * (1 - linear)
 where
  far   = fromIntegral amFar
  near  = fromIntegral amNear
  u     = P.max 0 (P.min 1 ((far - p) / (far - near)))
  linear = log (1 + u * (exp amLinK - 1)) / amLinK

-- | 1025 entries, as 'noteTableList'.
ampTableList :: AmpMapParams -> [Unsigned 12]
ampTableList ps = [ entry i | i <- [0 .. 1024 :: Int] ]
 where
  s = ampIndexShift ps
  entry i = fromIntegral (P.round (4095 * ampModel ps p) :: Integer)
   where
    d = i * 2 P.^ s
    p = fromIntegral (toInteger (amFar ps) - toInteger d)

-- | The table is monotone non-increasing; the step between neighbours is
-- bounded well inside 9 bits (checked in the tests).
interpAmp :: Unsigned 12 -> Unsigned 12 -> Unsigned 8 -> Unsigned 12
interpAmp a0 a1 frac = a0 - resize (prod `shiftR` 8)
 where
  diff = truncateB (a0 - a1) :: Unsigned 9
  prod = diff `mul` frac                     -- 17 bits

-- | Reading in, 12-bit amplitude out, three clocks later.
ampMapWith ::
  HiddenClockResetEnable dom =>
  AmpMapParams ->
  (Signal dom (Unsigned 10) -> Signal dom (Unsigned 12)) ->
  (Signal dom (Unsigned 10) -> Signal dom (Unsigned 12)) ->
  Signal dom (BitVector 32) ->
  Signal dom (Unsigned 12)
ampMapWith ps romLo romHi reading = amp
 where
  idxFrac = periodToIndexWith (amFar ps) (ampIndexShift ps) <$> reading
  frac1   = register 0 (snd <$> idxFrac)
  a0      = romLo (fst <$> idxFrac)
  a1      = romHi (fst <$> idxFrac)
  amp     = register 0 (interpAmp <$> a0 <*> a1 <*> frac1)

ampMap ::
  HiddenClockResetEnable dom =>
  AmpMapParams -> AmpTable -> Signal dom (BitVector 32) -> Signal dom (Unsigned 12)
ampMap ps tbl = ampMapWith ps (romPow2 (init tbl)) (romPow2 (tail tbl))

ampMapFile ::
  HiddenClockResetEnable dom =>
  AmpMapParams -> FilePath -> FilePath -> Signal dom (BitVector 32) -> Signal dom (Unsigned 12)
ampMapFile ps lo hi =
  ampMapWith ps (fmap unpack . romFilePow2 lo) (fmap unpack . romFilePow2 hi)

writeAmpTableFiles :: AmpMapParams -> FilePath -> FilePath -> P.IO ()
writeAmpTableFiles ps lo hi = do
  let t = ampTableList ps
  P.writeFile lo (memFile Nothing (P.take 1024 t))
  P.writeFile hi (memFile Nothing (P.drop 1 t))

-- | @sample * amp / 4096@, combinational reference.
ampScale :: Signed 16 -> Unsigned 12 -> Signed 16
ampScale s amp = truncateB (r `shiftR` 12)
 where
  r = (resize s `mul` (unpack (zeroExtend (pack amp)) :: Signed 13)) :: Signed 29

-- | The same, in two clocks: the 12-bit amplitude is split into two 6-bit
-- halves, each multiplied in the first cycle, recombined in the second.
ampScaleP ::
  HiddenClockResetEnable dom =>
  Signal dom (Signed 16) -> Signal dom (Unsigned 12) -> Signal dom (Signed 16)
ampScaleP s amp = register 0 (combine <$> pHi <*> pLo)
 where
  hi = (\a -> unpack (zeroExtend (pack (truncateB (a `shiftR` 6) :: Unsigned 6))) :: Signed 7) <$> amp
  lo = (\a -> unpack (zeroExtend (pack (truncateB a :: Unsigned 6))) :: Signed 7) <$> amp
  pHi = register 0 (mul <$> s <*> hi)            -- Signed 23
  pLo = register 0 (mul <$> s <*> lo)
  combine h l = truncateB (r `shiftR` 12) :: Signed 16
   where
    r = (resize h `shiftL` 6) + resize l :: Signed 29
