# STATUS — POETIC MUSINGS

**As of 2026-09-15.** One-page state of the program: where each phase stands, what
the library holds, what is on order, what is blocking. Update this file at the end of
every working session; the detail it summarises lives in `PLAN.md`,
`CLASH-LIBRARY-MAP.md` § Status, and `ORDERS.md`.

## Headline

The program is reoriented as a **Clash FPGA signal-processing library** demonstrated on
one box (Panel body + Oracle brains) with ten hardware spokes. Docs are unified in one
self-contained repo. Gateware is ahead of hardware: 33 library blocks are verified in
simulation, the H2 boots real eForth, and every Phase 0 gate is met — but the FPGA
board is on backorder, so nothing runs on silicon until October.

## Phases

| Phase | Letter | State | Gate | Next action |
|---|---|---|---|---|
| 0 Foundations | — | **done** 08-31 | both firmwares compile, eForth boots in sim | — |
| 0b Repo hygiene | — | **done** 09-15 | unified repo, DESIGN/ORDERS per directory | — |
| 1 Santa Glide | C | parts in hand; **Rev D: FSM moves into the box** (Cu retired) | slug glides A→B→A | wind coils, build driver channels now; `PM.Sleigh` when the board lands |
| 2 IRIG clock | I | **sim-verified** | spec-valid IRIG-B on a scope | scope check once R1 lands |
| 3 Oracle | O | ladder pre-proven in sim | `ok` on glass, SD loads, keyer decodes | wire real pins when R1 lands |
| 4 Theremin | T | Clash port measured, green | pitch/volume from antennas | bench the LC oscillators |
| 5 Panel | P | design done; fabrication + printer spec'd | events, zones, console, synth blocks | order printer, print coupon |
| 6 Erand49 | E | frame CAD done, gateware spec'd | one string plucks (gate 1) | bore gauge, then gate-1 kit |
| 7 GPS | G | design done; NMEA parser ✓ | clock stops drifting | u-blox module after O |
| 8 Network | N | design done; UDP TX ✓ | zero-drop 10 min | PHY PMOD after O |
| 9 UHF | U | design done; keyer ✓ | wsprnet spot | after G |
| 10 SDR | S | design done; DSP blocks ✓ | AM decoded in-box | after T |
| 11 Imaging | I | design done (snooker) | gap-free ball track @ 200 fps | Sep FOV study, then camera |
| 12 Motion radar | M | design done (snooker) | radar speed within 5 % of camera | after Imaging + G |

Build order: **O → P → T**, then spokes as hardware arrives. December path: O → P →
I → G → N → snooker demo; C ships for Christmas standalone.

## Library (CLASH-LIBRARY-MAP.md § Status)

| Family | ✓ | ◐ | ○ |
|---|---|---|---|
| DSP core | 11 | 1 | 4 |
| Audio and synthesis | 6 | 0 | 4 |
| I/O and links | 7 | 2 | 5 |
| Timing and CDC | 4 | 2 | 2 |
| Control and display | 4 | 0 | 1 |
| **Total** | **32** | **5** | **16** |

Regression gate (theremin suite): **green**. Measured on ECP5: ThereminTop 1,816 LUT4,
Fft512 4,620 LUT4, IirNStage 175 LUT4, text console ~200 LUT4.

## Orders (ORDERS.md)

| Status | Items |
|---|---|
| backorder | ULX3S ECP5-85F — Mouser batch **2026-10-02** |
| received | Santa Glide parts; theremin oscillator parts |
| order now | Bambu Lab P1S + filament; bore gauge |
| next | TFT kit, switches/pots (after print coupon), gate-1 harp kit (after board) |

## Blockers and risks

- **Board backorder** to 2026-10-02: no silicon measurements before then. Mitigation:
  printer, coupon, oscillator bench and Santa Glide bring-up all proceed without it.
- **Sep Basic Plan inputs due:** Imaging FOV/sensor study (now with the snooker table
  as the fixed target) and the GPSDO metrology pick.
- **Decided 09-15: one FPGA board (ULX3S).** Cu retired; no harp-side board.
- **Open design items:**
  Panel silk layer; M and S register groups unassigned; `lib/` migration out of the
  `MAIDEN/` archive.

## Recent changes

- 09-15: one-FPGA rule (ULX3S only; Santa Glide Rev D in the box, Cu retired; no harp board);
  reorientation to library + root/spokes; Piano → Panel; MAIDEN capstone
  dropped, M = Motion radar; snooker tracking as the I/M demo; DESIGN.md in every
  directory; ORDERS files; repo unified and pushed to github.com/jclements3/poetic-musings.
- 08-31: Phase 0 gate met; H2 boots eForth in Clash sim; IRIG sim-verified.
