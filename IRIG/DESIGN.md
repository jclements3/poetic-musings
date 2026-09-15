# IRIG — Phase 2 design (IRIG-B timecode clock)

Phase 2 of PLAN.md: an IRIG-B generator on the ULX3S, free-running on the board
crystal until G (GPS) disciplines it. Gate: spec-valid IRIG-B verified on a
scope/decoder. The skills are deliberately the second rep of Santa Glide's:
counters, framing, serialization.

**Spoke framing (`../PROGRAM.md`):** I adds one piece of hardware to the Panel+Oracle
root — an IRIG-B output (DCLS on a GPIO, AM on the audio path) and the scope that
checks it — and exercises the library's *time* set: the DCLS/AM framer, BCD time
fields, the settable RTC, and the TOD-set strobe contract shared with G. It is the
timestamp source for every recorded thing in the box: N's TIME_MARK, the snooker
demo's camera frames (Imaging, via `strobe_latch`) and radar velocity records (M),
so PLAN Phase 12's 5 % speed-match gate is aligned by *this* clock once G disciplines
it. Status: implemented + sim-verified (`clash/`); the `MAIDEN/…` path below is the
library source archive (a plain directory in this unified repo since 2026-09-15) whose
erratum-fixed reference the port was checked against. In `../CLASH-LIBRARY-MAP.md`
§ Module list, I contributes the IRIG-B DCLS + AM framer with settable BCD RTC
(Timing and clock domains, ✓); the PPS discipline and strobe latch it pairs with are
G's and Imaging's ◐ entries in the same family.

## IRIG-B in one page

- 1 frame/second, 100 bit cells of 10 ms each.
- Cell encoding by pulse width (DC-level shift, "IRIG-B00x"): binary 0 = 2 ms high,
  binary 1 = 5 ms high, position marker P = 8 ms high.
- Frame: P_r (reference) then BCD fields with a position marker every 10 cells
  (P1..P9): seconds (7 bits BCD 00-59), minutes (7), hours (6), day-of-year (10),
  optional year (8), then control functions and straight-binary-seconds (17 bits).
- Modulated variant ("IRIG-B12x"): the same envelope amplitude-modulates a 1 kHz
  sine, mark:space 10:3. We generate BOTH: DC-level out on one pin (BNC per
  LAYOUT.html rear panel), modulated via the audio ΣΔ/PWM path for demo/aux.

## Architecture (Clash modules — names match vl1-clash-module-tree conventions)

```
tick1k   : 25 MHz sys -> 1 kHz cell-phase enable (10 ms cells = 10 phases)
         also the 1 kHz carrier phase for the modulated output
rtc      : BCD clock registers ss:mm:hh + day-of-year; settable via register bus
framer   : 100-cell frame ROM/mux: cell index -> {ZERO, ONE, MARK} from rtc BCD
pwmcell  : cell class -> 2/5/8 ms high within the 10 ms cell
irigb    : top: dcOut :: Bit, amOut :: Signed 8 (to the audio DAC path)
```

Free-run timebase: ULX3S 25 MHz crystal (±~30 ppm) divided to 1 kHz; a fractional
divider trim register allows ppm-level nudging at CAL. When G lands (Phase 7), the
1 kHz enable locks to the PPS-disciplined 10 MHz instead — same modules, new enable.

## Register plan (aligns with Oracle/eforth-pm.md; set/trim moved to the 0x4040 block)

**Moved (Aug 2026):** the original 0x4036–0x403A set-register group collided with
eforth-pm.md's oHarp at 0x4036. Per GPS/DESIGN.md the IRIG/TOD-set and trim registers
now live in the fresh 0x4040 GPS/time block (oTodSet 0x4044, oTodSecs 0x4046,
oTodDay 0x4048, trim under oGpsTrim 0x4042); only status/control stays at 0x4034.

| addr | r/w | function |
|---|---|---|
| 0x4034 | R | status: {locked(0 until G), pps_seen, frame_phase} |
| 0x4034 | W | control: {set_strobe} — latches the set registers into rtc at next P_r |
| 0x4044 | W | oTodSet — strobe semantics shared with GPS/DESIGN.md |
| 0x4046 | W | oTodSecs — seconds-of-day (packed per GPS/DESIGN.md) |
| 0x4048 | W | oTodDay — day-of-year + secs msb |
| 0x4042 | W | oGpsTrim — signed ppm nudge (CAL fallback; not implemented in Phase 2) |

