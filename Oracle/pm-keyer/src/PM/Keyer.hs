{-# LANGUAGE RecordWildCards #-}
-- PM.Keyer — CW keyer and decoder for the Oracle console (O5, eforth-pm.md 0x4030).
--
-- Two halves, sharing one timing base (the CW "unit", PARIS convention:
-- dot = 1u, dash = 3u, intra-element gap = 1u, letter gap = 3u, word gap = 7u):
--
--   * keyer   : character stream in -> keyed line out (plus sidetone gate).
--               A message keyer: the CPU writes ASCII, gateware plays the
--               elements with correct timing. A straight key ORs onto the
--               same line at the top entity.
--   * decoder : keyed line in -> ASCII out. Run-length classifies marks
--               (dash if > 2u) and spaces (letter gap if >= 2u.., word gap
--               if >= 5u), walks the Morse code accumulated as (bits, count).
--
-- The unit length in ticks is a runtime input (WPM control: unit ticks =
-- clk / (WPM * 50 / 60); Forth computes it, gateware just counts), so the
-- same hardware serves 5 WPM teaching and 25 WPM operating.
module PM.Keyer where

import Clash.Prelude

-- Morse code as (elements MSB-first, element count); dot = 0, dash = 1.
-- Letters A-Z and digits 0-9; anything else keys nothing (treated as space).
morse :: Char -> Maybe (Unsigned 8, Unsigned 4)
morse c = case c of
  'A' -> Just (0b01, 2);       'B' -> Just (0b1000, 4)
  'C' -> Just (0b1010, 4);     'D' -> Just (0b100, 3)
  'E' -> Just (0b0, 1);        'F' -> Just (0b0010, 4)
  'G' -> Just (0b110, 3);      'H' -> Just (0b0000, 4)
  'I' -> Just (0b00, 2);       'J' -> Just (0b0111, 4)
  'K' -> Just (0b101, 3);      'L' -> Just (0b0100, 4)
  'M' -> Just (0b11, 2);       'N' -> Just (0b10, 2)
  'O' -> Just (0b111, 3);      'P' -> Just (0b0110, 4)
  'Q' -> Just (0b1101, 4);     'R' -> Just (0b010, 3)
  'S' -> Just (0b000, 3);      'T' -> Just (0b1, 1)
  'U' -> Just (0b001, 3);      'V' -> Just (0b0001, 4)
  'W' -> Just (0b011, 3);      'X' -> Just (0b1001, 4)
  'Y' -> Just (0b1011, 4);     'Z' -> Just (0b1100, 4)
  '0' -> Just (0b11111, 5);    '1' -> Just (0b01111, 5)
  '2' -> Just (0b00111, 5);    '3' -> Just (0b00011, 5)
  '4' -> Just (0b00001, 5);    '5' -> Just (0b00000, 5)
  '6' -> Just (0b10000, 5);    '7' -> Just (0b11000, 5)
  '8' -> Just (0b11100, 5);    '9' -> Just (0b11110, 5)
  _   -> Nothing

-- Inverse: (elements, count) -> ASCII. Unmatched patterns decode as '?'.
unmorse :: (Unsigned 8, Unsigned 4) -> Char
unmorse p = case p of
  (0b01, 2) -> 'A';    (0b1000, 4) -> 'B';  (0b1010, 4) -> 'C'
  (0b100, 3) -> 'D';   (0b0, 1) -> 'E';     (0b0010, 4) -> 'F'
  (0b110, 3) -> 'G';   (0b0000, 4) -> 'H';  (0b00, 2) -> 'I'
  (0b0111, 4) -> 'J';  (0b101, 3) -> 'K';   (0b0100, 4) -> 'L'
  (0b11, 2) -> 'M';    (0b10, 2) -> 'N';    (0b111, 3) -> 'O'
  (0b0110, 4) -> 'P';  (0b1101, 4) -> 'Q';  (0b010, 3) -> 'R'
  (0b000, 3) -> 'S';   (0b1, 1) -> 'T';     (0b001, 3) -> 'U'
  (0b0001, 4) -> 'V';  (0b011, 3) -> 'W';   (0b1001, 4) -> 'X'
  (0b1011, 4) -> 'Y';  (0b1100, 4) -> 'Z'
  (0b11111, 5) -> '0'; (0b01111, 5) -> '1'; (0b00111, 5) -> '2'
  (0b00011, 5) -> '3'; (0b00001, 5) -> '4'; (0b00000, 5) -> '5'
  (0b10000, 5) -> '6'; (0b11000, 5) -> '7'; (0b11100, 5) -> '8'
  (0b11110, 5) -> '9'
  _ -> '?'

-- ---------------------------------------------------------------------------
-- Keyer: plays queued characters as keyed elements.

data KSt = KSt
  { kBusy  :: !Bool
  , kBits  :: !(Unsigned 8)   -- remaining elements, MSB-first in kLeft bits
  , kLeft  :: !(Unsigned 4)   -- elements remaining
  , kMark  :: !Bool           -- currently keying a mark
  , kCnt   :: !(Unsigned 24)  -- ticks remaining in the current mark/space
  , kSpace :: !(Unsigned 24)  -- pending inter-letter/word gap after last element
  } deriving (Generic, NFDataX)

kInit :: KSt
kInit = KSt False 0 0 False 0 0

-- input: (unit ticks, Maybe char). Accepts a char only when idle (busy is
-- exported; the 0x4030 register exposes it as tx-ready). Space chars insert
-- a word gap. Output: (keyed line, busy).
keyerT :: KSt -> (Unsigned 24, Maybe Char) -> (KSt, (Bool, Bool))
keyerT s@KSt{..} (unit, mc)
  | kCnt /= 0 = (s { kCnt = kCnt - 1 }, (kMark, True))
  | kMark
  = -- a mark just ended: inter-element gap (1u) or trailing letter gap
    let s' = s { kMark = False
               , kCnt = if kLeft == 0 then kSpace else unit - 1 }
    in (s', (False, True))
  | kBusy && kLeft /= 0
  = -- start the next element: dot 1u, dash 3u
    let dash = testBit kBits (fromIntegral kLeft - 1)
        s' = s { kMark = True
               , kCnt = (if dash then 3 * unit else unit) - 1
               , kLeft = kLeft - 1 }
    in (s', (True, True))
  | kBusy = (s { kBusy = False }, (False, False))   -- trailing gap done
  | otherwise = case mc of
      Just ' ' -> (s { kBusy = True, kLeft = 0, kCnt = 4 * unit - 1 }, (False, True))
                  -- 3u letter gap already sent after last char; +4u = 7u word gap
      Just c | Just (bits, n) <- morse c
        -> (s { kBusy = True, kBits = bits, kLeft = n
              , kSpace = 3 * unit - 1 }, (False, True))
      _ -> (s, (False, False))

keyer
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 24)          -- unit ticks
  -> Signal dom (Maybe Char)           -- char strobe
  -> Signal dom (Bool, Bool)           -- (key line, busy)
