-- PM.Ks — Karplus-Strong plucked string for the Erand49 harp
-- (Erand49/DESIGN.md "Signal path": KS waveguide x49 @ 96 kHz, one engine,
-- allpass fractional delay; fpga-resource-swag.md KS row).
--
--   * ksStep  : the pure per-string, per-sample update. Loop = block-RAM
--               delay line (<= 2048 samples, Signed 16) -> 2-point averager
--               (+0.5 sample, the classic KS loss filter) -> first-order
--               allpass (0.5 + frac/256 samples, coefficient from apCoef)
--               -> loop gain (Unsigned 8, /256) -> + excitation. Excitation
--               is a 16-bit LFSR noise burst of kDelay samples on pluck,
--               scaled by velocity (/256). Loop period = kDelay + frac/256
--               samples exactly (the allpass phase-delay error at the
--               fundamental is < 0.05 cent for kDelay >= 40).
--   * ksVoice : one string, everything clocked by the 96 kHz tick enable.
--   * ksBank  : N strings time-multiplexed on one engine, one string per
--               clock, 2-stage pipeline (RAM read issue / step + write).
--               A pass over N strings takes N+1 clocks after the tick.
-- Rounding is round-half-up everywhere (no DC drift in the loop) and the
-- golden model golden/ks_model.py is bit-exact with ksStep.
module PM.Ks where

import Clash.Prelude
import qualified Prelude as P

-- ---------------------------------------------------------------------------
-- Configuration and state.

-- Per-string configuration. kDelay must be >= 3 and <= 2047.
data KsCfg = KsCfg
  { kDelay :: !(Unsigned 11)   -- integer loop period in samples
  , kFrac  :: !(Unsigned 8)    -- fractional period, /256
  , kGain  :: !(Unsigned 8)    -- loop gain, /256 (255 = longest decay)
  } deriving (Generic, NFDataX, Eq, Show)

-- Per-string state (everything except the delay line itself).
data KsState = KsState
  { sWp    :: !(Unsigned 11)   -- delay-line slot written by the next step
  , sPrev  :: !(Signed 16)     -- previous delayed sample (2-point averager)
  , sApX   :: !(Signed 16)     -- allpass x[n-1]
  , sApY   :: !(Signed 16)     -- allpass y[n-1]
  , sLfsr  :: !(Unsigned 16)   -- free-running noise generator
  , sBurst :: !(Unsigned 11)   -- excitation samples remaining
  , sVel   :: !(Unsigned 8)    -- velocity of the current burst
  } deriving (Generic, NFDataX, Eq, Show)

-- Reset state: pointer 0, silent, LFSR seeded 0xACE1.
ksInit :: KsState
ksInit = KsState 0 0 0 0 0xACE1 0 0

-- ---------------------------------------------------------------------------
-- Fixed-point helpers.

-- Allpass coefficient table: a = (1 - d) / (1 + d) * 256 for the delay
-- d = 0.5 + frac/256 (Jaffe-Smith DC tuning; d in [0.5, 1.5) keeps the
-- allpass transient short). Range 85 .. -51.
apCoef :: Vec 256 (Signed 8)
apCoef = $(listToVecTH
  [ fromInteger (P.round (256.0 * (1.0 - d) / (1.0 + d))) :: Signed 8
  | i <- [0 :: Int .. 255]
  , let d = 0.5 + P.fromIntegral i / 256.0 :: P.Double
  ])

-- Saturate a wide signed value to Signed 16.
sat16 :: KnownNat m => Signed m -> Signed 16
sat16 x
  | x > 32767  = maxBound
  | x < -32768 = minBound
  | otherwise  = resize x

-- Round-half-up divide by 256 of a 25-bit product, to 16 bits.
rnd8 :: Signed 25 -> Signed 16
rnd8 x = resize (shiftR (x + 128) 8)

-- 16-bit Fibonacci LFSR, taps 16 14 13 11 (maximal length).
lfsrNext :: Unsigned 16 -> Unsigned 16
lfsrNext v =
  let b = testBit v 15 `xor` testBit v 13 `xor` testBit v 12 `xor` testBit v 10
  in shiftL v 1 .|. (if b then 1 else 0)

