-- PM.I2s proofs:
--  1. bit-clock divider: exactly 64 sck rising edges per frame (div 1, 2, 5).
--  2. ws changes one sck before the MSB; ws low during the left slot.
--  3. tx->rx loop returns the same (L,R) pairs for 20 samples incl. extremes.
--  4. rx started mid-frame drops the partial frame, then is correct.
import Clash.Prelude
import qualified Prelude as P
import PM.I2s
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok msg = do
  putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ msg)
  P.pure ok

samples :: Vec 32 (Sample, Sample)
samples =
  (0x7FFFFF, 0x800000) :> (0x800000, 0x7FFFFF) :> (0, 0) :> (1, -1) :>
  (0x123456, 0x654321) :> (-0x123456, -0x654321) :> (0x555555, 0x2AAAAA) :>
  (0x0000FF, 0x00FF00) :> (0x7F0000, 0x00007F) :> (-1, 0x7FFFFF) :>
  (0x400000, 0x3FFFFF) :> (-0x400000, 0x1) :> (0x0F0F0F, 0x707070) :>
  (0x314159, -0x271828) :> (0x2, 0x4) :> (0x7FFFFE, 0x800001) :>
  (0x0C0FFE, 0x0BEEF0) :> (-0x7FFFFF, 0x7FFFFF) :> (0x101010, 0x010101) :>
  (0x0ABCDE, 0x0FEDCB) :> repeat (0, 0)

-- tx driven from `samples`, advancing on every frameStart
txStreams :: Unsigned 8 -> Int -> [(Bit, Bit, Bit, Bool)]
txStreams dv n = sampleN @System n
  (let smp = (samples !!) <$> idx
       idx = regEn (0 :: Index 32) fs (idx + 1)
       (_, _, _, fs) = unbundle (i2sTx (pure dv) smp)
   in i2sTx (pure dv) smp)

-- tx -> rx loop driven from `samples`; the rx pulses only
loopOut :: Unsigned 8 -> Int -> [(Sample, Sample)]
loopOut dv n = [ p | Just p <- sampleN @System n
  (let smp = (samples !!) <$> idx
       idx = regEn (0 :: Index 32) fs (idx + 1)
       (fs, out) = i2sLoop (pure dv) smp
   in out) ]

risingEdges :: [Bit] -> [Int]
risingEdges xs = [ i | (i, (a, b)) <- P.zip [1 ..] (P.zip xs (P.drop 1 xs)), a == 0, b == 1 ]

main :: IO ()
main = do
  -- 1. 64 sck per frame
  let perFrame dv =
        let n = 64 * 2 * P.fromIntegral dv * 6
            st = txStreams dv n
            scks = [ s | (s, _, _, _) <- st ]
            starts = [ i | (i, (_, _, _, f)) <- P.zip [0 :: Int ..] st, f ]
            edges = risingEdges scks
            counts = [ P.length [ e | e <- edges, e > a, e <= b ] | (a, b) <- P.zip starts (P.drop 1 starts) ]
        in P.length counts >= 3 && P.all (== 64) counts
  r1 <- check (P.all perFrame [1, 2, 5]) "64 sck per frame for div 1, 2, 5"
  -- 2. ws timing: L = R = 0x800000 (MSB only)
  let st2 = sampleN @System 2000 (i2sTx (pure 2) (pure (0x800000, 0x800000)))
      edges2 = risingEdges [ s | (s, _, _, _) <- st2 ]
      wsSd i = let (_, w, d, _) = st2 P.!! i in (w, d)
      seen = P.map wsSd edges2
      -- (ws before, sd at the change edge, ws after, sd one edge later)
      -- (the first frame after reset is the all-zero idle frame: skip it)
      trans = P.drop 2
        [ (w0, s1, w1, s2) | ((w0, _), (w1, s1), (_, s2))
                             <- P.zip3 seen (P.drop 1 seen) (P.drop 2 seen), w0 /= w1 ]
      -- after a ws change sampled at edge e: sd at e is the pad (0), sd at e+1 is the MSB (1)
      transOK = P.and [ d == 0 && d' == 1 | (_, d, _, d') <- trans ]
      -- every MSB seen while ws = 0 was preceded by a 1 -> 0 ws change (left slot);
      -- and the left slot is exactly what follows a falling ws
      wsLeftOK = P.and [ w == 1 | (w, _, w', d') <- trans, w' == 0, d' == 1 ] &&
                 P.or  [ w' == 0 && d' == 1 | (_, _, w', d') <- trans ] &&
                 P.or  [ w' == 1 && d' == 1 | (_, _, w', d') <- trans ]
  r2 <- check (P.length trans >= 4 && transOK) "MSB one sck after the ws transition"
  r3 <- check wsLeftOK "ws low = left, high = right"
  -- 3. loop returns the samples
  let got = P.take 20 (loopOut 2 (256 * 24))
      want = P.take 20 (toList samples)
  r4 <- check (got == want) ("loop returns 20 (L,R) pairs: " P.++ P.show (P.length got))
  -- 4. rx started mid-frame: drop k cycles of the tx streams, feed rx
  let midOK k =
        let st = txStreams 2 (256 * 24)
            dropped = P.drop k st
            rx = sampleN @System (P.length dropped)
                   (i2sRx (fromList [ s | (s, _, _, _) <- dropped ])
                          (fromList [ w | (_, w, _, _) <- dropped ])
                          (fromList [ d | (_, _, d, _) <- dropped ]))
            outs = [ p | Just p <- rx ]
            firstIdx = P.length (P.takeWhile (/= P.head outs) (toList samples))
        in not (P.null outs) && firstIdx <= 2 &&
           outs == P.take (P.length outs) (P.drop firstIdx (toList samples))
  r5 <- check (P.all midOK [37, 100, 150, 200, 300, 333]) "rx re-syncs after mid-frame start (drops partial frame)"
  if P.and [r1, r2, r3, r4, r5]
    then putStrLn "ALL PASS: PM.I2s" >> exitSuccess
    else exitFailure
