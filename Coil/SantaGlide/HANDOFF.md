# HANDOFF — Santa Glide (FPGA-controlled linear reluctance motor, snow village show)

**Owner:** JC (James Clements), Laceys Spring, AL
**Handoff date:** 2026-08-31
**From:** Claude (mobile chat) → **To:** Claude Desktop / Claude Code
**Status:** Design complete, all parts ordered, firmware Rev B written but **not yet compile-tested**. Next phase is bring-up.

---

## 1. What this project is

A holiday animatronic for the grandkids. A small steel slug with Santa's sleigh
painted on it glides back and forth inside a clear 1/8" ID silicone tube strung
in an arc over a snow village on a 5×10 ft American snooker table. The slug is
moved by **8 coils wound around the tube**, energized in sequence by an
**Alchitry Cu (iCE40 HX8K)** FPGA running firmware written in **Clash**
(Haskell HDL). It is an open-loop, 8-pole linear reluctance motor — a stepper
motor unrolled flat. Velocity is set entirely by the coil-stepping schedule.

The magic: nothing touches Santa, no wires, no visible mechanism. He floats
from house A to house B, pauses, floats back, forever, while a show switch is on.

## 2. Design history (so you don't re-litigate settled decisions)

| Rev | Idea | Why it was dropped |
|---|---|---|
| v1 | Servo sweeping Santa on a wire | JC wanted a coil launcher |
| v2 | Single coil launcher + push button | Needed to return to A |
| v3 | Two coils (launch/catch at each house) | Ballistic, hard to tune, not "magical" |
| **v4 (current)** | **8-coil sequenced glide, slug inside tube** | — |

Settled decisions — don't reopen unless JC asks:
- Slug is **soft mild steel, not a magnet** (single MOSFET per coil, attraction only).
- Santa is **painted directly on the slug**; nothing hangs from it.
- Power is a **bench supply (NANKADF 30V/10A)** for development, not AA batteries.
  A fixed 24 V brick may replace it for the deployed show later.
