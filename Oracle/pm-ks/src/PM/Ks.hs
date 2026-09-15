-- PM.Ks — Karplus-Strong plucked string for the Erand49 harp
-- (Erand49/DESIGN.md "Signal path": KS waveguide x49 @ 96 kHz, one engine,
-- allpass fractional delay; fpga-resource-swag.md KS row).
--
--   * ksStep  : the pure per-string, per-sample update. Loop = block-RAM
--               delay line (<= 4096 samples, Signed 16; A0 at 96 kHz needs 3491) -> 2-point averager
--               (+0.5 sample, the classic KS loss filter) -> first-order
--               allpass (0.5 + frac/256 samples, coefficient from apCoef)
--               -> loop gain (Unsigned 8, /256) -> + excitation. Excitation
--               is a 16-bit LFSR noise burst of kDelay samples on pluck,
--               scaled by velocity (/256). Loop period = kDelay + frac/256
--               samples exactly (the allpass phase-delay error at the
--               fundamental is < 0.05 cent for kDelay >= 40).
--   * ksVoice : one string, everything clocked by the 96 kHz tick enable.
--   * ksBank  : N strings time-multiplexed on one engine, one string per
--               clock, 3-stage pipeline (state/config RAM read -> delay-line
--               read -> step + writes). Per-string state and config live in
--               block RAM indexed by string; the delay lines share one block
--               RAM with packed per-string regions sized from a static
--               max-delay table (bases = prefix sums). A pass over N strings
--               takes N+3 clocks after the tick; the output is a stream
--               (string, sample), one string per clock (ksBankVec collects
--               it into a Vec for small banks / tests).
--   * erard   : the 49-string Erard table at 96 kHz. Natural tuning needs
--               96000/f samples (30.6 for G7 .. 3490.9 for A0); each region
--               is sized for the pedal-flat pitch (f / 2^(1/12)) plus one
--               guard word: 34 .. 3700 words, 39260 words total (76.7 KB,
--               39 DP16KD at 1024x16) instead of 49 x 4096 = 200704.
-- Rounding is round-half-up everywhere (no DC drift in the loop) and the
-- golden model golden/ks_model.py is bit-exact with ksStep.
module PM.Ks where

import Clash.Prelude
import qualified Prelude as P
import Data.Maybe (isNothing, fromMaybe)

-- ---------------------------------------------------------------------------
-- Configuration and state.

-- Per-string configuration. kDelay must be >= 3 and <= 4095.
data KsCfg = KsCfg
  { kDelay :: !(Unsigned 12)   -- integer loop period in samples
  , kFrac  :: !(Unsigned 8)    -- fractional period, /256
  , kGain  :: !(Unsigned 8)    -- loop gain, /256 (255 = longest decay)
  } deriving (Generic, NFDataX, Eq, Show)

