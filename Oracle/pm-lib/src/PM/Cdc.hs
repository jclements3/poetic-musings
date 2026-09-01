-- PM.Cdc — clock-domain crossing primitives for the One Box's five domains
-- (100 sys / ~74 pixel / 65 ADC / 50 RMII / audio; fpga-resource-swag.md).
--
--   * bitSync   : classic 2-flop synchronizer for a quasi-static level.
--   * pulseSync : toggle-based pulse crossing — every source pulse produces
--                 exactly one destination pulse (source pulses must be spaced
--                 further apart than ~3 destination periods).
--   * cdcFifo   : data crossing via Clash's Gray-pointer
--                 asyncFIFOSynchronizer, in a PM push/pop shape.
module PM.Cdc where

import Clash.Explicit.Prelude
import Clash.Explicit.Synchronizer (asyncFIFOSynchronizer)

-- 2-flop level synchronizer. unsafeSynchronizer does the domain move; the
-- two destination registers absorb metastability (in hardware; in simulation
-- they model the settling latency).
bitSync
  :: (KnownDomain src, KnownDomain dst, NFDataX a)
  => Clock src -> Clock dst -> Reset dst -> Enable dst
  -> a
  -> Signal src a
  -> Signal dst a
bitSync cSrc cDst rDst eDst iv x =
  register cDst rDst eDst iv
    (register cDst rDst eDst iv (unsafeSynchronizer cSrc cDst x))

-- Pulse synchronizer: source pulse flips a toggle; destination syncs the
-- toggle and emits a pulse on every observed flip.
pulseSync
  :: (KnownDomain src, KnownDomain dst)
  => Clock src -> Reset src -> Enable src
  -> Clock dst -> Reset dst -> Enable dst
  -> Signal src Bool
  -> Signal dst Bool
pulseSync cS rS eS cD rD eD p = out
 where
  tog = register cS rS eS False (xor <$> tog <*> p)
  togD = bitSync cS cD rD eD False tog
  togD' = register cD rD eD False togD
  out = xor <$> togD <*> togD'

-- Cross-domain FIFO: write side pushes Maybe, read side pops with rinc.
-- Returns (read data, read-side empty, write-side full).
cdcFifo
  :: forall wdom rdom a addr
   . (KnownDomain wdom, KnownDomain rdom, NFDataX a, KnownNat addr, 2 <= addr)
  => SNat addr
  -> Clock wdom -> Reset wdom -> Enable wdom
  -> Clock rdom -> Reset rdom -> Enable rdom
  -> Signal wdom (Maybe a)          -- push
  -> Signal rdom Bool               -- pop
  -> (Signal rdom a, Signal rdom Bool, Signal wdom Bool)
cdcFifo depth cW rW eW cR rR eR wdata rinc =
  asyncFIFOSynchronizer depth cW cR rW rR eW eR rinc wdata
