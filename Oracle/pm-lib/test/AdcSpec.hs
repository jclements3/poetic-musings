-- PM.Adc proof: wire the sequencer to a behavioural MCP3208 (a Moore
-- machine whose MISO depends on state only, so the loop closes without a
-- combinational cycle) and assert:
--   1. after a few sweeps the three slider outputs hold the model's
--      channel-0/1/2 codes and aux holds the selected channel's code;
--   2. changing the aux select moves aux to the new channel's code;
--   3. aoTick pulses once per completed sweep;
--   4. SCLK never runs while CS is high (framing).
import Clash.Prelude
import qualified Prelude as P
import PM.Adc
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- Per-channel codes the model serves (12-bit).
vals :: Vec 8 (Unsigned 12)
vals = 0x123 :> 0x456 :> 0x789 :> 0xABC :> 0xDEF :> 0x210 :> 0x543 :> 0x876 :> Nil

-- Behavioural MCP3208: count rising edges while CS is low, record MOSI
-- (command) bits, and present data bit (24-k) for the upcoming edge k once
-- k >= 13.  The channel is bits 2:0 of the recorded command register after
-- 10 edges (start/SGL/D2 at edges 6..8, D1/D0 at 9..10 in the 3-byte
-- framing — bit2 = edge 8's D2, bit1 = D1, bit0 = D0).
data M3208 = M3208
  { mCnt  :: Unsigned 6      -- rising edges seen this frame
  , mCmd  :: BitVector 24
  , mCh   :: Index 8         -- channel, latched once the command is complete
  , mPrev :: Bit
  } deriving (Generic, NFDataX)

modelT :: M3208 -> (Bit, Bit, Bit) -> M3208
modelT M3208{..} (cs, sclk, mosi)
  | cs == 1   = M3208 0 0 mCh sclk
  | rising    = M3208 (mCnt + 1) cmd' ch' sclk
  | otherwise = M3208 mCnt mCmd mCh sclk
 where
  rising = mPrev == 0 && sclk == 1
  cmd' = mCmd `shiftL` 1 .|. zeroExtend (pack mosi)
  -- D0 arrives at edge 10; latch the channel there, before the register
  -- keeps shifting under the data edges
  ch' = if mCnt + 1 == 10 then unpack (slice d2 d0 cmd') else mCh

modelO :: M3208 -> Bit
modelO M3208{..}
  | k >= 13 && k <= 24 = unpack (slice d0 d0 (pack v `shiftR` (24 - fromIntegral k)))
  | otherwise          = 0
 where
  k = mCnt + 1                                    -- the edge about to happen
  v = vals !! mCh

main :: IO ()
main = do
  let n = 3000
      auxSelIn = fromList (P.replicate 1500 (3 :: BitVector 3)
                           P.++ P.repeat 5)
      out = withClockResetEnable (clockGen @System) (resetGen @System) (enableGen @System) sys
      sys :: HiddenClockResetEnable dom => Signal dom AdcOut
      sys = o
       where
        o = adc (pure 2) auxSelIn miso
        miso = moore modelT modelO (M3208 0 0 0 0)
                 (bundle (aoCs <$> o, aoSclk <$> o, aoMosi <$> o))
      outs = sampleN @System n out
      mid  = outs P.!! 1490
      fin  = P.last outs
      ticks = P.length (P.filter aoTick outs)
      framingOk = P.all (\o -> aoCs o == 0 || aoSclk o == 0) outs
  r1 <- check (aoSliders fin == takeI vals)
              ("sliders S2/S3/S4 = model ch0..2: " P.++ P.show (aoSliders fin))
  r2 <- check (aoAux mid == vals !! (3 :: Index 8))
              ("aux (sel 3, S0) = " P.++ P.show (aoAux mid))
  r3 <- check (aoAux fin == vals !! (5 :: Index 8))
              ("aux follows select change to 5: " P.++ P.show (aoAux fin))
  -- one conversion = 24 SCLKs * 2 half-periods * hp 2 + gap 8 = 104 ticks;
  -- a sweep = 4 conversions ~ 416 ticks; 3000 ticks ~ 7 sweeps.
  r4 <- check (ticks >= 5 && ticks <= 8) ("sweep ticks: " P.++ P.show ticks)
  r5 <- check framingOk "SCLK idle whenever CS is high"
  if P.and [r1, r2, r3, r4, r5]
    then putStrLn "ALL PASS: PM.Adc" >> exitSuccess
    else exitFailure
