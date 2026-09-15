# Lesson 11 — Video Tracker II: Tracks [desk]

*Where we are.* Candidates exist and are measured: on twin imagery the
front end proposes the aircraft essentially every frame it's ≥ 6 px, with
a known dip when the sun is in frame. But candidates are not
measurements — they are unlabeled blobs, some of which are the airplane.
This lesson finishes `maiden.track`: a detector that scores candidates, a
per-station 2-D Kalman filter that strings them into tracks, and the
emission path that turns a confirmed track into what the rest of MAIDEN
consumes — az/el/conf as `StateSample`s, and Ch 5 message packets so a
recorded session carries its tracker output per IF-1.

## Objectives

- Implement a classical scoring detector over lesson-10 candidates
  (size, contrast, motion agreement), with the D6 learned detector
  positioned honestly as the upgrade path once labeled field frames
  exist.
- Build a 2-D constant-velocity Kalman tracker in pixel space with
  gated association and spawn/coast/kill track management.
- Define track confidence from detector score and track age, and emit
  az/el/conf via lesson 09's geometry — as `StateSample`s and as packed
  Ch 5 `TRACKER` messages.
- Score the whole tracker against twin truth with the lesson-10 harness:
  VT-15's criteria (recall ≥ 90 % at ≥ 6 px, false tracks ≤ 1/min) on
  twin sequences including the sun-crossing window — while stating
  plainly what twin numbers do and don't prove.

## Concepts

### Detection is a score, not a verdict

The two-stage design in D6 confirms candidates with a detector. Before
any network, a weighted score gets surprisingly far on this problem:

```
  score = w_a · size_plausibility(area | expected px from track range)
        + w_c · contrast_norm
        + w_m · motion_agreement(candidate | track prediction)
```

Early in a track's life there is no range and no prediction, so the first
terms carry it; once fusion runs (lesson 13), predicted range can flow
back and sharpen `size_plausibility` — note the hook, don't build it yet.
Calibrate the weights and threshold on twin sequences by sweeping and
plotting recall vs. false confirmations; pick the knee, record the sweep.

The D6 YOLO-class detector is *deferred, not forgotten*: it needs labeled
field frames that don't exist until the validation campaign era, and the
twin's renderer is too clean to train against (its docstring says so).
The module boundary is drawn so the classical scorer and a future learned
scorer are interchangeable: `score(candidates, context) -> ndarray`.

### The pixel-space Kalman filter

Per station, per track: state **x** = [u, v, u̇, v̇]ᵀ, constant velocity,
30 Hz updates.

```
  F = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]     H = [[1,0,0,0],
  Q = q · G Gᵀ   (white-accel model)                        [0,1,0,0]]
  R = diag(σ_px², σ_px²)
```

σ_px ≈ 1 px from the candidate centroid; q from the worst pixel
acceleration you expect — an aerobatic pull at 150 m can slew hundreds of
px/s², so compute it from the twin's truth rather than guessing.
Association is gated nearest-neighbor on the Mahalanobis distance
(gate ≈ 9.2 for 2 dof, 99 %); with one aircraft in the box (D1
constraint), nearest-neighbor inside a gate is entirely adequate, and the
multi-aircraft case is explicitly Phase 2.

This filter is deliberately the lesson-12 EKF's little sibling: same
predict/update algebra, two dimensions, linear H. Everything you debug
here — innovation monitoring, gate tuning, Q vs. R balance — transfers
directly, which is why the course does pixels before ENU.

### Track management and the meaning of `conf`

```
  TENTATIVE --(M of N confirms, e.g. 3 of 5)--> CONFIRMED
  CONFIRMED --(miss)--> COASTING --(hit)--> CONFIRMED
  COASTING  --(K consecutive misses, e.g. 15)--> DEAD
```

Coasting is what carries the track through the sun-crossing dip: the
filter predicts, uncertainty grows, and reacquisition re-gates on the
inflated covariance. `conf` ∈ [0, 1] must *mean* something downstream —
define it as a bounded function of (recent detector scores, track age,
frames since last hit), monotonically decreasing while coasting, and
document it in the module docstring: fusion will de-weight measurements
by it, and D9's "wide band ≠ bad pilot" story ultimately traces to this
number being honest.

Only CONFIRMED (and, flagged, COASTING) tracks emit. Emission is two
sinks fed by one code path: `StateSample(t_utc, source=station.id,
az_deg, el_deg, conf)` for the live pipeline, and lesson 08's
`payloads.TRACKER` struct into Ch 5 packets for recorded sessions —
byte-identical to what ingest already decodes, which your round-trip test
will prove.

### What twin numbers prove

On twin imagery you are verifying the *machinery*: association logic,
coasting, emission, the harness. You are not verifying SW-002 against
real sky — D7 scopes VT-15's evidence to labeled field frames plus CI
replay. Run the twin numbers, log them as `results/VT-15/twin/`, and
keep the field column empty until it can be filled honestly. CI (lesson
15) will replay the twin subset as a regression floor, which is exactly
what SW-005 asks of it.

