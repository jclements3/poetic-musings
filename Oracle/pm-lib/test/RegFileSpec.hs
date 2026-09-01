-- PM.RegFile proof: drive the H2-shaped bus against the full file and check
-- every carried semantic:
--   1. iPanel read (0x4020) reflects the dwell-qualified S3 zone.
--   2. oMatrixCtrl write enables the scan; a held key produces exactly one
--      press event; the 0x4024 READ pops it (second read shows empty).
--   3. oAudio resets muted (bit 0 = 1); a write releases it.
--   4. Synth/keyer writes surface as exactly one command pulse each, with
--      the written value.
--   5. TX interlock: arm key 0x0C1D with mode C arms; leaving C disarms in
--      hardware even though the key register still holds; a non-key write
--      disarms.
import Clash.Prelude
import qualified Prelude as P
import qualified Data.Maybe as M
import PM.RegFile
import PM.Matrix (MatrixCfg (..))
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

idleBus :: PmBus
idleBus = PmBus 0 False False 0

wr, rd :: BitVector 16 -> BitVector 16 -> PmBus   -- rd ignores data
wr a v = PmBus a True False v
rd a _ = PmBus a False True 0

-- The script: (cycle, transaction). Sparse; idle in between.
-- Timing: MatrixCfg settle 9 -> one scan pass = 72 ticks; debounce 2 passes.
-- S3 sits at zone C (3800) from reset; dwell 50 ticks.
script :: [(Int, PmBus)]
script =
  [ (2,    wr 0x4024 0x0021)   -- scan enable, debounce 2 (bits 9:4)
  , (60,   rd 0x4020 0)        -- iPanel: mode C dwelled by now
  , (400,  rd 0x4024 0)        -- key held since t=0: event ready; pop it
  , (410,  rd 0x4024 0)        -- FIFO now empty
  , (420,  rd 0x402C 0)        -- audio: still reset-muted
  , (422,  wr 0x402C 0x0000)   -- release mute
  , (424,  rd 0x402C 0)
  , (430,  wr 0x402E 0x8123)   -- synth command
  , (432,  wr 0x4030 0x0042)   -- keyer command
  , (440,  wr 0x4032 0x0C1D)   -- arm key, in mode C
  , (442,  rd 0x4032 0)
  , (450,  wr 0x4032 0x1111)   -- wrong key: disarm
  , (452,  rd 0x4032 0)
  , (460,  wr 0x4032 0x0C1D)   -- re-arm (S3 leaves C at t=500 in the drive)
  , (600,  rd 0x4032 0)        -- key still latched but mode left C: disarmed
  ]

n :: Int
n = 700

busIn :: [PmBus]
busIn = [ M.fromMaybe idleBus (P.lookup t script) | t <- [0 .. n - 1] ]

-- S3 slider: zone C until t=500, then zone P; dwell 50 ticks re-qualifies.
s3In :: [Unsigned 12]
s3In = [ if t < 500 then 3800 else 100 | t <- [0 .. n - 1] ]

main :: IO ()
main = do
  let cfg = MatrixCfg 9 2
      out = withClockResetEnable (clockGen @System) (resetGen @System) (enableGen @System) $
              regFile 64 50 cfg
                (fromList (busIn P.++ P.repeat idleBus))
                (pure 100)
                (fromList (s3In P.++ P.repeat 100))
                (pure 100)
                cols
                (pure (PmStatus 0x0AAA 0x00F0 0x0055 True 0x1234 0))
      -- key (row 2, col 3) held down the whole run: col 3 pulls low when
      -- row 2 is strobed (rows are one-hot active low)
      cols = fmap (\rws -> if rws !! (2 :: Index 8) == low
                             then replace (3 :: Index 8) low (repeat high)
                             else repeat high)
                  (prRows <$> out)
      outs = sampleN @System n out
      dinAt t = prDin (outs P.!! t)   -- read mux is combinational: valid on the strobe cycle
      pulses f = M.catMaybes (P.map f outs)

  r1 <- check (dinAt 60 .&. 7 == 5) ("iPanel S3 zone = C: " P.++ P.show (dinAt 60))
  let ev = dinAt 400
  r2 <- check (testBit ev 15 && testBit ev 7 && ev .&. 0x3F == 19)
              ("key event valid+press, keycode 19 (row2 col3): " P.++ P.show ev)
  r3 <- check (P.not (testBit (dinAt 410) 15)) "second 0x4024 read: FIFO popped/empty"
  r4 <- check (testBit (dinAt 420) 0 && P.not (testBit (dinAt 424) 0))
              "oAudio: reset-muted, write releases"
  r5 <- check (pulses prSynthCmd == [0x8123] && pulses prKeyerCmd == [0x0042])
              "synth/keyer: exactly one command pulse each, value intact"
  r6 <- check (testBit (dinAt 442) 0 && testBit (dinAt 442) 1)
              ("armed in mode C (+PA ok): " P.++ P.show (dinAt 442))
  r7 <- check (P.not (testBit (dinAt 452) 0)) "wrong key disarms"
  r8 <- check (P.not (testBit (dinAt 600) 0)) "leaving mode C disarms in hardware"
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8]
    then putStrLn "ALL PASS: PM.RegFile" >> exitSuccess
    else exitFailure
