{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}

-- | Boot the /real/ eForth image (@h2.bin@, built from upstream
--   @embed.fth@) in Clash simulation, type at it over the UART model, and
--   check the console transcript for the PM capabilities of
--   @Oracle\/eforth-pm.md@:
--
--   1. @2 3 + . cr@ — the stock console works (prints 5).
--
--   2. @mode?@ — the 0x4020 zone register reads back the scripted zones
--      (0x0022 = 34 decimal).
--
--   3. The SD\/SPI block interface (0x4028\/0x402A): the console defines
--      the SD command layer /in Forth/ (@spi@\/@tx@\/@rd@\/@sec@\/@rblk@ —
--      CMD17 per 512-byte sector, two sectors per 1024-byte Forth block),
--      reads block 0 of the card image built by @tools\/mkcard.py@ and
--      types the owner name (@owner: JC@), then reads block 1 into
--      eForth's block buffer and runs a real @1 load@ — the card's boot
--      source defines and runs @hello@, printing @PM card ok@.  (@block@
--      returns the buffer directly because cold boot left @blk@ = 1; the
--      card content itself arrives via the SPI registers.)
--
--   4. The IRIG registers (0x4034 status, 0x4040 TOD-set block): @time\@@
--      reads the status word twice a few thousand cycles apart and prints
--      @irig live@ only if the two values differ — a live clock, not a
--      constant.  Then the TOD is set to 12:34:50 day 245 through
--      @oTodSecs@\/@oTodDay@\/@oTodSet@ and @tods?@ polls until the
--      seconds-tens BCD digit reads 5, printing @tod ok@ — the set value
--      really landed in the rtc (the boot clock was seconds-tens 0 at that
--      point, and only the applied set reaches 5x within the poll window).
--
--   5. The 2026-09-15 groups (see @consoleInput@'s comments): 0x4050 Sleigh
--      parked → gliding + dwell readback, 0x4070 WSPR symbol\/div readback
--      and @arm refused@ through the RegFile interlock, 0x4060 Imaging
--      threshold readback + centroid (88, 56) of the synthetic frame, and
--      0x4080 Records\/Net datagram seq \/ drops \/ rxGood \/ rxBad.
--
--   Expected transcript shape (cross-checked against the upstream C
--   simulator for the stock part):
--
--   > eFORTH v666
--   >  1A0C 25F4
--   > loading... ok           (transfer from empty flash "succeeds"...)
--   > failed                  (...but block 1 holds no ASCII: no nvram here)
--   > 2 3 + . cr 5
--   > : mode? $4020 @ $7F and ; decimal mode? . cr 34
--   > ... stable ... 147 press ... fifo empty      (the REAL PM.RegFile)
--   > ... owner: JC ... PM card ok ... irig live ... tod ok
--
--   The line terminator is a bare CR (0x0D): eForth's @ktap@ ends a line
--   on @=cr@ ($D) and the upstream simulator's @getch@ clears ICRNL so the
--   CPU sees CR when Enter is pressed.
--
--   eForth syntax notes: the target's @number?@ (@embed.fth@) accepts a
--   @\$@ prefix for hex, so @\$4020@ parses in any base — but @cold@
--   leaves @base@ in /hex/ after the banner, so the test says @decimal@
--   explicitly.  The TIB is 80 characters, so the longer definitions are
--   split across input lines (compile state persists across lines).  The
--   assertion strings (@irig live@, @tod ok@) are printed from /split/
--   string literals (@." irig " ." live"@) so the echo of the typed line
--   can never satisfy the assertion — only execution can.  @."@ is
--   compile-only in this image (interpreting it is error -14), so every
--   printing line is a colon definition immediately executed.
module Main (main) where

import Clash.Prelude
import qualified Prelude as P
import qualified Data.List as L
import qualified Data.ByteString as BS
import Data.Char (chr, ord, isPrint)
import System.Exit (exitFailure)
import System.IO (hPutStr, hPutStrLn, hFlush, stderr)
import System.Process (callProcess)
import Control.Monad (when)
import Data.Time.Clock (getCurrentTime, diffUTCTime)

import H2.SystemUart (h2SystemSim)

-- | Where the card image built by tools/mkcard.py lands (not an artifact:
--   regenerated on every run, inside dist-newstyle).
cardImagePath :: FilePath
cardImagePath = "dist-newstyle/card.img"

-- | Bytes typed at the eForth console.
consoleInput :: String
consoleInput =
     "2 3 + . cr\r"
  P.++ ": mode? $4020 @ $7F and ; decimal mode? . cr\r"
  -- The stable flag (bit 15) is only set by the real zone decoder after
  -- its mode dwell — the old scripted constant could never satisfy this.
  -- 0< is the signed test; split literals so the echo can't match.
  P.++ ": st? $4020 @ 0< if .\" sta\" .\" ble\" then cr ; st?\r"
  -- The real matrix scanner has row2/col3 wired down: pop the debounced
  -- press event (keycode 19 = 0x13, press bit 7, valid bit 15) and then
  -- show the FIFO is empty.  The 0x4024 @ itself is the pop.
  -- ENABLE the scanner first (bit0 scan, debounce 2 passes) and let it run
  -- long enough to debounce the wired-down key (2 passes ~ 50k cycles)
  P.++ ": w8 $FFFF for next ;\r"
  P.++ "$21 $4024 ! w8 w8 w8\r"
  P.++ ": key? $4024 @ dup $FF and . 0< if .\" pre\" .\" ss\" then cr ;\r"
  P.++ "key? : nk? $4024 @ 0= if .\" fifo \" .\" empty\" then cr ; nk?\r"
  -- SD command layer over the 0x402A shifter (eforth-pm.md: "Forth
  -- implements the SD command layer; gateware is just the shifter").
  P.++ ": spi $402A ! $402A @ ;\r"
  P.++ ": tx spi drop ;\r"
  P.++ ": rd $FF spi ;\r"
  -- CMD17 (READ_SINGLE_BLOCK) for one 512-byte sector at byte address
  -- lo<<8 (block numbers are small, so a15:8 is the only varying byte).
  P.++ ": sec $51 tx 0 tx 0 tx tx 0 tx $95 tx\r"
  P.++ "begin rd $FF <> until begin rd $FE = until\r"
  P.++ "$1FF for rd over c! 1+ next rd drop rd drop ;\r"
  -- One 1024-byte Forth block = two sectors, into the block buffer $3C00.
  P.++ ": rblk 4 * >r $3C00 r@ sec r> 2 + sec drop ;\r"
  -- Identity block: magic "PM", name length at byte 2, name at byte 3.
  P.++ ": greet 0 rblk .\" owner: \" $3C03 $3C02 c@ type cr ;\r"
  P.++ "greet\r"
  -- Real `1 load`: block 1 through the SPI registers into the buffer,
  -- then eForth's own loader evaluates its 16 lines.
  P.++ "1 rblk 1 load\r"
  -- IRIG: status is seconds BCD + pps + frame phase; two reads a few
  -- thousand cycles apart must differ (1 s = 10 000 cycles at SNat 1).
  P.++ ": time@ $4034 @ ;\r"
  P.++ ": wait $3FF for next ;\r"
  P.++ ": live? time@ wait time@ 2dup . . <> if .\" irig \" .\" live\" then cr ;\r"
  -- TOD set: secs-of-day to $4046, doy to $4048, strobe $4044; applied at
  -- the next frame reference, so poll until the seconds-tens digit is 5.
  P.++ ": tod! $4046 ! $4048 ! 1 $4044 ! ;\r"
  -- Prints the status word before and after the poll: the first value
  -- shows the free-running boot clock was NOT already in the :5x seconds
  -- window (auditable in the transcript), the second shows the applied
  -- 12:34:5x.
  P.++ ": tods? time@ u. begin time@ $1000 / 7 and 5 = until\r"
  P.++ "time@ u. .\" tod \" .\" ok\" cr ;\r"
  P.++ "live?\r"
  P.++ "$F5 $B0EA tod! tods?\r"   -- day 245, 45290 s = 12:34:50
  -- Sleigh (0x4050/0x4052, real PM.Sleigh, tick every clock): parked and
  -- paused at reset (state 0, bit 7); enable at speed 255 and poll until
  -- the state reads GLIDE_FWD; write dwell[3] = 100 ms and read it back.
  P.++ ": sl? $4050 @ ;\r"
  P.++ ": pk? sl? dup 3 and 0= swap $80 and 0<> and\r"
  P.++ "if .\" par\" .\" ked\" then cr ; pk?\r"
  P.++ "$1FF $4050 !\r"
  P.++ ": gl? begin sl? 3 and 1 = until .\" gli\" .\" ding\" cr ; gl?\r"
  P.++ ": dw? $3064 $4052 ! .\" dwell\" $4052 @ . cr ; dw?\r"
  -- WSPR (0x4070 group, real PM.Wspr): symbol 3 at index 0 then symbol 2 at
  -- index 5 — the idle sequencer sits at index 0, so the table reads 3;
  -- symDiv readback; then the arm key at 0x4032 and a start at 0x4072 are
  -- both refused because S3 sits in E, not C (PM.RegFile interlock).
  P.++ ": sy? $300 $4070 ! $205 $4070 ! .\" sym\" $4070 @ 3 and . cr ; sy?\r"
  P.++ ": dv? 4 $4074 ! .\" div\" $4074 @ . cr ; dv?\r"
  P.++ "$C1D $4032 ! 1 $4072 !\r"
  P.++ ": ar? $4072 @ 3 and 0= $4032 @ 1 and 0= and\r"
  P.++ "if .\" arm \" .\" refused\" then cr ; ar?\r"
  -- Imaging (0x4060 group, real PM.Blob on the synthetic 16x8 frame):
  -- threshold 100 / hysteresis 10 written and read back; net enabled first
  -- so the centroid record flows on; fire a frame, wait, read the blob
  -- count, the pixel count and the centroid pair (88, 56 in Q4 = 5.5, 3.5);
  -- then threshold 250 (hysteresis 0) finds no blob in frame 2.
  P.++ ": th? $A64 $4064 ! .\" thr\" $4068 @ . cr ; th?\r"
  P.++ "1 $4080 ! 1 $4062 ! w8\r"
  P.++ ": bl? $4060 @ $100 / ; : bl. .\" blobs\" bl? . cr ; bl.\r"
  P.++ ": ce? .\" sum\" $4066 @ . .\" cent\" $4064 @ . $4064 @ . cr ; ce?\r"
  P.++ ": f2? $FA $4064 ! 1 $4062 ! w8 .\" seq\" $4062 @ . bl. ; f2?\r"
  -- Records / Net (0x4080 group): that one centroid record became datagram
  -- 1, a beacon frame and one CRC-good received frame (RMII loopback into
  -- PM.NetRx); no drops, no bad frames.  A manual PPS_STATUS fire makes
  -- datagram 2 / rxGood 2.
  P.++ ": nt? .\" net\" $4082 @ . $4084 @ . $4086 @ . $4088 @ . cr ; nt?\r"
  P.++ ": n2? 7 $4082 ! w8 .\" net\" $4082 @ . $4086 @ . cr ; n2?\r"

-- | Upper bound on simulated cycles.  The run stops early once the
--   expected output has been seen — a passing boot takes ~16M cycles,
--   dominated by eForth's cold-boot @transfer@ of 32KB from the (absent
--   here) flash.
maxCycles :: Int
maxCycles = 30000000

-- | The part of @s@ after the first occurrence of @needle@ (or @""@).
after :: String -> String -> String
after needle s = case L.filter (needle `L.isPrefixOf`) (L.tails s) of
  (t:_) -> P.drop (P.length needle) t
  []    -> ""

-- | All the expected evidence, in transcript terms (see module header).
bootedOk :: String -> Bool
bootedOk t = "eFORTH" `L.isInfixOf` t
          && "5"  `L.isInfixOf` after "cr" (after "eFORTH" t)
          && "34" `L.isInfixOf` after "decimal mode? . cr" t
          && "stable" `L.isInfixOf` t          -- zone decoder's dwell flag
          && "147press" `L.isInfixOf` t        -- matrix event: keycode 19 + press
                                               -- (eForth's . prints a LEADING space)
          && "fifo empty" `L.isInfixOf` t      -- the 0x4024 read popped it
          && "owner: JC" `L.isInfixOf` t
          && "PM card ok" `L.isInfixOf` after "1 rblk 1 load" t
          && "irig live" `L.isInfixOf` t
          && "tod ok" `L.isInfixOf` t
          && "parked" `L.isInfixOf` t             -- sleigh: reset state, paused
          && "gliding" `L.isInfixOf` t            -- sleigh: enable+speed -> GLIDE_FWD
          && "dwell 12388" `L.isInfixOf` t        -- 0x3064: index 3, 100 ms
          && "sym 3" `L.isInfixOf` t              -- wspr table entry 0 read back
          && "div 4" `L.isInfixOf` t
          && "arm refused" `L.isInfixOf` t        -- interlock: E mode, not C
          && "thr 2660" `L.isInfixOf` t           -- 0x0A64 threshold readback
          && "blobs 1" `L.isInfixOf` t
          && "sum 16cent 88 56" `L.isInfixOf` t  -- the 4x4 square's centroid
          && "blobs 0" `L.isInfixOf` after "seq 2" t
          && "net 1 0 1 0" `L.isInfixOf` t        -- seq 1, drops 0, rxGood 1, rxBad 0
          && "net 2 2" `L.isInfixOf` t            -- after the manual PPS_STATUS fire

main :: IO ()
main = do
  t0 <- getCurrentTime
  callProcess "python3" ["tools/mkcard.py", cardImagePath]
  card <- P.map fromIntegral . BS.unpack <$> BS.readFile cardImagePath
  let script = P.map (fromIntegral . ord) consoleInput
      -- sampleN provides the hidden clock/reset/enable of the System domain
      txSamples = sampleN @System maxCycles
                    (h2SystemSim (blockRamFilePow2 "h2.bin")
                                 (blockRamFilePow2 "h2.bin")
                                 script card)
      -- consume lazily, streaming progress to stderr, stopping as soon as
      -- the expected transcript is seen
      run acc [] = pure (acc, maxCycles)
      run acc ((n, mb) : rest) = do
        when (n `P.mod` 1000000 == 0) $ do
          hPutStrLn stderr ("[cycle " P.++ show n P.++ "]")
          hFlush stderr
        case mb of
          Nothing -> run acc rest
          Just b  -> do
            let c    = chr (fromIntegral b)
                acc' = acc P.++ [c]
            hPutStr stderr (render c)
            hFlush stderr
            if bootedOk acc' then pure (acc', n) else run acc' rest

  (transcript, lastCycle) <- run "" (P.zip [(0 :: Int) ..] txSamples)

  putStrLn "---- decoded eForth console transcript ----"
  putStrLn (P.concatMap render transcript)
  putStrLn "-------------------------------------------"
  t1 <- transcript `seqX` getCurrentTime
  putStrLn ("tx bytes: " P.++ show (P.length transcript)
            P.++ ", last tx at cycle " P.++ show lastCycle
            P.++ ", wall time " P.++ show (diffUTCTime t1 t0))

  if bootedOk transcript
    then putStrLn ("PASS: eForth booted, 2 3 + = 5, mode? read 34 from 0x4020, "
                   P.++ "SD card block 0 identity + real `1 load` from block 1 "
                   P.++ "over 0x4028/0x402A, and the IRIG clock at 0x4034 is "
                   P.++ "live and settable via the 0x4040 block; sleigh 0x4050, "
                   P.++ "WSPR 0x4070 (arm refused outside C), Imaging 0x4060 "
                   P.++ "centroid (88,56) and Records/Net 0x4080 seq/rxGood all "
                   P.++ "proven from Forth")
    else do
      putStrLn "FAIL: expected transcript evidence missing (see bootedOk)"
      exitFailure
  where
    render c
      | c == '\n'          = "\n"
      | c == '\r'          = ""
      | isPrint c          = [c]
      | otherwise          = "<" P.++ show (ord c) P.++ ">"
