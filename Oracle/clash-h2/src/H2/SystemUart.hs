{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | __Simulation-only__ system: the H2 core, 8Kx16 program RAM, and a
--   functional register-level model of the upstream UART sufficient to talk
--   to eForth's console words (@rx?@ \/ @tx!@ in @embed.fth@).
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
import H2 hiding (topEntity)
import H2.System (Memory)

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

-- | The simulation system: core + dual-port program RAM + UART model.
--   Returns the tx byte stream (@Just b@ on cycles with a @UART_TX_WE@
--   strobe).
h2SystemSim
  :: forall dom
   . HiddenClockResetEnable dom
  => Memory dom                          -- ^ instruction-fetch RAM
  -> Memory dom                          -- ^ data RAM
  -> [BitVector 8]                       -- ^ UART rx input script
  -> Signal dom (Maybe (BitVector 8))    -- ^ UART tx bytes
h2SystemSim instrMem dataMem script = txS
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
    uartWe  = (ioWr <$> core) .&&. ((== 0x4000) <$> ioAddrS)

    (iUartS, txS) =
      mealyB uartStep (script, 0) (uartWe, ioDout <$> core)

    -- iVT100: no keyboard char pending (bit 8), VT100 never busy (bit 11).
    iVT100 = 0x0900 :: Cell

    -- iPanel: scripted mode-slider zones (see module header) —
    -- {s4zone[5:4] = 2 PLAY, s3zone[2:0] = 2 "E"}.
    iPanel = 0x0022 :: Cell

    ioDinS = decode <$> ioAddrS <*> iUartS
    decode a u
      | a == 0x4000 = u
      | a == 0x4002 = iVT100
      | a == 0x4020 = iPanel
      | otherwise   = 0
