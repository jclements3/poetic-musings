{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-orphans #-}   -- createDomain's KnownDomain instance
-- PM.Sdram — single-port controller for the ULX3S's 32 MB SDRAM
-- (IS42S16160G class: 16-bit wide, 4 banks, 13 row x 9 column bits,
-- 4M x 16 per bank = 16M words = 32 MB), plus a byte-oriented ring wrapper.
--
-- Clock: 100 MHz (10 ns). Timing parameters (cycles, from the -7 grade
-- datasheet, rounded up) are the constants under "Timing" below:
--   tRP 2 (15 ns)  tRCD 2 (15 ns)  tRFC 6 (60 ns)  tRC 6 (60 ns)  tRAS 5 (42 ns)
--   tWR 2          tMRD 2          CL 2            tREFI 7.8 us = 780 cycles
-- Mode register 0x020: CL=2, sequential, burst length 1, single-location
-- writes. Burst length 1 keeps the controller a plain one-word-per-request
-- machine; the ring wrapper is the place to add streaming if ever needed.
--
-- Address map (SdramReq.addr is a 16-bit-WORD address; the chip has 2^24
-- words, so bit 24 is ignored and reserved for a 64 MB part):
--   col  = addr[8:0]   bank = addr[10:9]   row = addr[23:11]
-- so sequential words walk a row, then the banks, then the next row.
--
-- Policy: OPEN PAGE with per-bank row tracking. A request to a bank whose
-- open row matches is issued immediately (row hit); a different row is
-- precharged (single bank) and re-activated (row miss); a closed bank is
-- activated. Refresh (every tRefresh cycles, a runtime divider, default 760
-- so the refresh lands within 780 even after a worst-case in-flight access)
-- precharges ALL banks first and closes every row. tRAS is enforced with a
-- saturating "cycles since last ACTIVATE" counter, conservatively across all
-- banks. DQM is held low at all times (no byte masking, no read gating).
--
-- Handshake: `ready` is a Moore output; a request is accepted in a cycle
-- where ready && isJust req. Read data comes back on `rdata` as a one-cycle
-- Just strobe, CL+1 cycles after the READ appears on the bus, in order.
-- Every bus output is registered (SdramBus is a state field).
--
-- Init: CKE high + NOP for tInitWait cycles (10_000 = 100 us), PRECHARGE ALL,
-- tRP, AUTO REFRESH, tRFC, AUTO REFRESH, tRFC, LOAD MODE, tMRD, then idle.
module PM.Sdram
  ( -- * Geometry and timing
    RowBits, ColBits, BankBits, tRP, tRCD, tRFC, tRC, tRAS, tWR, tMRD, tCL, tRefi
  , modeRegister, SdramTiming (..), defaultTiming
    -- * Bus
  , SdramCmd (..), SdramBus (..), busCmd, nopBus
    -- * Word controller
  , SdramReq (..), reqRow, reqBank, reqCol, sdramCtrl
    -- * Byte ring
  , sdramRing
    -- * Synthesis
  , Dom100, vDom100, topEntity
  ) where

import Clash.Prelude
import Data.Maybe (isJust, isNothing)

-- ---------------------------------------------------------------------------
-- Geometry (bits) and timing (cycles at 100 MHz).

type RowBits  = 13
type ColBits  = 9
type BankBits = 2

tRP, tRCD, tRFC, tRC, tRAS, tWR, tMRD, tCL, tRefi :: Unsigned 16
tRP   = 2      -- precharge to activate
tRCD  = 2      -- activate to read/write
tRFC  = 6      -- refresh to any command
tRC   = 6      -- activate to activate, same bank (checked by the model)
tRAS  = 5      -- activate to precharge
tWR   = 2      -- last write data to precharge
tMRD  = 2      -- load mode to any command
tCL   = 2      -- CAS latency
tRefi = 780    -- maximum refresh interval (7.8 us)

-- | CL=2 (bits 6:4 = 010), sequential, burst length 1, single-location write.
modeRegister :: BitVector 13
modeRegister = 0b0_00_0_00_010_0_000

-- | Runtime parameters: the power-up wait and the refresh tick divider.
data SdramTiming = SdramTiming
  { tInitWait :: !(Unsigned 16)   -- ^ NOP cycles with CKE high after power-up
  , tRefresh  :: !(Unsigned 16)   -- ^ refresh tick period, must leave room under tRefi
  } deriving (Generic, NFDataX, Show)

defaultTiming :: SdramTiming
defaultTiming = SdramTiming { tInitWait = 10_000, tRefresh = 760 }

-- ---------------------------------------------------------------------------
-- Bus.

data SdramCmd = CmdNop | CmdActive | CmdRead | CmdWrite | CmdPrecharge
              | CmdRefresh | CmdLoadMode
  deriving (Generic, NFDataX, Eq, Show)

-- | Registered pins toward the chip. Active-low strobes are named *N and
-- carry True when the pin is high. sbDqOe True means the FPGA drives DQ.
data SdramBus = SdramBus
  { sbCke  :: !Bool
  , sbCsN  :: !Bool
  , sbRasN :: !Bool
  , sbCasN :: !Bool
  , sbWeN  :: !Bool
  , sbBa   :: !(BitVector BankBits)
  , sbA    :: !(BitVector RowBits)
  , sbDqm  :: !(BitVector 2)
  , sbDq   :: !(BitVector 16)
  , sbDqOe :: !Bool
  } deriving (Generic, NFDataX, Eq, Show)

nopBus :: SdramBus
nopBus = SdramBus { sbCke = True, sbCsN = False, sbRasN = True, sbCasN = True
                  , sbWeN = True, sbBa = 0, sbA = 0, sbDqm = 0, sbDq = 0
                  , sbDqOe = False }

-- | Decode the command on the bus (truth table of RAS#/CAS#/WE#).
busCmd :: SdramBus -> SdramCmd
busCmd SdramBus{..}
  | sbCsN = CmdNop
  | otherwise = case (sbRasN, sbCasN, sbWeN) of
      (True,  True,  True ) -> CmdNop
      (False, True,  True ) -> CmdActive
      (True,  False, True ) -> CmdRead
      (True,  False, False) -> CmdWrite
      (False, True,  False) -> CmdPrecharge
      (False, False, True ) -> CmdRefresh
      (False, False, False) -> CmdLoadMode
      (True,  True,  False) -> CmdNop     -- BURST TERMINATE: never issued

encode :: SdramCmd -> BitVector BankBits -> BitVector RowBits -> SdramBus
encode c b a = nopBus { sbRasN = r, sbCasN = ca, sbWeN = w, sbBa = b, sbA = a }
  where
    (r, ca, w) = case c of
      CmdNop       -> (True,  True,  True )
      CmdActive    -> (False, True,  True )
      CmdRead      -> (True,  False, True )
      CmdWrite     -> (True,  False, False)
      CmdPrecharge -> (False, True,  False)
      CmdRefresh   -> (False, False, True )
      CmdLoadMode  -> (False, False, False)

-- ---------------------------------------------------------------------------
-- Request interface.

data SdramReq = SdramReq
  { addr  :: !(Unsigned 25)     -- ^ 16-bit word address (bit 24 ignored)
  , wdata :: !(BitVector 16)
  , we    :: !Bool
  } deriving (Generic, NFDataX, Eq, Show)

reqRow :: SdramReq -> Unsigned RowBits
reqRow r = unpack (slice d23 d11 (addr r))

reqBank :: SdramReq -> Index 4
reqBank r = unpack (slice d10 d9 (addr r))

reqCol :: SdramReq -> BitVector ColBits
reqCol r = slice d8 d0 (addr r)

-- ---------------------------------------------------------------------------
-- Controller.

data Phase = PInit | PInitRef1 | PInitRef2 | PInitMrs | PIdle | PPre | PAct | PRw
  deriving (Generic, NFDataX, Eq, Show)

data CtrlS = CtrlS
  { csPhase  :: !Phase
  , csWait   :: !(Unsigned 16)                    -- NOP cycles still to insert
  , csRefCnt :: !(Unsigned 16)
  , csRefDue :: !Bool
  , csOpen   :: !(Vec 4 (Maybe (Unsigned RowBits)))
  , csCur    :: !SdramReq
  , csActAge :: !(Unsigned 4)                     -- saturating cycles since ACTIVATE
  , csRdPipe :: !(Vec 2 Bool)                     -- tCL deep read-return pipeline
  , csRdOut  :: !(Maybe (BitVector 16))
  , csBus    :: !SdramBus
  } deriving (Generic, NFDataX)

ctrl0 :: SdramTiming -> CtrlS
ctrl0 t = CtrlS
  { csPhase = PInit, csWait = tInitWait t, csRefCnt = 0, csRefDue = False
  , csOpen = repeat Nothing, csCur = SdramReq 0 0 False, csActAge = 0
  , csRdPipe = repeat False, csRdOut = Nothing, csBus = nopBus }

ctrlReady :: CtrlS -> Bool
ctrlReady CtrlS{..} = csPhase == PIdle && csWait == 0 && not csRefDue

ctrlT :: SdramTiming -> CtrlS -> (Maybe SdramReq, BitVector 16) -> CtrlS
ctrlT SdramTiming{..} s@CtrlS{..} (req, dqIn)
  | csWait /= 0 = base { csWait = csWait - 1 }
  | otherwise = case csPhase of
      PInit     -> emit CmdPrecharge 0 a10 base { csPhase = PInitRef1, csWait = tRP - 1 }
      PInitRef1 -> emit CmdRefresh 0 0 base { csPhase = PInitRef2, csWait = tRFC - 1 }
      PInitRef2 -> emit CmdRefresh 0 0 base { csPhase = PInitMrs, csWait = tRFC - 1 }
      PInitMrs  -> emit CmdLoadMode 0 modeRegister
                     base { csPhase = PIdle, csWait = tMRD - 1, csRefCnt = 0 }
      PIdle
        | csRefDue ->
            if any isJust csOpen
              then if canPre
                     then emit CmdPrecharge 0 a10
                            base { csOpen = repeat Nothing, csWait = tRP - 1 }
                     else base
              else emit CmdRefresh 0 0 base { csRefDue = False, csWait = tRFC - 1 }
        | otherwise -> case req of
            Nothing -> base
            Just r  -> case csOpen !! reqBank r of
              Just ro | ro == reqRow r -> rw r base { csCur = r }
              Just _  -> base { csCur = r, csPhase = PPre }
              Nothing -> activate r base { csCur = r }
      PPre
        | canPre -> emit CmdPrecharge (pack (reqBank csCur)) 0
                      base { csOpen = replace (reqBank csCur) Nothing csOpen
                           , csPhase = PAct, csWait = tRP - 1 }
        | otherwise -> base
      PAct -> activate csCur base
      PRw  -> rw csCur base
  where
    inInit = csPhase == PInit || csPhase == PInitRef1
          || csPhase == PInitRef2 || csPhase == PInitMrs
    tick = csRefCnt + 1 >= tRefresh
    base = s
      { csRefCnt = if inInit || tick then 0 else csRefCnt + 1
      , csRefDue = csRefDue || (tick && not inInit)
      , csActAge = if csActAge == maxBound then csActAge else csActAge + 1
      , csRdPipe = (busCmd csBus == CmdRead) +>> csRdPipe
      , csRdOut  = if last csRdPipe then Just dqIn else Nothing
      , csBus    = nopBus
      }
    canPre = csActAge >= resize tRAS
    a10 = bit 10
    emit c b a st = st { csBus = encode c b a }
    activate r st = emit CmdActive (pack (reqBank r)) (pack (reqRow r))
      st { csOpen = replace (reqBank r) (Just (reqRow r)) csOpen
         , csActAge = 0, csPhase = PRw, csWait = tRCD - 1 }
    rw r st
      | we r = st { csPhase = PIdle, csWait = tWR
                  , csBus = (encode CmdWrite b c) { sbDq = wdata r, sbDqOe = True } }
      | otherwise = st { csPhase = PIdle, csWait = tCL + 1, csBus = encode CmdRead b c }
      where b = pack (reqBank r)
            c = resize (reqCol r)

-- | The word controller. Inputs: request (accepted when ready), DQ input
-- pins. Outputs: ready, read-data strobe, registered bus.
sdramCtrl
  :: HiddenClockResetEnable dom
  => SdramTiming
  -> Signal dom (Maybe SdramReq)
  -> Signal dom (BitVector 16)
  -> (Signal dom Bool, Signal dom (Maybe (BitVector 16)), Signal dom SdramBus)
sdramCtrl t req dqIn = (ready, rdata, bus)
  where
    st = moore (ctrlT t) id (ctrl0 t) (bundle (req, dqIn))
    ready = ctrlReady <$> st
    rdata = csRdOut <$> st
    bus   = csBus <$> st

-- ---------------------------------------------------------------------------
-- Byte ring: a FIFO over the whole 32 MB (byte pointers, Unsigned 25, wrap
-- naturally). Bytes are paired into words (low byte at the even address); a
-- word is written when its second byte arrives, so a trailing odd byte is
-- held until its partner shows up. `avail` counts bytes committed to the
-- chip and not yet popped. A pop is honoured when rready; the byte comes
-- out as a Just strobe a few cycles later (immediately if it is the buffered
-- high half of the last word read). One read in flight at a time.

data RingS = RingS
  { rWptr     :: !(Unsigned 25)     -- next byte to accept
  , rCommit   :: !(Unsigned 25)     -- bytes written to the chip (even)
  , rRptr     :: !(Unsigned 25)     -- next byte to hand out
  , rLo       :: !(Maybe (BitVector 8))
  , rWord     :: !(Maybe (Unsigned 25, BitVector 16))
  , rHi       :: !(Maybe (BitVector 8))
  , rPop      :: !Bool
  , rInFlight :: !Bool
  , rOut      :: !(Maybe (BitVector 8))
  } deriving (Generic, NFDataX)

ring0 :: RingS
ring0 = RingS 0 0 0 Nothing Nothing Nothing False False Nothing

ringAvail :: RingS -> Unsigned 25
ringAvail RingS{..} = rCommit - rRptr

ringReq :: RingS -> Maybe SdramReq
ringReq RingS{..}
  | rInFlight = Nothing
  | rPop && isNothing rHi = Just (SdramReq (shiftR rRptr 1) 0 False)
  | otherwise = fmap (\(a, d) -> SdramReq a d True) rWord

ringRready :: RingS -> Bool
ringRready s@RingS{..} = not rPop && not rInFlight && ringAvail s /= 0

ringT :: RingS -> (Maybe (BitVector 8), Bool, Bool, Maybe (BitVector 16)) -> RingS
ringT s@RingS{..} (byteIn, pop, ready, rdata) = s
  { rWptr = wptr', rLo = lo', rWord = word'', rCommit = commit'
  , rInFlight = inFlight', rOut = out', rHi = hi', rRptr = rptr', rPop = pop' }
  where
    (wptr', lo', word') = case byteIn of
      Just b | isNothing rWord -> case rLo of
        Nothing -> (rWptr + 1, Just b, Nothing)
        Just l  -> (rWptr + 1, Nothing, Just (shiftR rWptr 1, b ++# l))
      _ -> (rWptr, rLo, rWord)
    req = ringReq s
    acked = ready && isJust req
    isRd = maybe False (not . we) req
    word'' = if acked && not isRd then Nothing else word'
    commit' = if acked && not isRd then rCommit + 2 else rCommit
    inFlight' | acked && isRd = True
              | isJust rdata  = False
              | otherwise     = rInFlight
    (out', hi', rptr', pop') = case rdata of
      Just d | rInFlight -> (Just (slice d7 d0 d), Just (slice d15 d8 d), rRptr + 1, False)
      _ | pop && ringRready s -> case rHi of
            Just h  -> (Just h, Nothing, rRptr + 1, False)
            Nothing -> (Nothing, rHi, rRptr, True)
        | otherwise -> (Nothing, rHi, rRptr, rPop)

-- | Byte FIFO on the SDRAM. Inputs: byte in (accepted when wready), pop
-- (honoured when rready), DQ input pins. Outputs: wready, rready, byte-out
-- strobe, bytes available, registered bus.
sdramRing
  :: HiddenClockResetEnable dom
  => SdramTiming
  -> Signal dom (Maybe (BitVector 8))
  -> Signal dom Bool
  -> Signal dom (BitVector 16)
  -> ( Signal dom Bool, Signal dom Bool, Signal dom (Maybe (BitVector 8))
     , Signal dom (Unsigned 25), Signal dom SdramBus )
sdramRing t byteIn pop dqIn = (isNothing . rWord <$> st, ringRready <$> st
                              , rOut <$> st, ringAvail <$> st, bus)
  where
    st = moore ringT id ring0 (bundle (byteIn, pop, ready, rdata))
    (ready, rdata, bus) = sdramCtrl t (ringReq <$> st) dqIn

-- ---------------------------------------------------------------------------
-- Synthesis entry: the word controller at 100 MHz with default timing.

createDomain vSystem{vName="Dom100", vPeriod=10_000}

topEntity
  :: Clock Dom100 -> Reset Dom100 -> Enable Dom100
  -> Signal Dom100 (Maybe SdramReq)
  -> Signal Dom100 (BitVector 16)
  -> (Signal Dom100 Bool, Signal Dom100 (Maybe (BitVector 16)), Signal Dom100 SdramBus)
topEntity = exposeClockResetEnable (sdramCtrl defaultTiming)
{-# NOINLINE topEntity #-}
{-# ANN topEntity
  (Synthesize
    { t_name   = "pm_sdram"
    , t_inputs = [ PortName "clk", PortName "rst", PortName "en"
                 , PortName "req", PortName "dq_in" ]
    , t_output = PortProduct "" [ PortName "ready", PortName "rdata", PortName "bus" ]
    }) #-}
