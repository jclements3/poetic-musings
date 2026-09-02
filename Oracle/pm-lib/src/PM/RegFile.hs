-- PM.RegFile — the eForth-PM I/O decode (Oracle/eforth-pm.md section 1).
-- This is the seam between the H2 core and the PM gateware library: the CPU
-- side is exactly the H2 bus (ioDaddr/ioWr/ioRe/ioDout -> ioDin, see
-- Oracle/clash-h2/src/H2.hs H2Out), the peripheral side binds the in-package
-- blocks directly (PM.Zones at 0x4020, PM.Matrix at 0x4024) and exposes
-- typed command/status ports for the blocks that live in their own packages
-- (audio 0x402C, synth 0x402E, keyer 0x4030, IRIG 0x4034/0x4040, harp
-- 0x4036) so clash-h2's sim stubs can be replaced register by register.
--
-- Semantics carried in hardware, not convention:
--   * 0x4024 read POPS the matrix event FIFO (H2 ioRe exists exactly for
--     such side-effecting reads).
--   * 0x402C oAudio resets to muted (bit 0 = 1): the no-power-on-pop rule.
--     Forth RELEASES mute; it never has to assert it first.
--   * 0x4032 oTxGate: only the arm key 0x0C1D arms; any other write disarms;
--     and the armed flag read back (and exported to the PA branch) is
--     additionally ANDed with "S3 mode == C" (zone 5) — software alone can
--     never key RF outside C mode (LAYOUT power-table interlock).
--   * 0x402E / 0x4030 writes surface as one-cycle Maybe pulses for the synth
--     and keyer command ports; their status words are inputs read back
--     combinationally.

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.RegFile where

import Clash.Prelude
import PM.Matrix (MatrixCfg, decodeMatrixCtrl, matrix)
import PM.Zones (ZonesOut (..), zones)
import PM.Ulx25 (Ulx25)
import qualified PM.Matrix
import qualified PM.Zones

type Word16 = BitVector 16

