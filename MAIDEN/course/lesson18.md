# Lesson 18 — Station Time Source [bench]

*Where we are.* Lesson 17 gave each station a radar that reports velocity
fifty times a second — but a measurement without a timestamp is gossip.
Recall the arithmetic from D3 that justifies SYS-006: at 30 m/s, a timing
error of one video frame (1/30 s) displaces the aircraft a full metre —
as large as the entire SYS-002 position budget. So every station carries
its own GPS-disciplined clock, speaks IRIG-B like the range community does,
and stamps every video frame and PCM minor frame against it. You built a
frequency *measurer* in the theremin course (lesson 10); today you build
its dual — a frequency *keeper* — plus the encoder that serializes time
itself.

## Objectives

- Understand PPS discipline: how a 1-pulse-per-second edge steers a local
  10 MHz counter, and what holdover means when GPS drops.
- Learn the IRIG-B DCLS frame format for real: pulse-width coding, position
  identifiers, BCD time-of-day, straight binary seconds.
- Build `firmware/timebase/`: `pps_discipline`, `irigb_gen`,
  `strobe_latch`, with SYS-006-tagged testbenches including jitter and
  holdover cases.
- Build the LED-flash rig that lesson 04's VT-02 procedure specified, and
  capture first end-to-end alignment evidence.

## Concepts

### The RTC and its discipline

Ch. 10 packet headers carry a free-running 10 MHz relative time counter
(RTC); the Ch 1 time packets map RTC → absolute time (lesson 04 built the
decoder side). The station's job is to make that mapping *stable*: a
10 MHz counter derived from the FPGA clock (12 MHz osc → PLL ×5 = 60 MHz →
÷6 = 10 MHz; the iCE40/ECP5 PLL primitive does the ×5), steered by the
u-blox PPS.

Discipline is simpler than it sounds. On each PPS rising edge, latch the
RTC and difference against the previous latch: you *expect* 10,000,000
counts. The error tells you your oscillator's fractional frequency offset
(a cheap crystal is ±20–50 ppm — 200–500 counts per second, thousands of
µs per hour if uncorrected). Two design options:

1. **Trim the counter** — a fractional-N accumulator occasionally adds or
   drops a count so RTC tracks true 10 MHz. Elegant, but now your RTC is
   non-monotonic in rate and every consumer must not care.
2. **Don't touch the counter; publish the mapping** — leave RTC
   free-running and let the *time packets* carry the truth: each Ch 1
   packet pairs an absolute second with its latched RTC value; ingest
   (lesson 04) interpolates. Drift becomes a slope, not an error.

MAIDEN takes option 2 — it is exactly what the Ch. 10 time-channel
mechanism was designed for, and it keeps the RTC dead simple. The
discipline block therefore *measures and reports* (offset ppm, PPS
present, lock state) rather than steers. Lock state feeds the recorder's
Ch 6 status channel and the deploy checklist's "LED shows PPS lock" step
in D9.

**Holdover:** GPS drops (foliage, cable, gremlin). Keep counting, keep
emitting IRIG-B from the last-known second + crystal rate, but drop the
lock flag and let the ingest widen its error model. D4's clap fallback is
the deep backstop; holdover is the graceful middle.

### IRIG-B on the wire

IRIG-B, DCLS flavor (DC level shift — the logic-level variant, no carrier):
**100 bits per second**, each bit cell 10 ms, one full frame per second.
Three symbols, distinguished by high-time within the cell:

```
  '0'  = 2 ms high, 8 ms low
  '1'  = 5 ms high, 5 ms low
  'P'  = 8 ms high, 2 ms low   (position identifier / reference)
```

Frame layout (bit index = cell number, 0–99; P0…P9 land on every 10th
cell; two consecutive 8 ms symbols — P_r then P0 — mark the on-time
second):

```
  0     P_r  reference marker        } back-to-back with previous
  1–8   seconds, BCD  (1,2,4,8 | 10,20,40)     units then tens
  9     P1
  10–17 minutes, BCD
  19    P2
  20–28 hours, BCD
  29    P3
  30–41 days-of-year, BCD (3 digits)
  49    P5 … (year, control functions in 50–78 — emit zeros, legal)
  79    P8
  80–97 straight binary seconds-of-day (17 bits, LSB first)
  99    P9  (followed by next frame's P_r)
```

