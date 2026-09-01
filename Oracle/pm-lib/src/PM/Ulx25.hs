-- PM.Ulx25 — the one shared clock domain for pm-lib synthesis targets.
--
-- The ULX3S 25 MHz crystal, same as IRIG/clash's Ulx25.  It lives in its own
-- module so PM.Matrix and PM.Zones can both import it without duplicating the
-- (necessarily orphan) KnownDomain instance `createDomain` generates.

{-# OPTIONS_GHC -Wno-orphans #-}   -- createDomain necessarily makes an orphan KnownDomain

module PM.Ulx25 where

import Clash.Prelude

createDomain vSystem{vName="Ulx25", vPeriod=40000}   -- 25 MHz, 40 ns