- Coil wire is **24 AWG** (JC bought this instead of 28 AWG — it's fine, spec was updated).
- Houses are pulled in ~1 ft from the table corners so the flight path fits the 10 ft tube.
- Firmware is a **pure Moore machine** (Rev B); the earlier Mealy leak from the
  show switch to the MOSFET gates was identified and fixed.

## 3. Drawing set (drawings/)

| No. | File | Contents |
|---|---|---|
| SS-001 | `SS-001_slug.svg` | Slug: Ø2.8 × 20 mm mild steel, 0.5×45° chamfers, 0.4 mm anti-roll flat. ISO 128, first angle, 10:1 |
| SS-002 | `SS-002_tube_winding.svg` | 10 ft tube layout: 6" in each house mount, 108" flight path, 8 stations at 4/14/28/46/62/80/94/104" from datum A. Coil detail: 20 mm band. **Winding spec in this drawing says 300T of 28 AWG — superseded, see §6.** |
| SS-003 | `SS-003_power_drive_wiring.svg` | 8-channel low-side driver: FPGA pin → 100 Ω → IRLZ44N gate (10 kΩ pulldown), coil to +24 V bus, 1N5408 flyback (stripe to +), bulk cap, single star ground. Battery symbol = now the bench supply. |
| SS-004 | `SS-004_state_machine.svg` | UML state machine of the firmware: PARK_A → GLIDE_FWD → PARK_B → GLIDE_REV ring, dwell table, ¬showOn freeze rule. |

Open all SVGs in a browser. They're the spec; the prose in this file is the commentary.

## 4. Firmware (firmware/SantaGlide.hs) — Rev B

- Clash, target `System` domain = 100 MHz (Alchitry Cu).
- `controller = moore next output initSt` — output depends on state only.
- State: `St { phase, coil :: Index 8, t, rest, paused }`.
- Output: `Vec 8 Drive` where `Drive = Off | Hold | Run`, then a PWM stage
  (`holdDuty ≈ 5 %`, `runDuty ≈ 20 %`, 8-bit carrier ~390 kHz) → `Vec 8 Bit` gates.
  **Never drive a coil 100 % continuous** — coils are ~0.4 Ω, that's a 50 A short at 24 V.
- Velocity profile = `dwellMs :: Index 8 -> Unsigned 32` (400/250/150/100/100/150/250/400 ms, symmetric).
- Show switch is debounced (10 ms) and registered into `paused`; ¬showOn freezes
  timers and drops the active coil to `Hold` so Santa parks in place.
- `topEntity` ports: `clk rst en show_on` in, `gates[7:0]` out. `gates[0]` = station C0 nearest house A.

**Not yet done:** it has never been compiled. Expect small type errors
(`RecordWildCards` pragma may be needed for `St{..}`, `boolToBit` import, etc.).
First task on desktop: `clash --verilog SantaGlide.hs` and fix whatever falls out.

## 5. Hardware inventory

### Ordered (screenshots in orders/)
| Part | Qty | Role | Note |
|---|---|---|---|
| Alchitry Cu (iCE40 HX8K) | 1 | Controller | 100 MHz, 3.3 V I/O, USB-C powered |
| IRLZ44N MOSFET | 10 | Coil switches | 8 used + 2 spare |
| 1N5408 diode | 10 | Flyback | 8 used + 2 spare, stripe to +24 V |
| Silicone tube 1/8" ID × 1/4" OD, 10 ft | 1 | Motor bore / arc | 10 ft is the flight-path budget |
| BNTECHGO 24 AWG magnet wire, 4 oz (~195 ft) | 1 | Coils | **Recommend 2nd spool** — 8 coils need ~135 ft |
| NANKADF 30V/10A bench supply | 1 | Coil power | Use CC limit! Start 24 V / 2 A |
| XB2EA31 green push button | 1 | Spare / speed preset | Unused in Rev B; candidate for 3-speed cycling |
| 2×8 AA battery holders | 1 | Retired | Was the original supply; bench/backup only |
| Reaction Tackle monofilament | 1 | Bore pull line | For cleaning/retrieving the slug; not electrical |
| BOJACK resistor kit (1/4 W, 1 %) | 1 | 100 Ω gate, 10 kΩ pulldown | |

### Recommended / possibly in cart (JC was ordering at handoff time)
2200 µF 35 V caps · 22 AWG stranded hookup wire · 12-pos barrier terminal strip
(MILAPEAK, jumper strips become the buses) · ELEGOO proto boards · Wirefy heat
shrink · AstroAI DM130B multimeter · WEP 927-IV soldering station ·
rolling workbench (PAKASEPT 55" was the pick). Hardware store: 10d finishing
nails (slug stock), talc/dry PTFE, primer + enamel.

## 6. Coil spec — CURRENT (supersedes SS-002 note 1)

- 24 AWG enameled: **200 turns per coil = 5 layers × 40 turns**, 20 mm band.
- ~16–17 ft per coil, ~135 ft for 8. Build height ~2.5 mm.
- R ≈ **0.4 Ω per coil** → *must* use PWM duty and supply current limit.
- Wind in place on the tube, all same direction, mark start leads.
- Finish leads → +24 V bus. Start leads → MOSFET drains.

## 7. Bring-up plan (suggested order)

1. **Compile firmware** (`clash --verilog`), fix type errors, simulate in `clashi`:
   feed `showOn = True` and confirm `gates` walks 0→7→0 with the right dwells.
2. Alchitry constraints: `show_on` to a switch, `gates[0..7]` to bank I/O, all outputs, no pullups.
3. **Channel 0 alone** on the bench: supply 12 V / CC 2 A, one coil, verify slug snaps in.
   Manually touch 3.3 V to the gate node before involving the FPGA.
4. Build the other 7 channels on proto board; test each with a one-hot test bitstream
   (a trivial `topEntity` that maps DIP switches to gates is useful here).
5. Mount tube, load slug, run Rev B with all dwells = 400 ms. Confirm handoff station-to-station.
6. Tune: `runDuty` first (pull strength), then `dwellMs` table (speed profile), then supply voltage.
7. Optional next features: 3-speed preset on the green button; adjacent-coil overlap
   ("half-stepping") during handoff; per-station sensing (phototransistor or
   unpowered-coil pickup) for closed-loop v2.

## 8. Things JC cares about / how to work with him

- Learns Clash by doing; explain hardware inference (Moore vs Mealy, fold vs tree) when relevant.
- Mobile-first: he pastes whole messages into Amazon search — when giving search terms,
  put **just the term as the entire message** or give **direct product links**.
- Likes ISO 128 / IEC 60617 drawing conventions; keep the SS-00n sheet numbering going (next is SS-005).
- Grandkids will be around the show: safety notes (locked supply, no 24 V near FPGA, fused +) are welcome, not nagging.

## 9. Open questions

- Exact house positions on the table (must give ≤ ~9 ft straight-line span).
- Whether the deployed show uses the bench supply or a fixed 24 V brick.
- Whether to add the second magnet-wire spool before winding starts.