keyer u c = mealy keyerT kInit (bundle (u, c))

-- ---------------------------------------------------------------------------
-- Decoder: keyed line -> ASCII.

data DSt = DSt
  { dLine  :: !Bool
  , dRun   :: !(Unsigned 24)  -- ticks in the current run (saturating)
  , dBits  :: !(Unsigned 8)
  , dCount :: !(Unsigned 4)
  , dDone  :: !Bool           -- letter gap already emitted for this idle
  , dWord  :: !Bool           -- word gap already emitted
  } deriving (Generic, NFDataX)

dInit :: DSt
dInit = DSt False 0 0 0 True True

-- Emits Just Char at letter boundaries and Just ' ' at word boundaries.
decoderT :: DSt -> (Unsigned 24, Bool) -> (DSt, Maybe Char)
decoderT s@DSt{..} (unit, line)
  | line /= dLine, dLine
  = -- mark ended: classify dot/dash into the accumulator
    let dash = dRun > 2 * unit
        s' = s { dLine = line, dRun = 1
               , dBits = shiftL dBits 1 .|. (if dash then 1 else 0)
               , dCount = satAdd SatBound dCount 1
               , dDone = False, dWord = False }
    in (s', Nothing)
  | line /= dLine
  = (s { dLine = line, dRun = 1 }, Nothing)         -- space ended, mark begins
  | not line, not dDone, dRun >= 2 * unit, dCount /= 0
  = -- letter gap: emit the accumulated character
    (s { dRun = satAdd SatBound dRun 1, dDone = True, dBits = 0, dCount = 0 }
    , Just (unmorse (dBits, dCount)))
  | not line, not dWord, dRun >= 5 * unit
  = (s { dRun = satAdd SatBound dRun 1, dWord = True }, Just ' ')
  | otherwise
  = (s { dRun = satAdd SatBound dRun 1 }, Nothing)

decoder
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 24)
  -> Signal dom Bool
  -> Signal dom (Maybe Char)
decoder u l = mealy decoderT dInit (bundle (u, l))

-- ---------------------------------------------------------------------------
-- Top entity: straight key in (debounced upstream) OR message keyer, decoder
-- listening to the combined line, sidetone gate = line. Char I/O is exposed
-- for the 0x4030 register file (O phase); here as plain ports.

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System (Unsigned 24)              -- unit ticks (WPM)
  -> Signal System Bool                       -- straight key
  -> Signal System (Maybe (Unsigned 8))       -- tx char strobe (ASCII)
  -> Signal System (Bool, Bool, Maybe (Unsigned 8))
     -- (keyed line / sidetone gate, tx busy, decoded ASCII strobe)
topEntity = exposeClockResetEnable $ \u skey txc ->
  let kc = fmap (fmap (toEnum . fromIntegral)) txc
      kout = keyer u kc
      (kline, kbusy) = unbundle kout
      line = (||) <$> skey <*> kline
      dch  = decoder u line
      dout = fmap (fmap (fromIntegral . fromEnum)) dch
  in bundle (line, kbusy, dout)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_keyer"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "unit", PortName "straight_key", PortName "tx_char" ]
    , t_output = PortName "out"
    }) #-}
