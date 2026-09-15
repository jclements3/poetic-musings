{-# LANGUAGE RecordWildCards #-}
-- PM.Wspr — the WSPR symbol sequencer (UHF/DESIGN.md, "Symbol timing" and
-- "Hardware TX interlock"; CLASH-LIBRARY-MAP "WSPR modulator").
--
-- Forth does the encoding (callsign/grid/power -> 162 symbols 0..3, see
-- golden/wspr_model.py) and writes the table into a 256-entry blockRam
-- through `wr`.  The gateware only replays it in real time:
--
--   * `start` strobe (even-minute tick from the GPS/IRIG block) while
--     `armed` -> walk symbols 0..161, one per `symDiv` clocks.  symDiv is
--     the runtime tick divider: system clock / 1.4648 baud, i.e.
--     round(f_clk * 8192 / 12000) — 17 066 667 at 25 MHz.
--   * `symbol`   : the current 2-bit symbol (blockRam output, 1 clock after
--                  the index advances; `txOn` is delayed to match).
--   * `phaseInc` : baseInc + symbol * toneStep, for the existing NCO/DAC.
--                  toneStep = 1.4648 Hz * 2^32 / f_nco, loaded by Forth.
--   * `txOn`     : high for exactly 162 symbol periods (110.6 s) — ANDed
--                  combinationally with `armed` (PM.RegFile oTxGate key +
--                  S3 zone C), so it can never assert unarmed and drops the
--                  same clock `armed` does.  A disarm also aborts the walk.
--   * `done`     : one-clock strobe after the 162nd symbol period.
module PM.Wspr where

import Clash.Prelude

-- ---------------------------------------------------------------------------
-- Sequencer state.

data Seq = Seq
  { sRun :: !Bool
  , sIdx :: !(Unsigned 8)     -- symbol index 0..161
  , sCnt :: !(Unsigned 32)    -- clocks into the current symbol
  } deriving (Generic, NFDataX)

-- Transition: (armed, start, symDiv) -> (running, index, done).
seqT :: Seq -> (Bool, Bool, Unsigned 32) -> (Seq, (Bool, Unsigned 8, Bool))
seqT s@Seq{..} (armed, start, symDiv)
  | not armed             = (Seq False 0 0, (False, 0, False))       -- abort / idle
  | not sRun              = if start then (Seq True 0 1, (True, 0, False))   -- start clock is clock 1 of symbol 0
                                     else (s, (False, 0, False))
  | sCnt + 1 < symDiv     = (s { sCnt = sCnt + 1 }, (True, sIdx, False))
  | sIdx == 161           = (Seq False 0 0, (True, sIdx, True))       -- last period ends
  | otherwise             = (s { sIdx = sIdx + 1, sCnt = 0 }, (True, sIdx, False))

-- ---------------------------------------------------------------------------
-- The sequencer.

wspr
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe (Unsigned 8, Unsigned 2))  -- symbol table write (Forth)
  -> Signal dom Bool                              -- armed (PM.RegFile interlock)
  -> Signal dom Bool                              -- start strobe (even-minute tick)
  -> Signal dom (Unsigned 32)                     -- symDiv: clocks per symbol
  -> Signal dom (Unsigned 32)                     -- baseInc: NCO increment, tone 0
  -> Signal dom (Unsigned 32)                     -- toneStep: increment per tone
  -> ( Signal dom (Unsigned 2)                    -- symbol
     , Signal dom Bool                            -- txOn
     , Signal dom (Unsigned 32)                   -- phaseInc
     , Signal dom Bool )                          -- done
wspr wr armed start symDiv baseInc toneStep = (symbol, txOn, phaseInc, done)
 where
  (running, idx, doneRaw) = unbundle (mealy seqT (Seq False 0 0) (bundle (armed, start, symDiv)))
  symbol   = blockRam (replicate d256 0) idx wr
  runningD = register False running       -- align with the blockRam read latency
  txOn     = runningD .&&. armed
  done     = register False (register False doneRaw)   -- lands the clock after txOn falls
  phaseInc = (+) <$> baseInc <*> ((*) <$> toneStep <*> (resize <$> symbol))

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Maybe (Unsigned 8, Unsigned 2))
  -> Signal System Bool
  -> Signal System Bool
  -> Signal System (Unsigned 32)
  -> Signal System (Unsigned 32)
  -> Signal System (Unsigned 32)
  -> ( Signal System (Unsigned 2), Signal System Bool
     , Signal System (Unsigned 32), Signal System Bool )
topEntity = exposeClockResetEnable wspr
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_wspr"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "sym_wr", PortName "armed", PortName "start"
                 , PortName "sym_div", PortName "base_inc", PortName "tone_step" ]
    , t_output = PortProduct "" [ PortName "symbol", PortName "tx_on"
                                , PortName "phase_inc", PortName "done" ]
    }) #-}
