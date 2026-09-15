-- PM.Wspr proofs (symDiv = 5 clocks per symbol for simulation speed):
--  1. all 162 loaded symbols come out in order, each held exactly symDiv clocks.
--  2. tx_on is high for exactly 162 * symDiv clocks, then done strobes once.
--  3. not armed: a start strobe never raises tx_on.
--  4. phase_inc == base_inc + symbol * tone_step on every tx_on clock.
--  5. disarm mid-transmission: tx_on is low on the very clock armed drops,
--     and stays low (the walk is aborted, not paused).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Wspr
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) P.>> P.pure ok

symDiv :: Unsigned 32
symDiv = 5

baseInc, toneStep :: Unsigned 32
baseInc = 0x0E6B_0000
toneStep = 0x0000_0195

-- a non-trivial table: every symbol value, no simple period
table :: [Unsigned 2]
table = [ fromInteger ((i * 7 + i `P.div` 3) `P.mod` 4) | i <- [0 .. 161] ]

-- one stimulus stream: load table, idle 3, start strobe, then run;
-- `armF` gives armed as a function of clock index.
stim :: (Int -> Bool) -> Int -> [(Maybe (Unsigned 8, Unsigned 2), Bool, Bool, Unsigned 32, Unsigned 32, Unsigned 32)]
stim armF n =
  [ (wr, armF t, t == startAt, symDiv, baseInc, toneStep)
  | t <- [0 .. n - 1]
  , let wr = if t < 162 then Just (fromIntegral t, table P.!! t) else Nothing ]

startAt :: Int
startAt = 165

run :: (Int -> Bool) -> Int -> [(Unsigned 2, Bool, Unsigned 32, Bool)]
run armF n = simulateN @System n
  (\i -> let (wr, a, s, d, b, ts) = unbundle i
             (sym, tx, pinc, dn) = wspr wr a s d b ts
         in bundle (sym, tx, pinc, dn))
  (stim armF n)

main :: IO ()
main = do
  let n = startAt + 162 * fromIntegral symDiv + 20
      out = run (const True) n
      onSyms = [ sym | (sym, tx, _, _) <- out, tx ]
      groups = L.group onSyms
      -- runs of equal *index*: rebuild from symbol changes is ambiguous when
      -- neighbours match, so compare the whole held stream directly
      expected = P.concatMap (P.replicate (fromIntegral symDiv)) table
  r1 <- check (onSyms == expected)
          ("162 symbols in order, each held " P.++ P.show symDiv P.++ " clocks ("
           P.++ P.show (P.length groups) P.++ " runs)")
  let txLen = P.length (P.filter (\(_, tx, _, _) -> tx) out)
      txIdx = [ t | (t, (_, tx, _, _)) <- P.zip [0 :: Int ..] out, tx ]
      contiguous = P.and (P.zipWith (\a b -> b == a + 1) txIdx (P.drop 1 txIdx))
      dones = [ t | (t, (_, _, _, dn)) <- P.zip [0 :: Int ..] out, dn ]
  r2 <- check (txLen == 162 * fromIntegral symDiv && contiguous)
          ("tx_on high for " P.++ P.show txLen P.++ " clocks, contiguous")
  r2b <- check (dones == [P.last txIdx + 1])
          ("done strobes once, right after tx_on falls (" P.++ P.show dones P.++ ")")
  let outU = run (const False) n
  r3 <- check (P.all (\(_, tx, _, _) -> not tx) outU) "unarmed: tx_on never asserts"
  r4 <- check (P.and [ pinc == baseInc + toneStep * resize sym | (sym, tx, pinc, _) <- out, tx ])
          "phase_inc = base_inc + symbol * tone_step throughout"
  let dropAt = startAt + 40 * fromIntegral symDiv + 2
      outD = run (< dropAt) n
      txD = [ t | (t, (_, tx, _, _)) <- P.zip [0 :: Int ..] outD, tx ]
  r5 <- check (P.not (P.null txD) && P.maximum txD == dropAt - 1)
          ("disarm at clock " P.++ P.show dropAt P.++ ": tx_on last high at "
           P.++ P.show (P.maximum txD) P.++ ", never again")
  if P.and [r1, r2, r2b, r3, r4, r5]
    then putStrLn "ALL PASS: PM.Wspr" P.>> exitSuccess
    else exitFailure
