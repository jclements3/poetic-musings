# Lesson 07 — Digital Twin II: Sensors & Files [desk]

*Where we are.* Lesson 06 gave you truth: a Sportsman sequence as 100 Hz
arrays with maneuver Events. But the pipeline you are building never gets
truth — it gets what three stations *saw*. This lesson closes the twin:
project the truth through each station's pose into az/el angles and
radial velocities, corrupt them the way real sensors will, and write the
result as genuine `.ch10` files with genuine TMATS — indistinguishable in
format from what the real stations will record in December. From this
lesson on, every software lesson has data; that is the SEMP's twin-first
strategy paying out.

## Objectives

- Project truth through station Poses into per-station az/el and v_r.
- Inject calibrated noise (σ_θ ≈ 0.5 mrad, Doppler noise), dropouts, and
  a sun-crossing outage window.
- Write STATION_A/B/C and TRUTH `.ch10` files per the IF-1 channel map,
  plus `truth.npz`, behind the pinned `maiden twin` CLI.
- Verify the D3 triangulation error formula (σ_range ≈ R²·σ_θ/B) against
  a Monte-Carlo triangulation of your own twin output.
- State exactly which channels the twin does *not* synthesize, and why.

## Concepts

### From truth to measurement

Each station is a `Pose` (lesson 01): position in the field frame, survey
heading, boresight elevation. For a truth point **p** and station at
**s**, the line-of-sight vector is **d** = **p** − **s**, rotated into
the station frame by the heading. Then:

```
az = atan2(d_east_sta, d_north_sta)      el = atan2(d_up, |d_horizontal|)
v_r = v · û        where û = d / |d|     (positive = receding)
```

That `v_r` line is worth staring at: it is the same projection your
theremin's Doppler chain measured — the CW radar sees only the component
of velocity along the beam. Three stations see three different
projections, and lesson 13 will show that three projections of one
velocity vector are enough to recover all of it. The twin encodes the
*forward* model; the EKF is that model run backwards.

### Noise you can defend

