-- PM.Spi proof: master against a behavioral mode-0 slave shift register.
-- Asserts, at two dividers: full-duplex exchange (master receives the
-- slave's byte, slave captures the master's), and exactly 8 SCK rising
-- edges per transfer.
import Clash.Prelude
import qualified Prelude as P
import PM.Spi
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- one full exchange; returns (rx byte seen by master, slave shift reg after,
-- number of SCK rising edges)
exchange :: Unsigned 16 -> BitVector 8 -> BitVector 8
         -> (Maybe (BitVector 8), BitVector 8, Int)
exchange halfT txB slaveB =
  let n = 800
      rows = sampleN @System n sys
      rx = case [ r | ((_, _, _, Just r), _) <- rows ] of
             (r : _) -> Just r
             []      -> Nothing
      scks = [ s | ((s, _, _, _), _) <- rows ]
      edges = P.length [ () | (a, b) <- P.zip scks (P.drop 1 scks), not a, b ]
      slaveEnd = P.last [ g | (_, g) <- rows ]
  in (rx, slaveEnd, edges)
 where
  sys :: HiddenClockResetEnable dom
      => Signal dom ((Bool, Bit, Bool, Maybe (BitVector 8)), BitVector 8)
  sys = bundle (mo, slaveReg)
   where
    rdyR = register True ((\(_, _, r, _) -> r) <$> mo)
    req = mealy (\sent rdy -> if not sent && rdy then (True, Just txB) else (sent, Nothing))
                False rdyR
    mo = spiMaster (pure halfT) req (msb <$> slaveReg)
    slaveReg = mealy
      (\(sh, pv) (sck, mosi) ->
         let sh' = if sck && not pv then shiftL sh 1 .|. resize (pack mosi) else sh
         in ((sh', sck), sh))   -- expose PRE-shift value: MSB stable through the edge
      (slaveB, False)
      (bundle ((\(s, _, _, _) -> s) <$> mo, (\(_, m, _, _) -> m) <$> mo))

main :: IO ()
main = do
  let (rx1, sl1, e1) = exchange 2 0xA5 0x3C
  r1 <- check (rx1 == Just 0x3C) ("master rx = slave byte 0x3C: " P.++ P.show rx1)
  r2 <- check (sl1 == 0xA5) ("slave captured master byte 0xA5: " P.++ P.show sl1)
  r3 <- check (e1 == 8) ("exactly 8 SCK rising edges: " P.++ P.show e1)
  let (rx2, sl2, e2) = exchange 9 0x96 0x81
  r4 <- check (rx2 == Just 0x81 && sl2 == 0x96 && e2 == 8)
              ("slow divider exchange (0x96 <-> 0x81, 8 edges): "
               P.++ P.show (rx2, sl2, e2))
  if P.and [r1, r2, r3, r4]
    then putStrLn "ALL PASS: PM.Spi" >> exitSuccess
    else exitFailure
