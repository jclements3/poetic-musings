{-# LANGUAGE RecordWildCards #-}
-- PM.Sdram proofs, driven against a behavioural SDRAM model at 100 MHz.
-- The model (a Map of words) checks every command against tRP/tRCD/tRFC/
-- tRC/tRAS/tWR/tMRD, the 780-cycle refresh interval, DQ contention, and
-- that every READ/WRITE lands on an open row; it returns read data CL
-- cycles after the READ. Tests:
--  1. init sequence: NOP for tInitWait, PRE-ALL, tRP, REF, tRFC, REF, tRFC,
--     MRS (0x020), tMRD; no model errors.
--  2. write then read back 256 words over 3 banks x 2 rows each.
--  3. 1 ms of random traffic: no timing errors, refresh gap <= 780, reads
--     match a reference replay.
--  4. row miss: WRITE b0 row 5, READ b0 row 9 -> PRE(b0), ACT(b0,9), READ.
--  5. sdramRing round-trips 4096 bytes in order (push and pop interleaved).
import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, catMaybes)
import PM.Sdram
import System.Exit (exitFailure, exitSuccess)

check :: Bool -> P.String -> IO Bool
check ok m = putStrLn ((if ok then "PASS: " else "FAIL: ") P.++ m) >> P.pure ok

-- ---------------------------------------------------------------------------
-- Behavioural model.

newtype Mem = Mem (M.Map (Unsigned 24) (BitVector 16))
instance NFDataX Mem where
  deepErrorX = errorX
  rnfX (Mem m) = m `seq` ()
  hasUndefined _ = False
  ensureSpine = id

data Model = Model
  { mMem    :: !Mem
  , mOpen   :: !(Vec 4 (Maybe (Unsigned 13)))
  , mActAt  :: !(Vec 4 Int)
  , mPreAt  :: !(Vec 4 Int)
  , mWrAt   :: !(Vec 4 Int)
  , mRefAt  :: !Int
  , mMrsAt  :: !Int
  , mInited :: !Bool
  , mCycle  :: !Int
  , mRdQ    :: ![(Int, BitVector 16)]
  , mErr    :: !(Maybe P.String)
  } deriving (Generic, NFDataX)

far :: Int
far = -100_000

model0 :: Model
model0 = Model (Mem M.empty) (repeat Nothing) (repeat far) (repeat far) (repeat far)
               far far False 0 [] Nothing

cyc :: Unsigned 16 -> Int
cyc = fromIntegral

modelO :: Model -> (BitVector 16, Maybe P.String)
modelO Model{..} = (maybe 0 snd (L.find ((== mCycle) . fst) mRdQ), mErr)