## Doc Trace

- **SW-002** is completed in structure by this lesson (az/el with
  confidence, per station); its field-grade verification remains open.
- **VT-15** — criteria exercised on twin data today; the CI subset is
  handed to lesson 15; the labeled-field-frames subset is scheduled for
  the campaign era (lesson 99 collects the frames).
- **IF-1 Ch 5** — the TRACKER message emission; **IF-4** — the
  StateSample emission; both structs are lesson 08's shared definitions.
- **D5 risk R1** — coasting + reacquisition is the software half of the
  mitigation; the measured sun-window recovery time goes in the risk
  register's evidence trail.
- The `size_plausibility`-from-fused-range hook is a documented forward
  reference to lesson 13.

## Build

**`software/maiden/track/detector.py`** (skeleton): `score(candidates,
context) -> np.ndarray` plus `Context` (previous-track predictions,
expected size if known). Pure function of its inputs; the sweep tool
(`tools/sweep_detector.py`) lives beside it and writes the
recall/false-alarm curve to `results/VT-15/twin/`.

**`software/maiden/track/kalman2d.py`** — complete this one yourself,
small and fully tested: `Kalman2D(dt, q, sigma_px)` with `predict()`,
`update(z)`, `mahalanobis(z)`, exposing state and covariance. Unit tests:
a constant-velocity synthetic target is tracked with innovation whiteness
(normalized innovations squared ≈ 2-dof χ²); a missed update inflates P.

**`software/maiden/track/tracker.py`** (skeleton):

```python
class StationTracker:
    """One per station. consume(t_utc, candidates) -> list[TrackOut];
    TrackOut carries (u, v, conf, state) for emitters."""
    def __init__(self, model: CameraModel, pose: Pose, cfg: TrackerCfg): ...
```

State machine as in Concepts; parameters (M, N, K, gate) in `TrackerCfg`
with the defaults you tuned, not magic numbers in code.

**`software/maiden/track/emit.py`**: TrackOut → StateSamples (via
`px_to_azel`) and → Ch 5 packets (via `payloads.TRACKER`, bbox from the
candidate). One function each, shared timestamping.

**`software/tests/test_tracker.py`**: kalman2d units; state-machine unit
tests with scripted hit/miss sequences (confirmation at M of N, death at
K, conf monotone while coasting); an emission round-trip — track a twin
sequence, write Ch 5 packets into a session file, `maiden.ingest.load`
it, and assert the ingested az/el/conf equal the emitted ones; and the
end-to-end twin metric: recall ≥ 0.90 at ≥ 6 px on the clean-sky
sequence (the CI floor).

## Verify

- `pytest software/tests/test_tracker.py` — green, including the Ch 5
  round-trip.
- Full harness, clean sky: track recall at ≥ 6 px should clear 0.90 with
  margin on twin imagery, false tracks ≈ 0 (the renderer is kind; that's
  the point of the bird/junk Explore below).
- Full harness, sun crossing: compare the *track*-level recall trace
  against lesson 10's *candidate*-level trace. Coasting should visibly
  bridge part of the dip; record dip depth, coast duration, and
  reacquisition delay in `results/VT-15/twin/`.
- False-track pressure test: raise the renderer's noise and add the
  Explore-3 bird from lesson 10; measure false confirmed tracks per
  minute against VT-15's ≤ 1/min line. Log the settings with the number —
  a false-alarm rate without its noise level is not evidence.

## Explore

1. **Gate autopsy.** Log every association's Mahalanobis distance for a
   full sequence and histogram it against the χ² prediction. If the tails
   are fat, your Q is lying about maneuvers — retune from the twin's
   snap-roll segment, the sharpest px-acceleration in the script.
2. **Coast limit K.** Sweep K from 5 to 45. Long coasts bridge the sun
   but hallucinate a straight-line aircraft that isn't there (watch the
   az/el error of coasted emissions vs. truth — they're flagged, but are
   they *usable*?). Decide what fusion should receive: coasted samples
   with low conf, or silence? Write the decision into `emit.py`'s
   docstring; lesson 13 will implement its half.
3. **Two targets.** Script a twin variant with two aircraft crossing.
   Watch nearest-neighbor association swap tracks at the crossing. You
   are looking at the reason D1 says one-aircraft-at-a-time and why
   multi-aircraft is a Phase 2 hardening item — no fix required, just
   the understanding.

## Checkpoint

- `pytest software/tests/test_tracker.py` passes; the emission
  round-trip through a real Ch. 10 file is among the tests.
- Twin clean-sky tracker metrics logged: recall ≥ 0.90 at ≥ 6 px, false
  tracks ≤ 1/min, in `results/VT-15/twin/` beside the detector sweep and
  the sun-window numbers — each labeled as twin evidence, field column
  open.
- `TrackerCfg` defaults are the tuned values, with the sweeps that chose
  them committed.
- You can explain what `conf` means, mechanically, and how it will reach
  a pilot as a wide band on a score.
