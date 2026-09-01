-- PM.HarpLink proof: loop frameTx's serial line into frameRx and assert
-- three frames survive byte-exact; then corrupt one bit on the wire mid-
-- frame and assert that frame is rejected but the following frame is
-- recovered (resync).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.Maybe as M
import PM.HarpLink
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

dv :: Unsigned 8
dv = 8

frames :: [HFrame]
frames =
  [ HFrame 0x01 12 0x03 0xE8 0x40 0x00   -- pluck string 12
  , HFrame 0x01 48 0x00 0x7F 0xC0 0x01   -- pluck a0
  , HFrame 0x04 0  0x00 0x00 0x00 0x02   -- heartbeat
  ]

-- run the loop with an optional wire corruption (one full bit period)
run :: Maybe Int -> [HFrame] -> [HFrame]
run corrupt fs =
  let n = 12000
      out = sampleN @System n sys
      line = [ l | (l, _) <- out ]
      got = M.catMaybes [ g | (_, g) <- out ]
  in got
 where
  sys :: HiddenClockResetEnable dom => Signal dom (Bit, Maybe HFrame)
  sys = bundle (lineC, rxf)
   where
    feed = mealy
      (\(i, prevRdy) rdy ->
         if rdy && not prevRdy && i < P.length fs
           then ((i + 1, rdy), Just (fs P.!! i))
           else ((i, rdy), Nothing))
      (0, False) freadyR
    (txo) = frameTx (pure dv) feed
    (lineT, fready) = unbundle txo
    freadyR = register False fready
    -- optional single-bit corruption at a given sample index
    lineC = case corrupt of
      Nothing -> lineT
      Just k  -> mealy (\i b -> (i + 1, if i >= k && i < k + 8 then complement b else b)) (0 :: Int) lineT
    rxf = frameRx (pure dv) lineC

main :: IO ()
main = do
  let clean = run Nothing frames
  r1 <- check (clean == frames) ("clean loop: 3 frames byte-exact: " P.++ P.show (P.length clean))
  -- corrupt a bit inside the first frame's serial window (frame 1 ~ bytes 0..8
  -- x 10 bits x 8 ticks => tick ~300 is mid-frame-1)
  let dirty = run (Just 300) frames
  r2 <- check (P.notElem (P.head frames) dirty && P.length dirty == 2
               && P.drop 1 frames == dirty)
              ("corrupted frame dropped, next frames recovered: got " P.++ P.show (P.length dirty))
  if r1 && r2 then putStrLn "ALL PASS: PM.HarpLink" >> exitSuccess else exitFailure