-- Per-string state (everything except the delay line itself).
data KsState = KsState
  { sWp    :: !(Unsigned 12)   -- delay-line slot written by the next step
  , sPrev  :: !(Signed 16)     -- previous delayed sample (2-point averager)
  , sApX   :: !(Signed 16)     -- allpass x[n-1]
  , sApY   :: !(Signed 16)     -- allpass y[n-1]
  , sLfsr  :: !(Unsigned 16)   -- free-running noise generator
  , sBurst :: !(Unsigned 12)   -- excitation samples remaining
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
wrapAdd :: Unsigned 12 -> Unsigned 12 -> Unsigned 13 -> Unsigned 12
wrapAdd lr wp k =
  let s = resize wp + k :: Unsigned 13
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
rdAddr :: Unsigned 13 -> KsCfg -> KsState -> Unsigned 12
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
  ram         = blockRam (replicate (SNat @4096) 0 :: Vec 4096 (Signed 16))
                  (rdAddr 2 <$> cfg <*> st)
                  (Just <$> bundle (sWp <$> st, out))
  started     = register False (pure True)
  rd          = mux started ram 0

-- ---------------------------------------------------------------------------
-- Time-multiplexed bank.

-- Engine bookkeeping for ksBank: the string whose state/config read is
-- issued this clock (stage 0) is bCur when a pass is active.
data BankCtl n = BankCtl
  { bBusy :: !Bool       -- a pass is issuing reads
  , bCur  :: !(Index n)  -- next string to read
  } deriving (Generic, NFDataX)

-- Sum of a static max-delay table: the delay-RAM words a bank needs.
bankWords :: KnownNat n => Vec n (Unsigned 12) -> Unsigned 32
bankWords = sum . map resize

-- Base offset of each string's delay region (prefix sums of the table).
bankBases :: KnownNat n => Vec n (Unsigned 12) -> Vec n (Unsigned 32)
bankBases = init . scanl (+) 0 . map resize

-- ksBank words maxD tick cfgWr pluck: N strings on one engine.
--   words : delay-RAM size (must be >= bankWords maxD).
--   maxD  : static per-string region size; a string's kDelay must stay
--           <= its maxD (a larger one reads the neighbour's region).
--   cfgWr : configuration write port (string, cfg); the config RAM starts
--           at KsCfg maxD 0 0 (silent, longest period).
-- Pipeline, one string per clock after a tick (ignored while a pass or its
-- tail is in flight, i.e. for N+3 clocks):
--   stage 0: read state RAM and config RAM at string i
--   stage 1: state/config valid -> issue the delay-line read at
--            base i + rdAddr 1 (register state/config for stage 2)
--   stage 2: delay sample valid -> ksStep; write state RAM, delay RAM
--            (base i + wp) and emit (i, sample).
-- Hazards: each string is visited once per pass, so its state-RAM write
-- (stage 2, clock t+2) precedes its next read (>= t+3 even for N = 1 because
-- a new pass waits for the tail to drain). Delay regions are disjoint, so
-- the read-during-write of consecutive strings never hits one address.
-- Plucks are latched per string in registers (N x 9 FF) until its next
-- step: the state RAM's single write port is owned by stage 2.
ksBank
  :: forall w n dom
   . (HiddenClockResetEnable dom, KnownNat n, 1 <= n, KnownNat w, 1 <= w)
  => SNat w                                    -- delay-RAM words
  -> Vec n (Unsigned 12)                       -- max delay per string
  -> Signal dom Bool                           -- sample-rate tick
  -> Signal dom (Maybe (Index n, KsCfg))       -- config write
  -> Signal dom (Maybe (Index n, Unsigned 8))  -- pluck (string, velocity)
  -> Signal dom (Maybe (Index n, Signed 16))   -- (string, sample) stream
ksBank _ maxD tick cfgWr pluck = out
 where
  bases = bankBases maxD
  -- stage 0
  ctl    = register (BankCtl False 0) ctl'
  idle   = (\c a b -> not (bBusy c) && isNothing a && isNothing b) <$> ctl <*> s1 <*> s2
  active = (bBusy <$> ctl) .||. (tick .&&. idle)
  cur    = bCur <$> ctl
  s0     = mux active (Just <$> cur) (pure Nothing)
  ctl'   = (\a c -> if a then BankCtl (c /= maxBound) (if c == maxBound then 0 else c + 1)
                         else BankCtl False 0) <$> active <*> cur
  stRam  = blockRam (repeat ksInit :: Vec n KsState) cur stWr
  cfgRam = blockRam (map (\d -> KsCfg d 0 0) maxD) cur cfgWr
  -- stage 1
  s1     = register Nothing s0
  st1    = stRam
  cfg1   = cfgRam
  addr1  = (\i c s -> fromIntegral (bases !! i + resize (rdAddr 1 c s)) :: Index w)
             <$> (fromMaybe 0 <$> s1) <*> cfg1 <*> st1
  dRam   = blockRam (replicate (SNat @w) 0 :: Vec w (Signed 16)) addr1 dWr
  -- stage 2
  s2     = register Nothing s1
  st2    = register ksInit st1
  cfg2   = register (KsCfg 3 0 0) cfg1
  started = register False (pure True)
  rd     = mux started dRam 0
  pend   = register (repeat Nothing) pend'
  (stWr, dWr, out, pend') = unbundle (step2 <$> s2 <*> cfg2 <*> st2 <*> rd <*> pluck <*> pend)
  step2 mi cfg st r pl pend0 = case mi of
    Nothing -> (Nothing, Nothing, Nothing, latch Nothing)
    Just i  ->
      let ev = case pl of
                 Just (j, v) | j == i -> Just v
                 _                    -> Nothing
          (st', y) = ksStep cfg (ev <|> (pend0 !! i)) r st
          wa = fromIntegral (bases !! i + resize (sWp st)) :: Index w
      in (Just (i, st'), Just (wa, y), Just (i, y), latch (Just i))
   where
    latch consumed = imap (\j p -> if Just j == consumed then Nothing
                                   else case pl of
                                     Just (k, v) | k == j -> Just v
                                     _                    -> p) pend0

-- ksBankVec: ksBank with the stream collected into a per-string Vec
-- (N x 16 FF); the harp instance sums the stream instead.
ksBankVec
  :: forall w n dom
   . (HiddenClockResetEnable dom, KnownNat n, 1 <= n, KnownNat w, 1 <= w)
  => SNat w -> Vec n (Unsigned 12)
  -> Signal dom Bool
  -> Signal dom (Maybe (Index n, KsCfg))
  -> Signal dom (Maybe (Index n, Unsigned 8))
  -> Signal dom (Vec n (Signed 16))
ksBankVec w maxD tick cfgWr pluck = outs
 where
  outs = register (repeat 0) (upd <$> ksBank w maxD tick cfgWr pluck <*> outs)
  upd Nothing v = v
  upd (Just (i, y)) v = replace i y v

-- ---------------------------------------------------------------------------
-- The Erard 49 (Erand49/string-specs.md), string 1 = G7 .. string 49 = A0.

-- Fundamentals in Hz, string order (inlined in the splices below: the
-- Template Haskell stage restriction forbids a same-module binding).

-- Delay-region size per string: ceil(96000 / (f / 2^(1/12))) + 1, i.e. the
-- pedal-flat pitch plus a guard word. 34 (G7) .. 3700 (A0).
erardMaxDelay :: Vec 49 (Unsigned 12)
erardMaxDelay = $(listToVecTH
  [ fromInteger (P.ceiling (96000 / (f / 2 P.** (1 / 12)) :: P.Double) + 1) :: Unsigned 12
  | f <- [ 3136, 2793.8, 2637, 2349.3, 2093, 1975.5, 1760, 1568, 1396.9, 1318.5, 1174.7
      , 1046.5, 987.77, 880, 783.99, 698.46, 659.26, 587.33, 523.25, 493.88, 440
      , 392, 349.23, 329.63, 293.66, 261.63, 246.94, 220, 196, 174.61, 164.81
      , 146.83, 130.81, 123.47, 110, 97.99, 87.31, 82.41, 73.42, 65.41, 61.74, 55
      , 49, 43.65, 41.2, 36.71, 32.7, 30.868, 27.5 ] ])

-- Natural-tuning configuration at 96 kHz: kDelay = floor(96000/f),
-- kFrac = round(256 * frac), gain 255 (built from a (delay, frac) table:
-- KsCfg itself cannot appear in a same-module splice).
erardCfg :: Vec 49 KsCfg
erardCfg = map (\(d, fr) -> KsCfg d fr 255) erardPeriod

erardPeriod :: Vec 49 (Unsigned 12, Unsigned 8)
erardPeriod = $(listToVecTH
  [ (fromInteger d :: Unsigned 12, fromInteger fr :: Unsigned 8)
  | f <- [ 3136, 2793.8, 2637, 2349.3, 2093, 1975.5, 1760, 1568, 1396.9, 1318.5, 1174.7
      , 1046.5, 987.77, 880, 783.99, 698.46, 659.26, 587.33, 523.25, 493.88, 440
      , 392, 349.23, 329.63, 293.66, 261.63, 246.94, 220, 196, 174.61, 164.81
      , 146.83, 130.81, 123.47, 110, 97.99, 87.31, 82.41, 73.42, 65.41, 61.74, 55
      , 49, 43.65, 41.2, 36.71, 32.7, 30.868, 27.5 ]
  , let p = 96000 / f :: P.Double
        d = P.floor p
        fr = P.min 255 (P.round (256 * (p - P.fromInteger d))) ])

-- sum erardMaxDelay = 39260 words (checked by the test suite).
type ErardWords = 39260

-- ---------------------------------------------------------------------------
-- Top entities: a 4-string bank (2048-word regions, the old layout) and the
-- 49-string harp instance with the packed Erard allocation.

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool
  -> Signal System (Maybe (Index 4, KsCfg))
  -> Signal System (Maybe (Index 4, Unsigned 8))
  -> Signal System (Vec 4 (Signed 16))
topEntity = exposeClockResetEnable (ksBankVec (SNat @8192) (repeat 2048))
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_ks4"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "tick", PortName "cfg_wr", PortName "pluck" ]
    , t_output = PortName "samples"
    }) #-}

ks49
  :: Clock System -> Reset System -> Enable System
  -> Signal System Bool
  -> Signal System (Maybe (Index 49, KsCfg))
  -> Signal System (Maybe (Index 49, Unsigned 8))
  -> Signal System (Maybe (Index 49, Signed 16))
ks49 = exposeClockResetEnable (ksBank (SNat @ErardWords) erardMaxDelay)
{-# NOINLINE ks49 #-}
{-# ANN ks49
  (Synthesize
    { t_name   = "pm_ks49"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "tick", PortName "cfg_wr", PortName "pluck" ]
    , t_output = PortName "sample"
    }) #-}
