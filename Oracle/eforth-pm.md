# eForth-PM — the capability layer that makes the Oracle the brains of the PM device

Design spec — first registers live in Clash simulation (`clash-h2/src/H2/SystemUart.hs`
models them; `cabal test h2-boot` proves each from live Forth typed at the booted eForth
console):

- **0x4020 zone register** (iPanel S3/S4 zones), 2026-08-31: `: mode? $4020 @ ;` reads
  the scripted zones back.
- **0x4028/0x402A SD/SPI block interface**, 2026-08-31: the SD command layer is defined
  *in Forth* over the shifter register (CMD17 per 512-byte sector, two per 1024-byte
  block) against a behavioural SPI-mode card backed by an image from
  `clash-h2/tools/mkcard.py` — block 0 identity is read and greets the owner
  (`owner: JC`), and a real `1 load` evaluates block 1's boot source (`PM card ok`).
- **0x4034 IRIG status + 0x4040 TOD-set block**, 2026-08-31: the sim-verified
  `IRIG/clash` core is instantiated at its `SNat 1` sim scale (1 s = 10 000 cycles);
  live Forth reads the status word twice and sees it advance, then sets the time of day
  through oTodSecs/oTodDay/oTodSet and reads the applied BCD seconds back.
- **0x4050 Sleigh, 0x4060 Imaging, 0x4070 WSPR, 0x4080 Records/Net**, 2026-09-15: the
  real `PM.Sleigh`, `PM.Blob`, `PM.Wspr` and `PM.Records`→`PM.Net`→`PM.NetRx` (RMII
  loopback) blocks are on the bus in the same sim; live Forth parks and glides the sleigh
  and reads a dwell entry back, writes a WSPR symbol and reads it from the table, is
  refused an arm outside C (the RegFile interlock, seen at 0x4032 and 0x4072), fires a
  synthetic frame and reads one centroid pair (88, 56) then none at a higher threshold,
  and sees that centroid leave as a datagram, a beacon frame and a counted rxGood.

This defines what the H2/eForth console
must be able to *do* so that every PM mode (S3: P·O·E·T·I·C) is driven from Forth, per
`../LAYOUT.html` (panel, storage, modes) and `../PLAN.md` Phase 3. The CPU is the H2
port in `clash-h2/` (howerj forth-cpu derivative); existing eForth images stay valid,
so everything below is *additions around* the stock core, never changes to it.

## 1. Memory-map extension

Stock forth-cpu convention: memory-mapped I/O begins at `0x4000`, 16-bit registers on
even addresses (`Oracle/forth-cpu-upstream/readme.md`; `clash-h2` implements the
LED/switch pair at `0x4004`). Stock registers `0x4000–0x4014` are kept exactly as
upstream — the eForth image already knows them:

| Addr | Write (stock) | Read (stock) |
|---|---|---|
| 0x4000 | oUart | iUart |
| 0x4002 | oVT100 (terminal char/attr write) | iVT100 (terminal status; PS/2 unused on PM) |
| 0x4004 | oLeds | iSwitches |
| 0x4006 | oTimerCtrl | iTimerDin |
| 0x4008–0x400C | oMem* (external memory port → reused for SDRAM) | iMemDin |
| 0x400E–0x4014 | o7SegLED · oIrcMask · oUartBaud{Tx,Rx} | — |

PM peripherals extend from `0x4020`. **All PM addresses are provisional** until
`forth-cpu-notes.md` (in progress) pins the stock map against the VHDL; only the
*grouping* below is contractual.

