# Lesson 13 — Fusion II: Velocity & Dropouts [desk]

*Where we are.* Lesson 12's filter turns A+B angles into a position track
with honest covariance, but its velocity estimate is whatever falls out of
differenced positions — noisy, laggy, and not what D3 promised. The
architecture's second idea is that three CW radars each measure one
component of velocity *directly*, and three projections of one vector are
enough to reconstruct it. This lesson finishes `maiden.fuse`: v_r updates,
innovation gating, per-epoch alignment, dropout coasting, continuity
accounting, and covariance publication. At the end you run the full
three-station twin with imperfections on and measure yourself against the
SYS-002/003/004 numbers — in sim.

## Objectives

- Derive the radial-velocity measurement model and its full Jacobian,
  including the position-dependent term everyone forgets.
- Restate and numerically verify D3's claim: three radial velocities
  resolve the full velocity vector without differentiating position.
- Implement chi-square innovation gating and per-epoch measurement
  scheduling.
- Implement coasting, track-validity declaration, and SYS-004-style
  continuity accounting.
- Run the full twin with dropouts and imperfections; measure position
  RMS, velocity RMS, and continuity against twin truth.

## Concepts

### The v_r measurement model

A CW Doppler chain at station **s** measures the projection of target
velocity onto the line of sight. With d = p − s, û = d/‖d‖:

```
h_vr(x) = v · û        (scalar; sign: positive = receding from station,
                        i.e. h = d(range)/dt — match the twin's convention,
                        and write the convention down in fuse.py)
```

### The Jacobian, including the term everyone forgets

h_vr depends on v *and on p* — moving the target sideways rotates û. The
derivative of a unit vector is the classic identity

```
∂û/∂p = (I₃ − û ûᵀ) / ‖d‖
```

so the full 1×6 Jacobian is

```
∂h/∂p = vᵀ (I₃ − û ûᵀ) / ‖d‖        (1×3)
∂h/∂v = ûᵀ                           (1×3)
H_vr  = [ ∂h/∂p   ∂h/∂v ]            (1×6)
```

At 150 m the position term is small (v_⊥/‖d‖ ≈ 0.2 (m/s)/m for a 30 m/s
crossing target) but it is not zero, and dropping it biases the filter
exactly when the target maneuvers. Your finite-difference test will catch
you if you cheat. R for this update: σ_vr² with σ_vr from the twin's
injected Doppler noise for now; the bench value arrives in lesson 17.

### Why three radials give you the whole vector

D3's argument, restated: each station measures v·û_i, one linear
functional of v. Three stations with linearly independent û_i give

```
[ û_Aᵀ ]         [ vr_A ]
[ û_Bᵀ ]  v  =   [ vr_B ]      ⇒  v = U⁻¹ vr
[ û_Cᵀ ]         [ vr_C ]
```

— full 3D velocity from a single epoch, no differencing of noisy
positions, no lag. The catch is conditioning: if the target is far from
all stations the three û_i point nearly the same way, U is nearly
singular, and the vertical velocity component gets amplified noise. The
EKF handles this gracefully (a badly conditioned epoch just updates less)
— but verify the clean linear-algebra version numerically in Build so you
believe the mechanism before burying it inside the filter.

### Gating: refusing to believe nonsense

Trackers produce outliers — a bird, a sun glint, a wrong association.
Before applying any update, test the innovation against its own predicted
statistics:

```
γ = yᵀ S⁻¹ y      ~ χ²(m) if the measurement is consistent
```

Reject when γ exceeds the χ² quantile at 0.999: **13.82** for m = 2
(az/el), **10.83** for m = 1 (v_r). A rejected measurement is logged, not
applied. Gating is also your safety net against the lesson 12 angle-wrap
class of bug — a 2π innovation gates out instead of destroying the track.
(It also masks real bugs the same way, which is why the gate-rejection
*rate* goes in your logs: a healthy run rejects a fraction of a percent.)

### Epochs, lag, and the measurement queue

Stations timestamp on their own IRIG-B-disciplined clocks; measurements
arrive interleaved but not simultaneous. D6's phrase is "lags stations to
a common epoch": collect all measurements, sort by t_utc, and for each
one predict-to-time then update — sequential processing is exactly
optimal for the Kalman filter, no batching needed. *Publishing* is
separate: emit FUSED samples on a fixed 50 Hz epoch grid (predict to the
epoch, publish state + covariance), so downstream consumers see a uniform
stream regardless of sensor timing. The small delay this imposes is the
"lag" — bounded by one epoch.

### Coasting, validity, and continuity

No measurements (sun crossing, dropout window)? Predict only. P grows
with Q every epoch — the filter honestly reports that it knows less. A
FUSED sample is **valid** while position uncertainty stays useful; the
course threshold is √trace(P_pos) ≤ 3 m (≈3× the SYS-002 number —
recorded as a constant with this comment, revisit after the campaign).
Continuity, in SYS-004's sense as tested by VT-12, is the fraction of the
sequence duration covered by valid FUSED samples. Count it exactly that
way: valid-epoch time over total sequence time, per flight.