-- Ring-buffer pointer add: (wp + k) mod (lr + 1) for a loop of lr + 1 slots.
-- If the delay shrank under a live pointer the result may still exceed lr;
-- it self-heals within a few samples.
wrapAdd :: Unsigned 11 -> Unsigned 11 -> Unsigned 12 -> Unsigned 11
wrapAdd lr wp k =
  let s = resize wp + k :: Unsigned 12
  in resize (if s > resize lr then s - (resize lr + 1) else s)

-- ---------------------------------------------------------------------------
-- The per-sample step, shared by ksVoice and ksBank.

-- ksStep cfg pluck rd st: rd is the delay-line sample written kDelay - 1
-- steps ago. Returns the new state and the sample to write / output.
ksStep :: KsCfg -> Maybe (Unsigned 8) -> Signed 16 -> KsState -> (KsState, Signed 16)
ksStep cfg pluck rd st = (st', out)
 where
  lr     = kDelay cfg - 1
  burst0 = maybe (sBurst st) (const (kDelay cfg)) pluck
  vel0   = maybe (sVel st) id pluck
  avg    = resize (shiftR (resize rd + resize (sPrev st) + 1 :: Signed 17) 1) :: Signed 16
  a      = apCoef !! kFrac cfg
  t      = resize avg - resize (sApY st) :: Signed 17
  m      = rnd8 (resize a * resize t)
  ap     = sat16 (resize (sApX st) + resize m :: Signed 17)
  fb     = rnd8 (resize ap * fromIntegral (kGain cfg))
  nz     = rnd8 (resize (bitCoerce (sLfsr st) :: Signed 16) * fromIntegral vel0)
  noise  = if burst0 > 0 then nz else 0
  out    = sat16 (resize fb + resize noise :: Signed 17)
  st'    = KsState
    { sWp    = wrapAdd lr (sWp st) 1
    , sPrev  = rd
    , sApX   = avg
    , sApY   = ap
    , sLfsr  = lfsrNext (sLfsr st)
    , sBurst = if burst0 > 0 then burst0 - 1 else 0
    , sVel   = vel0
    }

-- Delay-line read address k steps ahead of the slot the state will write.
-- rd for step n lives at wp_n + 1 (mod kDelay); ksVoice issues the read one
-- tick early (k = 2), ksBank one clock early (k = 1).
rdAddr :: Unsigned 12 -> KsCfg -> KsState -> Unsigned 11
rdAddr k cfg st = wrapAdd (kDelay cfg - 1) (sWp st) k

-- ---------------------------------------------------------------------------
-- Single string.

-- ksVoice tick cfg pluck: one string. Everything but the pluck latch runs
-- under the tick enable, so the block RAM's one-cycle latency is one tick.
-- A pluck arriving between ticks is latched and consumed at the next tick.
ksVoice
  :: HiddenClockResetEnable dom
  => Signal dom Bool                  -- sample-rate tick (96 kHz enable)
  -> Signal dom KsCfg
  -> Signal dom (Maybe (Unsigned 8))  -- pluck with velocity
  -> Signal dom (Signed 16)
ksVoice tick cfg pluck = andEnable tick (ksCore cfg latched)
 where
  latched = liftA2 (<|>) pluck pend
  pend    = register Nothing (mux tick (pure Nothing) latched)

-- The tick-domain body of ksVoice.
ksCore
  :: HiddenClockResetEnable dom
  => Signal dom KsCfg -> Signal dom (Maybe (Unsigned 8)) -> Signal dom (Signed 16)
ksCore cfg pluck = out
 where
  st          = register ksInit st'
  (st', out)  = unbundle (ksStep <$> cfg <*> pluck <*> rd <*> st)
  ram         = blockRam (replicate (SNat @2048) 0 :: Vec 2048 (Signed 16))
                  (rdAddr 2 <$> cfg <*> st)
                  (Just <$> bundle (sWp <$> st, out))
  started     = register False (pure True)
  rd          = mux started ram 0

-- ---------------------------------------------------------------------------
-- Time-multiplexed bank.

-- Engine bookkeeping for ksBank.
data BankCtl n = BankCtl
  { bBusy :: !Bool               -- a pass is in flight
  , bCur  :: !(Index n)          -- string whose read is issued this clock
  , bStep :: !(Maybe (Index n))  -- string whose step runs this clock
  } deriving (Generic, NFDataX)

-- ksBank tick cfgs pluck: N strings on one engine, N x 2048 samples of RAM
-- (string index in the address MSBs). On tick, strings 0..N-1 issue their
-- delay-line reads on consecutive clocks; each step runs the clock after
-- its read, writes the RAM and its output slot. Ticks closer than N+1
-- clocks are ignored. Plucks are latched per string until its next step.
ksBank
  :: forall n dom
   . (HiddenClockResetEnable dom, KnownNat n, 1 <= n)
  => Signal dom Bool                              -- sample-rate tick
  -> Signal dom (Vec n KsCfg)
  -> Signal dom (Maybe (Index n, Unsigned 8))     -- pluck (string, velocity)
  -> Signal dom (Vec n (Signed 16))
ksBank tick cfgs pluck = outs
 where
  ctl  = register (BankCtl False 0 Nothing) ctl'
  sts  = register (repeat ksInit) sts'
  pend = register (repeat Nothing) pend'
  outs = register (repeat 0) outs'
  started = register False (pure True)
  rd   = mux started ram 0
  ram  = blockRam (replicate (SNat @(n * 2048)) 0 :: Vec (n * 2048) (Signed 16))
           rdA wr
  (ctl', sts', pend', outs', rdA, wr) =
    unbundle (bankStep <$> tick <*> cfgs <*> pluck <*> rd <*> ctl <*> sts <*> pend <*> outs)

-- Address of slot wp in string s's region.
bankAddr :: forall n. (KnownNat n, 1 <= n) => Index n -> Unsigned 11 -> Index (n * 2048)
bankAddr s wp = fromIntegral s * 2048 + fromIntegral wp

-- One clock of the bank engine (pure).
bankStep
  :: forall n. (KnownNat n, 1 <= n)
  => Bool -> Vec n KsCfg -> Maybe (Index n, Unsigned 8) -> Signed 16
  -> BankCtl n -> Vec n KsState -> Vec n (Maybe (Unsigned 8)) -> Vec n (Signed 16)
  -> ( BankCtl n, Vec n KsState, Vec n (Maybe (Unsigned 8)), Vec n (Signed 16)
     , Index (n * 2048), Maybe (Index (n * 2048), Signed 16) )
bankStep tick cfgs pluck rd ctl sts pend outs = (ctl', sts', pend', outs', rdA, wr)
 where
  -- stage B: step the string whose read was issued last clock
  (sts', outs', wr, consumed) = case bStep ctl of
    Nothing -> (sts, outs, Nothing, Nothing)
    Just i  ->
      let ev        = case pluck of
                        Just (j, v) | j == i -> Just v
                        _                    -> Nothing
          pl        = ev <|> (pend !! i)
          st0       = sts !! i
          (st1, y)  = ksStep (cfgs !! i) pl rd st0
      in (replace i st1 sts, replace i y outs, Just (bankAddr i (sWp st0), y), Just i)
  -- pluck latch: consume for the stepped string, set for anyone else
  pend' = imap latch pend
  latch j p
    | Just j == consumed = Nothing
    | otherwise = case pluck of
        Just (k, v) | k == j -> Just v
        _                    -> p
  -- stage A: issue the next read
  active = bBusy ctl || tick
  cur    = bCur ctl
  rdA    = bankAddr cur (rdAddr 1 (cfgs !! cur) (sts !! cur))
  ctl'
    | active    = BankCtl (cur /= maxBound) (if cur == maxBound then 0 else cur + 1) (Just cur)
    | otherwise = BankCtl False 0 Nothing

-- ---------------------------------------------------------------------------
-- Top entity: a 4-string bank (the harp instance is ksBank @49).

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool
  -> Signal System (Vec 4 KsCfg)
  -> Signal System (Maybe (Index 4, Unsigned 8))
  -> Signal System (Vec 4 (Signed 16))
topEntity = exposeClockResetEnable (ksBank @4)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_ks4"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "tick", PortName "cfg", PortName "pluck" ]
    , t_output = PortName "samples"
    }) #-}