The Clash core's set interface takes BCD digits directly (no /3600, /60 dividers in
hardware); the register file in O does the word packing/unpacking.

Forth words (CLOCK vocabulary per eforth-pm.md): `time!` `time@` `trim!` `irig?`.
Until O exists, the set interface is a DIP-switch/UART-free default: boot at
001:00:00:00 — the scope check doesn't need wall time.

## Verification (the gate)

1. Simulation: Clash testbench asserts cell widths (2/5/8 ms in ticks), marker
   positions every 10 cells, frame length exactly 1.000 s, BCD rollovers
   (59->00 carries, 23:59:59 -> day increment).
2. Bench: scope on the DC output — measure cell widths and the 1 s frame;
   a software decoder (audio-in on a laptop against the modulated output, or a
   logic-analyzer capture) decodes back the set time.
3. Drift log: 24 h against WWV/phone NTP — record ppm for the CAL trim default.

## Demo (per PLAN.md)

"A clock that speaks range timecode": scope shows the frame; the decoder prints the
advancing time; later, Phase 7 makes the same clock stop drifting — the before/after
IS the GPS lesson.

## Explicitly out of scope for Phase 2

GPS/PPS (Phase 7), IEEE-1588/NTP anything, battery backup, display (I mode's V0
screen arrives with O; until then the scope is the display), stamping other spokes'
records (that is `strobe_latch` and the record mux — Imaging/DESIGN.md and
Network/DESIGN.md consume this clock; they do not extend it).

## Status (31 Aug 2026)

Implemented and simulation-verified in `clash/` (GHC 9.6.7 + Clash 1.8.5, own cabal
project patterned on Oracle/clash-h2 and MAIDEN/lessons):

- `clash/src/Irig.hs` — all five modules per the architecture above: `tick1k`,
  `framePos` (cell/ms sequencer, split out of tick1k), `rtc`, `framer`, `pwmcell`,
  `irigb`, plus the synthesis `topEntity` ("irigb", domain `Ulx25` = 25 MHz).
- Timing is one parameter, `SNat k` = ticks per 0.1 ms (the carrier needs 10 sine
  samples per 1 kHz cycle, so 0.1 ms is the finest phase): `SNat 2500` = real ULX3S
  timing (25 000 ticks/ms), `SNat 1` = simulation (10 ticks/ms, one frame in 10 000
  ticks).
- Frame layout cross-checked bit-for-bit against the decoder-verified reference
  `MAIDEN/firmware/timebase/rtl/irigb_gen.vhd` — including its lesson-18 erratum fix:
  P9 at cell 89, SBS split 80–88 / 90–97, cell 98 zero, P0 at 99.
- Both outputs: `dcOut` (DC-level shift, IRIG-B00x) and `amOut :: Signed 8`
  (1 kHz sine, mark:space 10:3 ≈ 95:29 peak, IRIG-B12x) for the audio ΣΔ/PWM path.
- Set interface: BCD digit ports + `set_strobe`, latched and applied at the next P_r.

How to run (needs `$HOME/.ghcup/bin:$HOME/.cabal/bin` on PATH; work in `clash/`):

    cabal test irig-test --test-show-details=direct   # the Verification #1 gate
    cabal exec -- clash -isrc Irig --verilog          # -> verilog/Irig.topEntity/irigb.v

The testbench (`clash/test/Spec.hs`) asserts over 8 full frames: 2/5/8 ms cell widths
in ticks with high-then-low shape, markers exactly every 10th cell + the P0/P_r
double marker, 100 cells / exactly 1.000 s per frame, unused cells zero, seconds
59→00 carrying into minutes, the full 23:59:59 → day-increment carry (with SBS wrap),
the set_strobe next-P_r latch, and the exact AM carrier tables. The generated Verilog
compiles under iverilog and elaborates in yosys (~285 cells before techmap).

Not yet implemented: the fractional-divider CAL trim (register reserved at 0x4042),
the register-file/status hookup (arrives with O), and the bench/drift verification
steps (need hardware).
