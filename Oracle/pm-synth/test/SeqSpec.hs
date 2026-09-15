-- PM.Seq proofs:
--  1. record 5 notes (durations 1..5 ticks), then PLAY replays the same
--     notes in order, each gated for exactly its recorded tick count, and
--     stops after the last.
--  2. OKP: each key press sounds the next recorded note, one per press.
--  3. overflow: recording 105 notes leaves cmdLen at 100.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import PM.Seq
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

type In = (SeqMode, Maybe (Unsigned 7), Bool)

-- one tick every 4 cycles; a key press is offset by one cycle from the tick
-- so that "held for d ticks" is exact: hold 4d cycles then release 4 cycles.
press :: SeqMode -> Unsigned 7 -> Int -> [In]
press m n d = P.replicate (4 * d) (m, Just n, False) P.++ P.replicate 4 (m, Nothing, False)

withTicks :: [In] -> [In]
withTicks = P.zipWith (\i (m, k, _) -> (m, k, i `P.mod` 4 == 3)) [0 :: Int ..]

sim :: [In] -> [SeqCmd]
sim ins = simulateN @System (P.length ins)
  (\i -> let (m, k, t) = unbundle i in sequencer m k t) ins

-- gate-high runs -> (note, ticks inside the run)
runs :: [(SeqCmd, In)] -> [(Unsigned 7, Int)]
runs xs = [ (cmdNote (P.fst (P.head g)), P.length [ () | (_, (_, _, t)) <- g, t ])
          | g <- L.groupBy (\a b -> on a == on b) xs, on (P.head g) ]
 where on (c, _) = cmdGate c

main :: IO ()
main = do
  let notes = [(40, 1), (42, 2), (44, 3), (45, 4), (47, 5)] :: [(Unsigned 7, Int)]
      recIn = P.replicate 4 (MRec, Nothing, False) P.++ P.concat [ press MRec n d | (n, d) <- notes ]
      playIn = P.replicate 200 (MPlay, Nothing, False)
      ins = withTicks (recIn P.++ playIn)
      outs = sim ins
      playPart = P.drop (P.length recIn) (P.zip outs ins)
      got = runs playPart
  r1 <- check (got P.== notes) ("playback in order with durations: " P.++ P.show got)
  r2 <- check (cmdLen (P.last outs) == 5) "recorded length = 5"
  r3 <- check (not (cmdGate (P.last outs)) && cmdPos (P.last outs) == 5) "play stops after the last entry"
  -- 2. OKP: 3 presses -> first 3 notes, one per press; 6th press wraps
  let okpIn = P.replicate 8 (MOkp, Nothing, False) P.++ P.concat [ press MOkp 60 2 | _ <- [1 :: Int .. 6] ]
      ins2 = withTicks (recIn P.++ okpIn)
      outs2 = sim ins2
      got2 = P.map P.fst (runs (P.drop (P.length recIn) (P.zip outs2 ins2)))
  r4 <- check (got2 P.== [40, 42, 44, 45, 47, 40]) ("okp one entry per press, wraps: " P.++ P.show got2)
  -- 3. overflow
  let ovIn = withTicks (P.replicate 4 (MRec, Nothing, False) P.++ P.concat [ press MRec 50 1 | _ <- [1 :: Int .. 105] ])
      len3 = cmdLen (P.last (sim ovIn))
  r5 <- check (len3 == 100) ("recording stops at 100 (len " P.++ P.show len3 P.++ ")")
  if P.and [r1, r2, r3, r4, r5]
    then putStrLn "ALL PASS: PM.Seq" >> exitSuccess
    else exitFailure