| Addr | Write | Read | Peripheral |
|---|---|---|---|
| 0x4020 | oPanelCtrl — ADC mux/start, backlight, LED dim | iPanel — S3 zone (0–5 = P·O·E·T·I·C), S4 zone (OFF·CAL·PLAY·REC), S2 zone, `stable` flag | **Mode sliders.** Gateware digitizes S2–S4, compares against zone thresholds *with hysteresis* (a slider parked on a boundary never flickers — PLAN Panel BOM rule). Forth reads clean zone numbers, never raw counts. |
| 0x4022 | — | iAdc — raw 12-bit ADC, channel select via oPanelCtrl (S0 volume, S1 balance, spare) | **Continuous sliders.** Raw values; scaling/curves are Forth's job. |
| 0x4024 | oMatrixCtrl — scan enable, debounce time (default 10 ms), FIFO clear | iKeys — event FIFO head: bit7 press/release, bits5:0 keycode 0–63 (A0–G7 = 0–48, P0–P9 = 49–58), bit15 `valid` | **8×8 matrix scanner.** Free-running scan + debounce in gateware; Forth pops *events*, never scans rows. |
| 0x4026 | oTFT — char/attr write, VT100 stream (same contract as oVT100) | iTFT — ready/busy, cursor row·col | **Bar TFT console.** The upstream vga.vhd text/VT100 interface reused verbatim at 1920×480 timing (240×30 cells @ 8×16 font; a large-font mode for the I-clock face is a VT100 escape, not a new register). oVT100 (serial-side terminal) and oTFT can be fanned out together so `emit` hits both. |
| 0x4028 | oSdCtrl — CS, clock divisor, card power | iSdStat — busy, card-detect, write-protect | **SD/SPI block interface** (raw SPI master, mode 0). |
| 0x402A | oSdTx — byte to shift out | iSdRx — last byte shifted in | Forth implements the SD command layer; gateware is just the shifter. Blocks are raw 1024-byte Forth blocks = two 512-byte sectors, no filesystem (LAYOUT storage model). |
| 0x402C | oAudio — master mute (the GPIO amp mute), source-select bits: synth · theremin · keyer sidetone · harp I²S · SDR | iAudio — mute state, source ack | **Audio mixer.** Mute is asserted at reset by hardware (no power-on pop); Forth *releases* it once a mode is live. |
| 0x402E | oSynth — command port to the gateware synth: note-on/off, voice select, envelope slot, tempo tick | iSynth — voice-busy mask, sequencer position | **Synth control.** One command word per event; the VL-1 engine, KS voices, and envelopes run entirely in gateware. |
| 0x4030 | oKeyer — WPM, iambic mode, sidetone on/off, element from Forth send queue | iKeyer — decoder FIFO (decoded ASCII), paddle/straight-key state, decoder-locked flag | **CW keyer/decoder.** Element timing and tone decode in gateware; text in/out in Forth. |
| 0x4032 | oTxGate — write the arm key `0x0C1D` to enable the UHF PA branch; any other value disarms | iTxGate — armed flag, PA fuse-branch OK | **TX interlock.** Gateware additionally ANDs `armed` with `iPanel zone == C` (or U-mode flag later): software alone can never key RF outside C mode — the LAYOUT power-table interlock, enforced in hardware. |
| 0x4034 | oIrig — display/capture control | iIrig — BCD time fields, lock/holdover status (from the Phase 2 clock, later G-disciplined) | **Time.** |
| 0x4036 | oHarp — event-link control | iHarp — pluck event FIFO (string 0–48, velocity) from the Erand49 3 Mbaud link | **Harp events** (Phase 6; address reserved now). |

### 1.1 Later groups (concrete; each proven from Forth in `cabal test h2-boot`)

**0x4050 Sleigh (C · `PM.Sleigh`, header is normative):**

| Addr | Write | Read |
|---|---|---|
| 0x4050 | oSleigh — bits 7:0 speed (0 = follow the theremin), bit 8 enable, bit 9 manual park | iSleigh — bits 1:0 state (0 PARK_A 1 GLIDE_FWD 2 PARK_B 3 GLIDE_REV), 4:2 coil, 5 ribbon present, 6 show switch, 7 paused, 15:8 effective speed |
| 0x4052 | oSleighDwell — bits 11:0 dwell ms, 14:12 index | iSleighDwell — same layout, the pending entry at the last-written index |

