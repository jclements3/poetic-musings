# Coil — Phase 1 design (C · Santa Glide, the one spoke on its own board)

PLAN.md Phase 1: the first demo, standalone. A painted steel slug (Santa's sleigh)
glides inside a 10 ft silicone tube strung over the snow village, driven by 8 coils
sequenced by an **Alchitry Cu (iCE40 HX8K)** running Clash — an open-loop 8-pole
linear reluctance motor. Personal ledger, parts ordered. Working docs live in
`SantaGlide/`: `HANDOFF.md` (design history, drawing set SS-001..004, coil spec,
bring-up order), `firmware/BUILD.md` (Rev B/C build and sim proof), `drawings/`.
**Gate:** slug glides house A→B→A continuously while the show switch is on; parks in
place on pause; dwell profile tuned. **Demo:** flip the switch; Santa floats over
the village with no laptop — the Christmas deliverable.

**Spoke framing (`../PROGRAM.md`):** C is the only spoke whose hardware is *not*
inside the box: the tube, coils, driver board and the Cu pack alongside. It attaches
to the Panel+Oracle root by one wire — `PM.SleighSpeed` on the ULX3S sends (0xA5,
speed) frames at 250 kbaud (SS-005) and the Cu's Rev C firmware receives them. The
library components it exercises: the sleigh speed link (✓ both ends, `sleighspeed-test`
+ `SleighSim`), the 250 ms dead-man watchdog, the virtual-tick coil pacer, the Moore
FSM / dwell table (SS-004), PWM coil drive, and the iCE40 build flow (PLL from the
Cu's 100 MHz, 59.1 MHz closure). It is the library's second target device: the same
Clash blocks synthesised for iCE40 and ECP5. In `../CLASH-LIBRARY-MAP.md` § Module
list, C contributes the sleigh speed link with watchdog and pacer (I/O and links, ✓);
the Moore FSM / PWM drive stay in `SantaGlide/firmware` as the Cu-side consumer.
Everything C needs is inside this unified repo — `SantaGlide/` holds the handoff,
drawings, firmware and order screenshots.

**Shared fixture with I and M:** the snow village sits on the 5×10 ft American snooker
table (`HANDOFF.md` §1) — the same table the overhead camera and Doppler radar watch
in PLAN Phases 11–12. The sleigh is a known-trajectory moving target for the snooker
vision chain: a free calibration object for centroid tracking and radial speed.

## Signal path

```
One Box (T mode)  theremin pitch ─► speed 1..255 ─┐   volume off / cable out / sender
                                                    ├─► PM.SleighSpeed ─ 250 kbaud ─► Cu sleigh_rx
show switch (local, always overrides) ─────────────┘        (0xA5, speed) 50/s      │
                                                        UART rx ─► 250 ms watchdog ─► pacer (rate speed/256)
                                                                                        │
                                   PARK_A → GLIDE_FWD → PARK_B → GLIDE_REV ring (SS-004 dwell table)
                                                                                        │
                                   gates[0..7] ─► 100 Ω ─► IRLZ44N low-side ─► coil ─► +24 V bus, 1N5408 flyback (SS-003)
```

- **Open loop by design:** velocity comes from the coil-stepping schedule; no
  position sensing in v1 (per-station pickup is the closed-loop v2 option).
- **Watchdog = dead-man:** an unplugged or idle link parks the sleigh at hold duty;
  the show switch still freezes the FSM regardless of the link (Moore, no leak to
  the gates — the Rev B fix).
- **Pacer, not multipliers:** speed scales the dwell table by skipping virtual ticks;
  speed 255 is Rev B timing within 0.4 %, so the tuned table survives the link.

## Register / Forth interface (`../Oracle/eforth-pm.md`)

The box side is one TX-only link driven from the THEREMIN vocabulary; no register
of its own beyond the SleighSpeed enable. Cu side: `show_on` switch, `sleigh_rx`
(Br bank A, pullup), `gates[0..7]` (bank A, no pullups, `santa_glide.pcf`).

## Verification (the gate)

1. **Sim (green):** `SleighSim.hs` — UART decode at divisor 200, watchdog decay,
   exact pacer rates, FSM hold/step; `sleighspeed-test` in `Oracle/pm-lib` for the
   TX side (frames track pitch, clamps, dead-man 0). FSM re-verified in clashi
   after retiming (`BUILD.md`).
2. **Build (green):** Rev C bitstream, PLL 100 → 50 MHz, closes at 59.1 MHz, ~4 %
   of the HX8K. Flash from Windows with Alchitry Labs.
3. **Bench (the gate), HANDOFF §7 order:** channel 0 alone at 12 V / CC 2 A → 7
   more channels → wind 8 coils (200 T, 24 AWG, 0.4 Ω) → slug in, all dwells
   400 ms → tune `runDuty`, then the dwell table, then voltage. Pass = continuous
   A→B→A glide with the switch on, parked on pause. Evidence to `SantaGlide/results/`.
4. **Link (Rev C):** theremin pitch changes the glide speed live; pulling the cable
   parks Santa within 250 ms.

## Safety (grandkids present)

Locked bench supply with current limit; no 24 V near the FPGA; fused + bus; gate
pulldowns keep every MOSFET off at power-up (SS-003).

## Out of scope

Closed-loop position (v2), half-stepping overlap, battery power for the deployed
show (a fixed 24 V brick later), anything the library already proves on the ULX3S.
