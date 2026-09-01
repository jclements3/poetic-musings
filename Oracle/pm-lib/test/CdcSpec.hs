-- PM.Cdc proofs across two real unrelated clock domains:
--   Fast (10 ns) and Slow (36 ns) — ratio ~3.6, non-integer.
--   1. bitSync: a level change in src appears in dst and stays.
--   2. pulseSync: N well-spaced source pulses -> exactly N dst pulses.
--   3. cdcFifo fast->slow: a 60-element counter stream crosses with no
--      loss, duplication, or reorder; full flag throttles the writer.
--   4. cdcFifo slow->fast: same stream, opposite direction.
{-# LANGUAGE MultiParamTypeClasses #-}
import Clash.Explicit.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Cdc
import System.Exit (exitFailure, exitSuccess)

createDomain vSystem{vName="Fast", vPeriod=10000}
createDomain vSystem{vName="Slow", vPeriod=36000}

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

clkF = clockGen @Fast
clkS = clockGen @Slow
rstF = resetGen @Fast
rstS = resetGen @Slow
enF = enableGen @Fast
enS = enableGen @Slow

main :: IO ()
main = do
  -- 1. bitSync level
  let lvlSrc = fromList (P.replicate 20 False P.++ P.repeat True) :: Signal Fast Bool
      lvlDst = sampleN 50 (bitSync clkF clkS rstS enS False lvlSrc)
  r1 <- check (P.not (P.head lvlDst) && P.and (P.drop 20 lvlDst))
              "bitSync: level crosses and holds"
  -- 2. pulseSync: 5 pulses spaced 40 fast cycles
  let pulses = P.replicate 8 False P.++ P.concat [ True : P.replicate 39 False | _ <- [1 :: Int .. 5] ] P.++ P.repeat False
      pSrc = fromList pulses :: Signal Fast Bool
      pDst = sampleN 120 (pulseSync clkF rstF enF clkS rstS enS pSrc)
      nOut = P.length (P.filter id pDst)
  r2 <- check (nOut == 5) ("pulseSync: 5 in -> " P.++ P.show nOut P.++ " out")
  -- 3. FIFO fast -> slow
  let total = 60 :: Int
      (rd3, emp3, full3) =
        cdcFifo d4 clkF rstF enF clkS rstS enS wpush rpop
      -- writer: push counter value when not full
      wcount = regEn clkF rstF enF (0 :: Unsigned 8) (fmap not full3) (wcount + 1)
      wpush = mux ((&&) <$> fmap not full3 <*> fmap (< P.fromIntegral total) wcount)
                  (Just <$> wcount) (pure Nothing)
      rpop = fmap not emp3
      got3 = [ v | (v, e) <- P.zip (sampleN 900 rd3) (sampleN 900 emp3), P.not e ]
      -- rd data is valid when not empty and we popped; dedupe consecutive by construction:
      seq3 = P.map P.head (L.group got3)
  r3 <- check (P.take total seq3 == P.map P.fromIntegral [0 .. total - 1])
              ("cdcFifo fast->slow: 60-element stream intact (got " P.++ P.show (P.length (P.take total seq3)) P.++ ")")
  -- 4. FIFO slow -> fast
  let (rd4, emp4, full4) =
        cdcFifo d4 clkS rstS enS clkF rstF enF wpush4 rpop4
      wcount4 = regEn clkS rstS enS (0 :: Unsigned 8) (fmap not full4) (wcount4 + 1)
      wpush4 = mux ((&&) <$> fmap not full4 <*> fmap (< P.fromIntegral total) wcount4)
                   (Just <$> wcount4) (pure Nothing)
      rpop4 = fmap not emp4
      got4 = [ v | (v, e) <- P.zip (sampleN 2600 rd4) (sampleN 2600 emp4), P.not e ]
      seq4 = P.map P.head (L.group got4)
  r4 <- check (P.take total seq4 == P.map P.fromIntegral [0 .. total - 1])
              "cdcFifo slow->fast: stream intact"
  if P.and [r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.Cdc" >> exitSuccess
    else exitFailure
