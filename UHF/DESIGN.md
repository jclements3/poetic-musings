# UHF — Phase 9 design (GPS-disciplined CW + WSPR beacon)

Phase 9 of PLAN.md: a GPS-disciplined CW + WSPR beacon in the PM box. Ham radio,
**personal ledger** (U is the one MUSING-group spoke on the P ledger — see
fpga-development-plan.md; the ledger is bookkeeping only, PROGRAM.md). Prereq: G (the disciplined clock — see
GPS/DESIGN.md; everything here consumes its outputs loosely: the PPS-locked 10 MHz
station copy — GPS/DESIGN.md names the WSPR beacon as a customer — and UTC
time-of-day via the iIrig/GPS time registers). Gate: **a spot appears on wsprnet.org**
— transmit, then show the grandkids their signal was heard hundreds of miles away.

**Spoke framing (PROGRAM.md):** U adds one piece of hardware to the Panel+Oracle root
— the whip on its SMA bulkhead plus the PA can at the rear-right — and owns the
library's radio set: `PM.Keyer` (CW keyer + Morse decoder, ✓, currently housed in
`Oracle/pm-keyer`), the planned Goertzel tone detector and WSPR modulator, and the
hardware TX interlock in `PM.RegFile` (✓). Those blocks *run* in the box's C mode
(the RF mode, below) but they are U's components; Oracle is the runtime, not their
owner. Shared with S: the antenna end-plate hardware and the disciplined 10 MHz from G.

## Band choice — honest note on the name

"UHF" earned its letter from the MUSING mnemonic, not from an RF plan. For the gate as
written, UHF is the wrong place to start:

- WSPR's monitoring network lives on HF. 20 m and 30 m have thousands of reporting
  receivers worldwide; 70 cm has effectively none. No monitors, no spot, no gate.
- WSPR tone spacing is 1.4648 Hz. At 432 MHz that demands ~3 ppb stability through a
  110.6 s transmission — GPS discipline helps, but the PA chain and every multiplier
  stage must hold it too.
- "Heard hundreds of miles away" is ionospheric propagation — an HF phenomenon at
  these power levels.

**Decision: the first on-air TX is HF WSPR — 20 m (TX ≈ 14.0971 MHz) primary, 30 m
(≈ 10.1402 MHz) as the day/night alternative.** The letter keeps its name; the ladder
up is 6 m → 2 m WSPR (SI5351-class synth territory), and a true 70 cm CW beacon is the
stretch goal that eventually redeems the U. State this plainly in the demo patter —
"the UHF project starts at HF because that's where the listeners are" is itself a
propagation lesson.

## WSPR in one paragraph

Type-1 message = callsign + 4-char grid + power (dBm) packed into 50 bits →
K=32 r=1/2 convolutional encode (162 bits) → bit-reverse interleave → merged with the
162-bit pseudo-random sync vector → **162 symbols of 4-FSK** (bit 0 = sync, bit 1 =
data). Symbol rate 12000/8192 ≈ 1.4648 baud, tone spacing equal to it (total occupied
bandwidth ~6 Hz), duration 162 × 0.6827 s ≈ 110.6 s, starting 1 s after an even UTC
minute. Decoders tolerate ±1.5 Hz drift; a free-running ±30 ppm crystal is ±420 Hz at
14 MHz — this is *why* G is the prerequisite.

## Encode path — Forth on Oracle (decided here)

The encoder runs **in Forth on the H2**, not in gateware:

- It runs once per transmission (or once per grid change), seconds of latency are
  irrelevant — eforth-pm.md's rule of thumb ("if a human notices the latency, it is
  Forth") puts it squarely on the CPU.
- It is bit-twiddling on 50 bits: base-37 callsign packing, the K=32 shift-register
  convolution, an interleave permutation. Small integer work, ideal Forth lesson.
- The 162 2-bit symbols land in a buffer the gateware sequencer reads; the finished
  symbol table is also `spot`-logged to an SD block, so a **precomputed symbol block
  on the demo card is the fallback** if the encoder word set isn't done yet.

Gateware gets only the real-time part: a 162-entry symbol sequencer with GPS-derived
symbol timing driving the NCO tone select. `BEACON` vocabulary (SD-loaded, per
eforth-pm.md conventions): `call! grid! dbm!` set the message · `wspr-enc ( -- )`
build the symbol table · `wspr-tx ( -- )` arm and schedule the next even minute ·
`beacon ( -- )` repeat every N minutes · `wspr-log ( -- )` `spot` the transmission.

## Symbol timing from the disciplined clock

- Symbol tick: fractional divider on the disciplined 10 MHz — an accumulator adds
  12000 every 10 MHz tick and strobes a symbol on each 81 920 000 000 overflow
  (= 8192/12000 s exactly on average; jitter is one 10 MHz tick, irrelevant against
  683 ms symbols).
