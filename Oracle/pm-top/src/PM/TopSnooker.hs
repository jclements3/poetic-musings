{-# OPTIONS_GHC -Wno-orphans #-}   -- createDomain (TmdsBit) makes an orphan KnownDomain
-- PM.TopSnooker — the "Snooker mode bitstream" of fpga-resource-swag.md as
-- one Clash design: H2 SoC + register file, video (console + overlay + TMDS),
-- network (records -> datagrams -> RMII beacon, RMII MAC rx), imaging
-- (DVP -> blob labeller -> centroid records), Motion radar chain
-- (DDC = NCO/CIC/FIR -> FFT512 -> CA-CFAR), IRIG-B generator, PPS
-- discipline + strobe latch, CDC blocks and the UART.
--
-- Purpose: a fit / area / Fmax measurement on the ECP5-85F. Every block is
-- instantiated exactly once and every output reaches a pin (or an xor-reduced
-- LED) so synthesis cannot drop it. The wiring is plausible, not verified:
-- see measurements/2026-09-15-snooker-fit.md for the stub list.
--
-- Clock domains (four): Snk25 (25 MHz crystal, system), PixelDom (~66.7 MHz
-- from pm-video), TmdsBit (5x pixel: the DDR-halved serialiser rate) and
-- Rmii50 (50 MHz RMII REF_CLK). PLL and reset synchronisers are the Verilog
-- wrapper's job; the entity takes one clock+reset pair per domain.
module PM.TopSnooker (topEntity, snooker, Snk25, TmdsBit) where

import Clash.Prelude
import Data.Maybe (isJust)

import H2 (h2, defaultConfig, H2In(..), H2Out(..))
import PM.RegFile (PmBus(..), PmStatus(..), PmRegs(..), regFile, heldReg, cmdPulse, isWr, isRe)
import PM.Zones (hwHyst, hwDwellTicks)
import PM.Matrix (hwMatrixCfg)
import PM.Cdc (bitSync, pulseSync, cdcFifo)
import PM.HarpLink (uartTx, uartRx)
import PM.Video.Top (PixelDom)
import PM.Video.Timing (pm1920x480, timingGen)
import PM.Video.TextConsole (CharWrite(..), PixelOut(..), textConsole)
import PM.Video.Overlay (OverlayOp(..), OverlayOut(..), overlayStrip)
import PM.Video.Tmds (tmdsEncoder, tmdsShift)
import PM.Net (Rmii50, Byte, beaconTx)
import PM.NetRx (macRx, RxOut(..))
import PM.Records (recordPath4, beaconGoAdapter, DgByte(..), PpsStatus(..), TimeMark(..), StrobeStamp(..), Centroid(..))
import PM.Dvp (DvpIn(..), Pix(..), dvpCapture)
import PM.Blob (BlobCfg(..), BlobOut(..), BlobRec(..), blobLabel)
import PM.Ddc (ddc)
import Theremin.Fft (fft512, Cplx)
import Maiden.Cfar (cfar)
import Irig (irigb, SetVal(..))
import qualified PM.StrobeLatch as SL
import qualified PM.PpsDiscipline as PD

createDomain vSystem{vName="Snk25", vPeriod=40000}    -- 25 MHz crystal (own name: Irig and PM.Ulx25 both define "Ulx25")
createDomain vSystem{vName="TmdsBit", vPeriod=3000}   -- 333 MHz (5x pixel, DDR-halved)

type W = BitVector 16

-- ---------------------------------------------------------------------------
-- System domain: H2 + register decode + everything at 25 MHz.

data SysIn = SysIn
  { siSwitches :: BitVector 8
  , siUartRx   :: Bit
  , siDvpPclk  :: Bit
  , siDvpHref  :: Bit
  , siDvpVsync :: Bit
  , siDvpData  :: BitVector 8
  , siAdc      :: BitVector 12
  , siPps      :: Bit
  , siGates    :: BitVector 2
  , siSdMiso   :: Bit
  , siMatCols  :: BitVector 8
  , siCharFull :: Bool
  , siOvFull   :: Bool
  , siNetFull  :: Bool
  , siRxGood   :: Unsigned 16
  , siRxBad    :: Unsigned 16
  , siOvBusy   :: Bool
  } deriving (Generic, NFDataX)

data SysOut = SysOut
  { soLeds     :: BitVector 8
  , soUartTx   :: Bit
  , soCharPush :: Maybe CharWrite
  , soCurPush  :: Maybe (Unsigned 5, Unsigned 8)
  , soOvPush   :: Maybe OverlayOp
  , soDgPush   :: Maybe DgByte
  , soDgSeq    :: Unsigned 16
  , soOurMac   :: BitVector 48
  , soIrigDc   :: Bit
  , soIrigAm   :: BitVector 8
  , soSd       :: BitVector 3     -- (cs, sclk, mosi)
  , soMatRows  :: BitVector 8
  , soSleigh   :: BitVector 8
  } deriving (Generic, NFDataX)

sysBlock :: HiddenClockResetEnable Snk25 => Signal Snk25 SysIn -> Signal Snk25 SysOut
sysBlock si = SysOut <$> leds <*> uartLine <*> charPush <*> curPush <*> ovPush
                     <*> dgOut <*> dgSeq <*> ourMac <*> irigDc <*> (pack <$> irigAm)
                     <*> sdPins <*> (pack . prRows <$> regs) <*> sleigh
 where
  sync2 :: NFDataX a => a -> Signal Snk25 a -> Signal Snk25 a
  sync2 iv = register iv . register iv

  ---- H2 core + program RAM ------------------------------------------------
  core = h2 @Snk25 @6 @3 defaultConfig inp
  inp  = H2In <$> pure False <*> ioDin <*> irq <*> pure 0 <*> insnS <*> dinS
  pcS    = unpack . pcOut <$> core
  daddrS = unpack . daddr <$> core
  wr     = mux (dwe <$> core) (Just <$> bundle (daddrS, dout <$> core)) (pure Nothing)
  insnS  = blockRamFilePow2 "h2.bin" pcS wr
  dinS   = blockRamFilePow2 "h2.bin" daddrS wr
  irq    = PD.ppsStb <$> ppsO

  bus = (\o -> PmBus (ioDaddr o) (ioWr o) (ioRe o) (ioDout o)) <$> core

  ---- pm-lib register file (0x4020 block) -----------------------------------
  adcS = unpack <$> (siAdc <$> si) :: Signal Snk25 (Unsigned 12)
  s2 = adcS
  s3 = register 0 s2
  s4 = register 0 s3
  status = PmStatus <$> (zeroExtend . pack <$> adcS)
                    <*> (resize . pack <$> detCount)
                    <*> (resize . pack <$> lastCell)
                    <*> (PD.locked <$> ppsO)
                    <*> irigStat
                    <*> (resize . pack . SL.rdSeq <$> so)
  regs = regFile hwHyst hwDwellTicks hwMatrixCfg bus s2 s3 s4
                 (unpack . siMatCols <$> si) status

  ---- UART (0x4000, upstream H2 contract subset) ---------------------------
  uartDiv = pure 217 :: Signal Snk25 (Unsigned 8)   -- 25 MHz / 115200
  rxLine = sync2 1 (siUartRx <$> si)
  rxM    = uartRx uartDiv rxLine
  rxHold = regMaybe 0 rxM
  rxPop  = (\b -> isWr 0x4000 b && testBit (pbDout b) 10) <$> bus
  rxAvail = register False ((\n a p -> n || (a && not p)) <$> (isJust <$> rxM) <*> rxAvail <*> rxPop)
  txM    = (\b -> if isWr 0x4000 b && testBit (pbDout b) 13 then Just (resize (pbDout b)) else Nothing) <$> bus
  (uartLine, txReady) = unbundle (uartTx uartDiv txM)
  uartStat = (\a rdy h -> (if a then 0 else bit 8) .|. (if rdy then bit 11 else 0) .|. zeroExtend h)
               <$> rxAvail <*> txReady <*> rxHold

  ---- LEDs (0x4004) ---------------------------------------------------------
  ledReg = heldReg 0 0x4004 bus

  ---- console / overlay ports (0x4010..0x4018) ------------------------------
  rowCol   = heldReg 0 0x4010 bus
  charPush = (\rc m -> (\w -> CharWrite (unpack (slice d12 d8 rc)) (unpack (slice d7 d0 rc)) (resize w)) <$> m)
               <$> rowCol <*> cmdPulse 0x4012 bus
  curPush  = fmap (\w -> (unpack (slice d12 d8 w), unpack (slice d7 d0 w))) <$> cmdPulse 0x4014 bus
  ovX      = heldReg 0 0x4018 bus
  ovPush   = (\x m -> decodeOv (unpack (slice d8 d0 x)) <$> m) <$> ovX <*> cmdPulse 0x4016 bus
  decodeOv :: Unsigned 9 -> W -> OverlayOp
  decodeOv x w = case slice d15 d14 w of
    0 -> OvPlot x (unpack (slice d6 d0 w)) (lsb (slice d7 d7 w))
    1 -> OvColumn x (unpack (slice d6 d0 w))
    _ -> OvClear

  ---- SD/SPI bit-bang stub (0x4028) ----------------------------------------
  sdCtl  = heldReg 0 0x4028 bus
  sdPins = resize <$> sdCtl
  sdMiso = sync2 1 (siSdMiso <$> si)

  ---- IRIG-B (0x4044..0x404A) -----------------------------------------------
  ssmm = heldReg 0 0x4046 bus
  hhdl = heldReg 0 0x4048 bus
  dh   = heldReg 0 0x404A bus
  setStrobe = isWr 0x4044 <$> bus
  setv = mkSet <$> ssmm <*> hhdl <*> dh
  mkSet :: W -> W -> W -> SetVal
  mkSet a b c = SetVal
    { setSs  = (unpack (slice d15 d12 a), unpack (slice d11 d8 a))
    , setMm  = (unpack (slice d7  d4  a), unpack (slice d3  d0 a))
    , setHh  = (unpack (slice d15 d12 b), unpack (slice d11 d8 b))
    , setDoy = (unpack (slice d3 d0 c), unpack (slice d7 d4 b), unpack (slice d3 d0 b)) }
  (irigDc, irigAm, cellIx) = irigb (SNat @2500) setStrobe setv
  cellPrev   = register 0 cellIx
  frameStart = (\c p -> c == 0 && p /= 0) <$> cellIx <*> cellPrev
  irigStat   = (\c l -> zeroExtend (pack c) .|. (if l then bit 15 else 0)) <$> cellIx <*> (PD.locked <$> ppsO)

  ---- PPS discipline + strobe latch (0x4070..0x4076) -----------------------
  ppsO = PD.ppsDiscipline 25_000_000 250 (bitToBool <$> (siPps <$> si))
  rtcS = PD.rtc <$> ppsO
  gateAny = (/= 0) <$> (siGates <$> si)
  rdEn = isRe 0x4070 <$> bus
  so   = SL.strobeLatch gateAny rtcS rdEn

  ---- imaging: DVP -> blob -> centroid records (0x4050..0x4054) ------------
  pclk  = sync2 0 (siDvpPclk <$> si)
  pclkRise = (\a b -> a == 1 && b == 0) <$> pclk <*> register 0 pclk
  dvpIn = DvpIn <$> (bitToBool <$> sync2 0 (siDvpHref <$> si))
                <*> (bitToBool <$> sync2 0 (siDvpVsync <$> si))
                <*> (unpack <$> sync2 0 (siDvpData <$> si))
  (pixRaw, frameSeq) = andEnable pclkRise (dvpCapture dvpIn)
  pixM = mux pclkRise pixRaw (pure Nothing)
  thrHyst = heldReg 0x0880 0x4050 bus
  minA    = heldReg 4     0x4052 bus
  maxA    = heldReg 40000 0x4054 bus
  blobCfg = (\th mn mx -> BlobCfg (unpack (slice d7 d0 th)) (unpack (slice d15 d8 th))
                                   (resize (unpack mn)) (resize (unpack mx)))
              <$> thrHyst <*> minA <*> maxA
  blobO = blobLabel blobCfg pixM
  fc = (\o r sq -> (\b -> Centroid r sq (pack (bLabel b)) (bCx b) (bCy b) (bCount b)
                                      (zeroExtend (pack (boOverflow o, boDropped o)))) <$> boRec o)
         <$> blobO <*> rtcS <*> frameSeq

  ---- Motion radar chain: DDC -> FFT512 -> CFAR (0x4060..0x4066) -----------
  fwLo = heldReg 0x1000 0x4060 bus
  fwHi = heldReg 0x0000 0x4062 bus
  freqWord = (\h l -> unpack (h ++# l)) <$> fwHi <*> fwLo
  (ddcI, ddcQ, ddcV) = unbundle (ddc (SNat @512) freqWord (unpack <$> (siAdc <$> si)))
  fftOut = andEnable ddcV (fft512 (bundle (ddcI, ddcQ)))
  mag :: Cplx -> Unsigned 18
  mag (re, im) = resize (bitCoerce (abs re) :: Unsigned 16) + resize (bitCoerce (abs im) :: Unsigned 16)
  (det, cell) = unbundle (cfar 80 (mag <$> fftOut))
  detCount = regEn (0 :: Unsigned 16) det (detCount + 1)
  lastCell = regEn (0 :: Unsigned 18) det cell

  ---- record path -> datagrams (net) ----------------------------------------
  tick10ms = tickCnt .==. 0
  tickCnt  = register (0 :: Index 250_000) (satSucc SatWrap <$> tickCnt)
  fp = (\o -> if PD.ppsStb o then Just (PpsStatus (PD.offset o) (zeroExtend (pack (PD.locked o)))) else Nothing) <$> ppsO
  ft = (\f o -> if f then Just (TimeMark (PD.ppsRtc o) (resize (PD.rtc o)) (resize (PD.rtc o `shiftR` 17))) else Nothing)
         <$> frameStart <*> ppsO
  fs = (\r s -> if r && SL.rdValid s then Just (StrobeStamp (SL.rdRtc s) (SL.rdSeq s) (SL.overflow s)) else Nothing)
         <$> rdEn <*> so
  (dgOut, dgSeq, _dgLen, drops) = recordPath4 fp ft fs fc tick10ms
  macHi = heldReg 0x0250 0x4090 bus
  macMd = heldReg 0x4D00 0x4092 bus
  macLo = heldReg 0x0001 0x4094 bus
  ourMac = (\a b c -> a ++# b ++# c) <$> macHi <*> macMd <*> macLo

  ---- sleigh gates (0x4080) --------------------------------------------------
  sleigh = resize <$> heldReg 0 0x4080 bus

  ---- CPU read mux ------------------------------------------------------------
  ioDin = sel <$> bus <*> regs <*> uartStat <*> ledReg <*> sdMiso <*> so <*> ppsO
              <*> si <*> dgSeq <*> (drops !! (3 :: Int)) <*> detCount <*> lastCell <*> blobO <*> frameSeq
  sel PmBus{..} r u l m s p i sq dr dc lc b fsq
    | pbAddr == 0x4000 = u
    | pbAddr == 0x4004 = l
    | pbAddr == 0x4028 = zeroExtend (pack m) .|. 2
    | pbAddr == 0x4064 = pack dc
    | pbAddr == 0x4066 = resize (pack lc)
    | pbAddr == 0x4070 = pack (SL.rdSeq s)
    | pbAddr == 0x4072 = zeroExtend (pack (SL.overflow s, SL.count s, SL.rdValid s))
    | pbAddr == 0x4074 = resize (pack (PD.offset p))
    | pbAddr == 0x4076 = zeroExtend (pack (PD.locked p))
    | pbAddr == 0x4078 = pack (siRxGood i)
    | pbAddr == 0x407A = pack (siRxBad i)
    | pbAddr == 0x407C = pack sq
    | pbAddr == 0x407E = pack dr
    | pbAddr == 0x4082 = zeroExtend (siGates i)
    | pbAddr == 0x4084 = pack fsq
    | pbAddr == 0x4086 = zeroExtend (pack (boOverflow b, boDropped b, siOvBusy i, siCharFull i, siOvFull i, siNetFull i))
    | otherwise        = prDin r

  ---- LEDs: H2's register xor a diagnostic byte so nothing is dead ----------
  diag = (\d sw st ov ful -> zeroExtend (pack (d, st, ov, ful)) `xor` sw)
           <$> det <*> (siSwitches <$> si)
           <*> (PD.locked <$> ppsO) <*> (siOvBusy <$> si) <*> (siNetFull <$> si)
  leds = (\l d r -> resize l `xor` resize d `xor` r) <$> ledReg <*> diag <*> (resize . pack . SL.rdSeq <$> so)

-- ---------------------------------------------------------------------------
-- Pixel domain: console + overlay + TMDS encoders.

pixBlock
  :: HiddenClockResetEnable PixelDom
  => Signal PixelDom (Maybe CharWrite)
  -> Signal PixelDom (Maybe (Unsigned 5, Unsigned 8))
  -> Signal PixelDom (Maybe OverlayOp)
  -> (Signal PixelDom (BitVector 10), Signal PixelDom (BitVector 10), Signal PixelDom (BitVector 10), Signal PixelDom Bool)
pixBlock charM curM ovM = (wB, wG, wR, ooBusy <$> ov)
 where
  (pix, _cursor) = textConsole pm1920x480 charM curM
  t   = timingGen pm1920x480      -- second timing instance: textConsole hides its own
  originM = fmap (\(r, c) -> (resize c * 8, resize r * 16)) <$> curM
  ov  = overlayStrip ovM originM t
  on  = (||) <$> (poPixel <$> pix) <*> (ooOn <$> ov)
  de  = poDe <$> pix
  ctl = (\p -> pack (poVSync p, poHSync p)) <$> pix
  r   = mux (poPixel <$> pix) (pure 0x9f) (mux on (pure 0xff) (pure 0))
  g   = mux (poPixel <$> pix) (pure 0xff) (mux on (pure 0x40) (pure 0))
  b   = mux (poPixel <$> pix) (pure 0x8a) (mux on (pure 0x00) (pure 0))
  wB  = tmdsEncoder de ctl b
  wG  = tmdsEncoder de (pure 0) g
  wR  = tmdsEncoder de (pure 0) r

-- Bit domain: 10:1 shifters, one per TMDS channel plus the clock channel.
bitBlock
  :: HiddenClockResetEnable TmdsBit
  => Signal TmdsBit (BitVector 10) -> Signal TmdsBit (BitVector 10) -> Signal TmdsBit (BitVector 10)
  -> Signal TmdsBit (BitVector 4)
bitBlock wB wG wR = (\c r g b -> pack (c, r, g, b)) <$> ck <*> d2 <*> d1 <*> d0
 where
  cnt  = register (0 :: Index 10) (satSucc SatWrap <$> cnt)
  load = (== 0) <$> cnt
  d0 = tmdsShift load wB
  d1 = tmdsShift load wG
  d2 = tmdsShift load wR
  ck = tmdsShift load (pure 0b0000011111)

-- RMII domain: datagram stream -> beacon TX; MAC RX.
rmiiBlock
  :: HiddenClockResetEnable Rmii50
  => Signal Rmii50 (Maybe DgByte) -> Signal Rmii50 (Unsigned 16) -> Signal Rmii50 (BitVector 48)
  -> Signal Rmii50 (BitVector 2) -> Signal Rmii50 Bool
  -> (Signal Rmii50 (BitVector 2), Signal Rmii50 Bool, Signal Rmii50 RxOut, Signal Rmii50 Bool)
rmiiBlock dg sq ourMac rxd crsDv = (txd, txEn, rx, ready)
 where
  (go, mode) = beaconGoAdapter dg sq
  (txd, txEn, ready) = unbundle (beaconTx go mode)
  rx = macRx rxd crsDv ourMac

-- ---------------------------------------------------------------------------
-- The whole thing with explicit clocks.

snooker
  :: Clock Snk25 -> Reset Snk25
  -> Clock PixelDom -> Reset PixelDom
  -> Clock TmdsBit -> Reset TmdsBit
  -> Clock Rmii50 -> Reset Rmii50
  -> Signal Snk25 (BitVector 8)      -- btn/sw
  -> Signal Snk25 Bit                -- ftdi_txd (UART rx)
  -> Signal Snk25 Bit                -- dvp_pclk
  -> Signal Snk25 Bit                -- dvp_href
  -> Signal Snk25 Bit                -- dvp_vsync
  -> Signal Snk25 (BitVector 8)      -- dvp_d
  -> Signal Snk25 (BitVector 12)     -- adc_d
  -> Signal Snk25 Bit                -- pps_in
  -> Signal Snk25 (BitVector 2)      -- gate_in (sleigh photogates)
  -> Signal Snk25 Bit                -- sd_miso
  -> Signal Snk25 (BitVector 8)      -- matrix_col
  -> Signal Rmii50 (BitVector 2)     -- rmii_rxd
  -> Signal Rmii50 Bit               -- rmii_crs_dv
  -> ( Signal Snk25 (BitVector 8)    -- led
     , Signal Snk25 Bit              -- ftdi_rxd (UART tx)
     , Signal TmdsBit (BitVector 4)  -- gpdi_dp (ck, r, g, b)
     , Signal Rmii50 (BitVector 2)   -- rmii_txd
     , Signal Rmii50 Bit             -- rmii_tx_en
     , Signal Snk25 (BitVector 3)    -- sd (cs, clk, mosi)
     , Signal Snk25 Bit              -- irig_dc
     , Signal Snk25 (BitVector 8)    -- irig_am
     , Signal Snk25 (BitVector 8)    -- matrix_row
     , Signal Snk25 (BitVector 8)    -- sleigh_gate
     )
snooker cS rS cP rP cB rB cR rR sw urx pclk href vs dd adc pps gates miso cols rxd crsDv =
  ( soLeds <$> so, soUartTx <$> so, gpdi, txd, boolToBit <$> txEn, soSd <$> so
  , soIrigDc <$> so, soIrigAm <$> so, soMatRows <$> so, soSleigh <$> so )
 where
  eS = enableGen; eP = enableGen; eB = enableGen; eR = enableGen

  si = SysIn <$> sw <*> urx <*> pclk <*> href <*> vs <*> dd <*> adc <*> pps <*> gates <*> miso <*> cols
             <*> charFull <*> ovFull <*> netFull <*> rxGoodS <*> rxBadS <*> ovBusyS
  so = withClockResetEnable cS rS eS (sysBlock si)

  -- sys -> pixel: three small CDC FIFOs (chars, cursor, overlay ops)
  (charD, charE, charFull) = cdcFifo (SNat @4) cS rS eS cP rP eP (soCharPush <$> so) (not <$> charE)
  (curD,  curE,  _curFull) = cdcFifo (SNat @2) cS rS eS cP rP eP (soCurPush  <$> so) (not <$> curE)
  (ovD,   ovE,   ovFull)   = cdcFifo (SNat @4) cS rS eS cP rP eP (soOvPush   <$> so) (not <$> ovE)
  charM = mux charE (pure Nothing) (Just <$> charD)
  curM  = mux curE  (pure Nothing) (Just <$> curD)
  ovM   = mux ovE   (pure Nothing) (Just <$> ovD)
  (wB, wG, wR, ovBusy) = withClockResetEnable cP rP eP (pixBlock charM curM ovM)
  ovBusyS = bitSync cP cS rS eS False ovBusy

  -- pixel -> bit (phase-locked in hardware; 2-flop for the study)
  gpdi = withClockResetEnable cB rB eB
           (bitBlock (bitSync cP cB rB eB 0 wB) (bitSync cP cB rB eB 0 wG) (bitSync cP cB rB eB 0 wR))

  -- sys -> RMII: datagram byte stream through a 2k CDC FIFO
  (dgD, dgE, netFull) = cdcFifo (SNat @11) cS rS eS cR rR eR (soDgPush <$> so) (not <$> dgE)
  dgM   = mux dgE (pure Nothing) (Just <$> dgD)
  sqR   = bitSync cS cR rR eR 0 (soDgSeq <$> so)
  macR  = bitSync cS cR rR eR 0 (soOurMac <$> so)
  (txd, txEn, rx, _ready) = withClockResetEnable cR rR eR (rmiiBlock dgM sqR macR rxd (bitToBool <$> crsDv))
  rxGoodS = bitSync cR cS rS eS 0 (rxGood <$> rx)
  rxBadS  = bitSync cR cS rS eS 0 ((\r -> rxBad r `xor` unpack (resize (pack (rxByte r, rxValid r, rxStart r, rxEnd r, rxOk r)))) <$> rx)
  -- keep pulseSync in the design too: rx frame-end strobe back to sys, folded into the bad counter LSB
  _rxEndS = pulseSync cR rR eR cS rS eS (rxEnd <$> rx)

topEntity
  :: Clock Snk25 -> Reset Snk25
  -> Clock PixelDom -> Reset PixelDom
  -> Clock TmdsBit -> Reset TmdsBit
  -> Clock Rmii50 -> Reset Rmii50
  -> Signal Snk25 (BitVector 8) -> Signal Snk25 Bit
  -> Signal Snk25 Bit -> Signal Snk25 Bit -> Signal Snk25 Bit -> Signal Snk25 (BitVector 8)
  -> Signal Snk25 (BitVector 12) -> Signal Snk25 Bit -> Signal Snk25 (BitVector 2)
  -> Signal Snk25 Bit -> Signal Snk25 (BitVector 8)
  -> Signal Rmii50 (BitVector 2) -> Signal Rmii50 Bit
  -> ( Signal Snk25 (BitVector 8), Signal Snk25 Bit, Signal TmdsBit (BitVector 4)
     , Signal Rmii50 (BitVector 2), Signal Rmii50 Bit, Signal Snk25 (BitVector 3)
     , Signal Snk25 Bit, Signal Snk25 (BitVector 8), Signal Snk25 (BitVector 8), Signal Snk25 (BitVector 8) )
topEntity = snooker
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_top_snooker"
    , t_inputs =
        [ PortName "clk_25mhz", PortName "rst_sys"
        , PortName "clk_pixel", PortName "rst_pixel"
        , PortName "clk_tmds",  PortName "rst_tmds"
        , PortName "clk_rmii",  PortName "rst_rmii"
        , PortName "btn", PortName "ftdi_txd"
        , PortName "dvp_pclk", PortName "dvp_href", PortName "dvp_vsync", PortName "dvp_d"
        , PortName "adc_d", PortName "pps_in", PortName "gate_in"
        , PortName "sd_miso", PortName "matrix_col"
        , PortName "rmii_rxd", PortName "rmii_crs_dv" ]
    , t_output = PortProduct ""
        [ PortName "led", PortName "ftdi_rxd", PortName "gpdi_dp"
        , PortName "rmii_txd", PortName "rmii_tx_en", PortName "sd"
        , PortName "irig_dc", PortName "irig_am", PortName "matrix_row", PortName "sleigh_gate" ]
    }) #-}
