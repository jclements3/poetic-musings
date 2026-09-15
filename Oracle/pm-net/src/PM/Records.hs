{-# LANGUAGE RecordWildCards #-}   -- in-file: the clash CLI doesn't read cabal extensions
-- PM.Records — the record layer under N's UDP path: tagged-record framers,
-- an N-port round-robin record mux, a byte-wide elastic BRAM FIFO, and a
-- datagram packer that emits "16-bit datagram seq + whole records" payloads
-- of <= 1400 bytes as a byte stream with start/end flags.
--
--     Test:     cabal test records-test --test-show-details=direct
--
-- Wire format is owned by MAIDEN/firmware/recorder/PROTOCOL.md and is NOT
-- restated here beyond what the code needs:
--
--     A5  TYPE  SEQ  PAYLOAD(fixed per TYPE, little-endian)  CKSUM
--
-- There is no length byte: the record length is implied by TYPE (recLen),
-- SEQ is a per-TYPE modulo-256 counter (held in each producer port, bumped
-- once per accepted record), CKSUM is the two's complement of the byte sum
-- so the whole frame sums to 0 mod 256.  Types framed here: 0x10 PPS_STATUS
-- (4 B), 0x11 TIME_MARK (10 B), 0x12 STROBE_STAMP (9 B) from GPS/DESIGN.md,
-- 0x20 CENTROID (16 B: rtc u48, seq u16, blob u8, cx_q4 u16, cy_q4 u16,
-- sum_w u16, flags u8) from Imaging/DESIGN.md.
--
-- Pipeline (Network/DESIGN.md "Architecture" / "Transport"):
--
--     recordPort x N ──recordMux──► byteFifo (BRAM 4096) ──datagramPacker──► DgByte stream
--
-- - recordPort: latches a payload on `fire`, frames it with the current SEQ,
--   holds the request until the mux acks; a fire while a request is pending
--   is dropped AND counted (never-drop-silently).
-- - recordMux: round-robin over the N ports, one byte per clock, a granted
--   record streams to completion before the next grant (no interleaving).
--   A record is only started when the FIFO has >= maxRec bytes free, so it
--   never stalls or overflows mid-record.
-- - byteFifo: 4096 x 8 blockRam ring, first-word-fall-through, one pop per
--   clock with no bubble.
-- - datagramPacker: fills a 1400-byte blockRam with "seq(BE) + records",
--   tracking record boundaries from TYPE so a record is never split across
--   datagrams; flushes at record end when (a) fewer than maxRec bytes of
--   room remain (size limit), (b) a timeout tick was seen (the tick source
--   is the caller's, <= 10 ms; a tick is latched whatever phase it lands in,
--   so it flushes no later than the next record boundary), or (c) the
--   record was a TIME_MARK; then streams the datagram out with first/last
--   flags and its length.  A tick with nothing buffered is a no-op.
--
-- Datagram seq is big-endian ("network order", as PM.Net's beacon seq);
-- record payloads stay little-endian per PROTOCOL.md.
--
-- PM.Net.beaconTx carries a FIXED 16-byte payload and takes only (go, mode),
-- so it cannot transport these datagrams; `beaconGoAdapter` at the bottom is
-- the thin shim that pulses `go` per finished datagram (mode = seq low byte)
-- until a variable-length UDP TX exists.
module PM.Records where

import Clash.Prelude
import PM.Net (Byte)

-- ---------------------------------------------------------------------------
-- Framing (pure, elaboration-usable).

-- Little-endian byte split of an n*8-bit value.
le :: forall n. KnownNat n => BitVector (n * 8) -> Vec n Byte
le = reverse . unpack

-- SYNC TYPE SEQ PAYLOAD CKSUM.
frameRecord :: KnownNat n => Byte -> Byte -> Vec n Byte -> Vec (n + 4) Byte
frameRecord tag sq p = body :< negate (sum body)
 where body = 0xA5 :> tag :> sq :> p

-- Record length (whole frame) implied by TYPE; unknown types count as the
-- 4-byte minimum frame so the packer resynchronises instead of wedging.
recLen :: Byte -> Unsigned 5
recLen t = case t of
  0x01 -> 13   -- DOPPLER_V      9 B
  0x04 -> 16   -- STATION_STATUS 12 B
  0x10 -> 8    -- PPS_STATUS     4 B
  0x11 -> 14   -- TIME_MARK      10 B
  0x12 -> 13   -- STROBE_STAMP   9 B
  0x20 -> 20   -- CENTROID       16 B
  _    -> 4    -- minimum frame; keeps the packer from wedging

tagPpsStatus, tagTimeMark, tagStrobeStamp, tagCentroid :: Byte
tagPpsStatus   = 0x10
tagTimeMark    = 0x11
tagStrobeStamp = 0x12
tagCentroid    = 0x20

-- 0x10 PPS_STATUS: offset s20 sign-extended into 3 bytes; flags u8
-- {bit0 locked, bit1 holdover, bit2 pps_seen_since_reset}.
data PpsStatus = PpsStatus
  { psOffset :: !(Signed 20)
  , psFlags  :: !(BitVector 3)
  } deriving (Generic, NFDataX, Show, Eq)

ppsStatusPayload :: PpsStatus -> Vec 4 Byte
ppsStatusPayload PpsStatus{..} =
  le (pack (resize psOffset :: Signed 24)) ++ (zeroExtend psFlags :> Nil)

-- 0x11 TIME_MARK: pps_rtc u48; tod u32 = secs-of-day (bits 0-16) | day-of-year (bits 17-25).
data TimeMark = TimeMark
  { tmPpsRtc :: !(Unsigned 48)
  , tmSecs   :: !(Unsigned 17)
  , tmDay    :: !(Unsigned 9)
  } deriving (Generic, NFDataX, Show, Eq)

timeMarkPayload :: TimeMark -> Vec 10 Byte
timeMarkPayload TimeMark{..} = le (pack tmPpsRtc) ++ le tod
 where tod = (0 :: BitVector 6) ++# pack tmDay ++# pack tmSecs

-- 0x12 STROBE_STAMP: rtc u48; seq u16; flags u8 {bit0 fifo_overflow}.
data StrobeStamp = StrobeStamp
  { ssRtc :: !(Unsigned 48)
  , ssSeq :: !(Unsigned 16)
  , ssOvf :: !Bool
  } deriving (Generic, NFDataX, Show, Eq)

strobeStampPayload :: StrobeStamp -> Vec 9 Byte
strobeStampPayload StrobeStamp{..} =
  le (pack ssRtc) ++ le (pack ssSeq) ++ (boolToBV ssOvf :> Nil)

-- 0x20 CENTROID: rtc u48, seq u16, blob u8, cx_q4 u16, cy_q4 u16, sum_w u16, flags u8.
data Centroid = Centroid
  { ceRtc   :: !(Unsigned 48)
  , ceSeq   :: !(Unsigned 16)
  , ceBlob  :: !Byte
  , ceCx    :: !(Unsigned 16)
  , ceCy    :: !(Unsigned 16)
  , ceSumW  :: !(Unsigned 16)
  , ceFlags :: !Byte
  } deriving (Generic, NFDataX, Show, Eq)

centroidPayload :: Centroid -> Vec 16 Byte
centroidPayload Centroid{..} =
     le (pack ceRtc) ++ le (pack ceSeq) ++ (ceBlob :> Nil)
  ++ le (pack ceCx) ++ le (pack ceCy) ++ le (pack ceSumW) ++ (ceFlags :> Nil)

ppsStatusRecord   :: Byte -> PpsStatus   -> Vec 8  Byte
ppsStatusRecord   sq = frameRecord tagPpsStatus   sq . ppsStatusPayload
timeMarkRecord    :: Byte -> TimeMark    -> Vec 14 Byte
timeMarkRecord    sq = frameRecord tagTimeMark    sq . timeMarkPayload
strobeStampRecord :: Byte -> StrobeStamp -> Vec 13 Byte
strobeStampRecord sq = frameRecord tagStrobeStamp sq . strobeStampPayload
centroidRecord    :: Byte -> Centroid    -> Vec 20 Byte
centroidRecord    sq = frameRecord tagCentroid    sq . centroidPayload

-- ---------------------------------------------------------------------------
-- Producer port: one fixed-width record slot per producer.

type MaxRec = 20

data Rec = Rec
  { rLen   :: !(Unsigned 5)
  , rBytes :: !(Vec MaxRec Byte)
  } deriving (Generic, NFDataX, Show)

data PortSt p = PortSt
  { pSeq     :: !Byte
  , pPending :: !(Maybe p)
  , pDrops   :: !(Unsigned 16)
  } deriving (Generic, NFDataX)

-- Outputs: (request to the mux, sticky-saturating drop count).
recordPort
  :: forall dom n p. (HiddenClockResetEnable dom, KnownNat n, n <= 16, NFDataX p)
  => Byte                        -- TYPE
  -> (p -> Vec n Byte)           -- payload encoder
  -> Signal dom (Maybe p)        -- fire with payload
  -> Signal dom Bool             -- ack from the mux
  -> (Signal dom (Maybe Rec), Signal dom (Unsigned 16))
recordPort tag enc fire ack = unbundle (mealy step (PortSt 0 Nothing 0) (bundle (fire, ack)))
 where
  toRec sq p = Rec (snatToNum (SNat @(n + 4)))
                   (frameRecord tag sq (enc p) ++ repeat @(16 - n) 0)
  step s@PortSt{..} (f, a) = (s', (fmap (toRec pSeq) pPending, pDrops))
   where
    afterAck   = if a then Nothing else pPending
    seq'       = if a then pSeq + 1 else pSeq
    (pend', d) = case (afterAck, f) of
      (Nothing, Just p) -> (Just p, False)
      (Just _,  Just _) -> (afterAck, True)
      _                 -> (afterAck, False)
    s' = s { pSeq = seq', pPending = pend'
           , pDrops = if d then satAdd SatBound pDrops 1 else pDrops }

-- ---------------------------------------------------------------------------
-- Round-robin record mux.  Grants at most one port at a time and streams the
-- whole record before considering the next; arbitration starts from the
-- port after the last grant.

data MuxSt n = MuxSt
  { mBusy :: !Bool
  , mLast :: !(Index n)          -- last granted port
  , mIdx  :: !(Unsigned 5)       -- next byte to send
  , mRec  :: !Rec
  } deriving (Generic, NFDataX)

-- Round-robin pick: first requesting index strictly after `lastG`, wrapping.
rrPick :: forall n. (KnownNat n, 1 <= n) => Index n -> Vec n Bool -> Maybe (Index n)
rrPick lastG reqs = foldr (<|>) Nothing (map cand order)
 where
  next i = if i == maxBound then 0 else i + 1
  order = iterateI next (next lastG) :: Vec n (Index n)
  cand i = if reqs !! i then Just i else Nothing

recordMux
  :: forall dom n. (HiddenClockResetEnable dom, KnownNat n, 1 <= n)
  => Vec n (Signal dom (Maybe Rec))
  -> Signal dom Bool             -- FIFO has room for a whole record
  -> (Vec n (Signal dom Bool), Signal dom (Maybe Byte))
recordMux ports room = (unbundle acks, out)
 where
  (acks, out) = unbundle (mealy step (MuxSt False maxBound 0 (Rec 0 (repeat 0)))
                                     (bundle (bundle ports, room)))
  step s@MuxSt{..} (reqs, rm)
    | mBusy =
        let b    = rBytes mRec !! mIdx
            done = mIdx + 1 == rLen mRec
        in (s { mIdx = mIdx + 1, mBusy = not done }, (repeat False, Just b))
    | rm, Just g <- rrPick mLast (map (\r -> case r of Just _ -> True; _ -> False) reqs)
    , Just r <- reqs !! g =
        (s { mBusy = True, mLast = g, mIdx = 0, mRec = r }, (replace g True (repeat False), Nothing))
    | otherwise = (s, (repeat False, Nothing))

-- ---------------------------------------------------------------------------
-- Byte-wide elastic FIFO on blockRam, depth 4096, first-word-fall-through.
-- Read address is chosen combinationally from (rd, pop) so a pop every clock
-- streams without bubbles; the blockRam's registered read means the byte
-- for the new head arrives exactly when `valid` says so.

type FifoDepth = 4096

data FifoSt = FifoSt
  { fWr    :: !(Index FifoDepth)
  , fRd    :: !(Index FifoDepth)
  , fValid :: !Bool              -- ramOut holds mem[fRd]
  } deriving (Generic, NFDataX)

-- Outputs: (head byte if valid, free-bytes count).  Push when full is dropped
-- (the mux's `room` gate makes that unreachable for well-formed producers).
byteFifo
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe Byte)     -- push
  -> Signal dom Bool             -- pop (only honoured when head is valid)
  -> (Signal dom (Maybe Byte), Signal dom (Unsigned 13))
byteFifo push pop = (headB, free)
 where
  (rdAddr, wr, headB, free) = unbundle (mealy step (FifoSt 0 0 False) (bundle (push, pop, ramOut)))
  ramOut = blockRam (replicate (SNat @FifoDepth) (0 :: Byte)) rdAddr wr
  step FifoSt{..} (pu, po, ro) = (s', (rdA, wrOp, hd, fr))
   where
    used  = fromIntegral fWr - fromIntegral fRd :: Unsigned 12
    fr    = resize (maxBound - used)          -- max 4095 usable slots
    full  = used == maxBound
    hd    = if fValid then Just ro else Nothing
    doPop = po && fValid
    doPu  = case pu of Just _ -> not full; _ -> False
    wrOp  = if doPu then fmap (\b -> (fWr, b)) pu else Nothing
    rd'   = if doPop then satAdd SatWrap fRd 1 else fRd
    wr'   = if doPu then satAdd SatWrap fWr 1 else fWr
    rdA   = rd'
    -- valid only for bytes written BEFORE this cycle: blockRam read-during-
    -- write at the same address returns the old contents.
    s'    = FifoSt wr' rd' (fWr /= rd')

-- ---------------------------------------------------------------------------
-- Datagram packer.

type DgMax = 1400

data DgByte = DgByte
  { dbData  :: !Byte
  , dbFirst :: !Bool
  , dbLast  :: !Bool
  } deriving (Generic, NFDataX, Show, Eq)

data DgPhase = DPrefix | DFill | DSend
  deriving (Generic, NFDataX, Eq, Show)

data DgSt = DgSt
  { dPhase   :: !DgPhase
  , dPos     :: !(Index (DgMax + 1))   -- next write position / bytes so far
  , dRem     :: !(Unsigned 5)          -- bytes left in the current record (0 = between records)
  , dType    :: !Byte                  -- TYPE of the current record
  , dTick    :: !Bool                  -- timeout seen while filling
  , dSeq     :: !(Unsigned 16)
  , dLen     :: !(Index (DgMax + 1))   -- length of the datagram being sent
  , dRdA     :: !(Index DgMax)
  , dOut     :: !(Maybe (Bool, Bool))  -- (first, last) for the byte arriving now
  } deriving (Generic, NFDataX)

dgInit :: DgSt
dgInit = DgSt DPrefix 0 0 0 False 0 0 0 Nothing

-- Outputs: (pop, byte stream, current datagram seq, datagram length while
-- sending).  `tick` is the caller's <= 10 ms timeout strobe.
datagramPacker
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe Byte)     -- FIFO head
  -> Signal dom Bool             -- timeout tick
  -> (Signal dom Bool, Signal dom (Maybe DgByte), Signal dom (Unsigned 16), Signal dom (Unsigned 11))
datagramPacker hd tick = (pop, out, sq, dlen)
 where
  (pop, rdAddr, wr, out, sq, dlen) =
    unbundle (mealy step dgInit (bundle (hd, tick, ramOut)))
  ramOut = blockRam (replicate (SNat @DgMax) (0 :: Byte)) rdAddr wr
  maxRec = snatToNum (SNat @MaxRec) :: Index (DgMax + 1)
  step s@DgSt{..} (h, tk, ro) = (s', (po, rdA, wrOp, ob, dSeq, resize (fromIntegral dLen :: Unsigned 11)))
   where
    ob = fmap (\(f, l) -> DgByte ro f l) dOut
    tick' = dTick || tk
    (s', po, rdA, wrOp) = case dPhase of
      DPrefix ->
        let b = if dPos == 0 then slice d15 d8 (pack dSeq) else slice d7 d0 (pack dSeq)
        in ( s { dPos = dPos + 1, dPhase = if dPos == 1 then DFill else DPrefix
               , dTick = tick', dOut = Nothing }
           , False, 0, Just (resize dPos, b) )
      DFill -> case h of
        Just b ->
          let rem' | dRem == 0 = 0                       -- SYNC; length known at TYPE
                   | dRem == maxBound = recLen b - 2     -- TYPE byte: rest after it
                   | otherwise = dRem - 1
              rem1 = if dRem == 0 then maxBound else rem'  -- maxBound flags "TYPE next"
              ty'  = if dRem == maxBound then b else dType
              pos' = dPos + 1
              endRec = rem1 == 0
              flush = endRec && (pos' > maxBound - maxRec || tick' || ty' == tagTimeMark)
          in ( s { dPos = pos', dRem = rem1, dType = ty', dTick = tick' && not flush
                 , dPhase = if flush then DSend else DFill
                 , dLen = pos', dRdA = 0, dOut = Nothing }
             , True, 0, Just (resize dPos, b) )
        Nothing
          | tick' && dRem == 0 && dPos > 2 ->
              ( s { dPhase = DSend, dLen = dPos, dRdA = 0, dTick = False, dOut = Nothing }
              , False, 0, Nothing )
          | otherwise -> (s { dTick = tick', dOut = Nothing }, False, 0, Nothing)
      DSend ->
        let lastA = resize dRdA + 1 == dLen
        in ( s { dOut = Just (dRdA == 0, lastA)
               , dRdA = if lastA then 0 else dRdA + 1
               , dPhase = if lastA then DPrefix else DSend
               , dTick = tick'                       -- a tick during send still counts
               , dPos = if lastA then 0 else dPos
               , dSeq = if lastA then dSeq + 1 else dSeq }
           , False, dRdA, Nothing )

-- ---------------------------------------------------------------------------
-- Whole record path for N producer ports.

recordPath
  :: forall dom n. (HiddenClockResetEnable dom, KnownNat n, 1 <= n)
  => Vec n (Signal dom (Maybe Rec))
  -> Signal dom Bool                       -- timeout tick
  -> (Vec n (Signal dom Bool), Signal dom (Maybe DgByte), Signal dom (Unsigned 16), Signal dom (Unsigned 11))
recordPath ports tick = (acks, out, sq, dlen)
 where
  (acks, mb)          = recordMux ports room
  room                = fmap (>= snatToNum (SNat @MaxRec)) free
  (hd, free)          = byteFifo mb pop
  (pop, out, sq, dlen) = datagramPacker hd tick

-- Thin shim onto PM.Net.beaconTx's (go, mode) input: one go pulse per finished
-- datagram, mode = datagram seq low byte.  The beacon cannot carry the
-- payload; this exists only so the two can be wired for bring-up counting.
beaconGoAdapter
  :: Signal dom (Maybe DgByte) -> Signal dom (Unsigned 16)
  -> (Signal dom Bool, Signal dom Byte)
beaconGoAdapter out sq = (fmap (maybe False dbLast) out, fmap (slice d7 d0 . pack) sq)

-- ---------------------------------------------------------------------------

-- N = 4 producers (PPS_STATUS, TIME_MARK, STROBE_STAMP, CENTROID), the
-- concrete instance the tests drive.
recordPath4
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe PpsStatus) -> Signal dom (Maybe TimeMark)
  -> Signal dom (Maybe StrobeStamp) -> Signal dom (Maybe Centroid)
  -> Signal dom Bool
  -> (Signal dom (Maybe DgByte), Signal dom (Unsigned 16), Signal dom (Unsigned 11), Vec 4 (Signal dom (Unsigned 16)))
recordPath4 fp ft fs fc tick = (out, sq, dlen, n0 :> n1 :> n2 :> n3 :> Nil)
 where
  (r0, n0) = recordPort tagPpsStatus   ppsStatusPayload   fp a0
  (r1, n1) = recordPort tagTimeMark    timeMarkPayload    ft a1
  (r2, n2) = recordPort tagStrobeStamp strobeStampPayload fs a2
  (r3, n3) = recordPort tagCentroid    centroidPayload    fc a3
  (acks, out, sq, dlen) = recordPath (r0 :> r1 :> r2 :> r3 :> Nil) tick
  a0 = acks !! (0 :: Index 4)
  a1 = acks !! (1 :: Index 4)
  a2 = acks !! (2 :: Index 4)
  a3 = acks !! (3 :: Index 4)