- Start trigger: Forth polls iIrig time-of-day (0x4034 block); at even-minute:00 it
  writes the go bit; gateware launches on the next PPS edge + 1 s so the ±ms of Forth
  polling never reaches the air.
- Tone synthesis: 32-bit NCO clocked at the DDS clock (≥100 MHz from the ECP5 PLL,
  itself disciplined); resolution «0.03 Hz, far inside the 1.4648 Hz spacing. Base
  phase-increment plus symbol × spacing comes from a 4-entry table loaded by Forth.

## TX chain

**Decision: FPGA-direct synthesis for HF** — NCO MSB out a pin, no external
synthesizer for the first TX:

- The disciplined clock is already inside the FPGA; an SI5351 would need CLKIN
  plumbing to inherit it. Zero extra BOM, and DDS-on-fabric is the lesson.
- Phase-truncation spurs and harmonics of the square output are handled by the
  band LPF; WSPR's 6 Hz occupied bandwidth is trivial for close-in cleanliness.
- The SI5351C-class part (clocked from the disciplined 10 MHz) is the named step-up
  for 6 m/2 m and the 70 cm stretch, where fabric ODDR runs out.

Chain: NCO pin (3.3 V square) → keying/envelope gate (CW shaping ~5 ms raised-cosine
via PWM on the driver enable; WSPR is constant-envelope, no shaping needed) →
**PA: paralleled 74ACT244 buffer or single BS170 class-E at 5 V → ~200 mW (23 dBm)**
→ 7-element Chebyshev LPF for the band (plug-in filter footprint, one per band) →
TX SMA. 200 mW is the canonical WSPR power and crosses continents on 20/30 m.
Full-carrier duty for 110.6 s: heatsink the PA to the shielded can. Power: the PA
branch has **its own polyfuse** per the LAYOUT power table; the whole chain lives
inside the 5 V / 4 A budget.

## Hardware TX interlock (per Oracle/eforth-pm.md)

0x4032 oTxGate: Forth writes the arm key `0x0C1D` to arm; anything else disarms.
Gateware **ANDs `armed` with `iPanel S3 zone == C`** — software alone can never key
RF outside C mode; iTxGate reads back armed + PA fuse-branch OK.

Conflict found and resolved here: the LAYOUT modes table lists "UHF beacon" under the
O-mode demo scripts, but the interlock hardware only passes RF in C mode. **The beacon
transmits in C mode** — C is the box's RF mode (keyer, decoder, TX). O-mode scripts
may encode, schedule, and display, but `wspr-tx` refuses (and the hardware would block
it anyway) until S3 sits in C. The "(or U-mode flag later)" escape in eforth-pm.md is
not taken. A mode-slider bump mid-transmission disarms within one zone-scan — safe by
construction, and the 1 s dwell means it takes a deliberate bump.

## Antennas and panel (per LAYOUT.html)

TX SMA is the 50 Ω bulkhead on the **right end panel** (LAYOUT end views; the rear
panel's RF block just points there), with the PA in the shielded can at the adjacent
rear corner — shortest possible SMA lead. The hand-thread whip that lives on that SMA
is a 2 m/70 cm-scale radiator: fine for the eventual VHF/UHF steps, **useless at
14 MHz**. For the HF gate the same SMA feeds an external wire — EFHW or random wire
with a small L-match/49:1 in a lid-pocket pouch. The theremin antennas are *not* the
TX antenna (they belong to T/S via the relay and are neither resonant nor isolated
from the receive front end).

## Licensing note

JC holds an amateur license; all transmissions are under his callsign, which is the
WSPR payload itself (plus a CW ID word in the `BEACON` vocabulary for good practice).
Demo transmissions are attended, control operator present — the Part 97 automated-
beacon restrictions (§97.203, which limits unattended beacons to specific segments)
do not bite an attended demo, but check them again before any leave-it-running
scheduling. Power ≤ 200 mW is far under any limit; keep the log (`wspr-log`) as the
station record.

## Verification and the gate

1. Simulation: symbol sequencer against a golden WSPR symbol table (WSJT-X `wsprd`
   ships reference vectors); timing testbench asserts 683 ms symbols and even-minute
   start vs a modeled PPS.
2. Bench: dummy load, SDR or the S-mode receiver watching 14.0971 MHz — WSJT-X on a
   laptop must decode the off-air signal locally first.
3. **Gate: antenna up, one even-minute cycle, callsign + grid on wsprnet.org's map.**
   Screenshot goes in this directory; distance of the farthest spot goes in the demo
   patter.

## Explicitly out of scope for Phase 9

6 m/2 m/70 cm hardware (SI5351 step-up, multipliers), any receive path (that is S,
Phase 10 — though S receiving U's own signal is the natural joint demo), QSO modes,
unattended scheduled beaconing, and antennas beyond the wire-plus-tuner pouch.
