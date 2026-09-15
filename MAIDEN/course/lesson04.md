# Lesson 04 — Time [desk]

*Where we are.* You can read and write raw Chapter 10 packets (lesson 02)
and describe a station in TMATS (lesson 03). But a packet's header carries
only a **relative time counter** — a free-running 10 MHz count with no idea
what day it is. Before any sample from any source can be compared to any
other, every RTC value must resolve to one shared absolute timebase. This
lesson builds that resolution: the physics of why MAIDEN cares so much, the
IRIG-B/PPS machinery that creates the timebase, and `maiden/timebase.py`,
which turns Ch 1 time packets into an RTC→UTC function with drift and gap
awareness. Everything downstream — ingest, fusion, validation — calls it.

## Objectives

- State, with numbers, why a 1/30 s timing error is as bad as consumer GPS.
- Read an IRIG-B frame description and explain PPS discipline in one
  sentence each.
- Explain how Ch. 10 Time F1 packets bind the RTC to absolute time.
- Build `TimeDecoder`: linear RTC→UTC mapping, drift estimate in ppm, and
  gap detection, with pytest coverage including a dropped packet.
- Write the VT-02 end-to-end alignment procedure as a committed document.

## Concepts

### Why timing is a first-class requirement

D3 makes the argument in one line: *a timing error of 1/30 s at 30 m/s is
1 m — the same as GPS.* Unpack it: the aircraft crosses the pattern box at
up to ~30 m/s. If Station B's clock is one video frame (33 ms) off from
Station A's, then when the fusion EKF intersects their rays it is
intersecting rays to two *different* aircraft positions a metre apart. The
entire σ_range ≈ 0.15 m advantage the triangulation geometry buys (D3,
Figure 2) is destroyed by one frame of skew. That is why SYS-006 demands
≤ 5 ms end-to-end: at 30 m/s, 5 ms is 0.15 m — matched to the geometry's
noise floor, not an order of magnitude above it.

### The timebase chain

```
GPS constellation ──> u-blox receiver ──> PPS (1 pulse/s, <100 ns to UTC)
                                            │
                                            v
                            FPGA: disciplines a 10 MHz RTC counter
                                  and generates IRIG-B
                                            │
              ┌─────────────────────────────┼──────────────────────┐
              v                             v                      v
      camera frame strobe            Ch. 10 packet             Ch 1 Time F1
      latched against RTC            headers carry RTC         packets: RTC + BCD
                                                               day/h/m/s, 1 Hz
```

**PPS discipline.** The receiver's pulse-per-second edge is aligned to UTC
to well under a microsecond; the FPGA counts its local 10 MHz oscillator
between edges and learns exactly how fast that oscillator really runs.

**IRIG-B** is the range-standard serial time code: one frame per second,
100 bit-cells of 10 ms each, carrying BCD time-of-day (seconds, minutes,
hours, day-of-year) plus control bits. MAIDEN uses the unmodulated DCLS
(DC level shift) form — a logic-level waveform an FPGA pin can drive and
another can decode. Lesson 18 builds the generator; today you only need
to know what the code *carries*, because the Ch 1 packets replicate it.

**The Ch. 10 time channel.** Every packet header carries a 48-bit RTC in
100 ns units. Once per second the recorder emits a Time F1 packet on Ch 1
whose payload is the absolute time (BCD day/h/m/s, from IRIG-B) and whose
header RTC was latched at that second boundary. Each time packet is
therefore one (rtc, utc) correspondence point. Between points, the RTC
advances at *nominally* 10 MHz — really 10 MHz × (1 + ε) where ε is the
local oscillator error, order 10⁻⁵ for a garden-variety crystal and far
better once PPS-disciplined. Resolving any packet's RTC to UTC is a
straight line fit through the correspondence points.

**Degraded sync.** If PPS is lost (antenna kicked, cold start), the RTC
keeps free-running and time packets keep coming, but their absolute times
may be stale or drifting. D4 defines the fallback: a hand clap in front of
Station A — an impulse visible in all three videos and, on validation
flights, in the airborne IMU — provides one manual cross-source alignment
event, and the session is flagged degraded. Your decoder must *detect* the
conditions that trigger the fallback (gaps, non-physical drift); applying
it happens in ingest.

## Doc Trace