## Doc Trace

- **SYS-001–SYS-004** — with this lesson, all four are exercised
  end-to-end on twin data; the D6 §Fusion EKF design element is complete
  (missing-measurement handling, common-epoch lag, published 6×6
  covariance).
- **VT-10 / VT-11 / VT-12** — rehearsed here in sim against the SYS-002,
  SYS-003, SYS-004 thresholds; the binding runs are field, on the
  validation campaign (lesson 99). Say it plainly: passing in sim is
  necessary, not sufficient.
- **VT-17** — the twin gate ("pipeline runs unchanged; residuals
  consistent with injected noise") is now fully checkable; lesson 14
  formalizes the residual math.
- The published covariance feeds D8 §Confidence bands via lessons 14
  and 24.

## Build

Extend `software/maiden/fuse.py`. *Skeleton additions:*

```python
class Ekf:
    ...
    def update_vr(self, vr: float, pose: Pose, sigma_vr: float): ...
    def gate(self, y: np.ndarray, S: np.ndarray, m: int) -> bool: ...

@dataclass
class FuseStats:
    n_updates: int; n_gated: int; coast_time: float; valid_time: float

def fuse(samples: Iterable[StateSample], stations: dict[str, Pose],
         epoch_hz: float = 50.0) -> tuple[list[StateSample], FuseStats]:
    """Full scheduler: sort, init (lesson 12), predict/update per
    measurement with gating, coast through gaps, emit valid-flagged
    FUSED samples on the epoch grid with cov attached."""
```

Order of work:

1. `update_vr` + its Jacobian; finite-difference test first, twin second.
2. The numerical demo of U⁻¹vr: one twin epoch, build U from the three
   true unit vectors, solve, compare to twin truth velocity. Ten lines in
   `software/tests/test_three_radials.py`; keep it as documentation.
3. Gating inside both update paths, with counters into `FuseStats`.
4. The scheduler/epoch publisher, replacing lesson 12's
   `fuse_azel_only` (keep the old entry point working — CI uses it as a
   degraded-mode test).
5. Validity flag + continuity accounting into `FuseStats`.
6. CLI: `maiden fuse --session DIR` — ingest a session directory (twin or
   real), write `fused.npz` + a stats line.

## Verify

- `test_jacobian_vr`: analytic H_vr vs central differences, random
  states/poses, 1e-6 relative — including the position block.
- `test_three_radials`: single-epoch U⁻¹vr recovers twin velocity to
  injected-noise levels.
- `test_gating`: inject a 30σ az outlier into a twin stream; the gate
  rejects it and final RMS is unchanged versus the clean run.
- **The headline run.** Full twin, three stations, `--imperfect` (noise,
  dropouts, sun-crossing gaps). Record, per flight, into
  `results/lesson13/`: position RMS, velocity RMS, continuity. Targets
  are the SYS-002, SYS-003, SYS-004 thresholds (cite D2; do not restate
  numbers in code — read them from the lesson 15 thresholds config once
  it exists, hardcode-with-TODO until then). If you miss: check gating
  rate (>1% means a modeling problem), then σ_a, then epoch lag handling.
- Watch velocity RMS specifically drop when you ablate the v_r updates
  back out — that delta is D3's architecture decision, measured.

## Explore

- **Geometry torture.** Script a twin pass along the A–B baseline
  extension (the initializer's singular direction). How do conditioning,
  covariance, and continuity respond? This is the case D3's third
  station exists for — verify that C rescues it.
- **Station-out ablations.** Run A+B, A+C, B+C, and A+B+C on the same
  twin flight; tabulate pos/vel RMS and continuity. You are reproducing
  the "C covers drop-outs, third ray tightens the fix" row of D3.
- **Innovation whiteness.** Plot normalized innovations over time; a
  well-tuned filter's are white with unit variance. Yours won't be,
  quite. Which segments are worst, and does that match the maneuver
  schedule?
- **Break it on purpose.** Drop the position block of H_vr (the term
  everyone forgets) and rerun the headline case. How much does velocity
  RMS degrade during the loop segments versus level legs?

## Checkpoint

- All fusion tests pass, including both finite-difference Jacobians and
  the three-radials demo.
- `maiden fuse --session <twin dir>` runs the imperfect twin end to end
  and reports stats; pos RMS, vel RMS, and continuity meet the
  SYS-002/003/004 thresholds in sim, and the numbers are logged in
  `results/lesson13/`.
- Gate-rejection rate on the clean twin is below 1% and you know what it
  was.
- FUSED StateSamples carry a 6×6 covariance and a validity flag; the
  epoch grid is uniform at 50 Hz.
