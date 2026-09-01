-- Sentence-level proof of the $GxRMC parser: real-shaped sentences fed
-- byte by byte (checksums computed here in ordinary Haskell), asserting
-- BCD field packing (incl. leap-year day-of-year), checksum rejection,
-- non-RMC rejection, the documented V-flag policy (time applied, locked
-- low), and a distinct tod_set strobe per accepted sentence.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.Char as C
import PM.Gps
import System.Exit (exitFailure, exitSuccess)

-- '$' ++ body ++ '*' ++ XOR-of-body in uppercase hex ++ CRLF.
nmea :: P.String -> P.String
nmea body = "$" P.++ body P.++ "*" P.++ [hex hi, hex lo] P.++ "\r\n"
  where
    ck = P.foldl xor (0 :: Int) (P.map C.ord body)
    (hi, lo) = (ck `div` 16, ck `mod` 16)
    hex n = "0123456789ABCDEF" P.!! n

-- Break the checksum: flip the low hex digit of a finished sentence.
corrupt :: P.String -> P.String
corrupt str = case P.splitAt (P.length str - 3) str of
  (pre, [c, cr, lf]) -> pre P.++ [if c == '0' then '1' else '0', cr, lf]
  _                  -> P.error "corrupt: not a sentence"

toBytes :: P.String -> [Maybe Byte]
toBytes = P.map (Just . fromIntegral . C.ord)

pad :: [Maybe Byte]
pad = P.replicate 8 Nothing

-- The scenario stream. Expected values worked by hand in the comments.
good1, badck, gga, vfix, good2a, good2b :: P.String
good1  = nmea "GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W"
         -- 12:35:19, 23 Mar 1994 (not leap): doy 59+23 = 082
badck  = corrupt (nmea "GPRMC,235959,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W")
gga    = nmea "GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,"
vfix   = nmea "GPRMC,010203.00,V,,,,,,,010100,,"
         -- void fix, 01:02:03, 1 Jan 2000: doy 001, locked must read low
good2a = nmea "GNRMC,120000.00,A,4807.038,N,01131.000,E,0.0,0.0,010316,,,A"
         -- GN talker; 1 Mar 2016 (leap): doy 59+1+1 = 061
good2b = nmea "GPRMC,120001,A,4807.038,N,01131.000,E,0.0,0.0,010316,,"

segs :: [[Maybe Byte]]
segs = [ pad
       , toBytes good1  P.++ pad
       , toBytes badck  P.++ pad
       , toBytes gga    P.++ pad
       , toBytes vfix   P.++ pad
       , toBytes good2a P.++ pad
       , toBytes good2b P.++ pad ]

main :: IO ()
main = do
  let stim = P.concat segs
      cum  = P.scanl1 (+) (P.map P.length segs)   -- checkpoint after each segment
      n    = P.last cum
      out  = simulateN @System n sys (stim P.++ P.repeat Nothing)
      smp k = out P.!! (k - 1)                    -- last (settled) sample of the pad
      pc  k = P.length [ () | (_, _, _, _, True) <- P.take k out ]
      ck  i = (cum P.!! i, smp (cum P.!! i), pc (cum P.!! i))

      checks =
        [ expct "good1 fields+lock"  (ck 1) (0x1935, 0x1282, 0x00, True)  1
        , expct "badck rejected"     (ck 2) (0x1935, 0x1282, 0x00, True)  1
        , expct "GPGGA ignored"      (ck 3) (0x1935, 0x1282, 0x00, True)  1
        , expct "V updates, no lock" (ck 4) (0x0302, 0x0101, 0x00, False) 2
        , expct "GNRMC leap doy"     (ck 5) (0x0000, 0x1261, 0x00, True)  3
        , expct "second good strobe" (ck 6) (0x0100, 0x1261, 0x00, True)  4 ]
  results <- P.sequence checks
  if P.and results
    then putStrLn "PASS: GPRMC -> 0x4040 TOD block (6 scenario checkpoints)" >> exitSuccess
    else exitFailure
  where
    expct name (k, (ssmm, hhdl, dh, lk, _), pulses)
              (essmm, ehhdl, edh, elk) epulses = do
      let ok = ssmm == essmm && hhdl == ehhdl && dh == edh
               && lk == elk && pulses == epulses
      if ok
        then putStrLn ("ok: " P.++ name)
        else putStrLn ( "FAIL: " P.++ name P.++ " @" P.++ show k
                 P.++ "  got (" P.++ show ssmm P.++ ", " P.++ show hhdl
                 P.++ ", " P.++ show dh P.++ ", " P.++ show lk
                 P.++ ", pulses " P.++ show pulses
                 P.++ ")  want (" P.++ show essmm P.++ ", " P.++ show ehhdl
                 P.++ ", " P.++ show edh P.++ ", " P.++ show elk
                 P.++ ", pulses " P.++ show epulses P.++ ")" )
      P.pure ok

    sys :: HiddenClockResetEnable dom
        => Signal dom (Maybe Byte)
        -> Signal dom (BitVector 16, BitVector 16, BitVector 8, Bool, Bool)
    sys mb = let (tod, pulse) = gps mb
             in bundle ( todSsmm <$> tod, todHhdl <$> tod, todDh <$> tod
                       , todLocked <$> tod, pulse )