Every injected error must have a stated source, or twin results mean
nothing (VT-17's pass criterion is literally "residuals consistent with
injected noise"):

- **Angles:** Gaussian, σ_θ = 0.5 mrad — D3's assumed tracker accuracy,
  which lesson 09 will justify as ~0.5 px through a 60° lens at 1080p.
  Add a per-frame confidence in [0.5, 1.0] correlated with an SNR proxy.
- **Radial velocity:** Gaussian, σ = 0.15 m/s at 50 Hz — half the VT-04
  bench criterion, revisit after lesson 17 measures the real chain.
- **Dropouts:** per-station Bernoulli gaps plus one scripted multi-second
  outage on Station B during the sequence ("sun crossing" per D6) — the
  case that makes Station C earn its keep in fusion.
- **Rates:** tracker messages at 30 Hz (per video frame), v_r at 50 Hz,
  deliberately *not* aligned to each other or to 100 Hz truth — the EKF
  must handle asynchronous measurements from day one, so the twin must
  refuse to make time convenient.

### What the twin honestly is not

The twin writes tracker *outputs* (Ch 5 messages) and radar *velocity
outputs* (Ch 4 PCM). It does not synthesize Ch 2 video or Ch 3 raw IF —
so it exercises everything **downstream of** the tracker and Doppler DSP,
and nothing inside them. That honesty has teeth: lessons 10–11 need
rendered frames to test the tracker, and the twin grows a simple frame
renderer *there*, not here; lesson 17 tests the DSP against recorded and
synthesized IF on the bench. Write this limitation into the module
docstring. A twin that quietly claims to validate the tracker would be
the most expensive lie in the project.

## Doc Trace

- **Implements:** SW-004 in full (with lesson 06).
- **Governed by:** D6 §Digital twin; channel map and payloads per D4
  IF-1; station geometry per D1 §Operating site and D3 Figure 2.
- **Verified by:** VT-17 — after this lesson you can run its
  demonstration end-to-end once lesson 08's ingest lands.
- **Closes:** nothing in D2, but the Monte-Carlo check below is your
  first quantitative evidence toward the SYS-002 error budget.

## Build

### `software/maiden/twin/sensors.py`  *(skeleton)*

```python
"""Forward sensor models: truth -> per-station measurements. SW-004."""
import numpy as np
from maiden.geo import Pose

SIGMA_THETA_RAD = 0.5e-3      # D3 assumption; revisit after lesson 09
SIGMA_VR = 0.15               # m/s; revisit after lesson 17
TRACKER_HZ, RADAR_HZ = 30.0, 50.0

def observe(truth, pose: Pose, *, rng, dropout_p=0.01,
            outage: tuple[float, float] | None = None):
    """Yield (t, az_deg, el_deg, conf) at TRACKER_HZ and (t, v_r, snr)
    at RADAR_HZ, noisy, with gaps. Angles in the station frame."""
    ...
```

### `software/maiden/twin/writer.py`  *(skeleton)*

Marries lesson 02's packet writer and lesson 03's TMATS generator:
one file per station (TMATS first, then Ch 1 time packets at 1 Hz, Ch 4
PCM and Ch 5 messages interleaved by RTC, Ch 6 status at 1 Hz with PPS
lock always true — the twin's stations are ideal recorders), plus a TRUTH
file with GPS/IMU-shaped PCM channels from the truth arrays. Synthesize
the RTC per file with a small per-station drift (tens of ppm) so lesson
04's decoder has something real to do — three stations sharing one
perfect clock would hide bugs the field will find for you.

### The CLI (pinned interface)

```
maiden twin --out DIR [--seed N] [--imperfect]
```

writes `STATION_A_*.ch10`, `STATION_B_*.ch10`, `STATION_C_*.ch10`,
`TRUTH_*.ch10`, and `truth.npz` (the lesson-06 arrays + events, for
consumers that want truth without ingesting). `--imperfect` applies a
seeded random `Imperfections` draw. Wire it as a `maiden` console-script
subcommand now; `validate`, `run`, and friends will join it.

Station poses for the default layout come from `config/field/rcrc.yaml`
(lesson 01): A at the origin looking into the box, B 75 m along the
flight line, C at the threshold — D3 Figure 2's geometry.

## Verify

- **Format truth.** Open each generated file with PyChapter10 (not your
  own writer's inverse — an independent implementation): all expected
  channels present, TMATS parses, time packets decode. This is a
  twin-scale rehearsal of VT-01.
- **Forward-model spot check.** pytest: place a synthetic target dead on
  Station A's boresight at known range moving straight away at 10 m/s;
  assert az≈0, el≈boresight, v_r≈+10 with zero noise injected.
- **The D3 formula, empirically.** New test/notebook: take noisy az/el
  from A and B (no dropouts), triangulate each frame pair by
  least-squares ray intersection, and compare position scatter against
  σ_range ≈ R²·σ_θ/B. At R = 150 m, σ_θ = 0.5 mrad, B = 75 m the formula
  says ≈ 0.15 m in the range direction; your Monte-Carlo should land
  within a factor of ~1.5 (the formula is a small-angle scalar sketch of
  a 3D problem — understand, and comment, why it is not exact). Assert
  the cross-range scatter is markedly smaller. This one test is the
  geometry argument of D3 Figure 2 made executable, and it is the number
  that says SYS-002's 1.0 m budget has margin.
- **Determinism.** Same `--seed` twice → byte-identical `truth.npz` and
  identical measurement streams (file bytes may differ only if you put
  wall-clock times in TMATS — don't; date it from the truth epoch).

## Explore

1. **Baseline sweep.** Regenerate with B moved to 25 m and re-run the
   Monte-Carlo. D3 predicts 0.45 m. Does the scaling law hold? Plot
   σ_range vs B and pin the figure in `results/` — it is the argument
   you'll reach for when someone asks why B must be so far down the
   flight line.
2. **Outage stress.** Lengthen the sun-crossing outage until only A + C
   cover part of the loop. Look at the triangulation geometry with that
   pair — what happened to the error ellipse, and why does D3 still call
   C "third angle for redundancy" rather than a full partner?
3. **Time skew.** Deliberately bias Station B's time mapping by 33 ms
   and re-triangulate. Compare the position error against lesson 04's
   1-frame argument. Keep this switch — lesson 14's validate tool should
   catch exactly this fault class.

## Checkpoint

- `maiden twin --out data/twin-ideal --seed 1` produces five files +
  `truth.npz`; PyChapter10 opens all four `.ch10` files with the IF-1
  channels present.
- Forward-model spot checks and the Monte-Carlo σ_range test pass in
  pytest; measured range error at the default geometry ≈ 0.15 m and
  scales with 1/B.
- Dropouts, the Station B outage, and per-station clock drift are
  present and visible in the data.
- The module docstring states what the twin does not model, verbatim
  enough that a stranger could not over-trust it.