**0x4060 Imaging (I · `PM.Blob`; per `../Imaging/DESIGN.md`):**

| Addr | Write | Read |
|---|---|---|
| 0x4060 | oImgCtrl — bit 0 capture en, bit 1 trigger master, bit 2 test pattern | iImgStat — bit 0 frame done, 1 label overflow (sticky), 2 pixels dropped (sticky), 3 sensor PLL locked, 15:8 blobs in the last frame |
| 0x4062 | oImgTrig — bit 0 manual fire, 15:8 frames-per-PPS divider | iImgSeq — frame seq |
| 0x4064 | oImgThresh — bits 7:0 threshold, 15:8 hysteresis | iImgCx / iImgCy — autoinc pair: 1st read cx_q4 of the oldest unread blob, 2nd read cy_q4 and pop (side-effecting read, like 0x4024) |
| 0x4066 | oImgExp — exposure/gain | iImgSum — pixel count (sum_w) of that blob |
| 0x4068 | oImgArea — bits 7:0 min area, 15:8 max area / 16 | iImgThresh readback |

**0x4070 WSPR (U, transmits in C · `PM.Wspr`):**

| Addr | Write | Read |
|---|---|---|
| 0x4070 | oWsprSym — bits 7:0 symbol index 0–161, 9:8 symbol | iWsprSym — bits 1:0 the table's symbol at the sequencer's current index (0 when idle), bit 2 txOn |
| 0x4072 | oWsprCtrl — bit 0 start (the even-minute go) | iWsprStat — bit 0 armed (= iTxGate's interlocked flag), bit 1 txOn, bit 2 done (sticky until the next start) |
| 0x4074 | oWsprDiv — clocks per symbol (low 16 bits; hardware widens to 32) | readback |
| 0x4076 | oWsprBase — NCO increment, tone 0 (low 16) | iWsprPhase — phaseInc low 16 |
| 0x4078 | oWsprStep — NCO increment per tone (low 16) | readback |

`armed` is `PM.RegFile.prTxArmed` (arm key ∧ S3 == C): a start while unarmed is ignored
and txOn can never assert — the same interlock `tx-arm` meets.

**0x4080 Records / Net (N · `PM.Records` + `PM.Net`/`PM.NetRx`; `../Network/DESIGN.md`'s
MAC/IP/port configuration registers follow at 0x408A+ when the UDP TX lands):**

| Addr | Write | Read |
|---|---|---|
| 0x4080 | oNetCtrl — bit 0 enable (records enter the path only when set), bit 1 flush | iNetStat — bit 0 enabled, 1 tx busy, 2 rx activity |
| 0x4082 | oNetTest — fire one PPS_STATUS record (offset = value) | iNetSeq — current datagram seq |
| 0x4084 | — | iNetDrops — record drops, all ports (sticky, loud) |
| 0x4086 | — | iNetRxGood — CRC-good frames accepted |
| 0x4088 | — | iNetRxBad — accepted frames with bad CRC/runt |

0x4090 is reserved for M (Motion radar), TBD at its phase start.

Status (2026-08-31): 0x4020 zone-decode gateware (S2/S3/S4 hysteresis, 1 s S3 dwell, iPanel packing) exists in `pm-lib` (`Oracle/pm-lib/src/PM/Zones.hs`), sim-verified by `cabal test zones-test`.
Status (2026-08-31): 0x4024 matrix-scanner gateware (8×8 scan, 10 ms debounce, event FIFO, iKeys/oMatrixCtrl) exists in `pm-lib` (`Oracle/pm-lib/src/PM/Matrix.hs`), sim-verified by `cabal test matrix-test`.
Status (2026-09-01): 0x4040-block GPS TOD source gateware ($GxRMC byte parser, XOR-checksum gate, BCD TOD words in the Irig set-stub formats + tod_set strobe + locked level) exists in `pm-gps` (`Oracle/pm-gps/src/PM/Gps.hs`), sim-verified by `cabal test gps-test`.
Status (2026-09-01): the register file itself — H2-bus decode for 0x4020–0x403F with the side-effecting 0x4024 read, reset-muted oAudio, synth/keyer command pulses, and the 0x4032 arm-key ∧ mode-C hardware interlock — exists in `pm-lib` (`Oracle/pm-lib/src/PM/RegFile.hs`), sim-verified by `cabal test regfile-test`; Verilog gen confirmed (`pm_regfile`).

Interrupts (via the stock `oIrcMask` controller): matrix key event, SD transfer done,
keyer decoder char, harp event, 1 ms timer. Everything else is polled.

## 2. Forth word set

eForth style: lower-case names, `( before -- after )` stack comments, one screen of
words per vocabulary. Kernel words live in the flash image; per-letter vocabularies
load from SD blocks and are `VOCABULARY`-separated so mode words never collide.

### Kernel vocabulary (always resident, in the golden bitstream's image)

| Word | Stack | Semantics |
|---|---|---|
| `mode?` | `( -- z )` | Current S3 zone 0–5 (P=0 … C=5), post-hysteresis, from iPanel. |
| `s4?` | `( -- z )` | S4 zone: 0 OFF · 1 CAL · 2 PLAY · 3 REC. |
| `stable?` | `( -- f )` | True if S3 has not changed zone since last read (gateware flag). |
| `cal` | `( -- )` | Run the current mode's calibration word (deferred; each vocab plugs its own — theremin retune, slider zone learn, harp sensor null). |
| `key-scan` | `( -- )` | Enable matrix scan and hook its event FIFO into `key?`/`key` so eForth's interpreter reads the music keys as an ASCII keyboard (base/SHIFT per panel silk). |
| `mkey?` | `( -- ev t \| f )` | Raw matrix event if present: press/release + keycode, undecoded — for instrument modes that want notes, not ASCII. |
| `tft-emit` | `( c -- )` | Emit one char to the bar TFT console (oTFT, VT100 semantics). `emit` is revectored to fan out UART + TFT. |
| `tft-page` | `( -- )` | Clear TFT, home cursor. |
| `big` | `( f -- )` | Large-font mode on/off (VT100 escape) — the I-clock face, mode banners. |
| `blk-read` `blk-write` | `( a blk -- ior )` | Move one 1024-byte block between buffer and SD; builds eForth's standard `BLOCK`/`BUFFER`/`FLUSH` on the SPI registers. |
| `blk-load` | `( blk -- )` | `LOAD` a block — interpret it as source. |
| `card?` | `( -- f )` | Card present (iSdStat). |
| `greet` | `( -- )` | Read the card's identity block; print the owner's name and defaults on V0, or the guest banner if no card. |
| `spot` | `( -- )` | Append a timestamped log line (IRIG time + current mode + text at `PAD`) to the card's log block range — CW transcripts, WSPR spots, IRIG captures. |
| `mute` `unmute` | `( -- )` | Audio amp mute GPIO via oAudio. |
| `source!` | `( n -- )` | Select audio source(s) bitmask. |
| `mode-go` | `( z -- )` | Dispatch: banner on V0, run zone `z`'s entry word, record it as current. |

### Per-letter vocabularies (from SD; one block range each)

**`PANEL` (P; VL-1 synth mode)** — `voice! ( n -- )` select VL-1 voice 0–9 · `patch! ( d -- )` install
an 8-digit ADSSR patch (`90099914 patch!`) · `rhythm! ( n -- )` · `tempo! ( n -- )` ·
`note-on ( k -- )` / `note-off ( k -- )` keycode→synth command · `seq-rec` / `seq-play`
100-note sequencer control (notes stored to card REC blocks) · `okp` One Key Play from
the recorded sequence · `calc` calculator sub-mode (matrix digits → V0).

**`THEREMIN` (T)** — `t-cal ( -- )` retune both oscillators to the room (S4 CAL) ·
`pitch@ ( -- n )` / `vol@ ( -- n )` current tracked values · `t-view ( -- )`
envelope/spectrum view on V0 · `t>synth ( f -- )` route theremin as a Panel voice
source · `t-range! ( lo hi -- )` playable window.

**`CLOCK` (I)** — `time@ ( -- s m h )` BCD from iIrig · `.time ( -- )` big-font
face on V0 · `lock? ( -- f )` disciplined vs holdover · `.lock ( -- )` status line ·
`irig-cap ( n -- )` capture n frames to log blocks.

**`KEYER` (C)** — `wpm! ( n -- )` · `iambic! ( n -- )` A/B/straight ·
`side! ( f -- )` sidetone into the mixer · `send ( c -- )` queue a char to key ·
`"send ( -- )` send the string at `PAD` · `rx. ( -- )` stream decoder FIFO to V0 ·
`tx-arm ( -- )` write the arm key to oTxGate (only effective in C mode — hardware
interlock) · `tx-off ( -- )` disarm · `cw-log ( -- )` `spot` the QSO transcript.

**`HARP` (E)** — `ev? ( -- f )` event pending · `ev@ ( -- vel str )` pop pluck event ·
`.pluck ( vel str -- )` show on V0 (gate-1 demo) · `harp>synth ( -- )` events drive KS
voices · `harp>midi ( -- )` re-emit as MIDI-style events out the link.

**`SLEIGH` (C; coil track)** — `sleigh-go ( spd -- )` enable at speed (`$100 or $4050 !`) ·
`sleigh-off ( -- )` · `park ( -- )` / `unpark ( -- )` manual park bit · `sleigh? ( -- w )` iSleigh ·
`.sleigh ( -- )` state/coil/paused line · `dwell! ( ms i -- )` / `dwell@ ( i -- ms )` pending table.

**`IMAGING` (I)** — `img-go ( -- )` capture enable · `trig! ( n -- )` divider · `fire ( -- )` manual
frame · `thresh! ( hyst thr -- )` · `area! ( max min -- )` · `blobs? ( -- n )` from iImgStat ·
`cent@ ( -- cy cx )` the 0x4064 pair · `sum@ ( -- n )` · `.cent ( -- )` one line per blob.

**`BEACON` (U; runs in C)** — `wspr-enc ( -- )` callsign/grid/power → 162 symbols (Forth) ·
`sym! ( s i -- )` one table entry · `wspr-load ( -- )` all 162 · `symdiv! ( n -- )` ·
`tones! ( base step -- )` · `wspr-tx ( -- )` `tx-arm` then start at even-minute:00, refused
unless armed · `wspr? ( -- w )` iWsprStat · `beacon ( n -- )` every n minutes · `wspr-log`.

**`NET` (N)** — `net-go ( -- )` / `net-halt ( -- )` enable bit · `net-test ( n -- )` fire a
PPS_STATUS · `seq? ( -- n )` · `drops? ( -- n )` · `rx? ( -- bad good )` · `net-cfg` (0x408A+, TBD).

**`MENU` (O)** — `menu ( -- )` list card contents (games, spoke demo scripts — snooker, SDR, beacon, net) on V0 ·
`run ( blk -- )` load and run an entry · `games` / `scripts` filtered menus · plus the
whole eForth interpreter itself: O mode *is* the ok prompt on glass.

## 3. Boot flow

1. **Power on.** Golden bitstream loads from ULX3S config flash — H2 + all gateware
   peripherals + the eForth kernel image (with the kernel vocabulary above) in BRAM.
   Box reaches `ok` with *no card and no laptop*; amp stays hardware-muted.
2. **Card probe.** `card?` — if present, SPI-init, then **block 0** = identity/boot
   descriptor (magic, owner name, default voice/tempo, block-range directory);
   **block 1** = boot source, `1 blk-load`, which loads the per-letter vocabularies
   and any personal extensions. Bad/absent card → guest mode from flash defaults.
3. **Greeting.** `greet` — V0 shows the owner's name (the card *is* the person) or
   the guest banner.
4. **Initial dispatch.** Read `mode?` once and `mode-go` it — the box wakes up in
   whatever mode the slider already sits in.
5. **Dispatch loop** (the kernel's outer loop, interleaved with the current mode via
   `PAUSE`/polling): when `mode?` differs from the current mode, start a 1 s dwell
   timer (stock timer at 0x4006); any further zone change restarts it. Only after a
   full 1 s in one zone: banner on V0, teardown word of the old mode (mute, tx-off,
   seq stop), `mode-go` the new one. A bumped slider never yanks a demo.
6. **RESET (P0)** is a matrix key, not a CPU reset: the kernel traps it and re-runs
   the *current* mode's entry word (state cleared, vocabulary kept). S4 OFF within a
   mode idles it (muted, screen saver clock); CAL runs `cal`; PLAY/REC gate the
   mode's transport words.

## 4. Gateware vs Forth

**Gateware (Clash), because it is real-time or sample-rate:** H2 core · UART · TFT
text/VT100 renderer and 1920×480 timing · matrix scan + debounce · ADC sequencing +
zone compare with hysteresis · SPI shifter · the entire audio path (VL-1 synth voices,
envelopes, rhythm patterns, KS strings, theremin NCO/frequency counters, mixer, ΣΔ DAC,
sidetone oscillator) · CW element timing and tone decode · IRIG framing · harp link
deserializer · the TX interlock AND-gate.

**Forth, because it is control/UI/sequencing:** mode dispatch and dwell logic · menus,
banners, greetings, views on V0 · SD command layer and the block system · sequencer
record/playback and One Key Play · patch/voice/tempo state · calibration procedures ·
keyer text queue and QSO logging · calculator · spoke demo scripts (snooker ball association and table drawing, SDR tuning, beacon schedule) · everything typed at
`ok`. Rule of thumb: if it must happen every sample or every scan tick, it is gateware;
if a human notices the latency, it is Forth.

## 5. Staged bring-up (PLAN Phase 3 gate)

| Stage | Deliverable | Registers proven | Gate check |
|---|---|---|---|
| 3.1 | eForth `ok` over USB serial (H2 black-box VHDL first, clash-h2 later as Lessons 12–14) | stock 0x4000–0x4014 | `1 2 + .` → 3 |
| 3.2 | `tft-emit`: prompt on the bar TFT, laptop unplugged (verify active area before cutting) | 0x4026 | ok prompt on glass |
| 3.3 | `blk-read`/`blk-load`: SD block 1 loads; plus GPIO/ADC words (`mode?`, `iAdc`) and timer/IRQ | 0x4028–0x402A, 0x4020–0x4022 | block 1 loads; slider zones read |
| 3.4 | Keyer sends, decoder prints to V0; interlock verified (arm refused outside C) | 0x4030–0x4032 | key CW, watch it decode |

Each stage is demoable on its own; the Phase 3 gate is all four. The matrix (0x4024),
synth (0x402E), and harp (0x4036) registers are specified now but first exercised in
Phases 5–6 — the map is laid out so no address moves when they arrive. Later groups:
0x4040 GPS/TOD (`../GPS/DESIGN.md`), 0x4050 Sleigh (`../Coil/DESIGN.md`), 0x4060 Imaging
(`../Imaging/DESIGN.md`), 0x4070 WSPR (`../UHF/DESIGN.md`), 0x4080 Records/Net
(`../Network/DESIGN.md`) — all concrete in §1.1; 0x4090 M (Motion radar) and the S (SDR)
group are assigned at their phase start.
