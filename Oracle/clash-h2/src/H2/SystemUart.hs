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
--   [@iPanel@ (read 0x4020)] the first PM capability register
--   (@Oracle/eforth-pm.md@ section 1): mode-slider zones, post-hysteresis.
--   Layout here: bits 2:0 = S3 zone 0–5 (P·O·E·T·I·C), bits 5:4 = S4 zone
--   (0 OFF · 1 CAL · 2 PLAY · 3 REC), all other bits 0.  On hardware the
--   gateware digitizes the sliders and compares against zone thresholds
--   with hysteresis; the sim scripts the clean zone numbers as a constant
--   (S3 = 2 \"E\", S4 = 2 PLAY, so the register reads @0x0022@).  Read-only
--   from Forth; writes (oPanelCtrl) are accepted and ignored like the other
--   unmodelled peripherals.
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

    -- iPanel: scripted mode-slider zones (see module header) —
    -- {s4zone[5:4] = 2 PLAY, s3zone[2:0] = 2 "E"}.
    iPanel = 0x0022 :: Cell

    ioDinS = decode <$> ioAddrS <*> iUartS <*> iSdRxS <*> iIrigS
    decode a u sd irig
      | a == 0x4000 = u
      | a == 0x4002 = iVT100
      | a == 0x4020 = iPanel
      | a == 0x4028 = iSdStat
      | a == 0x402A = sd
      | a == 0x4034 = irig
      | otherwise   = 0
