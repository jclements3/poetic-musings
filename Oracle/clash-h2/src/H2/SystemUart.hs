{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | __Simulation-only__ system: the H2 core, 8Kx16 program RAM, and
--   functional register-level models of the peripherals the PM boot
--   transcript exercises — the upstream UART (eForth's console), plus the
--   first PM capability registers from @Oracle\/eforth-pm.md@ section 1:
--   the 0x4020 zone register, the 0x4028\/0x402A SD\/SPI block interface,
--   and the 0x4034\/0x4040-block IRIG time registers (driven by the
--   sim-verified core from @IRIG\/clash\/src\/Irig.hs@).
--
--   This is /not/ a serdes: there is no baud clock, no start\/stop bits and
--   no 8-entry FIFO — the rx side is fed from a Haskell list of bytes given
--   at elaboration time and the tx side is exposed as a per-cycle
--   @Maybe byte@ event stream.  What it does model exactly is the register
--   contract from @h2.c@ \/ @top.vhd@ (see @forth-cpu-notes.md@):
--
--   [@iUart@ (read 0x4000)] bit 8 = rx-fifo-empty, bit 9 = rx-fifo-full
--   (always 0 here), bit 11 = tx-fifo-empty (always 1: infinite sink),
--   bit 12 = tx-fifo-full (always 0), low byte = the /rx holding register/,
--   i.e. the byte most recently popped by the @UART_RX_RE@ strobe.  Reads
--   are side-effect free.
--
--   [@oUart@ (write 0x4000)] bit 13 (@UART_TX_WE@) sends the low byte of
--   the written value; bit 10 (@UART_RX_RE@) pops the next script byte into
--   the rx holding register (a no-op when the script is exhausted).  This
--   matches @h2.c@ (@h2_io_set_default@), where the RE strobe fetches the
--   next input character and a later read returns it — eForth's @uart?@
--   depends on exactly this "write read-enable /before/ read" order.
--
--   [@iVT100@ (read 0x4002)] bit 8 set (no PS\/2 character pending),
--   bit 11 set \/ bit 12 clear (VT100 write path never busy).  eForth's
--   @tx!@ writes every character here too and @rx?@ polls it when the UART
--   has nothing; both must see sane status bits.  Writes to @oVT100@ are
--   accepted and dropped.
--
--   [@iPanel@ (read 0x4020) and the PM file] since PM.RegFile exists, the
--   0x4020\/0x4022\/0x4024\/0x402C…0x4036 range is no stub: the REAL
--   register file from @pm-lib@ is on the bus, with the real zone decoder
--   (constant slider samples put S3 in zone 2 \"E\", S4 in zone 2 PLAY;
--   after the shortened mode dwell the register reads @0x8022@ — stable
--   flag + the old @0x0022@) and the real matrix scanner at hardware scan
--   timing with one key wired down (row 2\/col 3 → keycode 19), whose
--   press event Forth pops with a 0x4024 read.  The audio\/synth\/keyer\/
--   TX-interlock semantics live in the file too (proven register-level by
--   @pm-lib@'s @regfile-test@; not revisited in the boot transcript).
--
--   [@iSdStat@ \/ @oSdCtrl@ (0x4028)] SD\/SPI block interface status\/
--   control.  Read layout here: bit 0 busy (always 0 — the modelled
--   shifter completes within the write cycle), bit 1 card-detect (1: a
--   card image was supplied), bit 2 write-protect (1: this model has no
--   write path).  @oSdCtrl@ writes (CS, clock divisor, card power) are
--   accepted and ignored — the modelled card ignores CS framing.
--
--   [@iSdRx@ \/ @oSdTx@ (0x402A)] the SPI shifter, exactly the
--   eforth-pm.md contract: /Forth implements the SD command layer; gateware
--   is just the shifter/.  A write shifts the low byte out to the card and
--   simultaneously captures the card's output byte into the rx holding
--   register; a read returns that byte, side-effect free.  Behind the
--   shifter sits a behavioural SPI-mode SD card backed by a Haskell byte
--   list (the card image from @tools\/mkcard.py@): it answers CMD0 with the
--   idle R1 and CMD17 (READ_SINGLE_BLOCK, byte-addressed like SDSC) with
--   R1, the 0xFE data token, 512 data bytes and a dummy CRC16.  The card
--   boots pre-initialized (no ACMD41 dance needed) — a sim convenience;
--   the register contract is what is being proven.  Reads beyond the image
--   return 0xFF like erased flash.  Forth blocks are 1024 bytes = two
--   512-byte sectors (LAYOUT storage model), so @blk-read@ issues two
--   CMD17s.
--
--   [@iIrig@ (read 0x4034)] IRIG status per @IRIG\/DESIGN.md@
--   ({locked, pps_seen, frame_phase} + the BCD seconds field from
--   eforth-pm.md's iIrig).  Layout pinned here: bit 15 locked (0 until G),
--   bits 14:8 seconds BCD {tens[2:0], ones[3:0]}, bit 7 pps_seen (a frame
--   reference has occurred since reset), bits 6:0 frame phase 0–99.  The
--   time engine is the sim-verified Irig core (@tick1k@\/@framePos@\/@rtc@)
--   at the @SNat 1@ sim scale: one second = one frame = 10 000 cycles, so
--   the phase advances every 100 cycles and live Forth can watch the clock
--   move.  (The waveform back-end, @framer@\/@pwmcell@\/AM, generates the
--   scope\/audio outputs on hardware and is not consumed by any register —
--   not instantiated here.)
--
--   [TOD set (writes 0x4034\/0x4040 block)] per IRIG\/DESIGN.md +
--   GPS\/DESIGN.md: @oTodSecs@ (0x4046) = seconds-of-day low 16 bits;
--   @oTodDay@ (0x4048) = day-of-year in bits 8:0, seconds-of-day bit 16 in
--   bit 9; @oTodSet@ (0x4044, and equivalently the 0x4034 control write) =
--   set_strobe, latching the packed registers into the rtc, applied at the
--   next frame reference.  The register file here does the binary→BCD
--   unpacking (div\/mod — sim-only code); the Irig core takes BCD digits
--   directly, per its port comment.
--
--   [Sleigh (0x4050\/0x4052)] the REAL @PM.Sleigh@ coil sequencer, with the
--   register semantics from its module header (oSleigh speed\/enable\/park,
--   iSleigh state\/coil\/ribbon\/show\/paused\/speed, oSleighDwell \/
--   iSleighDwell index+ms).  Sim scale: the 1 ms tick is EVERY clock (a
--   park rests 2 500 cycles, a station dwell is its ms count in cycles), the
--   show switch and ribbon-present lines are tied high, and speed 0 (\"follow
--   the theremin\") reads a theremin speed of 0 = paused — there is no
--   theremin here.
--
--   [WSPR (0x4070 group)] the REAL @PM.Wspr@ sequencer.  0x4070 write =
--   symbol-table entry {bits 9:8 symbol, 7:0 index}; read = {bit 2 txOn,
--   bits 1:0 the table's symbol at the sequencer's current index} — idle,
--   that is index 0.  0x4072 write bit 0 = start strobe (the even-minute
--   tick); read = {bit 0 armed, bit 1 txOn, bit 2 done (sticky, cleared by
--   start)}.  @armed@ is PM.RegFile's interlocked prTxArmed (arm key AND
--   S3 == C), so with the sliders parked in E a start is refused.  0x4074
--   oWsprDiv (clocks per symbol, 16-bit here), 0x4076 oWsprBase \/ read
--   phaseInc low 16, 0x4078 oWsprStep (NCO increments, low 16 bits).
--
--   [Imaging (0x4060 group)] the REAL @PM.Blob@ threshold+labeller on a
--   synthetic frame source instead of the DVP capture: a 0x4062 write with
--   bit 0 set fires one 16x8 frame (one pixel per clock; value 200 inside
--   the 4x4 square x 4..7, y 2..5, 10 elsewhere — centroid (5.5, 3.5) =
--   Q4 (88, 56), 16 pixels).  0x4064 write = {15:8 hysteresis, 7:0
--   threshold}; 0x4068 write = {15:8 max area \/ 16, 7:0 min area}; 0x4068
--   read = the threshold word back.  0x4064 read is the autoinc centroid
--   pair: the first read returns cx of the oldest unread blob, the second
--   cy and pops it (a side-effecting read, like 0x4024).  0x4066 read =
--   that blob's pixel count (sum_w).  0x4060 read = {15:8 blobs in the
--   last frame, bit 3 PLL locked (1), bit 2 dropped, bit 1 overflow, bit 0
--   frame done}; 0x4062 read = frame sequence.
--
--   [Records \/ Net (0x4080 group)] the REAL @PM.Records.recordPath4@
--   (CENTROID port fed by the blob records, PPS_STATUS port fired by a
--   0x4082 write, 256-cycle flush tick), its datagrams pulsing the REAL
--   @PM.Net.beaconTx@ through @beaconGoAdapter@, whose RMII output is looped
--   back into the REAL @PM.NetRx.macRx@ — so a centroid typed out of 0x4064
--   also ends as a counted, CRC-checked Ethernet frame.  0x4080 write bit 0
--   = enable (records only enter the path when set); read = {bit 0 enable,
--   bit 1 tx busy, bit 2 rx activity}.  0x4082 read = datagram seq, 0x4084
--   = drops (sum of the four ports), 0x4086 = rxGood, 0x4088 = rxBad.
--
--   All other reads return 0 and all other writes (timer, LEDs, 7-segment,
--   IRQ mask, baud divisors, memory controller, ...) are accepted and
--   ignored, like unpopulated peripherals.  In particular @iMemDin@
--   (0x4008) reads as 0, so eForth's @loading...@ phase runs against empty
--   non-volatile storage and reports @failed@ — same as upstream without an
--   @nvram.blk@.
module H2.SystemUart
  ( h2SystemSim
  ) where

import Clash.Prelude
import qualified Prelude as P
import H2 hiding (topEntity)
import H2.System (Memory)
import Irig (Rtc (..), SetVal (..), framePos, rtc, tick1k)
import PM.Matrix (MatrixCfg (..))
import PM.RegFile (PmBus (..), PmRegs (..), PmStatus (..), regFile)
import PM.Sleigh (SleighIn (..), SleighCtl (..), sleigh, decodeSleighCtl, effectiveSpeed,
                  encodeSleighStatus, decodeDwellWr, encodeDwellRd)
import PM.Wspr (wspr)
import PM.Dvp (Pix (..))
import PM.Blob (BlobCfg (..), BlobOut (..), BlobRec (..), blobLabel)
import PM.Records (PpsStatus (..), Centroid (..), recordPath4, beaconGoAdapter)
import PM.Net (beaconTx)
import PM.NetRx (RxOut (..), macRx)
import Data.Maybe (isJust)

-- | UART model state: bytes not yet offered to the CPU, and the rx holding
--   register (last byte popped by the @UART_RX_RE@ strobe).
type UartState = ([BitVector 8], BitVector 8)

-- | One cycle of the UART register model.  The visible register value is a
--   function of the /current/ state (peripheral registers in @top.vhd@ are
--   read combinationally); strobes take effect at the clock edge.
uartStep
  :: UartState
  -> (Bool, Cell)                        -- ^ (oUart write strobe, io_dout)
  -> (UartState, (Cell, Maybe (BitVector 8)))
uartStep (script, rxReg) (we, dat) =
  -- Forced before the pair is returned: 'mealyB' only evaluates the state
  -- to WHNF, and a lazy pair here would chain one thunk per cycle across
  -- the millions of cycles between console accesses (a space leak).
  script' `seq` rxReg' `seq` ((script', rxReg'), (iUart, txByte))
  where
    iUart = 0x0800                                    -- bit 11: tx fifo empty
        .|. (if null script then 0x0100 else 0)       -- bit  8: rx fifo empty
        .|. zeroExtend rxReg

    txByte | we && testBit dat 13 = Just (truncateB dat)   -- UART_TX_WE
           | otherwise            = Nothing

    (script', rxReg')
      | we && testBit dat 10 = case script of              -- UART_RX_RE
          (b:bs) -> (bs, b)
          []     -> ([], rxReg)
      | otherwise = (script, rxReg)

-- | SD card model state: response bytes still to shift out, command bytes
--   accumulated so far, and the rx holding register (the byte the card
--   shifted in during the last transfer).
type SdState = ([BitVector 8], [BitVector 8], BitVector 8)

-- | One cycle of the SPI shifter + behavioural SD card.  A write to
--   @oSdTx@ is one full-duplex transfer: the card's output byte for the
--   transfer is decided /before/ the incoming byte is processed (real SPI
--   semantics — the response to a command starts in later transfers).
--   While a response is draining, incoming bytes are treated as 0xFF fill;
--   when idle, a byte matching the SD command framing (b7:6 = 01) starts a
--   6-byte command frame.
sdStep
  :: [BitVector 8]                       -- ^ card image
  -> SdState
  -> (Bool, Cell)                        -- ^ (oSdTx write strobe, io_dout)
  -> (SdState, Cell)                     -- ^ iSdRx (side-effect-free read)
sdStep card st@(pending, cmdBuf, rxReg) (we, dat)
  | not we    = (st, iSdRx)
  | otherwise =
      -- WHNF forcing, same space-leak rationale as 'uartStep'.
      pending' `seq` cmdBuf' `seq` outB `seq`
        ((pending', cmdBuf', outB), iSdRx)
  where
    iSdRx = zeroExtend rxReg
    inB   = truncateB dat :: BitVector 8
    (outB, rest) = case pending of
      (b:bs) -> (b, bs)
      []     -> (0xFF, [])
    (pending', cmdBuf')
      | not (P.null pending)      = (rest, cmdBuf)  -- response draining
      | P.null cmdBuf             =
          if inB .&. 0xC0 == 0x40 then ([], [inB]) else ([], [])
      | P.length cmdBuf == 5      = (sdRespond card (cmdBuf P.++ [inB]), [])
      | otherwise                 = ([], cmdBuf P.++ [inB])

-- | The card's answer to a completed 6-byte command frame, as the byte
--   sequence it will shift out on subsequent transfers (leading 0xFF = the
--   response-delay gap, Ncr).
sdRespond :: [BitVector 8] -> [BitVector 8] -> [BitVector 8]
sdRespond card [c, a3, a2, a1, a0, _crc] = case c .&. 0x3F of
  0  -> [0xFF, 0x01]                               -- CMD0: R1 idle
  17 -> [0xFF, 0x00, 0xFF, 0xFE]                   -- R1 ok, gap, data token
          P.++ sector P.++ [0x00, 0x00]            -- 512 bytes + dummy CRC16
  _  -> [0xFF, 0x04]                               -- R1 illegal command
  where
    addr :: Int
    addr = foldl (\acc b -> acc * 256 + fromIntegral b) 0 (a3 :> a2 :> a1 :> a0 :> Nil)
    sector = P.take 512 (P.drop addr card P.++ P.repeat 0xFF)
sdRespond _ _ = [0xFF, 0x04]

-- | Pack the TOD-set registers into the Irig core's BCD set request
--   (binary seconds-of-day → hh:mm:ss digits; sim-only div\/mod).
mkSetVal :: Cell -> Cell -> SetVal
mkSetVal secsLo dayW = SetVal
  { setSs  = dig2 ss
  , setMm  = dig2 mm
  , setHh  = dig2 hh
  , setDoy = ( fromIntegral (doy `P.div` 100)
             , fromIntegral (doy `P.div` 10 `P.mod` 10)
             , fromIntegral (doy `P.mod` 10) )
  }
  where
    secs, doy :: Integer
    secs = toInteger (unpack secsLo :: Unsigned 16)
         + (if testBit dayW 9 then 65536 else 0)
    doy  = toInteger (unpack (slice d8 d0 dayW) :: Unsigned 9)
    ss   = secs `P.mod` 60
    mm   = secs `P.div` 60 `P.mod` 60
    hh   = secs `P.div` 3600
    dig2 x = (fromIntegral (x `P.div` 10), fromIntegral (x `P.mod` 10))

-- | The simulation system: core + dual-port program RAM + peripheral
--   models.  Returns the tx byte stream (@Just b@ on cycles with a
--   @UART_TX_WE@ strobe).
h2SystemSim
  :: forall dom
   . HiddenClockResetEnable dom
  => Memory dom                          -- ^ instruction-fetch RAM
  -> Memory dom                          -- ^ data RAM
  -> [BitVector 8]                       -- ^ UART rx input script
  -> [BitVector 8]                       -- ^ SD card image (tools/mkcard.py)
  -> Signal dom (Maybe (BitVector 8))    -- ^ UART tx bytes
h2SystemSim instrMem dataMem script card = txS
  where
    core :: Signal dom H2Out
    core = h2 @dom @6 @3 defaultConfig inp

    inp = H2In <$> pure False        -- stop
               <*> ioDinS
               <*> pure False        -- irq
               <*> pure 0            -- irq_addr
               <*> insnS
               <*> dinS

    pcS    = unpack . pcOut <$> core
    daddrS = unpack . daddr <$> core
    wr     = mux (dwe <$> core)
                 (Just <$> bundle (daddrS, dout <$> core))
                 (pure Nothing)

    insnS = instrMem pcS    wr
    dinS  = dataMem  daddrS wr

    ioAddrS = ioDaddr <$> core
    ioWrS   = ioWr <$> core
    dOutS   = ioDout <$> core
    wrAt a  = ioWrS .&&. ((== a) <$> ioAddrS)

    (iUartS, txS) =
      mealyB uartStep (script, 0) (wrAt 0x4000, dOutS)

    -- SD/SPI shifter + behavioural card (module header).
    iSdRxS :: Signal dom Cell
    iSdRxS = mealyB (sdStep card) ([], [], 0xFF) (wrAt 0x402A, dOutS)

    iSdStat = 0x0006 :: Cell   -- card-detect + write-protect, never busy

    -- IRIG time engine (Irig core, SNat 1 sim scale: 1 s = 10 000 cycles).
    (msT, _carrIx)             = tick1k (SNat @1)
    (cellIxS, _msIx, frameRef) = framePos msT
    todSecsS  = regEn (0 :: Cell) (wrAt 0x4046) dOutS
    todDayS   = regEn (0 :: Cell) (wrAt 0x4048) dOutS
    setStrobe = wrAt 0x4044 .||. wrAt 0x4034
    timeS     = rtc frameRef setStrobe (mkSetVal <$> todSecsS <*> todDayS)
    ppsSeenS  = regEn False frameRef (pure True)

    irigStat :: Rtc -> Bool -> Index 100 -> Cell
    irigStat t pps ix =
          (0 :: BitVector 1)                          -- 15: locked (0 until G)
      ++# (truncateB (pack (sTens t)) :: BitVector 3) -- 14:12 seconds tens BCD
      ++# pack (sOnes t)                              -- 11:8  seconds ones BCD
      ++# (if pps then 1 else 0 :: BitVector 1)       -- 7:    pps_seen
      ++# pack ix                                     -- 6:0   frame phase 0-99
    iIrigS = irigStat <$> timeS <*> ppsSeenS <*> cellIxS

    -- iVT100: no keyboard char pending (bit 8), VT100 never busy (bit 11).
    iVT100 = 0x0900 :: Cell

    -- The REAL PM register file (PM.RegFile: zones + matrix + held regs +
    -- TX interlock) on the H2 bus.  Slider samples are constants placing
    -- S3 in zone 2 "E" and S4 in zone 2 PLAY, so iPanel reads
    -- 0x8022 once the (shortened, 10 000-cycle) mode dwell sets the stable
    -- bit — the old scripted constant 0x0022 plus the stable flag.  The
    -- matrix runs at hardware scan timing with one key held: column 3
    -- pulls low whenever row 2 is strobed, so after debounce the event
    -- FIFO holds exactly one press of keycode 19 for Forth to pop through
    -- a 0x4024 read.  The IRIG status word enters as the file's stIrig so
    -- 0x4034 keeps its contract (the TOD-set write block below stays here).
    pmBus = PmBus <$> ioAddrS <*> ioWrS <*> (ioRe <$> core) <*> dOutS
    pmCols = fmap (\rws -> if rws !! (2 :: Index 8) == low
                             then replace (3 :: Index 8) low (repeat high)
                             else repeat high)
                  (prRows <$> pmRegs)
    pmStatus = (\ir -> PmStatus 0 0 0 True ir 0) <$> iIrigS
    pmRegs = regFile 64 10000 (MatrixCfg 3125 10)
               pmBus (pure 0) (pure 1700) (pure 2560) pmCols pmStatus

    armedS = prTxArmed <$> pmRegs
    reAt a = (ioRe <$> core) .&&. ((== a) <$> ioAddrS)
    bit0   = (`testBit` 0) <$> dOutS

    -- Sleigh (module header): real PM.Sleigh, tick every clock.
    sleighCtl  = decodeSleighCtl <$> regEn 0 (wrAt 0x4050) dOutS
    dwellPulse = mux (wrAt 0x4052) (Just . decodeDwellWr <$> dOutS) (pure Nothing)
    dwellLast  = regEn (0, 400) (wrAt 0x4052) (decodeDwellWr <$> dOutS)
    slSpeed    = (`effectiveSpeed` 0) <$> sleighCtl
    slIn = (\c sp dw -> SleighIn (scEnable c) sp True True (scPark c) True dw)
             <$> sleighCtl <*> slSpeed <*> dwellPulse
    slOut = sleigh slIn
    iSleigh      = (\o sp -> encodeSleighStatus o True True sp) <$> slOut <*> slSpeed
    iSleighDwell = uncurry encodeDwellRd <$> dwellLast

    -- WSPR (module header): real PM.Wspr, armed through the RegFile interlock.
    wsprWr    = mux (wrAt 0x4070)
                    ((\d -> Just (unpack (slice d7 d0 d), unpack (slice d9 d8 d))) <$> dOutS)
                    (pure Nothing)
    wsprStart = wrAt 0x4072 .&&. bit0
    wsprDivW  = regEn (0x4000 :: Cell) (wrAt 0x4074) dOutS
    wsprBaseW = regEn (0 :: Cell) (wrAt 0x4076) dOutS
    wsprStepW = regEn (0 :: Cell) (wrAt 0x4078) dOutS
    ext16 :: Signal dom Cell -> Signal dom (Unsigned 32)
    ext16 = fmap (zeroExtend . unpack)
    (wSym, wTxOn, wPhase, wDone) =
      wspr wsprWr armedS wsprStart (ext16 wsprDivW) (ext16 wsprBaseW) (ext16 wsprStepW)
    wDoneSt  = regEn False (wDone .||. wsprStart) (wDone .&&. (not <$> wsprStart))
    iWsprSym  = (\sy t -> zeroExtend (pack sy) .|. (if t then 4 else 0)) <$> wSym <*> wTxOn
    iWsprStat = (\a t d -> (if a then 1 else 0) .|. (if t then 2 else 0) .|. (if d then 4 else 0))
                  <$> armedS <*> wTxOn <*> wDoneSt
    iWsprPhase = (truncateB . pack) <$> wPhase :: Signal dom Cell

    -- Imaging (module header): real PM.Blob on a synthetic 16x8 frame.
    imgThreshW = regEn (0x0080 :: Cell) (wrAt 0x4064) dOutS
    imgAreaW   = regEn (0xFF01 :: Cell) (wrAt 0x4068) dOutS
    blobCfg = (\t a -> BlobCfg (unpack (slice d7 d0 t)) (unpack (slice d15 d8 t))
                                (zeroExtend (unpack (slice d7 d0 a)))
                                (zeroExtend (unpack (slice d15 d8 a)) `shiftL` 4))
                <$> imgThreshW <*> imgAreaW
    imgFire = wrAt 0x4062 .&&. bit0
    pixS    = mealy frameGen (False, 0, 0) imgFire
    blobOut = blobLabel blobCfg pixS
    recS    = boRec <$> blobOut
    frameSeq = regEn (0 :: Cell) imgFire (frameSeq + 1) :: Signal dom Cell
    nRecs :: Signal dom (Unsigned 8)
    nRecs = regEn 0 (imgFire .||. (isJust <$> recS))
                    (mux imgFire 0 (nRecs + 1))
    frameOk = regEn False (imgFire .||. (boFrameDone <$> blobOut)) (not <$> imgFire)
    iImgStat = (\n ok o -> (zeroExtend (pack n) `shiftL` 8) .|. 8
                             .|. (if boDropped o then 4 else 0) .|. (if boOverflow o then 2 else 0)
                             .|. (if ok then 1 else 0))
                 <$> nRecs <*> frameOk <*> blobOut
    (iImgCent, iImgSum) = mealyB centStep ([], False) (recS, reAt 0x4064)

    -- Records / Net (module header): real record path -> beacon -> RMII loopback -> macRx.
    netEn   = (`testBit` 0) <$> regEn (0 :: Cell) (wrAt 0x4080) dOutS
    ppsFire = mux (wrAt 0x4082 .&&. netEn)
                  ((\d -> Just (PpsStatus (resize (unpack d :: Signed 16)) 0)) <$> dOutS)
                  (pure Nothing)
    centFire = mux netEn ((\r sq -> fmap (toCentroid sq) r) <$> recS <*> frameSeq) (pure Nothing)
    (dgOut, dgSeq, _dgLen, drops) =
      recordPath4 ppsFire (pure Nothing) (pure Nothing) centFire (riseEvery (SNat @256))
    (bGo, bMode)       = beaconGoAdapter dgOut dgSeq
    (txd, txen, _rdy)  = unbundle (beaconTx bGo bMode)
    rxO                = macRx txd txen (pure 0x02504D000001)
    iNetStat  = (\e b r -> (if e then 1 else 0) .|. (if b then 2 else 0) .|. (if r then 4 else 0))
                  <$> netEn <*> (isJust <$> dgOut) <*> (rxValid <$> rxO)
    iNetDrops = pack . sum <$> bundle drops
    iNetSeq   = pack <$> dgSeq
    iRxGood   = pack . rxGood <$> rxO
    iRxBad    = pack . rxBad <$> rxO

    ioDinS = decode <$> ioAddrS <*> iUartS <*> iSdRxS <*> (prDin <$> pmRegs) <*> pmExt
    pmExt  = bundle ( bundle (iSleigh, iSleighDwell)
                    , bundle (iWsprSym, iWsprStat, wsprDivW, iWsprPhase, wsprStepW)
                    , bundle (iImgStat, frameSeq, iImgCent, iImgSum, imgThreshW)
                    , bundle (iNetStat, iNetSeq, iNetDrops, iRxGood, iRxBad) )
    decode a u sd pm ((sl, sld), (ws, wst, wdv, wph, wsp), (ist, isq, ic, isum, ith), (ns, nsq, nd, ng, nb))
      | a == 0x4000 = u
      | a == 0x4002 = iVT100
      | a == 0x4028 = iSdStat
      | a == 0x402A = sd
      | a == 0x4050 = sl
      | a == 0x4052 = sld
      | a == 0x4070 = ws
      | a == 0x4072 = wst
      | a == 0x4074 = wdv
      | a == 0x4076 = wph
      | a == 0x4078 = wsp
      | a == 0x4060 = ist
      | a == 0x4062 = isq
      | a == 0x4064 = ic
      | a == 0x4066 = isum
      | a == 0x4068 = ith
      | a == 0x4080 = ns
      | a == 0x4082 = nsq
      | a == 0x4084 = nd
      | a == 0x4086 = ng
      | a == 0x4088 = nb
      | otherwise   = pm   -- 0x4020/22/24/2C/2E/30/32/34/36 + 0 elsewhere

-- | Synthetic frame source for the Imaging block: state (running, x, y);
--   a fire starts one 16x8 frame, one pixel per clock, with a 4x4 bright
--   square at x 4..7, y 2..5 (see module header).
frameGen :: (Bool, Unsigned 10, Unsigned 9) -> Bool -> ((Bool, Unsigned 10, Unsigned 9), Maybe Pix)
frameGen (run, x, y) fire
  | not run   = if fire then ((True, 0, 0), Nothing) else ((False, 0, 0), Nothing)
  | otherwise = (st', Just pix)
  where
    w = 16; h = 8
    eol = x == w - 1
    eof = eol && y == h - 1
    val = if x >= 4 && x <= 7 && y >= 2 && y <= 5 then 200 else 10
    pix = Pix x y val (x == 0 && y == 0) eol eof
    st' | eof       = (False, 0, 0)
        | eol       = (True, 0, y + 1)
        | otherwise = (True, x + 1, y)

-- | The centroid read FIFO behind 0x4064\/0x4066 (sim-only Haskell list):
--   blob records are appended as they arrive; a 0x4064 read strobe first
--   returns cx, then cy and pops.  0x4066 reads the head's pixel count.
centStep
  :: ([(Cell, Cell, Cell)], Bool)
  -> (Maybe BlobRec, Bool)
  -> (([(Cell, Cell, Cell)], Bool), (Cell, Cell))
centStep (q, phase) (rec, re) =
  q' `seq` phase' `seq` ((q', phase'), (cent, cnt))
  where
    (cent, cnt) = case q of
      ((cx, cy, n) : _) -> (if phase then cy else cx, n)
      []                -> (0, 0)
    q1 = case rec of
      Just r  -> q P.++ [(pack (bCx r), pack (bCy r), pack (bCount r))]
      Nothing -> q
    (q', phase')
      | re && not (P.null q) = if phase then (P.drop 1 q1, False) else (q1, True)
      | otherwise            = (q1, phase)

-- | A blob record as the CENTROID port payload (rtc = 0 here; the frame seq
--   is the record's seq).
toCentroid :: Cell -> BlobRec -> Centroid
toCentroid sq r = Centroid 0 (unpack sq) (pack (bLabel r)) (bCx r) (bCy r) (bCount r) 0
