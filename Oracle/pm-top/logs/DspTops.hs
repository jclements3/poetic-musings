module DspTops where
import Clash.Prelude
import PM.Ddc (ddc)
import Maiden.Cfar (cfar)
import Maiden.Cic (cic)
import Maiden.Fir (fir, compCoeffs)

ddcTop :: Clock System -> Reset System -> Enable System -> Signal System (Unsigned 32) -> Signal System (Signed 12) -> Signal System (Signed 16, Signed 16, Bool)
ddcTop = exposeClockResetEnable (ddc (SNat @512))
{-# NOINLINE ddcTop #-}
{-# ANN ddcTop (Synthesize { t_name = "pm_ddc", t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "fw", PortName "adc"], t_output = PortName "out" }) #-}

cfarTop :: Clock System -> Reset System -> Enable System -> Signal System (Unsigned 18) -> Signal System (Bool, Unsigned 18)
cfarTop = exposeClockResetEnable (cfar 80)
{-# NOINLINE cfarTop #-}
{-# ANN cfarTop (Synthesize { t_name = "maiden_cfar", t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "mag"], t_output = PortName "out" }) #-}

cicTop :: Clock System -> Reset System -> Enable System -> Signal System (Signed 12) -> Signal System (Signed 39, Bool)
cicTop = exposeClockResetEnable (cic (SNat @3) (SNat @512))
{-# NOINLINE cicTop #-}
{-# ANN cicTop (Synthesize { t_name = "maiden_cic512", t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "x"], t_output = PortName "out" }) #-}

firTop :: Clock System -> Reset System -> Enable System -> Signal System (Signed 18) -> Signal System (Signed 38)
firTop = exposeClockResetEnable (fir compCoeffs)
{-# NOINLINE firTop #-}
{-# ANN firTop (Synthesize { t_name = "maiden_fir", t_inputs = [PortName "clk", PortName "rst", PortName "en", PortName "x"], t_output = PortName "y" }) #-}
