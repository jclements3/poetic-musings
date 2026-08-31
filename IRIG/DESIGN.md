# IRIG — Phase 2 design (IRIG-B timecode clock)

Phase 2 of PLAN.md: an IRIG-B generator on the ULX3S, free-running on the board
crystal until G (GPS) disciplines it. Gate: spec-valid IRIG-B verified on a
scope/decoder. The skills are deliberately the second rep of Santa Glide's:
counters, framing, serialization.

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

## Register plan (aligns with Oracle/eforth-pm.md, provisional 0x4034 block)

| addr | r/w | function |
|---|---|---|
| 0x4034 | R | status: {locked(0 until G), pps_seen, frame_phase} |
| 0x4034 | W | control: {set_strobe} — latches the set registers into rtc at next P_r |
| 0x4036 | W | set ss:mm (BCD) |
| 0x4038 | W | set hh:doy-low (BCD) |
| 0x403A | W | set doy-high : trim (signed ppm nudge) |

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
screen arrives with O; until then the scope is the display).