-- | The H2 I/O bus, CPU side (field-for-field H2Out's io* group).
data PmBus = PmBus
  { pbAddr :: !Word16   -- ^ ioDaddr
  , pbWr   :: !Bool     -- ^ ioWr — write strobe
  , pbRe   :: !Bool     -- ^ ioRe — read strobe (reads may have side effects)
  , pbDout :: !Word16   -- ^ ioDout — write data
  } deriving (Generic, NFDataX)

-- | Status words owned by out-of-package blocks, read back through the file.
data PmStatus = PmStatus
  { stAdc    :: !Word16   -- ^ iAdc     0x4022 (raw 12-bit, mux per oPanelCtrl)
  , stSynth  :: !Word16   -- ^ iSynth   0x402E (voice-busy mask, seq position)
  , stKeyer  :: !Word16   -- ^ iKeyer   0x4030 (decoder FIFO head, paddle state)
  , stPaOk   :: !Bool     -- ^ iTxGate  0x4032 bit 1 — PA fuse-branch OK
  , stIrig   :: !Word16   -- ^ iIrig    0x4034
  , stHarp   :: !Word16   -- ^ iHarp    0x4036 (pluck FIFO head)
  } deriving (Generic, NFDataX)

-- | Everything the file drives outward.
data PmRegs = PmRegs
  { prDin       :: !Word16        -- ^ ioDin back to the core (combinational mux)
  , prRows      :: !(Vec 8 Bit)     -- ^ matrix row strobes (one-hot, active low)
  , prPanelCtrl :: !Word16        -- ^ oPanelCtrl held register (ADC mux, backlight)
  , prAudio     :: !Word16        -- ^ oAudio held register; bit 0 = mute (resets 1)
  , prSynthCmd  :: !(Maybe Word16)  -- ^ one-cycle synth command pulse (0x402E write)
  , prKeyerCmd  :: !(Maybe Word16)  -- ^ one-cycle keyer command pulse (0x4030 write)
  , prTxArmed   :: !Bool          -- ^ interlocked PA arm: key written AND mode == C
  , prMode      :: !(Index 6)       -- ^ dwell-qualified S3 mode, for non-Forth consumers
  } deriving (Generic, NFDataX)

-- | One held 16-bit write register at an address.
heldReg
  :: HiddenClockResetEnable dom
  => Word16                       -- ^ reset value
  -> Word16                       -- ^ address
  -> Signal dom PmBus
  -> Signal dom Word16
heldReg iv a bus = r
 where
  r = regEn iv (isWr a <$> bus) (pbDout <$> bus)

isWr, isRe :: Word16 -> PmBus -> Bool
isWr a PmBus{..} = pbWr && pbAddr == a
isRe a PmBus{..} = pbRe && pbAddr == a

-- | A write surfaced as a one-cycle command pulse (synth, keyer).
cmdPulse
  :: HiddenClockResetEnable dom
  => Word16 -> Signal dom PmBus -> Signal dom (Maybe Word16)
cmdPulse a bus =
  register Nothing
    (mux (isWr a <$> bus) (Just . pbDout <$> bus) (pure Nothing))

-- | The register file. Zone/matrix parameters are arguments so the bench can
--   shrink the time constants; hardware passes 'PM.Zones.hwHyst',
--   'PM.Zones.hwDwellTicks', 'PM.Matrix.hwMatrixCfg'.
regFile
  :: HiddenClockResetEnable dom
  => Unsigned 12                    -- ^ zone hysteresis half-band
  -> Unsigned 32                    -- ^ S3 mode dwell, ticks
  -> MatrixCfg                      -- ^ matrix scan timing
  -> Signal dom PmBus               -- ^ CPU side
  -> Signal dom (Unsigned 12)       -- ^ S2 sample
  -> Signal dom (Unsigned 12)       -- ^ S3 sample
  -> Signal dom (Unsigned 12)       -- ^ S4 sample
  -> Signal dom (Vec 8 Bit)         -- ^ matrix column returns, active low
  -> Signal dom PmStatus            -- ^ out-of-package status words
  -> Signal dom PmRegs
regFile hyst dwellT mcfg bus s2 s3 s4 cols st = out
 where
  zo = zones hyst dwellT s2 s3 s4

  matCtrl = heldReg 0 0x4024 bus
  pop = isRe 0x4024 <$> bus
  (rows, ikeys) = matrix mcfg (decodeMatrixCtrl <$> matCtrl) pop cols

  panelCtrl = heldReg 0 0x4020 bus
  audio = heldReg 1 0x402C bus              -- resets muted (bit 0)
  synthCmd = cmdPulse 0x402E bus
  keyerCmd = cmdPulse 0x4030 bus

  -- TX interlock: the arm key latches, anything else clears, and the
  -- exported/readable flag is gated by the dwell-qualified mode.
  armKey = regEn False (pbWr' <$> bus) ((== 0x0C1D) . pbDout <$> bus)
   where pbWr' = isWr 0x4032
  armed = (&&) <$> armKey <*> ((== 5) . zoMode <$> zo)

  din = mkDin <$> bus <*> zo <*> ikeys <*> audio <*> armed <*> st
  mkDin PmBus{..} z ik au ar PmStatus{..} = case pbAddr of
    0x4020 -> zoIPanel z
    0x4022 -> stAdc
    0x4024 -> ik
    0x402C -> au
    0x402E -> stSynth
    0x4030 -> stKeyer
    0x4032 -> resize (pack stPaOk) `shiftL` 1 .|. resize (pack ar)
    0x4034 -> stIrig
    0x4036 -> stHarp
    _      -> 0

  out = PmRegs <$> din <*> rows <*> panelCtrl <*> audio
               <*> synthCmd <*> keyerCmd <*> armed <*> (zoMode <$> zo)

------------------------------------------------------------------------------------------------
-- Top entity — real timing on the ULX3S 25 MHz clock
------------------------------------------------------------------------------------------------

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 PmBus
  -> Signal Ulx25 (Unsigned 12)
  -> Signal Ulx25 (Unsigned 12)
  -> Signal Ulx25 (Unsigned 12)
  -> Signal Ulx25 (Vec 8 Bit)
  -> Signal Ulx25 PmStatus
  -> Signal Ulx25 PmRegs
topEntity clk rst en = withClockResetEnable clk rst en $
  regFile PM.Zones.hwHyst PM.Zones.hwDwellTicks PM.Matrix.hwMatrixCfg
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_regfile"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "bus", PortName "s2", PortName "s3", PortName "s4"
                 , PortName "cols", PortName "status" ]
    , t_output = PortName "regs"
    }) #-}
