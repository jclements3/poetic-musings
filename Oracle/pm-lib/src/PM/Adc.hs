-- PM.Adc — the slider digitizer: an MCP3208 (12-bit, 8-channel, SPI)
-- sequencer that continuously scans the three zone sliders S2/S3/S4 plus
-- one "aux" channel chosen by oPanelCtrl (S0 volume / S1 balance / spare),
-- feeding PM.Zones its samples and the 0x4022 iAdc register its raw word
-- (Oracle/eforth-pm.md: oPanelCtrl ADC mux, iAdc raw 12-bit).
--
-- Framing is the standard 3-byte MCP3208 exchange (24 SCLKs per
-- conversion, CS low throughout): TX = 0000_011,D2 | D1,D0,xxxxxx | dont-
-- care, and the 12 result bits land exactly in RX[11:0].  SPI mode 0,0:
-- MOSI changes on the falling edge, MISO is sampled on the rising edge.
-- The half-period divisor is a port; at the ULX3S 25 MHz clock a divisor
-- of 16 gives 781 kHz SCLK — inside the MCP3208's 1 MHz limit at 3.3 V —
-- and a full 4-channel sweep every ~140 us, far faster than a finger.
--
-- Channel plan (LAYOUT panel): 0 = S2, 1 = S3, 2 = S4, aux = 3..7 by the
-- oPanelCtrl mux field (3 = S0 volume, 4 = S1 balance).

{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions

module PM.Adc where

import Clash.Prelude
import PM.Ulx25 (Ulx25)

-- | Conversion command word for a channel, 3-byte framing (module header).
adcCmd :: BitVector 3 -> BitVector 24
adcCmd ch = b0 ++# b1 ++# (0 :: BitVector 8)
 where
  b0 = 0x06 .|. (zeroExtend (slice d2 d2 ch) :: BitVector 8)
  b1 = slice d1 d0 ch ++# (0 :: BitVector 6)

data Phase = Gap | Low | High
  deriving (Generic, NFDataX, Eq)

data AdcSt = AdcSt
  { aPhase :: !Phase
  , aCnt   :: !(Unsigned 8)         -- ^ ticks left in the current phase
  , aBit   :: !(Index 25)           -- ^ SCLKs left in the transfer
  , aTx    :: !(BitVector 24)
  , aRx    :: !(BitVector 24)
  , aCh    :: !(Index 4)            -- ^ 0..2 = S2/S3/S4, 3 = aux
  , aOut   :: !(Vec 3 (Unsigned 12))
  , aAux   :: !(Unsigned 12)
  } deriving (Generic, NFDataX)

data AdcOut = AdcOut
  { aoCs      :: !Bit               -- ^ chip select, active low
  , aoSclk    :: !Bit
  , aoMosi    :: !Bit
  , aoSliders :: !(Vec 3 (Unsigned 12))  -- ^ S2, S3, S4 held samples
  , aoAux     :: !(Unsigned 12)          -- ^ the muxed aux channel (iAdc)
  , aoTick    :: !Bool              -- ^ one-cycle pulse: a sweep completed
  } deriving (Generic, NFDataX)

-- | CS-high gap between conversions, in half-period units (MCP3208 needs
--   CS high to end a conversion; 2 half-periods is comfortably beyond
--   t_CSH at any usable divisor).
gapHp :: Unsigned 8
gapHp = 2

adcT :: AdcSt -> (Unsigned 8, BitVector 3, Bit) -> (AdcSt, AdcOut)
adcT s@AdcSt{..} (hp, auxSel, miso) = (s', out)
 where
  out = AdcOut
    { aoCs      = if aPhase == Gap then 1 else 0
    , aoSclk    = if aPhase == High then 1 else 0
    , aoMosi    = msb aTx
    , aoSliders = aOut
    , aoAux     = aAux
      -- the cycle the aux conversion retires = a full S2/S3/S4/aux sweep
    , aoTick    = aCnt == 0 && aPhase == High && aBit == 1 && aCh == 3
    }

  s' | aCnt /= 0 = s { aCnt = aCnt - 1 }
     | otherwise = case aPhase of
         -- gap over: start the next conversion
         Gap  -> s { aPhase = Low, aCnt = hp - 1, aBit = 24
                   , aTx = adcCmd (chSel aCh auxSel), aRx = 0 }
         -- rising edge: sample MISO
         Low  -> s { aPhase = High, aCnt = hp - 1
                   , aRx = aRx `shiftL` 1 .|. zeroExtend (pack miso) }
         -- falling edge: bit done; next bit or end of transfer
         High
           | aBit == 1 ->
               let v = unpack (slice d11 d0 aRx) :: Unsigned 12
                   done = aCh == 3
               in s { aPhase = Gap, aCnt = gapHp * hp - 1
                    , aCh = satSucc SatWrap aCh
                    , aOut = if aCh <= 2 then replace (resize aCh :: Index 3) v aOut else aOut
                    , aAux = if done then v else aAux }
           | otherwise ->
               s { aPhase = Low, aCnt = hp - 1
                 , aBit = aBit - 1, aTx = aTx `shiftL` 1 }

  chSel :: Index 4 -> BitVector 3 -> BitVector 3
  chSel 3 sel = if sel <= 2 then 3 else sel   -- aux mux; sliders shadowed to S0
  chSel c _   = pack (resize c :: Index 8)

adc
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 8)        -- ^ SCLK half-period, ticks (>= 1)
  -> Signal dom (BitVector 3)       -- ^ aux channel select (oPanelCtrl field)
  -> Signal dom Bit                 -- ^ MISO
  -> Signal dom AdcOut
adc hp auxSel miso = mealy adcT ini (bundle (hp, auxSel, miso))
 where
  ini = AdcSt Gap 4 24 0 0 0 (repeat 0) 0

topEntity
  :: Clock Ulx25 -> Reset Ulx25 -> Enable Ulx25
  -> Signal Ulx25 (Unsigned 8)
  -> Signal Ulx25 (BitVector 3)
  -> Signal Ulx25 Bit
  -> Signal Ulx25 AdcOut
topEntity clk rst en = withClockResetEnable clk rst en adc
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_adc"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "half_period", PortName "aux_sel", PortName "miso" ]
    , t_output = PortName "adc"
    }) #-}
