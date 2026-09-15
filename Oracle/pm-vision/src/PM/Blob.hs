{-# LANGUAGE RecordWildCards #-}
-- PM.Blob — threshold + single-pass run-length blob labeller with per-blob
-- centroids (Imaging/DESIGN.md, Architecture and "Centroid, per ball").
--
--   * threshold  : Unsigned 8 with hysteresis (oImgThresh, 0x4064): a pixel is
--                  foreground when v >= thr, or when v >= thr - hyst and the
--                  previous pixel of the same line was foreground.
--   * labelling  : 8-connected, one pass, one line buffer.  Each foreground
--                  pixel takes the label of an already-labelled neighbour —
--                  (x-1,y) on the current line, (x-1..x+1, y-1) from the line
--                  buffer — or a fresh one (32 labels per frame; a 33rd sets
--                  the sticky overflow flag and the pixel is dropped).  Where
--                  the neighbours carry different labels their roots are
--                  unioned in one cycle by *relabelling the flat parent table*
--                  (every entry equal to a merged root is rewritten to the
--                  target root), so parent !! l is always a root.
--   * accumulate : per provisional label: sum x (28b), sum y (28b), count
--                  (18b), bbox — an Acc of 112 bits, held in a label-indexed
--                  blockRam (32 x 112, single read port + single write port),
--                  NOT in the mealy state: a 32-entry Vec of Acc in registers
--                  cost 35k LUT4 of muxes (measurements/2026-09-15-area-A.md).
--                  The per-pixel path is a read-modify-write with a one-cycle
--                  pipeline: the labelled pixel issues the read of acc[label]
--                  and the next cycle adds (x, y) and writes it back.  Still
--                  one pixel per clock.  Hazards are closed by a single
--                  forwarding register holding the last (label, Acc) written:
--                  a read whose label equals it uses the register (the RAM
--                  read would miss a write of the previous cycle).  A 32-bit
--                  valid mask marks labels written this frame; a read of an
--                  unwritten label yields accEmpty, which replaces clearing
--                  the RAM at sof.
--   * parent table: 32 x 5 bits stays in registers (160 FF, ~300 LUT4) with
--                  the one-cycle flat relabel above: at that size it is far
--                  cheaper than a parent-pointer RAM with find-on-read, keeps
--                  parent !! l a root at all times, and gives the identical
--                  root (the picked label's root) for every merge.
--   * end of frame (after the eof pixel drains, whose write lands in the
--                  first merge cycle): merge phase, 2 cycles per label — read
--                  acc[l], read acc[root l], and in the following label's first
--                  cycle write acc[root] = acc[root] + acc[l] (the forwarding
--                  register covers the read of the label just written); then a
--                  scan over the 32 labels, 2 cycles per label (read, decide),
--                  latching the Acc of each root whose count lies in [minArea,
--                  maxArea] and running a 32-step restoring shift-subtract
--                  divide (cx and cy in parallel) that emits one BlobRec with a
--                  valid strobe; the scan ends with boFrameDone.  Worst case
--                  64 + 64 + 32*32 = 1152 cycles, which must fit in vertical
--                  blanking: pixels that arrive while the end-of-frame phases
--                  run are dropped and set the sticky boDropped flag.
--   * throughput : 1 clock per pixel while labelling (640x400 at 200 fps is
--                  51.2 Mpx/s, i.e. 0.51 clocks per pixel at 100 MHz, plus
--                  <= 1152 cycles (11.5 us) once per frame; the frame period
--                  is 5 ms).
--   * centroid   : cx_q4 = round(16 * sum x / count) (ties up) — an unweighted
--                  (binary) centroid in pixel-index units, the record's cx_q4 /
--                  cy_q4 fields of PROTOCOL.md 0x20 CENTROID.  count is
--                  saturated to the record's 16-bit sum_w.
--
-- Limitation (documented, tested): 8-connectivity means two balls that touch
-- even at a single diagonal pixel pair become ONE blob with a centroid between
-- them; the max-area register rejects such doubled blobs (~138 px vs ~69), and
-- software association must bridge the gap.
--
-- The pixel pipeline: a pixel arriving on pixIn issues the line-buffer read of
-- its own x (previous line's label).  Stage A holds the arrived pixel while
-- its read completes; stage B holds the pixel being labelled together with its
-- previous-line label; A's read data serves as B's (x+1, y-1) neighbour and a
-- register keeps B's read as the next pixel's (x-1, y-1) neighbour.  The
-- pipeline advances when a pixel arrives, and drains itself after an eol pixel
-- so a line is fully labelled without waiting for the next one.  Gaps between
-- pixels (idle cycles) are tolerated: the read address holds.
module PM.Blob where

import Clash.Prelude
import Data.Maybe (isNothing)

import PM.Dvp (Pix(..))

-- ---------------------------------------------------------------------------
-- Threshold with hysteresis.

data BlobCfg = BlobCfg
  { cThr     :: !(Unsigned 8)
  , cHyst    :: !(Unsigned 8)
  , cMinArea :: !(Unsigned 18)
  , cMaxArea :: !(Unsigned 18)
  } deriving (Generic, NFDataX, Eq, Show)

-- | fgPrev -> (thr, hyst, value) -> foreground
thresholdT :: Bool -> (Unsigned 8, Unsigned 8, Unsigned 8) -> Bool
thresholdT fgPrev (thr, hyst, v) = v >= thr || (fgPrev && v >= lo)
 where lo = if hyst > thr then 0 else thr - hyst

-- ---------------------------------------------------------------------------
-- Labels, accumulators, records.

type Label = Index 32

data Acc = Acc
  { aSx :: !(Unsigned 28)
  , aSy :: !(Unsigned 28)
  , aN  :: !(Unsigned 18)
  , aX0 :: !(Unsigned 10)
  , aX1 :: !(Unsigned 10)
  , aY0 :: !(Unsigned 9)
  , aY1 :: !(Unsigned 9)
  } deriving (Generic, NFDataX, Eq, Show)

accEmpty :: Acc
accEmpty = Acc 0 0 0 maxBound 0 maxBound 0

accAdd :: Acc -> (Unsigned 10, Unsigned 9) -> Acc
accAdd Acc{..} (x, y) = Acc
  { aSx = aSx + resize x, aSy = aSy + resize y, aN = aN + 1
  , aX0 = min aX0 x, aX1 = max aX1 x, aY0 = min aY0 y, aY1 = max aY1 y }

accMerge :: Acc -> Acc -> Acc
accMerge a b = Acc
  { aSx = aSx a + aSx b, aSy = aSy a + aSy b, aN = aN a + aN b
  , aX0 = min (aX0 a) (aX0 b), aX1 = max (aX1 a) (aX1 b)
  , aY0 = min (aY0 a) (aY0 b), aY1 = max (aY1 a) (aY1 b) }

-- | One blob of the frame just finished (PROTOCOL.md 0x20 CENTROID payload
-- less rtc/seq, which the record mux adds).
data BlobRec = BlobRec
  { bLabel :: !(Unsigned 8)
  , bCx    :: !(Unsigned 16)   -- Q4 pixel x
  , bCy    :: !(Unsigned 16)   -- Q4 pixel y
  , bCount :: !(Unsigned 16)   -- pixels, saturated
  , bX0    :: !(Unsigned 10)
  , bX1    :: !(Unsigned 10)
  , bY0    :: !(Unsigned 9)
  , bY1    :: !(Unsigned 9)
  } deriving (Generic, NFDataX, Eq, Show)

data BlobOut = BlobOut
  { boRec       :: !(Maybe BlobRec)
  , boFrameDone :: !Bool   -- strobe: all records of the frame are out
  , boOverflow  :: !Bool   -- sticky until next sof: more than 32 labels
  , boDropped   :: !Bool   -- sticky until next sof: pixel arrived during eof phases
  } deriving (Generic, NFDataX, Eq, Show)

-- ---------------------------------------------------------------------------
-- Labeller state.

data StageA = StageA { saPix :: !Pix, saFg :: !Bool }
  deriving (Generic, NFDataX)

data StageB = StageB { sbPix :: !Pix, sbFg :: !Bool, sbPrev :: !(Maybe Label) }
  deriving (Generic, NFDataX)

data Phase = PhLabel | PhMerge | PhScan | PhDiv
  deriving (Generic, NFDataX, Eq, Show)

data BlobSt = BlobSt
  { bsA        :: !(Maybe StageA)
  , bsB        :: !(Maybe StageB)
  , bsFgPrev   :: !Bool             -- hysteresis, in arrival order
  , bsLastX    :: !(Unsigned 10)    -- x of the last labelled pixel
  , bsLastCur  :: !(Maybe Label)    -- its label (current line)
  , bsLastPrev :: !(Maybe Label)    -- its previous-line label
  , bsNext     :: !(Unsigned 6)     -- next free label, 32 = full
  , bsParent   :: !(Vec 32 Label)   -- flat: every entry is a root
  , bsPend     :: !(Maybe (Label, Unsigned 10, Unsigned 9))  -- pixel whose acc read is in flight
  , bsRdLab    :: !Label            -- label whose acc read was issued last cycle
  , bsFwd      :: !(Label, Acc)     -- last acc written (forwarding)
  , bsValid    :: !(BitVector 32)   -- acc[l] written this frame
  , bsAccL     :: !Acc              -- merge: acc[l] latched; scan/divide: acc of bsIdx
  , bsMPend    :: !Bool             -- merge: write acc[bsRdLab] += bsAccL this cycle
  , bsPhase    :: !Phase
  , bsIdx      :: !(Unsigned 5)     -- label under merge / scan / divide
  , bsStep     :: !(Unsigned 5)     -- merge/scan sub-step, divide iteration
  , bsNx       :: !(Unsigned 32)    -- numerators, shifting left
  , bsNy       :: !(Unsigned 32)
  , bsQx       :: !(Unsigned 16)    -- quotients, shifting in
  , bsQy       :: !(Unsigned 16)
  , bsRx       :: !(Unsigned 19)    -- partial remainders
  , bsRy       :: !(Unsigned 19)
  , bsOverflow :: !Bool
  , bsDropped  :: !Bool
  } deriving (Generic, NFDataX)

blobInit :: BlobSt
blobInit = BlobSt Nothing Nothing False maxBound Nothing Nothing 0 indicesI
                  Nothing 0 (0, accEmpty) 0 accEmpty False
                  PhLabel 0 0 0 0 0 0 0 0 False False

-- | Restoring divide, one step: (numerator, quotient, remainder) with divisor d.
divStep :: Unsigned 18 -> (Unsigned 32, Unsigned 16, Unsigned 19)
        -> (Unsigned 32, Unsigned 16, Unsigned 19)
divStep d (n, q, r) =
  let r1 = (r `shiftL` 1) .|. (if msb n == 1 then 1 else 0)
      ge = r1 >= resize d
  in (n `shiftL` 1, (q `shiftL` 1) .|. (if ge then 1 else 0), if ge then r1 - resize d else r1)

-- | Type of the line-buffer write port.
type LineWr = Maybe (Unsigned 10, Maybe Label)

-- | Accumulator RAM ports: read address (data next cycle), write.
type AccWr = Maybe (Label, Acc)

-- | Inputs: config, pixel, line-buffer read, acc RAM read (of the address
-- output last cycle).  Outputs: line-buffer write, acc read address, acc
-- write, records.
blobT :: BlobSt -> (BlobCfg, Maybe Pix, Maybe Label, Acc)
      -> (BlobSt, (LineWr, Label, AccWr, BlobOut))
blobT st (BlobCfg{..}, pixIn, rd, accRam) = (st4, (wr, accAddr, accWr, out))
 where
  -- acc read data of last cycle's address, forwarded and masked
  accIn | not (testBit (bsValid st) (fromIntegral (bsRdLab st))) = accEmpty
        | fst (bsFwd st) == bsRdLab st = snd (bsFwd st)
        | otherwise = accRam
  -- pending pixel accumulate (read issued last cycle)
  -- (a write in flight when a sof pixel is labelled belongs to the old frame)
  sofNow = case labelling of
    Just sb -> pSof (sbPix sb) && bsPhase st == PhLabel
    Nothing -> False
  pixWr = if sofNow then Nothing
          else fmap (\(l, x, y) -> (l, accAdd accIn (x, y))) (bsPend st)
  st0 = st { bsPend = Nothing }
  -- threshold at arrival
  fgIn = maybe False (\p -> thresholdT (bsFgPrev st) (cThr, cHyst, pVal p)) pixIn
  fgPrev' = case pixIn of
    Just p  -> not (pEol p) && fgIn
    Nothing -> bsFgPrev st
  aEol = maybe False (pEol . saPix) (bsA st)
  bEol = maybe False (pEol . sbPix) (bsB st)
  advance = case pixIn of
    Just _  -> True
    Nothing -> aEol || (isNothing (bsA st) && bEol)
  -- the pixel to label this cycle, with its previous-line label
  labelling = if advance then bsB st else Nothing
  -- pipeline shift
  a' = if advance then fmap (\p -> StageA p fgIn) pixIn else bsA st
  b' = if advance then fmap (\StageA{..} -> StageB saPix saFg rd) (bsA st) else bsB st
  st1 = st0 { bsA = a', bsB = b', bsFgPrev = fgPrev' }

  -- end-of-frame phases (run regardless of the pipeline)
  (st2, rec0, done, eofAddr, eofWr) = eofPhase st1
  -- labelling of B
  (st3, wr, pixAddr) = case labelling of
    Nothing -> (st2, Nothing, Nothing)
    Just sb
      | bsPhase st /= PhLabel -> (st2 { bsDropped = True }, Nothing, Nothing)
      | otherwise          -> labelPixel st2 sb
  -- the pixel path owns the RAM ports while labelling, the eof phases after
  -- the eof pixel; the two never write in the same cycle (the eof pixel's
  -- write lands in the first merge cycle, whose write is idle).
  accWr = case pixWr of
    Just w  -> Just w
    Nothing -> eofWr
  accAddr = case pixAddr of
    Just a  -> a
    Nothing -> eofAddr
  st4 = st3 { bsRdLab = accAddr
            , bsFwd = maybe (bsFwd st3) id accWr
            , bsValid = case accWr of
                Just (l, _) -> setBit (bsValid st3) (fromIntegral l)
                Nothing     -> bsValid st3 }
  out = BlobOut rec0 done (bsOverflow st4) (bsDropped st4)

  -- (x+1, y-1) neighbour: A's read, valid when A is the next pixel of the line
  prevRight x = case bsA st of
    Just StageA{..} | pX saPix == x + 1 -> rd
    _ -> Nothing

  labelPixel :: BlobSt -> StageB -> (BlobSt, LineWr, Maybe Label)
  labelPixel s0 StageB{..} = (sN, Just (x, lab), lab)
   where
    Pix{..} = sbPix
    x = pX; y = pY
    s = if pSof then s0 { bsNext = 0, bsParent = indicesI, bsValid = 0
                        , bsOverflow = False, bsDropped = False, bsLastCur = Nothing }
                else s0
    adj = bsLastX s == x - 1
    prevOk = y /= 0
    nLeft = if adj then bsLastCur s else Nothing
    nUL   = if adj && prevOk then bsLastPrev s else Nothing
    nU    = if prevOk then sbPrev else Nothing
    nUR   = if prevOk then prevRight x else Nothing
    cands = nLeft :> nUL :> nU :> nUR :> Nil
    picked = nLeft <|> nUL <|> nU <|> nUR
    full = bsNext s >= 32
    (lab, next', ovf)
      | not sbFg = (Nothing, bsNext s, False)
      | Just l <- picked = (Just l, bsNext s, False)
      | full = (Nothing, bsNext s, True)
      | otherwise = (Just (fromIntegral (bsNext s)), bsNext s + 1, False)
    -- union: every candidate's root is relabelled to the chosen label's root
    par = bsParent s
    roots = map (fmap (par !!)) cands
    parent' = case lab of
      Just l  -> let tgt = par !! l
                 in map (\p -> if any (== Just p) roots then tgt else p) par
      Nothing -> par
    sN = s { bsParent = parent', bsNext = next'
           , bsPend = fmap (\l -> (l, x, y)) lab
           , bsOverflow = bsOverflow s || ovf
           , bsLastX = x, bsLastCur = lab, bsLastPrev = sbPrev
           , bsPhase = if pEof then PhMerge else bsPhase s
           , bsIdx = 0, bsStep = 0, bsMPend = False }

  -- (state, record, frame done, acc read address, acc write)
  eofPhase :: BlobSt -> (BlobSt, Maybe BlobRec, Bool, Label, AccWr)
  eofPhase s = case bsPhase s of
    PhLabel -> (s, Nothing, False, bsRdLab s, Nothing)
    PhMerge ->
      -- step 0: read acc[l]; step 1: read acc[r], latch acc[l]; the write of
      -- acc[r] happens in the next step 0 (of the next label, or of the scan)
      let l = fromIntegral (bsIdx s) :: Label
          r = bsParent s !! l
          lastL = bsIdx s == maxBound
      in if bsStep s == 0
           then (s { bsStep = 1, bsMPend = False }, Nothing, False, l, mWr)
           else (s { bsStep = 0, bsAccL = accIn, bsMPend = r /= l
                   , bsIdx = bsIdx s + 1, bsPhase = if lastL then PhScan else PhMerge }
                , Nothing, False, r, Nothing)
    PhScan ->
      -- step 0: read acc[l] (and finish the last merge write); step 1: decide
      let l = fromIntegral (bsIdx s) :: Label
          Acc{..} = accIn
          isRoot = bsParent s !! l == l
          keep = isRoot && aN /= 0 && aN >= cMinArea && aN <= cMaxArea
          lastL = bsIdx s == maxBound
          half = resize (aN `shiftR` 1) :: Unsigned 32
      in if bsStep s == 0
           then (s { bsStep = 1, bsMPend = False }, Nothing, False, l, mWr)
           else if keep
             then (s { bsPhase = PhDiv, bsStep = 0, bsAccL = accIn
                     , bsNx = (resize aSx `shiftL` 4) + half
                     , bsNy = (resize aSy `shiftL` 4) + half
                     , bsQx = 0, bsQy = 0, bsRx = 0, bsRy = 0 }, Nothing, False, l, Nothing)
             else (s { bsStep = 0, bsIdx = bsIdx s + 1, bsPhase = if lastL then PhLabel else PhScan }
                  , Nothing, lastL, l, Nothing)
    PhDiv ->
      let l = fromIntegral (bsIdx s) :: Label
          Acc{..} = bsAccL s
          (nx, qx, rx) = divStep aN (bsNx s, bsQx s, bsRx s)
          (ny, qy, ry) = divStep aN (bsNy s, bsQy s, bsRy s)
          lastStep = bsStep s == maxBound
          lastL = bsIdx s == maxBound
          rec = BlobRec { bLabel = fromIntegral l, bCx = qx, bCy = qy
                        , bCount = if aN > 0xFFFF then maxBound else resize aN
                        , bX0 = aX0, bX1 = aX1, bY0 = aY0, bY1 = aY1 }
          s' = s { bsNx = nx, bsNy = ny, bsQx = qx, bsQy = qy, bsRx = rx, bsRy = ry
                 , bsStep = bsStep s + 1 }
      in if lastStep
           then (s' { bsStep = 0, bsIdx = bsIdx s + 1, bsPhase = if lastL then PhLabel else PhScan }
                , Just rec, lastL, l, Nothing)
           else (s', Nothing, False, l, Nothing)
   where
    -- merge write: acc[root] (read last cycle, address bsRdLab) += acc[l]
    mWr = if bsMPend s then Just (bsRdLab s, accMerge accIn (bsAccL s)) else Nothing

-- | Threshold + labeller: register block in, pixel stream in, records out.
blobLabel
  :: HiddenClockResetEnable dom
  => Signal dom BlobCfg
  -> Signal dom (Maybe Pix)
  -> Signal dom BlobOut
blobLabel cfg pixIn = out
 where
  held   = register 0 rdAddr
  rdAddr = (\h p -> maybe h pX p) <$> held <*> pixIn
  rd     = blockRam (replicate d1024 Nothing) rdAddr wr
  accRd  = blockRam (replicate d32 accEmpty) accAddr accWr
  (wr, accAddr, accWr, out) =
    unbundle (mealy blobT blobInit (bundle (cfg, pixIn, rd, accRd)))

topEntity
  :: Clock System -> Reset System -> Enable System
  -> Signal System BlobCfg
  -> Signal System (Maybe Pix)
  -> Signal System BlobOut
topEntity = exposeClockResetEnable blobLabel
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_blob"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "cfg", PortName "pix" ]
    , t_output = PortName "blob"
    }) #-}
