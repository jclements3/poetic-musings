-- Round-trip proof: the keyer plays "PARIS 73", the decoder — listening to
-- the keyed line alone — must print it back. PARIS is the CW standard word;
-- 73 exercises the digit table.
import qualified Data.Maybe as M
import Clash.Prelude
import qualified Prelude as P
import PM.Keyer
import System.Exit (exitFailure, exitSuccess)

unitT :: Unsigned 24
unitT = 8   -- ticks per CW unit in sim

msg :: P.String
msg = "PARIS 73"

main :: IO ()
main = do
  let n = 6000
      keyed = sampleN @System n (fst3 <$> keyerOut)
      dec   = sampleN @System n decOut
      got   = P.takeWhile (/= '\0') (M.catMaybes dec)
  putStrLn ("keyed marks: " P.++ show (P.length (P.filter id keyed)) P.++ " ticks")
  putStrLn ("decoded: " P.++ show got)
  if got == msg P.++ " "     -- trailing word gap decodes as a final space
    then putStrLn "PASS: keyer->decoder round trip (PARIS 73)" >> exitSuccess
    else putStrLn ("FAIL: expected " P.++ show msg) >> exitFailure
 where
  fst3 (a, _, _) = a

  keyerOut :: Signal System (Bool, Bool, Maybe (Unsigned 8))
  keyerOut = withClockResetEnable clockGen resetGen enableGen system

  decOut :: Signal System (Maybe Char)
  decOut = (\(_, _, d) -> fmap (toEnum . fromIntegral) d) <$> keyerOut

  -- the system under test: a feeder FSM + topEntity's internals, all in one
  system :: HiddenClockResetEnable dom => Signal dom (Bool, Bool, Maybe (Unsigned 8))
  system = out
   where
    (line, busy) = unbundle (keyer (pure unitT) txc)
    dch = decoder (pure unitT) line
    out = bundle (line, busy, fmap (fromIntegral . fromEnum) <$> dch)
    -- feeder: index into msg, advance on accepted char. The busy feedback is
    -- registered — a same-cycle read would be a combinational loop.
    busyR = register False busy
    txc = mealy feedT (0 :: Index 16, False) busyR
    feedT (i, prevBusy) b
      | not b && not prevBusy && fromIntegral i < P.length msg
      = ((i + 1, True), Just (msg P.!! fromIntegral i))
      | otherwise = ((i, b), Nothing)