BCD means each digit is sent as its own 1-2-4-8 group, units first —
seconds "37" is 7 then 3. Emit the frame from a 100-state cell counter
clocked by the RTC (10 ms = 100,000 RTC counts, no rounding — this is why
10 MHz is a nice number). The *on-time point* is the leading edge of P_r:
align it to the PPS-derived top of second.

You will notice the format wastes most of its bits by our standards. It is
1960s telemetry, it interoperates with every range instrument ever made,
and D3 chose interoperability on purpose. Respect your elders; emit the
frame.

### Stamping frames

The camera asserts a strobe GPIO per exposure. That edge is asynchronous:
2-FF synchronize it (theremin lesson 09, verbatim discipline), edge-detect,
and latch `(RTC, frame_count)` into a small FIFO the recorder drains into
Ch 5/Ch 2 metadata. Worst-case synchronizer latency is 2 clocks ≈ 167 ns at
12 MHz — five orders below the 5 ms SYS-006 budget. The same latch pattern
serves the radar's PCM minor-frame boundaries.

## Doc Trace

- **Implements:** D6 §IRIG-B time source; D4 §Time and synchronization
  (the station side of it; lesson 04 built the ingest side).
- **Toward:** SYS-006, verified end-to-end by VT-02 (this lesson builds
  the rig; the full four-source check completes once lesson 21's logger
  exists).
- **Feeds:** recorder Ch 1 time packets and Ch 6 status (lesson 19); D9's
  deploy-checklist PPS-lock step.
- **Risk:** D5 risk R3 (time sync across stations and airframe) — this
  lesson is its primary mitigation.

## Build

All in `firmware/timebase/`, house style, Makefile per the phase1 pattern.

### 1 · `pps_discipline.vhd`

```
entity pps_discipline is
  generic (RTC_HZ : positive := 10_000_000;
           LOCK_TOL : positive := 500);       -- counts (=50 ppm) to call lock
  port (clk, rst : in std_logic;              -- clk = 10 MHz RTC domain
        pps_in   : in  std_logic;             -- async from u-blox
        rtc      : out unsigned(47 downto 0); -- free-running, Ch. 10 width
        pps_rtc  : out unsigned(47 downto 0); -- RTC latched at last PPS
        pps_stb  : out std_logic;
        offset   : out signed(19 downto 0);   -- counts vs RTC_HZ, per second
        locked   : out std_logic);
end entity;
```

2-FF sync + rising-edge detect on `pps_in`; free-running 48-bit RTC
(Ch. 10 header width — lesson 19 consumes it directly); per-PPS interval
measurement; `locked` = last 3 intervals within ±LOCK_TOL. Holdover:
missing PPS (interval watchdog > 1.5 s) clears `locked`, everything else
carries on.

### 2 · `irigb_gen.vhd`

```
entity irigb_gen is
  port (clk, rst : in std_logic;
        rtc      : in unsigned(47 downto 0);
        pps_stb  : in std_logic;
        tod_set  : in std_logic;              -- load TOD from NMEA (via SBC)
        tod_secs : in unsigned(16 downto 0);  -- seconds-of-day
        tod_day  : in unsigned(8 downto 0);   -- day-of-year
        irigb    : out std_logic;
        frame_stb: out std_logic);            -- at each P_r edge
end entity;
```

Internal: TOD counter (increments at top of second, aligned to pps_stb
when locked, RTC-derived in holdover); 100-cell frame sequencer; a
function building the 100-symbol vector from TOD (BCD encode + SBS);
pulse-width shaper off the RTC. The SBC feeds `tod_set` once at startup
from NMEA — GPS gives the *second label*, PPS gives the *edge*.

### 3 · `strobe_latch.vhd`

Camera strobe in (async) → 2-FF sync → edge → push `(rtc, seq)` into a
16-deep FIFO; simple read port for the recorder link. Overflow sets a
sticky error bit surfaced on Ch 6 — dropped stamps must be loud, not
silent.

### 4 · `timebase_tb.vhd`

Simulated GPS: a PPS process with programmable period error and jitter
(use a generic, not `now`-based randomness — determinism for CI). Cases,
each with SYS-006-tagged asserts:

