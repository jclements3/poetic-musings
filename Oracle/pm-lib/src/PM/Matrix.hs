-- PM.Matrix — 8×8 key/button matrix scanner behind the 0x4024 register pair
-- (Oracle/eforth-pm.md section 1: oMatrixCtrl / iKeys).
--
--     Build:    cabal build
--     Test:     cabal test matrix-test --test-show-details=direct
--     Verilog:  cabal run clash -- -isrc PM.Matrix --verilog
--     Output:   verilog/PM.Matrix.topEntity/
--
-- Free-running scan + per-key debounce in gateware; Forth pops *events*,
-- never scans rows (eforth-pm rule).  One switch + 1N4148 per crosspoint
-- (LAYOUT quality BOM), so any key combination is valid — no ghosting
-- assumptions beyond diode-per-switch.
--
-- Scan and keycodes (the LAYOUT fold: 49 music keys + P0–P9 in one matrix):
--
--     keycode = 8*row + col, bits 5:0 of the event byte
--     0–48   music keys A0..G7 in panel order (A0=0, B0=1, C1=2, … G7=48)
--     49–58  buttons P0..P9  (P0 = row 6 col 1, … P9 = row 7 col 2)
--     59–63  unpopulated crosspoints — scanned, never pressed, never event
--
-- Electrical convention: row strobes are one-hot ACTIVE LOW (bit i = row i);
-- columns are ACTIVE LOW with pull-ups (pressed key on the strobed row pulls
-- its column low through its diode).  Columns are sampled on the LAST tick of
-- each row's dwell, so they have the whole dwell to settle.
--
-- Timing (hwMatrixCfg): 3125 ticks/row @ 25 MHz × 8 rows = exactly 1 ms per
-- full scan pass, so the debounce threshold counts scan passes = milliseconds.
-- Default 10 passes = the 10 ms debounce norm (fpga-development-plan quality
-- BOM, as in Coil/SantaGlide).  Debounce is an integrating counter per key:
-- N consecutive samples disagreeing with the debounced state flip it (and
-- emit one event); any agreeing sample resets the counter, so the scan is
-- tolerant of slow/bouncy release and a sub-threshold glitch emits nothing.
--
-- Pipeline: at the sample tick the 8 columns of row r are latched and the
-- strobe moves to row r+1; during the first 8 ticks of the new dwell the 8
-- latched keys are processed one per tick (so at most one FIFO push per
-- cycle, and events land in scan order: row-major = ascending keycode).
-- This needs mcSettle >= 9.
--
-- Register contract implemented (bit layouts provisional per eforth-pm —
-- only the grouping is contractual until forth-cpu-notes pins the map):
--
--     oMatrixCtrl (0x4024 write): bit 0 scan enable · bit 1 FIFO clear
--       (acts every cycle it is held) · bits 9:4 debounce time in ms,
--       0 = default 10 ms
--     iKeys (0x4024 read):  bit 15 `valid` (FIFO non-empty; 0 = empty flag)
--       · bit 7 press(1)/release(0) · bits 5:0 keycode · bits 14:8, 6 zero.
--       The head is presented continuously; the CPU's read strobe pops it.
--
-- Event FIFO: depth 16 (eforth-pm says only "small"; 16 events ≫ anything
-- ten fingers do between 1 ms polls — provisional like the bit layouts).
-- When full, the NEWEST event is dropped; order of the survivors is kept.

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.Matrix where

import Clash.Prelude
import PM.Ulx25 (Ulx25)

------------------------------------------------------------------------------------------------
-- Parameters and control
------------------------------------------------------------------------------------------------

-- | Static scan parameters — constants at synthesis, small at simulation.
data MatrixCfg = MatrixCfg
  { mcSettle    :: Unsigned 12   -- ^ ticks per row dwell; must be >= 9 (see pipeline note)
  , mcDefaultDb :: Unsigned 6    -- ^ default debounce threshold, in scan passes
  }

-- | Hardware timing @ 25 MHz: 3125 ticks/row so one scan pass = 1 ms and the
--   debounce field is directly in milliseconds; default 10 ms.
hwMatrixCfg :: MatrixCfg
hwMatrixCfg = MatrixCfg 3125 10

