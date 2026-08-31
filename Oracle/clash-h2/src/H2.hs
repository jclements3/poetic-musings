{-# LANGUAGE BinaryLiterals      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | The H2 Forth CPU (a J1 derivative) ported from Richard Howe's
--   <https://github.com/howerj/forth-cpu h2.vhd> to Clash.
--
--   This module is a line-for-line translation of the VHDL core:
--
--   * same instruction encoding (ALU op in bits 12..8, R2P at bit 4)
--   * same single-cycle execution model
--   * same dual-port RAM / IO handshake (@pc@ and @daddr@ are the *next*
--     addresses so a synchronous BRAM returns the right word one cycle later)
--   * same interrupt scheme (an IRQ is turned into a CALL to @irq_addr@)
--   * same CPU-hold (@stop@) line
--
--   The VHDL generics become type-level parameters (@n@ = log2 stack size,
--   @i@ = interrupt address width) or fields of 'H2Config'.
module H2
  ( -- * Types
    Cell, Addr
  , H2Config (..), hardwareCpuId, simulationCpuId, defaultConfig
  , H2In (..), H2Out (..), H2State (..)
    -- * Core
  , h2, step
    -- * Synthesis entry point
  , topEntity
  ) where

import Clash.Prelude

-- | A machine word.
type Cell = BitVector 16

-- | A program-RAM address (words, not bytes).
type Addr = BitVector 13

-- | Value returned by the @cpu-id@ instruction when synthesised.
hardwareCpuId :: Cell
hardwareCpuId = 0x0666

-- | Value the original test bench uses for @cpu-id@.
simulationCpuId :: Cell
simulationCpuId = 0x1984

-- | Run-time generics of the VHDL entity.
data H2Config = H2Config
  { cpuId         :: Cell   -- ^ value of the CPU ID instruction
  , startAddress  :: Addr   -- ^ initial program counter
  , useInterrupts :: Bool   -- ^ enable the interrupt logic
  } deriving (Show, Generic, NFDataX)

defaultConfig :: H2Config
defaultConfig = H2Config
  { cpuId         = hardwareCpuId
  , startAddress  = 0
  , useInterrupts = True
  }

-- | Inputs to the core. Field order matches the VHDL port list.
data H2In i = H2In
  { stopIn    :: Bool         -- ^ assert to hold the core in place
  , ioDin     :: Cell         -- ^ data from IO register selected by @io_daddr@
  , irqIn     :: Bool         -- ^ interrupt request
  , irqAddrIn :: BitVector i  -- ^ interrupt vector (ISR number)
  , insn      :: Cell         -- ^ instruction at the previously requested @pc@
  , din       :: Cell         -- ^ RAM data at the previously requested @daddr@
  } deriving (Show, Generic, NFDataX)

-- | Outputs of the core.
data H2Out = H2Out
  { ioWr    :: Bool  -- ^ IO write strobe
  , ioRe    :: Bool  -- ^ IO read strobe (reads may have side effects)
  , ioDout  :: Cell  -- ^ IO write data
  , ioDaddr :: Cell  -- ^ IO address (full 16 bits, low bit is meaningful)
  , pcOut   :: Addr  -- ^ *next* program counter, feed to instruction port
  , dwe     :: Bool  -- ^ RAM write enable
  , dre     :: Bool  -- ^ RAM read enable
  , dout    :: Cell  -- ^ RAM write data
  , daddr   :: Addr  -- ^ RAM address (word address, low bit of T discarded)
  } deriving (Show, Generic, NFDataX)

-- | Architectural state held in flip-flops (the two stacks live in
--   distributed RAM and are not part of this record).
data H2State n i = H2State
  { pc       :: Addr
  , stop     :: Bool         -- ^ registered hold line; core starts stopped
  , vstkp    :: Unsigned n   -- ^ variable (data) stack pointer
  , rstkp    :: Unsigned n   -- ^ return stack pointer
  , tos      :: Cell         -- ^ top of data stack
  , irqAddrR :: BitVector i  -- ^ registered interrupt vector
  , irqEnR   :: Bool         -- ^ interrupts enabled
  , irqR     :: Bool         -- ^ registered interrupt request
  } deriving (Show, Generic, NFDataX)

resetState :: (KnownNat n, KnownNat i) => H2Config -> H2State n i
resetState cfg = H2State
  { pc       = startAddress cfg
  , stop     = True   -- VHDL: stop_c starts/resets to '1'
  , vstkp    = 0
  , rstkp    = 0
  , tos      = 0
  , irqAddrR = 0
  , irqEnR   = False
  , irqR     = False
  }

-- | The H2 core.  @n@ is log2 of the stack depth (VHDL default 6 = 64
--   entries), @i@ is the interrupt-vector width (VHDL default 3).
h2
  :: forall dom n i
   . (HiddenClockResetEnable dom, KnownNat n, KnownNat i)
  => H2Config
  -> Signal dom (H2In i)
  -> Signal dom H2Out
h2 cfg inp = out
  where
    st :: Signal dom (H2State n i)
    st = register (resetState cfg) st'

    -- Stacks: asynchronous read at the *current* pointer, synchronous write
    -- at the *next* pointer, exactly as the VHDL (infers distributed RAM).
    nos  = asyncRamPow2 (vstkp <$> st) dWr
    rtos = asyncRamPow2 (rstkp <$> st) rWr

    (st', out, dWr, rWr) = unbundle (step cfg <$> st <*> inp <*> nos <*> rtos)

-- | One cycle of combinational logic.  Returns the next state, the outputs,
--   and the data/return stack write requests.
step
  :: forall n i
   . (KnownNat n, KnownNat i)
  => H2Config
  -> H2State n i
  -> H2In i
  -> Cell   -- ^ next on stack (read from data-stack RAM)
  -> Cell   -- ^ top of return stack (read from return-stack RAM)
  -> (H2State n i, H2Out, Maybe (Unsigned n, Cell), Maybe (Unsigned n, Cell))
step cfg H2State{..} H2In{..} nos rtos = (st', out, dWr, rWr)
  where
    ---------------------------------------------------------------- decode
    isInterrupt = irqR && irqEnR && useInterrupts cfg

    instruction :: Cell
    instruction
      | stop        = (0b000 :: BitVector 3) ++# pc          -- branch to self
      | isInterrupt = 0x4000 .|. resize irqAddrR              -- CALL irq_addr
      | otherwise   = insn

    top3       = slice d15 d13 instruction
    isBranch   = top3 == 0b000
    isBranch0  = top3 == 0b001
    isCall     = top3 == 0b010
    isAlu      = top3 == 0b011
    isLit      = testBit instruction 15
    isRamWrite = isAlu && testBit instruction 5             -- N2A

    -- stack deltas: 2-bit two's complement, sign extended to pointer width
    delta :: BitVector 2 -> Unsigned n
    delta b = bitCoerce (resize (unpack b :: Signed 2) :: Signed n)
    dd = delta (slice d1 d0 instruction)
    rd = delta (slice d3 d2 instruction)

    pcPlusOne = pc + 1

    ------------------------------------------------------------- compares
    more  = (unpack tos :: Signed 16) > unpack nos   -- signed   T > N
    umore = tos > nos                                -- unsigned T > N
    equal = tos == nos
    zero  = tos == 0

    mask :: Bool -> Cell
    mask b = if b then maxBound else 0

    ------------------------------------------------------------------ ALU
    aluop :: BitVector 5
    aluop
      | isLit     = 0b10101
      | isBranch0 = 0b00001
      | isAlu     = slice d12 d8 instruction
      | otherwise = 0

    shamt = fromIntegral (unpack (slice d3 d0 tos) :: Unsigned 4) :: Int

    -- (next TOS, io read strobe, next interrupt-enable)
    (tos', ioReS, irqEn') = case aluop of
      -- register operations
      0b00000 -> (tos,                               False, irqEnR)
      0b00001 -> (nos,                               False, irqEnR)
      0b01011 -> (rtos,                              False, irqEnR)
      0b10100 -> (cpuId cfg,                         False, irqEnR)
      0b10101 -> (resize (slice d14 d0 instruction), False, irqEnR) -- literal
      -- logical operations
      0b00011 -> (tos .&. nos,                       False, irqEnR)
      0b00100 -> (tos .|. nos,                       False, irqEnR)
      0b00101 -> (tos `xor` nos,                     False, irqEnR)
      0b00110 -> (complement tos,                    False, irqEnR)
      -- comparisons
      0b00111 -> (mask equal,                        False, irqEnR)
      0b01000 -> (mask more,                         False, irqEnR)
      0b01111 -> (mask umore,                        False, irqEnR)
      0b10011 -> (mask zero,                         False, irqEnR)
      -- arithmetic
      0b01001 -> (nos `shiftR` shamt,                False, irqEnR)
      0b01101 -> (nos `shiftL` shamt,                False, irqEnR)
      0b00010 -> (nos + tos,                         False, irqEnR)
      0b01010 -> (tos - 1,                           False, irqEnR)
      -- load: 0x4000..0xFFFF is IO space, otherwise program RAM
      0b01100 | slice d15 d14 tos /= 0 -> (ioDin,    True,  irqEnR)
              | otherwise              -> (din,      False, irqEnR)
      -- stack depths
      0b01110 -> (resize (pack vstkp),               False, irqEnR)
      0b10010 -> (resize (pack rstkp),               False, irqEnR)
      -- CPU status get / set
      0b10001 -> (if irqEnR then 1 else 0,           False, irqEnR)
      0b10000 -> (nos,                               False, testBit tos 0)
      -- invalid
      _       -> (tos,                               False, irqEnR)

    --------------------------------------------------------- stack update
    vstkp'
      | isLit     = vstkp + 1
      | isAlu     = vstkp + dd
      | isBranch0 = vstkp - 1
      | otherwise = vstkp

    rstkp'
      | isAlu     = rstkp + rd
      | isCall    = rstkp + 1
      | otherwise = rstkp

    dstkWe = isLit || (isAlu && testBit instruction 7)      -- T2N
    rstkWe = (isAlu && testBit instruction 6) || isCall     -- T2R / CALL

    retAddr :: Addr -> Cell
    retAddr a = (0b00 :: BitVector 2) ++# a ++# (0b0 :: BitVector 1)

    rstkData
      | isCall && isInterrupt = retAddr pc         -- re-execute interrupted insn
      | isCall                = retAddr pcPlusOne
      | otherwise             = tos                -- T2R

    dWr = if dstkWe then Just (vstkp', tos)      else Nothing
    rWr = if rstkWe then Just (rstkp', rstkData) else Nothing

    ------------------------------------------------------------ PC update
    pc'
      | isBranch || (isBranch0 && zero) || isCall = slice d12 d0 instruction
      | isAlu && testBit instruction 4            = slice d13 d1 rtos  -- R2P
      | otherwise                                 = pcPlusOne

    ------------------------------------------------------------- outputs
    out = H2Out
      { ioWr    = isRamWrite && slice d15 d14 tos /= 0
      , ioRe    = ioReS
      , ioDout  = nos
      , ioDaddr = tos
      , pcOut   = pc'
      , dwe     = isRamWrite && slice d15 d14 tos == 0
      , dre     = slice d15 d14 tos' == 0
      , dout    = nos
      , daddr   = if isRamWrite then slice d13 d1 tos else slice d13 d1 tos'
      }

    st' = H2State
      { pc       = pc'
      , stop     = stopIn
      , vstkp    = vstkp'
      , rstkp    = rstkp'
      , tos      = tos'
      , irqAddrR = irqAddrIn
      , irqEnR   = irqEn'
      , irqR     = irqIn
      }

-- | Stand-alone synthesis entry point with the VHDL defaults
--   (64-entry stacks, 8 interrupt vectors, hardware CPU ID).
topEntity
  :: Clock System
  -> Reset System
  -> Enable System
  -> Signal System (H2In 3)
  -> Signal System H2Out
topEntity = exposeClockResetEnable (h2 @System @6 @3 defaultConfig)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "h2"
    , t_inputs =
        [ PortName "clk", PortName "rst", PortName "en"
        , PortProduct ""
            [ PortName "stop", PortName "io_din", PortName "irq"
            , PortName "irq_addr", PortName "insn", PortName "din" ]
        ]
    , t_output = PortProduct ""
        [ PortName "io_wr", PortName "io_re", PortName "io_dout", PortName "io_daddr"
        , PortName "pc", PortName "dwe", PortName "dre", PortName "dout", PortName "daddr" ]
    }) #-}
