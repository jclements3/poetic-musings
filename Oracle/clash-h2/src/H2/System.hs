{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | A minimal system around the H2 core: 8K x 16 program RAM loaded from a
--   file, plus the two simplest peripherals from the original register map
--   (LEDs at @oLeds = 0x4004@, switches at @iSwitches = 0x4004@).
--
--   The original @ram.vhd@ is a true dual-port block RAM (port A =
--   instruction fetch, port B = data).  Clash's @blockRamFile@ is a
--   read-port + write-port RAM, so we instantiate two of them fed by the
--   same write port.  That is functionally identical and lets the contents
--   be initialised from a file; the cost is 2x block RAM.  Swap in
--   'Clash.Explicit.BlockRam.trueDualPortBlockRam' if BRAM is tight.
module H2.System
  ( Memory
  , h2SystemWith
  , h2System
  , topEntity
  ) where

import Clash.Prelude
import H2 hiding (topEntity)

-- | A 8192-word memory: read address, optional (address, data) write.
type Memory dom
  =  Signal dom (Unsigned 13)
  -> Signal dom (Maybe (Unsigned 13, Cell))
  -> Signal dom Cell

-- | Build the system from two memory instances (instruction port, data
--   port).  Both must be initialised with the same program.
h2SystemWith
  :: forall dom
   . HiddenClockResetEnable dom
  => Memory dom              -- ^ instruction-fetch RAM
  -> Memory dom              -- ^ data RAM
  -> Signal dom (BitVector 8) -- ^ switches (iSwitches)
  -> Signal dom (BitVector 8) -- ^ LEDs (oLeds)
h2SystemWith instrMem dataMem switches = leds
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

    -- oLeds / iSwitches at 0x4004
    ioAddrS = ioDaddr <$> core
    isLedReg = (== 0x4004) <$> ioAddrS

    leds = register 0 $
      mux ((ioWr <$> core) .&&. isLedReg)
          (resize . ioDout <$> core)
          leds

    ioDinS = mux isLedReg (resize <$> switches) (pure 0)

-- | System with program RAM initialised from @h2.bin@ (see @tools/hex2bin.py@
--   to produce it from the project's @embed.hex@).
h2System
  :: HiddenClockResetEnable dom
  => Signal dom (BitVector 8)
  -> Signal dom (BitVector 8)
h2System = h2SystemWith (blockRamFilePow2 "h2.bin") (blockRamFilePow2 "h2.bin")

topEntity
  :: Clock System
  -> Reset System
  -> Enable System
  -> Signal System (BitVector 8)
  -> Signal System (BitVector 8)
topEntity = exposeClockResetEnable h2System
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "h2_system"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en", PortName "switches" ]
    , t_output = PortName "leds"
    }) #-}
