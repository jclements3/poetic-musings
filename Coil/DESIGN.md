# Coil — Phase 1 design (C · Sleigh Glide, driven from the box)

**Decision 2026-09-15: the ULX3S is the only FPGA board in PM.** The coil sequencer
moves into the box; the Alchitry Cu is retired from the program (kept as a bench
spare). Rev C's Cu firmware and the 250 kbaud sleigh link are superseded by **Rev D**:
the same Moore FSM, dwell table, watchdog and pacer, compiled for the ECP5, driving
the MOSFET board at the tube over a gate ribbon.

PLAN.md Phase 1: a painted steel slug (the sleigh) glides inside a 10 ft silicone
tube strung over the snow village, driven by 8 coils sequenced by the box — an
open-loop 8-pole linear reluctance motor. Personal ledger, parts in hand. Working docs
in `SleighGlide/`: `HANDOFF.md` (design history, drawings SS-001..004, coil spec,
bring-up order), `firmware/BUILD.md` (Rev B/C sim proof — still valid for the FSM),
`drawings/`. **Gate:** slug glides house A→B→A continuously while the show switch is
on; parks in place on pause; dwell profile tuned. **Demo:** flip the switch; The sleigh
floats over the village — theremin pitch sets the speed.

**Spoke framing (`../PROGRAM.md`):** C adds to the Panel+Oracle root the hardware
that lives at the table — the tube, 8 coils, the low-side MOSFET driver board and its
24 V supply — connected by **one 10-wire ribbon** (8 gates + show-switch sense +
ground) from the rear SLEIGH connector. Library components it exercises: the Moore
FSM / dwell table (SS-004), the virtual-tick pacer, the dead-man watchdog (now on the
ribbon's presence line), PWM coil drive, and the theremin-pitch → speed mapping from
`PM.SleighSpeed`. In `../CLASH-LIBRARY-MAP.md` § Module list this becomes one in-box
block, `PM.Sleigh` (○ — a port of `SleighGlide.hs` onto the register bus; the FSM and
pacer sims carry over unchanged).

**Shared fixture with I and M:** the snow village sits on the 5×10 ft American snooker
table (`HANDOFF.md` §1) — the table the overhead camera and Doppler radar watch in
PLAN Phases 11–12. The sleigh is a known-trajectory moving target for the vision chain.

## Signal path (Rev D)

```
Panel S4 PLAY / show switch (ribbon sense) ─┐
T mode: theremin pitch ─► speed 1..255 ─────┼─► PM.Sleigh  (0x4050 group)
volume off / ribbon unplugged ─► watchdog ──┘        │ pacer (rate speed/256)
                                                       │
                     PARK_A → GLIDE_FWD → PARK_B → GLIDE_REV ring (SS-004 dwell table)
                                                       │
   rear SLEIGH 10-pin ─ ribbon (≤ 3 m) ─► driver board at the tube:
   gates[0..7] ─► 100 Ω ─► IRLZ44N low-side ─► coil ─► +24 V bus, 1N5408 flyback (SS-003)
   (10 kΩ gate pulldowns keep every MOSFET off when the ribbon is out)
```

- **Open loop by design:** velocity comes from the coil-stepping schedule; no
  position sensing in v1 (per-station pickup is the closed-loop v2 option).
- **Watchdog = dead-man:** the ribbon carries a sense line pulled up at the box and
  grounded on the driver board; open ribbon = parked. Volume-off from T mode parks
  too. The show switch on the driver board is read over the same ribbon and still
  overrides (Moore, no leak to the gates — the Rev B fix).
- **Pacer, not multipliers:** speed scales the dwell table by skipping virtual
  ticks; speed 255 is Rev B timing within 0.4 %, so the tuned table survives.
- **24 V never enters the box:** only 3.3 V gate signals and ground cross the ribbon;
  series 100 Ω at the box, pulldowns at the board. The bench supply stays at the tube.
- **Retired:** the Cu, `sleigh_rx`, the 0xA5 frame link, `sleigh_glide.pcf`. The
  `PM.SleighSpeed` TX block stays in the library as tested code (its pitch → speed
  mapping is reused in `PM.Sleigh`).

## Register / Forth interface (`../Oracle/eforth-pm.md`, new 0x4050 group)

| addr | write | read |
|---|---|---|
| 0x4050 | oSleigh — enable, speed 1..255 (or "follow theremin"), manual park | iSleigh — state (PARK_A/GLIDE_FWD/PARK_B/GLIDE_REV), coil index, ribbon present, show switch |
| 0x4052 | oSleighDwell — dwell-table entry write (index, ms) for live tuning | iSleighDwell — readback |

Forth `SLEIGH` vocabulary (C mode or from T): `sleigh-go` `sleigh-park` `speed!
( n -- )` `t>sleigh ( -- )` follow theremin pitch · `dwell! ( ms i -- )` tune a
station live · `.sleigh` state on V0.

## Verification (the gate)

1. **Sim (carried over, green):** FSM hold/step, exact pacer rates, watchdog decay
   from `SleighSim.hs` and the Rev B clashi walk (`BUILD.md`); re-run against
   `PM.Sleigh` with the ribbon-sense input replacing UART rx.
2. **Build:** `PM.Sleigh` in the box bitstream; `synth_ecp5` area (expect < 300 LUT4).
3. **Bench (the gate), HANDOFF §7 order, driven from the Forth console:** channel 0
   alone at 12 V / CC 2 A → 7 more channels → wind 8 coils (200 T, 24 AWG, 0.4 Ω) →
   slug in, all dwells 400 ms → tune `runDuty`, then `dwell!` per station live from
   the prompt, then voltage. Pass = continuous A→B→A glide with the switch on, parked
   on pause. Evidence to `SleighGlide/results/`.
4. **Link:** theremin pitch changes the glide speed live; pulling the ribbon parks
   the sleigh immediately (pulldowns) and iSleigh reports ribbon absent.

**Schedule note:** Phase 1 now needs the ULX3S (backordered to 2026-10-02). Coil
winding, the driver board and channel tests with a bench 3.3 V source proceed before
it arrives; the FSM-driven glide follows in October — still ahead of Christmas.

## Safety (grandkids present)

Locked bench supply with current limit at the tube; 24 V never on the ribbon or in
the box; fused + bus; gate pulldowns keep every MOSFET off at power-up and with the
ribbon out (SS-003).

## Out of scope

Closed-loop position (v2), half-stepping overlap, battery power for the deployed
show (a fixed 24 V brick later), running the sleigh without the box (retired with
the Cu — the show needs the box present).
