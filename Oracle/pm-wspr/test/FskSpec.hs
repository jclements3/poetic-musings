-- PM.Wspr FSK-level check: a REAL WSPR symbol table drives the sequencer and
-- the phase_inc stream must reproduce the expected 4-FSK tone frequencies.
--
-- Table: "K1ABC FN42 37" from golden/wspr_model.py, cross-checked symbol for
-- symbol against the independent golden/wspr_ref.py
--   (cd golden && python3 wspr_ref.py K1ABC FN42 37).
-- NCO model: f_nco = 100 MHz, tone 0 at 1500 Hz (audio/IF offset; the RF
-- mix is outside this block), toneStep = round(12000/8192 Hz * 2^32 / f_nco).
--  1. tone frequency of every symbol period = 1500 + sym * 1.4648 Hz within
--     0.05 Hz (NCO LSB is 0.023 Hz; base + 3 tone-step roundings < 0.02 Hz).
--  2. exactly 162 symbol periods, in table order.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Wspr
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) P.>> P.pure ok

fNco, baud, f0 :: Double
fNco = 100e6
baud = 12000 / 8192
f0   = 1500

symDiv :: Unsigned 32
symDiv = 4

baseInc, toneStep :: Unsigned 32
baseInc  = P.round (f0 * 2 P.^ (32 :: Int) / fNco)     -- 64425
toneStep = P.round (baud * 2 P.^ (32 :: Int) / fNco)   -- 63

-- K1ABC FN42 37 (wspr_model == wspr_ref)
table :: [Unsigned 2]
table = [3,3,0,0,2,0,0,0,1,0,2,0,1,3,1,2,2,2,1,0,0,3,2,3,1,3,3,2,2,0,2,0,0,0,3,2,0,1,2,3,2,2,0,0,2,2,3,2,1,1,0,2,3,3,2,1,0,2,2,1,3,2,1,2,2,2,0,3,3,0,3,0,3,0,1,2,1,0,2,1,2,0,3,2,1,3,2,0,0,3,3,2,3,0,3,2,2,0,3,0,2,0,2,0,1,0,2,3,0,2,1,1,1,2,3,3,0,2,3,1,2,1,2,2,2,1,3,3,2,0,0,0,0,1,0,3,2,0,1,3,2,2,2,2,2,0,2,3,3,2,3,2,3,3,2,0,0,3,1,2,2,2]

startAt :: Int
startAt = 165

stim :: Int -> [(Maybe (Unsigned 8, Unsigned 2), Bool, Bool, Unsigned 32, Unsigned 32, Unsigned 32)]
stim n =
  [ (wr, True, t == startAt, symDiv, baseInc, toneStep)
  | t <- [0 .. n - 1]
  , let wr = if t < 162 then Just (fromIntegral t, table P.!! t) else Nothing ]

toHz :: Unsigned 32 -> Double
toHz inc = P.fromIntegral inc * fNco / 2 P.^ (32 :: Int)

main :: IO ()
main = do
  let n = startAt + 162 * fromIntegral symDiv + 20
      out = simulateN @System n
              (\i -> let (wr, a, s, d, b, ts) = unbundle i
                         (sym, tx, pinc, dn) = wspr wr a s d b ts
                     in bundle (sym, tx, pinc, dn))
              (stim n)
      onInc  = [ pinc | (_, tx, pinc, _) <- out, tx ]
      tones  = P.map P.head (L.group onInc)   -- adjacent equal symbols merge; compare held stream instead
      held   = P.map toHz onInc
      expect = P.concatMap (P.replicate (fromIntegral symDiv))
                 [ f0 + P.fromIntegral s * baud | s <- table ]
      errs   = P.zipWith (\a b -> P.abs (a - b)) held expect
  r1 <- check (P.length held == P.length expect && P.maximum errs < 0.05)
          ("162 x " P.++ P.show symDiv P.++ " clocks of phase_inc give f0 + sym*1.4648 Hz, max error "
           P.++ P.show (P.maximum errs) P.++ " Hz over " P.++ P.show (P.length tones) P.++ " tone runs")
  r2 <- check (P.length table == 162 && P.all (`P.elem` table) [0, 1, 2, 3])
          "table has 162 symbols using all four tones"
  if r1 P.&& r2 then putStrLn "ALL PASS: PM.Wspr FSK" P.>> exitSuccess else exitFailure
