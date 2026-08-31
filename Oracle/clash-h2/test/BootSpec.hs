{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | Boot the /real/ eForth image (@h2.bin@, built from upstream
--   @embed.fth@) in Clash simulation, type @2 3 + . cr@ at it over the
--   UART model, and check the console transcript.
--
--   Expected behaviour (cross-checked against the upstream C simulator,
--   which with an nvram image prints the same banner/values but
--   @loading... ok@):
--
--   > eFORTH v666
--   >  1A0C 25F4
--   > loading... ok           (transfer from empty flash "succeeds"...)
--   > failed                  (...but block 1 holds no ASCII: no nvram here)
--   > 2 3 + . cr 5
--
--   The line terminator is a bare CR (0x0D): eForth's @ktap@ ends a line
--   on @=cr@ ($D) and the upstream simulator's @getch@ clears ICRNL so the
--   CPU sees CR when Enter is pressed.
module Main (main) where

import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import Data.Char (chr, ord, isPrint)
import System.Exit (exitFailure)
import System.IO (hPutStr, hPutStrLn, hFlush, stderr)
import Control.Monad (when)
import Data.Time.Clock (getCurrentTime, diffUTCTime)

import H2.SystemUart (h2SystemSim)

-- | Bytes typed at the eForth console.
consoleInput :: String
consoleInput = "2 3 + . cr\r"

-- | Upper bound on simulated cycles.  The run stops early once the
--   expected output has been seen — a passing boot takes ~15.4M cycles
--   (~1 minute of wall time), dominated by eForth's cold-boot @transfer@
--   of 32KB from the (absent here) flash.
maxCycles :: Int
maxCycles = 30000000

-- | The part of @s@ after the first occurrence of @needle@ (or @""@).
after :: String -> String -> String
after needle s = case L.filter (needle `L.isPrefixOf`) (L.tails s) of
  (t:_) -> P.drop (P.length needle) t
  []    -> ""

-- | Success: the banner appeared, and a @5@ was printed after the echoed
--   command line.
bootedOk :: String -> Bool
bootedOk t = "eFORTH" `L.isInfixOf` t
          && "5" `L.isInfixOf` after "cr" (after "eFORTH" t)

main :: IO ()
main = do
  t0 <- getCurrentTime
  let script = P.map (fromIntegral . ord) consoleInput
      -- sampleN provides the hidden clock/reset/enable of the System domain
      txSamples = sampleN @System maxCycles
                    (h2SystemSim (blockRamFilePow2 "h2.bin")
                                 (blockRamFilePow2 "h2.bin")
                                 script)
      -- consume lazily, streaming progress to stderr, stopping as soon as
      -- the expected transcript is seen
      run acc [] = pure (acc, maxCycles)
      run acc ((n, mb) : rest) = do
        when (n `P.mod` 1000000 == 0) $ do
          hPutStrLn stderr ("[cycle " P.++ show n P.++ "]")
          hFlush stderr
        case mb of
          Nothing -> run acc rest
          Just b  -> do
            let c    = chr (fromIntegral b)
                acc' = acc P.++ [c]
            hPutStr stderr (render c)
            hFlush stderr
            if bootedOk acc' then pure (acc', n) else run acc' rest

  (transcript, lastCycle) <- run "" (P.zip [(0 :: Int) ..] txSamples)

  putStrLn "---- decoded eForth console transcript ----"
  putStrLn (P.concatMap render transcript)
  putStrLn "-------------------------------------------"
  t1 <- transcript `seqX` getCurrentTime
  putStrLn ("tx bytes: " P.++ show (P.length transcript)
            P.++ ", last tx at cycle " P.++ show lastCycle
            P.++ ", wall time " P.++ show (diffUTCTime t1 t0))

  if bootedOk transcript
    then putStrLn "PASS: eForth booted and computed 2 3 + = 5"
    else do
      putStrLn "FAIL: expected banner + \"5\" not found in transcript"
      exitFailure
  where
    render c
      | c == '\n'          = "\n"
      | c == '\r'          = ""
      | isPrint c          = [c]
      | otherwise          = "<" P.++ show (ord c) P.++ ">"