- **Implements:** the ground-software half of SYS-006 (the requirement
  itself is D2's; the ≤ 5 ms budget spans hardware you build in lesson 18).
- **Governed by:** D4 §Time and synchronization (the chain above is its
  prose, drawn), D4 IF-1 (Ch 1 packet definition).
- **Verified by:** VT-02 — this lesson writes its procedure; lesson 18
  executes the bench half, lesson 99 the field half.
- **Feeds:** `maiden.ingest` (lesson 08) calls `TimeDecoder` for every
  packet; `maiden.validate` (lesson 14) step 1 is "time-align on the
  common IRIG-B base".

## Build

### `software/maiden/timebase.py`

Complete file — this one is short and crisp enough to give whole:

```python
"""RTC -> UTC resolution from Ch. 10 time packets. See D4 §Time; SYS-006."""
from dataclasses import dataclass, field
import numpy as np

RTC_HZ = 10_000_000.0          # 100 ns ticks, per RCC 106 Ch. 10
NOMINAL = 1.0 / RTC_HZ

@dataclass
class TimePoint:
    rtc: int                   # 48-bit counter value from packet header
    utc: float                 # seconds since epoch, decoded from payload

@dataclass
class TimeDecoder:
    points: list = field(default_factory=list)
    max_gap_s: float = 2.5     # >2 missing 1 Hz packets = gap
    max_drift_ppm: float = 50.0

    def add(self, p: TimePoint) -> None:
        self.points.append(p)

    def fit(self) -> None:
        """Least-squares line utc = a*rtc + b over all points."""
        r = np.array([p.rtc for p in self.points], dtype=np.float64)
        u = np.array([p.utc for p in self.points], dtype=np.float64)
        if len(r) < 2:
            raise ValueError("need >= 2 time packets to fit")
        # Fit about (r[0], u[0]): un-demeaned polyfit on epoch-scale UTC
        # (~1.8e9 s) loses the microsecond budget to float64 conditioning.
        self._a, self._b = np.polyfit(r - r[0], u - u[0], 1)
        self._r0, self._u0 = r[0], u[0]

    def to_utc(self, rtc: int) -> float:
        return self._a * (rtc - self._r0) + self._b + self._u0

    @property
    def drift_ppm(self) -> float:
        """How far the RTC runs from nominal 10 MHz, in parts per million."""
        return (self._a / NOMINAL - 1.0) * 1e6

    def gaps(self) -> list[tuple[float, float]]:
        """UTC intervals where 1 Hz time packets went missing."""
        u = sorted(p.utc for p in self.points)
        du = np.diff(u)
        return [(u[i], u[i + 1]) for i in np.flatnonzero(du > self.max_gap_s)]

    def healthy(self) -> bool:
        return abs(self.drift_ppm) <= self.max_drift_ppm and not self.gaps()
```

Wire it to lesson 02's reader: add a small function (yours to write) that
walks a `.ch10` file, decodes every Ch 1 payload's BCD fields to seconds
since midnight UTC of the day-of-year, and returns a fitted `TimeDecoder`.
Watch the two classic traps: BCD is not binary (0x23 seconds is 23, not
35), and a session crossing midnight makes raw seconds-of-day jump
backwards — unwrap by adding 86 400 when a later packet's time is smaller.

### `results/VT-02/PROCEDURE.md`

Write the VT-02 procedure now, while the design is fresh; you will execute
it twice (bench, then field). It must specify, per D7's row for VT-02: an
LED driven directly by a GPS-PPS edge, positioned in view of all three
cameras; the same PPS edge logged on the airborne IMU (tap or interrupt
line); how you extract the stamped time of the LED onset from each video
(first frame where the LED pixel block crosses half brightness, minus half
a frame interval as the uncertainty statement) and from the IMU stream;
the pass criterion |Δt| ≤ 5 ms across all four sources; and what gets
committed as evidence.

## Verify

Write `software/tests/test_timebase.py`:

- **Exact recovery.** Generate synthetic points `utc = t0 + k`,
  `rtc = r0 + k*10_000_000` for k = 0…299; assert `to_utc` inverts a
  mid-span RTC to within 1 µs and `drift_ppm` ≈ 0.
- **Drift.** Regenerate with the RTC running at 10 MHz × (1 + 20 × 10⁻⁶);
  assert `drift_ppm` ≈ 20 within 0.1, and that `to_utc` at the far end of
  a 300 s span stays within 100 µs (a naive single-point offset would be
  6 ms off — put that comparison in the test as a comment or assertion so
  the *reason* for the fit is executable).
- **Gap.** Delete points 100–109; assert `gaps()` reports one interval
  covering them and `healthy()` is False.
- **BCD + midnight.** Feed your file-walking decoder a hand-built packet
  stream that crosses 23:59:59 → 00:00:00; assert monotonic UTC out.

`pytest software/tests/test_timebase.py` must pass. There is no captured
output to match — the assertions are the evidence, same as a
requirement-tagged testbench.

## Explore

1. **Budget the 5 ms.** SYS-006's budget spans PPS accuracy, FPGA latch
   granularity, camera exposure midpoint vs strobe, and your fit residual.
   Write the budget as a table with your estimates. Which term dominates?
   (Hint: it is not the electronics.)
2. **Clap accuracy.** A clap is ~5 ms of audio but the *video* onset is
   quantized to a 33 ms frame. Estimate the alignment error of the
   fallback and reconcile it with D4's statement that clap-aligned
   sessions are flagged degraded rather than rejected.
3. **Break the fit.** Feed one corrupted time packet (UTC off by an hour)
   into a 300-point stream. How badly does the least-squares line bend?
   Add an outlier rejection pass (fit, drop residuals > 3σ, refit) and a
   test proving it.

## Checkpoint

- `pytest software/tests/test_timebase.py` passes, covering exact
  recovery, drift, gap, and midnight-rollover cases.
- `TimeDecoder.drift_ppm` and `gaps()` behave per the tests above.
- `results/VT-02/PROCEDURE.md` exists, names all four time sources, states
  the ≤ 5 ms criterion, and is committed.
- You can say from memory why 5 ms and not 50 ms is the SYS-006 number.
