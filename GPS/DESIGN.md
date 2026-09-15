# GPS — Phase 7 design (G · PPS-disciplined time for the One Box)

PLAN.md Phase 7: u-blox PPS in → PPS-locked 10 MHz → discipline the Phase 2 IRIG
clock → disciplined clock copies as a stock module. Gate/demo: the Phase 2 clock stops
drifting — holdover vs. locked, verified against the GPSDO metrology reference
(used GS-101B or Thunderbolt-class, per HANDOFF and fpga-development-plan #7, ~$30
u-blox + reference). Ledger: IRAD.

**Spoke framing (PROGRAM.md):** G adds one piece of hardware to the Panel+Oracle root
— the u-blox module (PPS + NMEA) and a 10 MHz BNC out — and exercises `PM.Gps`
(NMEA parser, ✓), `pps_discipline.vhd` (measurement layer, measured VHDL) and the
planned DPLL. Its main customer inside the box is the snooker demo: I stamps every
camera frame and M every radar velocity record from the RTC this letter disciplines,
so the 5 % speed-match gate in PLAN Phase 12 depends on G. The `MAIDEN/…` paths below
are the library source archive, not a dependency on another program.

## What is already built (harvest from MAIDEN/firmware/timebase)

`pps_discipline.vhd` — sim-verified (maiden37, `tb/timebase_tb.vhd` with a
deterministic simulated GPS: programmable ppm error and jitter):

- free-running 48-bit RTC (Ch.10 header width), 1 clk = 1 count at 10 MHz;
- async PPS → 2-FF synchronizer → edge detect (house rule for every async input);
- per-PPS interval measurement: `offset` = interval − RTC_HZ, s20, clamped;
- `locked` = last 3 intervals within ±LOCK_TOL (500 counts = 50 ppm);
- watchdog: no PPS for >1.5 s drops lock → holdover; wild first-edge intervals
  classified bad, not folded into lock.

`irigb_gen.vhd` consumes `rtc/pps_stb/tod_set` and aligns P_r to the PPS-derived top
of second; `strobe_latch.vhd` stamps external events against the same RTC. All three
stay usable as black boxes (LIBRARY.md porting rule); the Clash port lands with this
letter, since G is the letter that needs them on the ULX3S.

## Design decision: measure-and-report AND steer — two layers

MAIDEN took lesson 18's **option 2**: the RTC is *never* steered; Ch 1 time packets
publish the RTC↔UTC mapping and drift becomes a slope in ingest. That contract is
correct for everything **recorded** (N's Ch.10 stream, I centroids, M velocity records) and PM keeps it
verbatim — `pps_discipline` is reused unmodified as the measurement layer.

PLAN's "10 MHz DPLL" is the second, *physical* layer PM adds on top: instruments
downstream of a BNC (IRIG DCLS out, 10 MHz station copy, U's WSPR beacon — WSPR
cares about absolute Hz) need a steered output, not a mapping. So:

```
             ┌──────────────────────────── ULX3S 25 MHz xtal ── PLL ──► clk_sys
  u-blox PPS ─2FF─► pps_discipline ──offset──► loop filter ──trim──► frac-N NCO ─► 10 MHz out
                    │  (unsteered RTC,          (PI, ppm units)      (steered)     1 PPS out
                    │   offset, locked)                                  │
                    └─► TIME_MARK / PPS_STATUS records (PROTOCOL.md 0x11/0x10) ─► N
                                                                         │
             IRIG (Phase 2) 1 kHz cell enable re-sourced from the ────────┘
             disciplined 10 MHz ("same modules, new enable" — IRIG/DESIGN.md)
```

DPLL loop: `offset` (counts/s ≡ ppm×10) feeds a PI filter; the correction updates a
32-bit fractional-N phase accumulator dividing clk_sys to the 10 MHz enable/output.
Time constant ~100 s (crystal is stable short-term; GPS PPS is noisy short-term),
slew-limited so a wild PPS cannot yank the output; on holdover the accumulator
freezes at its last correction (best-known crystal trim) — exactly the IRIG
free-run-with-trim behavior IRIG/DESIGN.md already specifies at CAL.

Disciplined clock copy (stock module, consumed by I, M, N, U): disciplined
10 MHz + 1 PPS + IRIG-B DCLS + the two status record types. One entity, N copies.

## Register block (Oracle/eforth-pm.md conventions — 16-bit, even addresses, PM
peripherals extend from 0x4020; all addresses provisional until forth-cpu-notes.md
pins the stock map)

**Collision flag:** IRIG/DESIGN.md provisionally uses 0x4036–0x403A for time-set
registers, but eforth-pm.md assigns 0x4036 to oHarp/iHarp. Resolution proposed here:
IRIG keeps only 0x4034 (status/control per eforth-pm), its set/trim registers move
into this GPS block, and GPS claims a fresh 0x4040 group:

| addr | write | read |
|---|---|---|
| 0x4040 | oGpsCtrl — dpll enable, loop-gain sel, holdover force (test), lock-LED sel | iGpsStat — {locked, holdover, pps_seen, sats>0 (from NMEA via O)} |
| 0x4042 | oGpsTrim — manual frac-N trim (signed ppm, CAL fallback = IRIG's trim word) | iGpsOffset — last PPS interval error, signed counts (s16 view of s20) |
| 0x4044 | oTodSet — strobe: latch 0x4046/0x4048 into irigb_gen tod_set | iPpsRtcLo — RTC at last PPS, low 16 |
| 0x4046 | oTodSecs — seconds-of-day (u17 packed w/ 0x4048 bit) | iPpsRtcMid |
| 0x4048 | oTodDay — day-of-year u9 + secs msb | iPpsRtcHi — RTC high 16 |

Forth (CLOCK vocabulary additions per eforth-pm.md): `lock?` `.lock` (already
specified) plus `trim!` `offset@` `tod!`. NMEA parsing (second *label*; PPS gives the
*edge*) is Forth's job over the stock UART — no NMEA parser in gateware.

## Verification (PLAN Phase 7 gate)

1. **Sim:** extend MAIDEN's `timebase_tb.vhd` pattern — deterministic PPS with +30
   ppm crystal error: DPLL output converges to 10.000 MHz ±0.1 ppm within 5 τ;
   holdover freezes trim; re-lock is slew-limited; RTC layer asserts unchanged
   (regression: option-2 contract not broken by the DPLL).
2. **Bench vs metrology:** disciplined 10 MHz against the GPSDO reference —
   frequency counter (mutual gating) and scope PPS-vs-PPS drift over 24 h; log to
   `GPS/results/`. Target: <0.1 ppm locked; record holdover drift rate.
3. **The demo:** IRIG clock from Phase 2 running side-by-side against the reference
   decoder, locked vs holdover — the before/after *is* the lesson.

## Out of scope

Position/velocity output (U takes NMEA directly), IEEE-1588/NTP, multi-GNSS timing
survey-in tuning (u-blox defaults first), OCXO holdover upgrades (crystal + trim is
enough until a longer-than-10-minute snooker session says otherwise).