modelT :: Model -> SdramBus -> Model
modelT m b = m' { mCycle = c + 1, mRdQ = P.filter ((> c) . fst) (rdq m'), mErr = firstErr }
  where
    Model { mOpen = mOpen, mActAt = mActAt, mPreAt = mPreAt, mWrAt = mWrAt, mRefAt = mRefAt
          , mMrsAt = mMrsAt, mInited = mInited, mCycle = c, mRdQ = mRdQ, mMem = mMem } = m
    rdq Model { mRdQ = q } = q
    cmd = busCmd b
    bank = unpack (sbBa b) :: Index 4
    allBanks = testBit (sbA b) 10
    banksHit = if allBanks then P.map fromIntegral [0 :: Int .. 3] else [bank]
    open = isJust (mOpen !! bank)
    since v = c - v
    errs = catMaybes
      [ when' (not (sbCke b)) "CKE dropped"
      , when' (cmd /= CmdNop && since mRefAt < cyc tRFC) ("tRFC at " P.++ P.show c)
      , when' (cmd /= CmdNop && since mMrsAt < cyc tMRD) ("tMRD at " P.++ P.show c)
      , when' (cmd == CmdActive && open) ("ACT on open bank at " P.++ P.show c)
      , when' (cmd == CmdActive && since (mPreAt !! bank) < cyc tRP) ("tRP at " P.++ P.show c)
      , when' (cmd == CmdActive && since (mActAt !! bank) < cyc tRC) ("tRC at " P.++ P.show c)
      , when' (isRw && not open) ("access to closed bank at " P.++ P.show c)
      , when' (isRw && since (mActAt !! bank) < cyc tRCD) ("tRCD at " P.++ P.show c)
      , when' (isRw && not mInited) ("access before init at " P.++ P.show c)
      , when' (cmd == CmdWrite && not (sbDqOe b)) ("write without DQ drive at " P.++ P.show c)
      , when' (sbDqOe b && P.any ((== c) . fst) mRdQ) ("DQ contention at " P.++ P.show c)
      , when' (cmd == CmdPrecharge && P.any (\i -> isJust (mOpen !! i) && since (mActAt !! i) < cyc tRAS) banksHit) ("tRAS at " P.++ P.show c)
      , when' (cmd == CmdPrecharge && P.any (\i -> since (mWrAt !! i) < cyc tWR) banksHit) ("tWR at " P.++ P.show c)
      , when' (cmd == CmdRefresh && P.any isJust mOpen) ("REF with open bank at " P.++ P.show c)
      , when' (cmd == CmdRefresh && P.any (\v -> since v < cyc tRP) mPreAt) ("tRP before REF at " P.++ P.show c)
      , when' (cmd == CmdLoadMode && (P.any isJust mOpen || sbA b /= modeRegister)) ("bad LOAD MODE at " P.++ P.show c)
      , when' (mInited && since mRefAt == cyc tRefi + 1) ("refresh interval exceeded at " P.++ P.show c)
      ]
    isRw = cmd == CmdRead || cmd == CmdWrite
    when' p s = if p then Just s else Nothing
    firstErr = case errs of { (e:_) -> Just e; [] -> Nothing }
    wordAddr = case mOpen !! bank of
      Just row -> unpack (pack row ++# sbBa b ++# slice d8 d0 (sbA b)) :: Unsigned 24
      Nothing  -> 0
    Mem mem = mMem
    m' = case cmd of
      CmdNop       -> m
      CmdActive    -> m { mOpen = replace bank (Just (unpack (sbA b))) mOpen
                        , mActAt = replace bank c mActAt }
      CmdRead      -> m { mRdQ = (c + cyc tCL, M.findWithDefault 0 wordAddr mem) : mRdQ }
      CmdWrite     -> m { mMem = Mem (M.insert wordAddr (sbDq b) mem), mWrAt = replace bank c mWrAt }
      CmdPrecharge -> m { mOpen = P.foldr (\i o -> replace i Nothing o) mOpen banksHit
                        , mPreAt = P.foldr (\i o -> replace i c o) mPreAt banksHit }
      CmdRefresh   -> m { mRefAt = c }
      CmdLoadMode  -> m { mMrsAt = c, mInited = True }

-- ---------------------------------------------------------------------------
-- Word-level driver: a list of operations, one request at a time.

data Op = OpW (Unsigned 25) (BitVector 16) | OpR (Unsigned 25) | OpIdle Int
  deriving (Generic, NFDataX, Show)

data DrvS = DrvS { dOps :: ![Op], dIdle :: !Int } deriving (Generic, NFDataX)

drvO :: DrvS -> Maybe SdramReq
drvO DrvS{..}
  | dIdle > 0 = Nothing
  | otherwise = case dOps of
      OpW a d : _ -> Just (SdramReq a d True)
      OpR a : _   -> Just (SdramReq a 0 False)
      _           -> Nothing

drvT :: DrvS -> Bool -> DrvS
drvT s@DrvS{..} ready
  | dIdle > 0 = s { dIdle = dIdle - 1 }
  | otherwise = case dOps of
      OpIdle n : rest -> s { dOps = rest, dIdle = n }
      _ : rest | ready -> s { dOps = rest }
      _ -> s

sys :: HiddenClockResetEnable dom
    => SdramTiming -> [Op]
    -> Signal dom (SdramBus, Maybe (BitVector 16), Maybe P.String)
sys t ops = bundle (bus, rdata, err)
  where
    req = moore drvT drvO (DrvS ops 0) ready
    (ready, rdata, bus) = sdramCtrl t req dq
    (dq, err) = unbundle (moore modelT modelO model0 bus)

runSys :: Int -> SdramTiming -> [Op] -> ([(Int, SdramBus)], [BitVector 16], [P.String])
runSys n t ops = (P.zip [0 ..] buses, catMaybes rds, catMaybes errs)
  where
    out = sampleN @System n (withClockResetEnable @System clockGen resetGen enableGen (sys t ops))
    (buses, rds, errs) = P.unzip3 out

-- reference replay of the reads
replay :: [Op] -> [BitVector 16]
replay = go M.empty
  where
    go _ [] = []
    go m (OpW a d : r) = go (M.insert (resize a :: Unsigned 24) d m) r
    go m (OpR a : r) = M.findWithDefault 0 (resize a) m : go m r
    go m (OpIdle _ : r) = go m r

mkAddr :: Unsigned 13 -> Unsigned 2 -> Unsigned 9 -> Unsigned 25
mkAddr row bank col = unpack (0 ++# pack row ++# pack bank ++# pack col)

cmds :: [(Int, SdramBus)] -> [(Int, SdramCmd, Index 4, BitVector 13)]
cmds tr = [ (i, busCmd b, unpack (sbBa b), sbA b) | (i, b) <- tr, busCmd b /= CmdNop ]

lcg :: Unsigned 32 -> Unsigned 32
lcg x = x * 1664525 + 1013904223

randomOps :: Unsigned 32 -> [Op]
randomOps seed = op : randomOps s3
  where
    s1 = lcg seed; s2 = lcg s1; s3 = lcg s2
    k = slice d31 d28 s1
    row = 3 + resize (unpack (slice d27 d26 s1) :: Unsigned 2) :: Unsigned 13
    bank = unpack (slice d25 d24 s1)
    col = unpack (slice d23 d15 s1)
    a = mkAddr row bank col
    op | k < 8 = OpW a (slice d15 d0 s2)
       | k < 14 = OpR a
       | otherwise = OpIdle (fromIntegral (slice d2 d0 s2))

-- ---------------------------------------------------------------------------
-- Ring driver.

data BDrv = BDrv { bLeft :: ![BitVector 8] } deriving (Generic, NFDataX)

ringSys :: HiddenClockResetEnable dom
        => [BitVector 8] -> Signal dom (Maybe (BitVector 8), Maybe P.String)
ringSys bytes = bundle (out, err)
  where
    drv = moore (\s ok -> if ok then s { bLeft = P.drop 1 (bLeft s) } else s)
                (\s -> case bLeft s of { (x:_) -> Just x; [] -> Nothing }) (BDrv bytes) wready
    (wready, rready, out, _avail, bus) = sdramRing defaultTiming drv rready dq
    (dq, err) = unbundle (moore modelT modelO model0 bus)

main :: IO ()
main = do
  let tm = defaultTiming
  -- 1. init sequence
  let (tr1, _, e1) = runSys 10_200 tm []
      c1 = cmds tr1
      c1cmds = [ x | (_, x, _, _) <- c1 ]
      c1at = [ i | (i, _, _, _) <- c1 ]
      gaps = P.zipWith (-) (P.drop 1 c1at) c1at
  r1 <- check (P.take 4 c1cmds == [CmdPrecharge, CmdRefresh, CmdRefresh, CmdLoadMode])
              ("init order " P.++ P.show (P.take 4 c1cmds))
  r2 <- check (P.length c1at >= 4 && P.head c1at >= 10_000
               && P.and (P.zipWith (>=) (P.take 3 gaps) [cyc tRP, cyc tRFC, cyc tRFC]))
              ("init timing: first cmd at " P.++ P.show (P.take 1 c1at) P.++ " gaps " P.++ P.show (P.take 3 gaps))
  r3 <- check (P.null e1) ("init: no model errors " P.++ P.show (P.take 3 e1))
  -- 2. 256 words across 3 banks x 2 rows
  let addrs = [ mkAddr (if (i `div` 3) `mod` 2 == 0 then 5 else 9) (fromIntegral (i `mod` 3))
                       (fromIntegral (i `div` 6)) | i <- [0 :: Int .. 255] ]
      vals = [ fromIntegral (i * 0x1234 + 7) :: BitVector 16 | i <- [0 :: Int .. 255] ]
      ops2 = P.zipWith OpW addrs vals P.++ P.map OpR addrs
      (_, rd2, e2) = runSys 16_000 tm ops2
  r4 <- check (rd2 == vals) ("256-word write/read back over 3 banks x 2 rows (" P.++ P.show (P.length rd2) P.++ " reads)")
  r5 <- check (P.null e2) ("256-word: no model errors " P.++ P.show (P.take 3 e2))
  -- 3. 1 ms random traffic
  let ops3 = randomOps 12345
      (tr3, rd3, e3) = runSys 110_200 tm ops3
      refAt = [ i | (i, CmdRefresh, _, _) <- cmds tr3, i > 10_100 ]
      refGap = P.maximum (P.zipWith (-) (P.drop 1 refAt) refAt)
      exp3 = P.take (P.length rd3) (replay ops3)
  r6 <- check (P.null e3) ("random 1 ms: no model errors " P.++ P.show (P.take 3 e3))
  r7 <- check (P.length refAt >= 128 && refGap <= cyc tRefi)
              ("random 1 ms: " P.++ P.show (P.length refAt) P.++ " refreshes, max gap " P.++ P.show refGap P.++ " cycles")
  r8 <- check (P.length rd3 > 2000 && rd3 == exp3) ("random 1 ms: " P.++ P.show (P.length rd3) P.++ " reads match reference")
  -- 4. row miss
  let (tr4, rd4, e4) = runSys 10_100 tm [OpW (mkAddr 5 0 3) 0xBEEF, OpR (mkAddr 9 0 3), OpW (mkAddr 9 0 4) 1]
      c4 = [ (x, bk, a) | (_, x, bk, a) <- cmds tr4, x /= CmdRefresh ]
      after = P.drop 1 (P.dropWhile (\(x, _, _) -> x /= CmdLoadMode) c4)
  r9 <- check (P.take 5 after == [ (CmdActive, 0, 5), (CmdWrite, 0, 3), (CmdPrecharge, 0, 0)
                                 , (CmdActive, 0, 9), (CmdRead, 0, 3) ] && rd4 == [0] && P.null e4)
              ("row miss: PRE(b0) then ACT(b0,row 9): " P.++ P.show (P.take 5 after))
  -- 5. ring round trip
  let bytes = [ fromIntegral (i * 7 + 3) :: BitVector 8 | i <- [0 :: Int .. 4095] ]
      out5 = sampleN @System 60_000 (withClockResetEnable @System clockGen resetGen enableGen (ringSys bytes))
      got5 = catMaybes (P.map fst out5)
      e5 = catMaybes (P.map snd out5)
  r10 <- check (got5 == bytes) ("ring: 4096 bytes round-trip in order (" P.++ P.show (P.length got5) P.++ " out)")
  r11 <- check (P.null e5) ("ring: no model errors " P.++ P.show (P.take 3 e5))
  if P.and [r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11]
    then putStrLn "ALL PASS: PM.Sdram" >> exitSuccess
    else exitFailure
