# VT-02 — End-to-End Time Alignment: Controlling Procedure

Verifies SYS-006 (all stations and the airborne logger on one IRIG-B
timebase, end-to-end alignment ≤ 5 ms). Method per D7's VT-02 row.
Executed twice: bench (maiden39) and field (maiden60). This document is
the controlling procedure for both runs; deviations are logged in the
result sheet, not silently absorbed.

## Stimulus

- A high-brightness LED driven **directly** by a GPS-PPS edge (buffered,
  no software in the path: PPS → gate driver → LED; propagation < 1 µs).
- The LED is positioned in view of **all three station cameras** (bench:
  one meter out, centered; field: on the flight line where every lens can
  see it before the session).
- The **same PPS edge** is logged on the airborne IMU path: the PPS line
  taps a logger interrupt/AUX pin (preferred), or the LED assembly is
  tapped against the airframe so the pulse lands as a mechanical impulse
  in the IMU stream (fallback; note which was used).

Fire at least **10 pulses** (10 consecutive PPS seconds) with all four
recorders running.

## The four time sources

| # | Source | Stamped time comes from |
|---|--------|--------------------------|
| 1 | Station A video (Ch 2) | frame IPTS latched by the FPGA strobe against IRIG-B/RTC |
| 2 | Station B video (Ch 2) | same |
| 3 | Station C video (Ch 2) | same |
| 4 | Airborne logger (converted Ch. 10) | GPS-disciplined logger timestamps |

## Extraction

- **Video onset:** for each pulse, the LED-onset time is the stamped time
  of the **first frame whose LED pixel block crosses half its saturated
  brightness**, minus **half a frame interval** (16.7 ms at 30 fps) —
  onset happened somewhere in the preceding interval, so the midpoint is
  the estimate and **±half a frame interval is the stated uncertainty**.
  Extract the pixel block from a short ROI marked at setup time.
- **IMU / interrupt:** the logged timestamp of the interrupt edge (or the
  leading edge of the mechanical impulse above 3σ of quiescent noise),
  resolved to UTC by the converter's time channel.
- All station times are resolved RTC→UTC via `maiden.timebase.TimeDecoder`
  over the session's Ch 1 packets (`healthy()` must be True, else the run
  is invalid — fix sync before testing it).

## Pass criterion

For each pulse, compute Δt of every source against the PPS true second
(known absolutely: pulses occur *at* UTC integer seconds).

**PASS: |Δt| ≤ 5 ms for all four sources, on every pulse.**

Report the per-source mean and worst-case Δt. A single excursion fails
the run — find the cause; do not average it away.

## Evidence committed under `results/VT-02/`

Per run (`bench/` and `field/` subdirectories):

- `result-sheet.md` — date, hardware serials, per-pulse Δt table,
  per-source mean/worst, PASS/FAIL, deviations.
- `deltas.csv` — pulse × source Δt matrix (raw numbers).
- `deltas.png` — Δt vs pulse index, one trace per source, ±5 ms lines.
- One annotated frame crop per camera showing the LED ROI at onset.
- The raw `.ch10` session files stay in `data/` per D5 CM; the sheet
  names the session directory.

## Timing budget (Explore 1)

Where the 5 ms goes — estimates to be confirmed on the bench:

| Term | Estimate | Notes |
|------|---------:|-------|
| GPS PPS accuracy | < 0.001 ms | u-blox spec, sky view assumed |
| LED drive path | < 0.001 ms | hardware gate, no software |
| FPGA strobe latch granularity | 0.0001 ms | 10 MHz RTC = 100 ns |
| TimeDecoder fit residual | < 0.1 ms | healthy() enforces drift/gap limits |
| **Camera exposure midpoint vs strobe** | **up to ±16.7 ms raw → ±half-interval stated** | dominates; the extraction rule subtracts the half-interval so the *estimate* error is bounded by exposure-time effects, order 1–3 ms |
| IMU sample quantization (100 Hz) | ±5 ms raw → edge-interp ~1 ms | interrupt-pin path avoids this |

**Dominant term: the camera frame interval — optics, not electronics.**
That is why the criterion is 5 ms and not 50 µs: 5 ms × 30 m/s = 0.15 m,
matched to the triangulation noise floor (D3), and achievable once the
half-frame correction is applied. If the bench run shows the video terms
blowing the budget, the fix is exposure shortening, not a faster clock.

## Degraded sync (Explore 2)

The D4 fallback — a hand clap visible in all three videos and the IMU —
aligns sources only to video-frame quantization: onset is smeared over a
33 ms frame interval, so cross-source alignment error is of order
**±17 ms**, more than 3× the SYS-006 budget. At 30 m/s that is ±0.5 m of
along-track ambiguity: too coarse to *verify* SYS-006, still far better
than nothing for scoring geometry. That is why clap-aligned sessions are
**flagged degraded, widened in the report's confidence bands, and kept**
(D4 §Time; D9's "degraded sync" troubleshooting row) rather than
rejected. VT-02 itself must never run on a clap-aligned session.