- Nominal: PPS at exactly 1 s → `locked` within 3 s; IRIG-B frame decodes
  (write a tiny procedure that decodes your own waveform — encoder and
  decoder written by the same hand find each other's bugs) to the loaded
  TOD; P_r edge within 1 RTC count of PPS edge.
- Crystal offset +30 ppm: `offset` reports ≈ +300; still locked at
  LOCK_TOL 500; frame cadence follows PPS, not the crystal.
- Holdover: kill PPS for 10 s → `locked` drops, TOD keeps counting, frames
  keep coming; PPS returns → relock without a TOD discontinuity assert.
- Strobe: 30 Hz strobe with jitter → FIFO stamps monotonic, count matches
  strobes, no overflow; 17-strobe burst → sticky overflow bit sets.

### 5 · The VT-02 rig (`hardware/vt02-rig/`)

A u-blox PPS output driving (a) a bright LED through a MOSFET — one 100 ms
flash at each top of second, visible to all three cameras — and (b) a
header pin you can also route into a spare FPGA input or, on validation
days, tap against the airborne IMU (a small solenoid clicker on the same
edge gives the IMU an accelerometer spike; build the clicker, mark its
mechanical delay *tune-on-bench* and measure it with a scope + microphone
before trusting it). Commit schematic and photos.

## Verify

1. **Sim.** `make sim`: all four TB cases green, SYS-006-tagged. This is
   the only place you can *prove* holdover behavior on demand.
2. **Scope the frame** — **observe on bench**: IRIG-B pin vs PPS pin on two
   channels. Confirm the 2/5/8 ms symbol widths, the double-8 ms frame
   mark, and P_r's leading edge landing on the PPS edge (expect well under
   1 µs; record what you see). If a lab IRIG-B reference or a commercial
   decoder is available, cross-check one frame by hand against the bit
   layout above.
3. **Two boards, one sky** — **observe on bench**: two FPGA boards, two
   GPS modules, scope both IRIG-B outputs. P_r edges from independent
   receivers should agree within ~±1 µs class numbers (u-blox PPS spec +
   your synchronizer). This is the station-to-station half of SYS-006 with
   ~three orders of margin on the 5 ms budget.
4. **VT-02, first pass** — **observe on bench**: LED rig in view of one
   camera + lesson 09's capture path; compare the flash's stamped frame
   time against the PPS second. |Δt| ≤ 5 ms is the D7 criterion; a 30 fps
   camera quantizes to ±16.7 ms per frame, so the *stamp* must come from
   the strobe latch, not the frame index — if your first try fails, that
   is almost certainly why. Log captures to `results/VT-02/`. The full
   four-source VT-02 (three cameras + airborne IMU) completes after
   lessons 20–21; leave the rig assembled.

## Explore

1. **Deliberate mislabel.** Load `tod_secs` one second off, PPS perfect.
   Everything locks; every timestamp is wrong by exactly 1 s. What
   downstream check catches it? (Lesson 04's decoder sees nothing amiss;
   the clap/LED event check is the answer — write the failure story in
   `docs/notes/` and make sure D9's procedure keeps the clap.)
2. **Holdover budget.** With your measured crystal ppm, how long can a
   station hold over before its share of the 5 ms budget is gone? Should
   `locked` have a third state — "degraded" — and should D4's sync section
   say so? If yes, that's a D4 revision; make it.
3. **Chase the PLL.** Reprogram the PLL for a 9.999990 MHz RTC (simulated
   via generic). Which testbench case catches it, and what does the Ch 1
   time-packet mapping do with the slope? Confirms option-2 discipline
   really is drift-tolerant.
4. **TCXO upgrade.** Price a 10 MHz TCXO (±2 ppm) as the FPGA clock
   source. Given Explore 2's answer, is it worth $8 per station? Add your
   verdict to the D6 parts table either way.

## Checkpoint

- `make sim` green in `firmware/timebase/` with SYS-006-tagged asserts
  covering nominal, offset, holdover, and strobe cases.
- IRIG-B waveform verified on the scope: symbol widths, frame mark, P_r
  aligned to PPS (**observe on bench**, capture committed).
- Two-board PPS agreement measured and logged (**observe on bench**).
- VT-02 LED rig built and committed; single-camera first-pass alignment
  evidence in `results/VT-02/`.
- You can state from memory why the RTC is free-running, where the
  RTC→UTC truth actually lives, and what happens to timestamps during
  holdover.
