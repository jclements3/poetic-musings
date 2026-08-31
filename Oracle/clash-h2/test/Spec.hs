{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | Smoke test: run a five-word hand-assembled program on the core and
--   check that it lights the LEDs.
--
--   @
--   0: 80A5   lit 0xA5              ( 0xA5 )
--   1: C004   lit 0x4004            ( 0xA5 0x4004 )
--   2: 6123   alu N  N2A d-1        ( 0xA5 )   -- writes N to [T] = oLeds
--   3: 6103   alu N  d-1            ( )        -- drop
--   4: 0004   branch 4              -- spin
--   @
module Main (main) where

import Clash.Prelude
import qualified Prelude as P
import System.Exit (exitFailure)

import H2 (Cell)
import H2.System (h2SystemWith)

program :: Vec 8192 Cell
program = (0x80A5 :> 0xC004 :> 0x6123 :> 0x6103 :> 0x0004 :> Nil) ++ repeat 0

main :: IO ()
main = do
  let out = sampleN @System 32
              (h2SystemWith (blockRamPow2 program) (blockRamPow2 program) (pure 0))
  putStrLn ("LED trace: " P.++ show out)
  if 0xA5 `P.elem` out
    then putStrLn "PASS: H2 wrote 0xA5 to oLeds"
    else putStrLn "FAIL: LEDs never became 0xA5" >> exitFailure
