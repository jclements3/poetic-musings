-- | TMDS 8b\/10b encoder (DVI 1.0 §3.2.2) and a 10:1 bit sequencer.
--
-- Per channel, per pixel clock:
--
-- >  stage 1  'tmdsMinimise'  : 8-bit data -> 9-bit q_m, XOR or XNOR chain
-- >                             chosen to minimise transitions (q_m[8] says
-- >                             which; the 8 data bits then carry <= 3
-- >                             transitions, the 10-bit word <= 5)
-- >  stage 2  'tmdsEncodeStep': invert or not to keep the running
-- >                             disparity near zero (q_out[9] says which)
-- >  blanking                 : one of four fixed control words carrying
-- >                             (c1, c0); on channel 0 those are (vsync,
-- >                             hsync).  Control words reset the disparity.
--
-- The 10-bit word is sent LSB first at 10x the pixel rate.  On the ECP5
-- that is a 5x-clock ODDRX1F\/ODDRX2F primitive (or the 10:1 ODDR71B
-- variants) plus a differential LVCMOS33D output -- vendor-specific, so
-- it is NOT modelled here; 'tmdsShift' is the plain 10:1 shift register
-- that sits behind it (one bit per bit-clock, load every 10th), which
-- is what an ODDR at half the bit clock replaces.  The Top for the real
-- board instantiates the ECP5 primitive as a black box around it.
module PM.Video.Tmds
  ( Disparity
  , tmdsMinimise
  , tmdsEncodeStep
  , tmdsControl
  , tmdsEncoder
  , tmdsShift
  ) where

import Clash.Prelude

-- | Running disparity, in (ones - zeros)\/2 units as DVI counts it:
-- the encoder keeps it within -8..+8 (the testbench asserts the bound).
type Disparity = Signed 6

-- | Stage 1: the transition-minimised 9-bit intermediate.  Bits 0..7 are
-- the chained data, bit 8 is 1 for the XOR chain and 0 for XNOR.
tmdsMinimise :: BitVector 8 -> BitVector 9
tmdsMinimise d = q8 ++# v2bv q
 where
  n1 :: Unsigned 4
  n1 = fromIntegral (popCount d)
  useXnor = n1 > 4 || (n1 == 4 && d ! (0 :: Int) == 0)
  q8 :: BitVector 1
  q8 = if useXnor then 0 else 1
  dv = reverse (bv2v d)   -- index i = bit i
  op a b = if useXnor then complement (xor a b) else xor a b
  qv = scanl1 op dv       -- q[0] = d[0]; q[i] = q[i-1] op d[i]
  q  = reverse qv         -- back to MSB-first for v2bv

-- | The four control-period words, indexed by @(c1, c0)@ = @{c1,c0}@.
tmdsControl :: BitVector 2 -> BitVector 10
tmdsControl c = case c of
  0 -> 0b1101010100
  1 -> 0b0010101011
  2 -> 0b0101010100
  _ -> 0b1011010100

-- | One pixel clock of the encoder, purely combinational:
-- (disparity, data enable, (c1, c0), data) -> (word, disparity').
tmdsEncodeStep
  :: Disparity -> Bool -> BitVector 2 -> BitVector 8
  -> (BitVector 10, Disparity)
tmdsEncodeStep cnt de c d
  | not de    = (tmdsControl c, 0)
  | otherwise = (out, cnt')
 where
  qm  = tmdsMinimise d
  q8  = slice d8 d8 qm :: BitVector 1
  qd  = truncateB qm :: BitVector 8
  n1q, n0q :: Signed 6
  n1q = fromIntegral (popCount qd)
  n0q = 8 - n1q
  q8s = if q8 == 1 then 1 else 0 :: Signed 6

  balanced = cnt == 0 || n1q == n0q
  invert   = (cnt > 0 && n1q > n0q) || (cnt < 0 && n0q > n1q)

  (out, cnt')
    | balanced  = ( (complement q8) ++# q8 ++# (if q8 == 1 then qd else complement qd)
                  , if q8 == 1 then cnt + (n1q - n0q) else cnt + (n0q - n1q) )
    | invert    = ( 1 ++# q8 ++# complement qd
                  , cnt + 2 * q8s + (n0q - n1q) )
    | otherwise = ( 0 ++# q8 ++# qd
                  , cnt - 2 * (1 - q8s) + (n1q - n0q) )

-- | Registered per-channel encoder: inputs sampled each pixel clock,
-- word out one cycle later, disparity carried in a register.
tmdsEncoder
  :: HiddenClockResetEnable dom
  => Signal dom Bool          -- ^ data enable
  -> Signal dom (BitVector 2) -- ^ (c1, c0): (vsync, hsync) on channel 0
  -> Signal dom (BitVector 8) -- ^ pixel data
  -> Signal dom (BitVector 10)
tmdsEncoder de c d = register (tmdsControl 0) word
 where
  cnt = register 0 cnt'
  (word, cnt') = unbundle (tmdsEncodeStep <$> cnt <*> de <*> c <*> d)

-- | 10:1 bit sequencer in the bit-clock domain: loads the word on
-- 'load' (assert once every 10 bit-clocks), otherwise shifts; the
-- output is the current LSB, so bit 0 is sent first.
tmdsShift
  :: HiddenClockResetEnable dom
  => Signal dom Bool
  -> Signal dom (BitVector 10)
  -> Signal dom Bit
tmdsShift load word = lsb <$> sr
 where
  sr = register 0 (mux load word (shiftR <$> sr <*> pure 1))
