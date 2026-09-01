{-# LANGUAGE RecordWildCards #-}
-- PM.Spi — mode-0 SPI master (CPOL=0, CPHA=0) for the microSD (eforth-pm.md
-- 0x4028) and the slider/audio ADC reader. 8-bit transfers, MSB first,
-- programmable half-period divider, software CS (the register file owns CS
-- so SD multi-byte commands hold it low across transfers).
--
-- Contract: present Just byte on txReq when ready is True; sck idles low;
-- MOSI changes on falling edges, both sides sample on rising edges; rxOut
-- strobes Just received-byte exactly when the transfer completes.
module PM.Spi where

import Clash.Prelude

data SpiSt = SpiSt
  { sBusy :: !Bool
  , sSck  :: !Bool
  , sBits :: !(Unsigned 4)     -- half-edges remaining counts via bit count
  , sShTx :: !(BitVector 8)
  , sShRx :: !(BitVector 8)
  , sCnt  :: !(Unsigned 16)    -- divider countdown
  } deriving (Generic, NFDataX)

spiInit :: SpiSt
spiInit = SpiSt False False 0 0 0 0

-- inputs: (half-period ticks, tx request, MISO)
-- outputs: (sck, mosi, ready, Maybe rx byte)
spiT :: SpiSt -> (Unsigned 16, Maybe (BitVector 8), Bit)
     -> (SpiSt, (Bool, Bit, Bool, Maybe (BitVector 8)))
spiT s@SpiSt{..} (halfT, req, miso)
  | not sBusy = case req of
      Just b  -> (s { sBusy = True, sSck = False, sBits = 8
                    , sShTx = b, sShRx = 0, sCnt = halfT }
                 , (False, msb' b, False, Nothing))
      Nothing -> (s, (False, msb' sShTx, True, Nothing))
  | sCnt /= 0 = (s { sCnt = sCnt - 1 }, (sSck, msb' sShTx, False, Nothing))
  | not sSck
  = -- rising edge: master samples MISO
    let rx' = shiftL sShRx 1 .|. resize (pack miso)
    in (s { sSck = True, sShRx = rx', sCnt = halfT }
       , (True, msb' sShTx, False, Nothing))
  | otherwise
  = -- falling edge: shift TX, count the bit; done after 8 bits
    let tx' = shiftL sShTx 1
        n' = sBits - 1
    in if n' == 0
         then (s { sBusy = False, sSck = False, sBits = 0, sShTx = tx' }
              , (False, msb' tx', True, Just sShRx))
         else (s { sSck = False, sBits = n', sShTx = tx', sCnt = halfT }
              , (False, msb' tx', False, Nothing))
 where
  msb' :: BitVector 8 -> Bit
  msb' v = msb v

spiMaster
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 16)              -- half-period ticks
  -> Signal dom (Maybe (BitVector 8))      -- tx request (accepted when ready)
  -> Signal dom Bit                        -- MISO
  -> Signal dom (Bool, Bit, Bool, Maybe (BitVector 8))
     -- (SCK, MOSI, ready, rx strobe)
spiMaster h req miso = mealy spiT spiInit (bundle (h, req, miso))

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 16)
  -> Signal System (Maybe (BitVector 8))
  -> Signal System Bit
  -> Signal System (Bool, Bit, Bool, Maybe (BitVector 8))
topEntity = exposeClockResetEnable spiMaster
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_spi"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "half_period", PortName "tx_req", PortName "miso" ]
    , t_output = PortName "out"
    }) #-}