-- | The oMatrixCtrl fields (eforth-pm 0x4024 write: scan enable, debounce
--   time, FIFO clear).
data MatrixCtrl = MatrixCtrl
  { ctlScanEn    :: Bool         -- ^ bit 0 — scan enable
  , ctlFifoClear :: Bool         -- ^ bit 1 — empty the event FIFO
  , ctlDebounce  :: Unsigned 6   -- ^ bits 9:4 — debounce, scan passes (= ms on hw); 0 = default
  } deriving (Generic, NFDataX)

-- | Unpack an oMatrixCtrl register word (layout in the module header).
decodeMatrixCtrl :: BitVector 16 -> MatrixCtrl
decodeMatrixCtrl w = MatrixCtrl (testBit w 0) (testBit w 1) (unpack (slice d9 d4 w))

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------

-- | FIFO event byte: bit 7 press(1)/release(0), bit 6 zero, bits 5:0 keycode —
--   exactly the low byte of iKeys.
type Event = BitVector 8

data MState = MState
  { msEnabled  :: !Bool                 -- ^ registered copy of ctlScanEn (keeps outputs Moore)
  , msRow      :: !(Index 8)              -- ^ row currently strobed
  , msDwell    :: !(Unsigned 12)          -- ^ tick within the current row dwell
  , msSampled  :: !(Vec 8 Bool)           -- ^ columns latched at the previous sample tick (True = pressed)
  , msPrevRow  :: !(Index 8)              -- ^ which row msSampled belongs to
  , msProcIx   :: !(Index 8)              -- ^ which latched key is being processed
  , msProcBusy :: !Bool                 -- ^ processing ticks remain this row
  , msKeySt    :: !(Vec 64 Bool)          -- ^ debounced state per key (True = down)
  , msCnt      :: !(Vec 64 (Unsigned 6))  -- ^ integrating debounce counter per key
  , msFifo     :: !(Vec 16 Event)         -- ^ the event FIFO
  , msRd, msWr :: !(Index 16)
  , msCount    :: !(Index 17)             -- ^ FIFO fill 0..16
  } deriving (Generic, NFDataX)

initMState :: MState
initMState = MState False 0 0 (repeat False) 0 0 False
                    (repeat False) (repeat 0) (repeat 0) 0 0 0

------------------------------------------------------------------------------------------------
-- Transition function  (s -> i -> s)
------------------------------------------------------------------------------------------------

