{-# LANGUAGE RecordWildCards #-}
-- PM.Seq — the VL-1 100-note sequencer (REC / PLAY / One-Key-Play).
--
--   * Entry     : (note Unsigned 7, duration Unsigned 8 ticks) packed into a
--                 BitVector 15 in a 100-word blockRam (1-cycle read latency).
--   * SeqMode   : MStop (live keys pass through), MRec, MPlay, MOkp.
--                 Entering MRec clears the memory count; entering MPlay or
--                 MOkp rewinds to entry 0.
--   * MRec      : live keys pass through to the voice. A key press starts a
--                 tick count; the release appends (note, ticks held) at the
--                 write pointer. At 100 entries further notes are dropped.
--   * MPlay     : each entry sounds for its duration in tempo ticks, then a
--                 one-tick gap (so repeated notes retrigger), then the next;
--                 playback stops (gate low) after the last recorded entry.
--   * MOkp      : each key press sounds the next entry for as long as the
--                 key is held; the pointer wraps to 0 after the last entry.
--   * Output    : SeqCmd { cmdNote, cmdGate } drives PM.Synth.voice's
--                 semitone and gate directly; cmdLen / cmdPos expose the
--                 recorded length and current position.
module PM.Seq where

import Clash.Prelude

data SeqMode = MStop | MRec | MPlay | MOkp
  deriving (Generic, NFDataX, Eq, Show)

data Ph = PhIdle | PhFetch | PhLoad | PhOn | PhGap | PhArmed
  deriving (Generic, NFDataX, Eq, Show)

data SeqCmd = SeqCmd
  { cmdNote :: Unsigned 7
  , cmdGate :: Bool
  , cmdLen  :: Index 101
  , cmdPos  :: Index 101
  } deriving (Generic, NFDataX, Show)

data SeqSt = SeqSt
  { sMode :: !SeqMode
  , sPh   :: !Ph
  , sWr   :: !(Index 101)    -- recorded length / write pointer
  , sRd   :: !(Index 101)    -- play pointer
  , sNote :: !(Unsigned 7)   -- current note (recording or playing)
  , sDur  :: !(Unsigned 8)   -- ticks held (rec) / ticks remaining (play)
  , sKey  :: !Bool           -- key held last cycle (edge detect)
  } deriving (Generic, NFDataX)

packEntry :: Unsigned 7 -> Unsigned 8 -> BitVector 15
packEntry n d = pack n ++# pack d

unpackEntry :: BitVector 15 -> (Unsigned 7, Unsigned 8)
unpackEntry v = (unpack (slice d14 d8 v), unpack (slice d7 d0 v))

ramAddr :: Index 101 -> Index 100
ramAddr i = if i == maxBound then 0 else resize i

type SeqIn  = (SeqMode, Maybe (Unsigned 7), Bool, BitVector 15)   -- mode, key, tick, ram read
type SeqOut = (SeqCmd, Maybe (Index 100, BitVector 15), Index 100) -- cmd, ram write, ram read addr

seqT :: SeqSt -> SeqIn -> (SeqSt, SeqOut)
seqT st@SeqSt{..} (mode, key, tick, ram)
  | mode /= sMode = (enter, out st { sMode = mode } False 0)
  | otherwise = case sMode of
      MStop -> (st { sKey = held }, out st held keyNote)
      MRec
        | rise -> (st { sKey = True, sNote = keyNote, sDur = 0 }, out st True keyNote)
        | fall, sWr < 100 ->
            ( st { sKey = False, sWr = sWr + 1 }
            , (cmd st False sNote, Just (ramAddr sWr, packEntry sNote sDur), ramAddr sRd) )
        | fall -> (st { sKey = False }, out st False sNote)
        | held && tick -> (st { sDur = satSucc SatBound sDur }, out st True keyNote)
        | otherwise -> (st, out st held keyNote)
      MPlay -> case sPh of
        PhFetch -> (st { sPh = PhLoad }, out st False sNote)
        PhLoad
          | sRd >= sWr -> (st { sPh = PhIdle }, out st False sNote)
          | otherwise -> let (n, d) = unpackEntry ram
                         in (st { sPh = PhOn, sNote = n, sDur = if d == 0 then 1 else d }, out st False n)
        PhOn
          | tick && sDur == 1 -> (st { sPh = PhGap, sRd = sRd + 1 }, out st True sNote)
          | tick -> (st { sDur = sDur - 1 }, out st True sNote)
          | otherwise -> (st, out st True sNote)
        PhGap
          | tick -> (st { sPh = PhFetch }, out st False sNote)
          | otherwise -> (st, out st False sNote)
        _ -> (st, out st False sNote)
      MOkp -> case sPh of
        PhFetch -> (st { sPh = PhLoad, sKey = held }, out st False sNote)
        PhLoad
          | sWr == 0 -> (st { sPh = PhIdle, sKey = held }, out st False sNote)
          | otherwise -> let (n, _) = unpackEntry ram
                         in (st { sPh = PhArmed, sNote = n, sKey = held }, out st False n)
        PhArmed
          | rise -> (st { sPh = PhOn, sKey = True }, out st True sNote)
          | otherwise -> (st { sKey = held }, out st False sNote)
        PhOn
          | fall -> let nxt = if sRd + 1 >= sWr then 0 else sRd + 1
                    in (st { sPh = PhFetch, sRd = nxt, sKey = False }, out st False sNote)
          | otherwise -> (st, out st True sNote)
        _ -> (st { sKey = held }, out st False sNote)
 where
  held    = case key of { Just _ -> True; Nothing -> False }
  keyNote = case key of { Just n -> n; Nothing -> sNote }
  rise    = held && not sKey
  fall    = not held && sKey
  enter = case mode of
    MStop -> st { sMode = mode, sPh = PhIdle, sKey = held }
    MRec  -> st { sMode = mode, sPh = PhIdle, sWr = 0, sKey = held }
    MPlay -> st { sMode = mode, sPh = PhFetch, sRd = 0, sKey = held }
    MOkp  -> st { sMode = mode, sPh = PhFetch, sRd = 0, sKey = held }
  cmd SeqSt { sWr = w, sRd = r } g n = SeqCmd { cmdNote = n, cmdGate = g, cmdLen = w, cmdPos = r }
  out s@SeqSt { sRd = r } g n = (cmd s g n, Nothing, ramAddr r)

seqInit :: SeqSt
seqInit = SeqSt MStop PhIdle 0 0 0 0 False

sequencer
  :: HiddenClockResetEnable dom
  => Signal dom SeqMode
  -> Signal dom (Maybe (Unsigned 7))   -- live key: Just note while held
  -> Signal dom Bool                   -- tempo tick
  -> Signal dom SeqCmd
sequencer mode key tick = cmdS
 where
  (cmdS, wr, rd) = unbundle (mealy seqT seqInit (bundle (mode, key, tick, ram)))
  ram = blockRam (replicate d100 (0 :: BitVector 15)) rd wr