step :: MatrixCfg -> MState -> (MatrixCtrl, Bool, Vec 8 Bit) -> MState
step MatrixCfg{..} s (MatrixCtrl{..}, pop, colsIn) = s'
  where
    thr = if ctlDebounce == 0 then mcDefaultDb else ctlDebounce

    -- FIFO clear (oMatrixCtrl bit 1) empties before this cycle's pop/push
    (rd0, wr0, n0)
      | ctlFifoClear = (0, 0, 0)
      | otherwise    = (msRd s, msWr s, msCount s)

    -- CPU read strobe pops the head (only when an event is actually there)
    (rd1, n1)
      | pop && n0 /= 0 = (satSucc SatWrap rd0, n0 - 1)
      | otherwise      = (rd0, n0)

    -- process ONE previously-latched key this tick (at most one event/cycle)
    kIx   = unpack (pack (msPrevRow s) ++# pack (msProcIx s)) :: Index 64
    kCode = bitCoerce kIx :: Unsigned 6                       -- keycode = 8*row + col
    sampl = msSampled s !! msProcIx s
    curSt = msKeySt s !! kIx
    hits  = satSucc SatBound (msCnt s !! kIx)
    flips = msProcBusy s && sampl /= curSt && hits >= thr
    cnt'  | not (msProcBusy s)      = msCnt s
          | sampl == curSt || flips = replace kIx 0 (msCnt s)   -- agree/flip: integrator resets
          | otherwise               = replace kIx hits (msCnt s)
    keySt' | flips     = replace kIx sampl (msKeySt s)
           | otherwise = msKeySt s
    evWord = pack sampl ++# (0 :: BitVector 1) ++# pack kCode :: Event

    (fifo', wr1, n2)
      | flips && n1 /= maxBound = (replace wr0 evWord (msFifo s), satSucc SatWrap wr0, n1 + 1)
      | otherwise               = (msFifo s, wr0, n1)           -- full: newest dropped

    procBusy' = msProcBusy s && msProcIx s /= maxBound
    procIx'   = if msProcBusy s then satSucc SatWrap (msProcIx s) else msProcIx s

    -- scan sequencing: sample the columns on the LAST tick of the dwell,
    -- advance the strobe, and queue the latched row for processing
    capture = msEnabled s && msDwell s == mcSettle - 1

    (row', dwell', sampled', prevRow', procIx'', procBusy'')
      | not (msEnabled s) = (msRow s, 0, msSampled s, msPrevRow s, procIx', procBusy')
      | capture           = ( satSucc SatWrap (msRow s), 0
                            , map (== low) colsIn, msRow s, 0, True )
      | otherwise         = (msRow s, msDwell s + 1, msSampled s, msPrevRow s, procIx', procBusy')

    s' = MState { msEnabled = ctlScanEn
                , msRow = row', msDwell = dwell'
                , msSampled = sampled', msPrevRow = prevRow'
                , msProcIx = procIx'', msProcBusy = procBusy''
                , msKeySt = keySt', msCnt = cnt'
                , msFifo = fifo', msRd = rd1, msWr = wr1, msCount = n2 }

------------------------------------------------------------------------------------------------
-- Output function  (s -> o)  — STATE ONLY: strobes and iKeys never glitch
------------------------------------------------------------------------------------------------

mOut :: MState -> (Vec 8 Bit, BitVector 16)
mOut s = (rows, ikeys)
  where
    rows  = map (\i -> if msEnabled s && i == msRow s then low else high) indicesI
    valid = msCount s /= 0
    ikeys = pack valid ++# (0 :: BitVector 7) ++# (msFifo s !! msRd s)

-- | The scanner: control + read strobe + column returns in, row strobes +
--   the iKeys register word out.
matrix
  :: HiddenClockResetEnable dom
  => MatrixCfg
  -> Signal dom MatrixCtrl        -- ^ oMatrixCtrl fields
  -> Signal dom Bool              -- ^ iKeys read strobe: pops the FIFO head
  -> Signal dom (Vec 8 Bit)       -- ^ column returns, active low
  -> (Signal dom (Vec 8 Bit), Signal dom (BitVector 16))
     -- ^ (row strobes, one-hot active low; iKeys word)
matrix cfg ctrl pop cols =
  unbundle (moore (step cfg) mOut initMState (bundle (ctrl, pop, cols)))

------------------------------------------------------------------------------------------------
-- Top entity — real timing on the ULX3S 25 MHz crystal
------------------------------------------------------------------------------------------------

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 (BitVector 16)   -- ^ oMatrixCtrl register word
  -> Signal Ulx25 Bit              -- ^ iKeys read strobe (the CPU's io_re at 0x4024)
  -> Signal Ulx25 (BitVector 8)    -- ^ columns, active low (bit i = col i)
  -> ( Signal Ulx25 (BitVector 8)  -- ^ row strobes, one-hot active low (bit i = row i)
     , Signal Ulx25 (BitVector 16) -- ^ iKeys register word
     )
topEntity clk rst en ctl popB colsB = exposeClockResetEnable board clk rst en
  where
    board :: HiddenClockResetEnable Ulx25
          => (Signal Ulx25 (BitVector 8), Signal Ulx25 (BitVector 16))
    board = (pack . reverse <$> rows, ikeys)   -- reverse: bit 0 = row 0
      where
        (rows, ikeys) = matrix hwMatrixCfg
                               (decodeMatrixCtrl <$> ctl)
                               (bitToBool <$> popB)
                               (reverse . unpack <$> colsB)
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_matrix"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "matrix_ctrl", PortName "ikeys_re", PortName "col_n" ]
    , t_output = PortProduct "" [PortName "row_n", PortName "ikeys"]
    }) #-}
{-# OPAQUE topEntity #-}
