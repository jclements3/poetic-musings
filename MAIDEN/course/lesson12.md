# Lesson 12 — Fusion I: The EKF [desk]

*Where we are.* You have a digital twin that writes real Ch. 10 files
(lesson 07), an ingest layer that turns them back into `StateSample`
streams (lesson 08), and a tracker that produces az/el/conf per station
(lessons 10–11). Two stations each see a bearing to the aircraft; nobody
yet sees *where it is*. This lesson builds the first half of `maiden.fuse`:
an extended Kalman filter that turns A's and B's angle measurements into a
3D position and velocity with an honest covariance. Lesson 13 adds the
radar velocities, gating, and dropout handling.

## Objectives

- Explain state, covariance, predict, and update well enough to derive
  each — not recite them.
- Derive the constant-velocity process model F and a process noise Q sized
  to aerobatic flight, per axis, from first principles.
- Derive the az/el measurement model h(x) for a posed station and its
  full Jacobian H, and verify H against finite differences.
- Implement the two-ray least-squares initializer from the first A+B pair.
- Run predict + az/el update on twin A+B data and compare fused position
  to twin truth.

## Concepts

### Estimation in one paragraph

You believe the aircraft is at state **x** (position and velocity), but
your belief is uncertain: it is a Gaussian with mean x and covariance P.
Physics evolves your belief forward in time (predict); a measurement —
which is itself uncertain — pulls your belief toward what the sensor saw
(update), weighted by *relative* uncertainty. The Kalman filter is just
the algebra that keeps the Gaussian bookkeeping exact for linear models.
Our measurement (angles to a target) is nonlinear, so we linearize around
the current estimate each step — that single word "linearize" is the E in
EKF, and it is the only difference.

### State and process model

Per the pinned interface, x = [E N U vE vN vU]ᵀ in the field frame.
Constant velocity over a short Δt:

```
x⁻ = F x,   F = [ I₃  Δt·I₃ ]      P⁻ = F P Fᵀ + Q
                [ 0₃    I₃  ]
```

Nothing about a pattern aircraft is constant-velocity — that is what Q is
for. Model the unmodeled acceleration as white noise of strength σ_a² per
axis (piecewise-white-acceleration model). Discretizing over Δt gives,
per axis:

```
Q_axis = σ_a² · [ Δt⁴/4   Δt³/2 ]
                [ Δt³/2   Δt²   ]
```

assembled into 6×6 with the position/velocity block layout of x. Sizing
σ_a: a Sportsman loop at ~30 m/s with ~40 m radius is v²/r ≈ 22 m/s², and
snap inputs are sharper, so σ_a in the 15–30 m/s² range is the honest
starting point — D6 calls this "process noise tuned to aerobatic g".
Tune it in Verify; too small and the filter smugly ignores maneuvers, too
large and it chases every pixel of tracker noise. (The Singer model —
exponentially correlated acceleration — is the standard refinement; an
Explore exercise, not a requirement.)

### The az/el measurement model

A station has a `Pose` (lesson 01): survey position **s** in ENU and
heading ψ, compass convention (clockwise from north). Define the station
frame axes in ENU: forward **f** = (sinψ, cosψ, 0), right
**r** = (cosψ, −sinψ, 0), up **u** = (0, 0, 1). With d = p − s
(target minus station, ENU) the station-frame components are

```
[xs]   [ cosψ  −sinψ  0 ] [dE]
[ys] = [ sinψ   cosψ  0 ] [dN]   ≡ M d
[zs]   [  0      0    1 ] [dU]
```

(xs = right, ys = forward, zs = up), and the measurement is

```
az = atan2(xs, ys)                 (0 = boresight, + to the right)
el = atan2(zs, ρ),  ρ = √(xs²+ys²)
```

This matches what the tracker emits: angles in the station frame, per D4.

### The Jacobian, fully

h depends only on position, so H = [∂h/∂p  0₂ₓ₃]. First differentiate in
the station frame (r² = xs²+ys²+zs²):

```
∂az/∂(xs,ys,zs) = (  ys/ρ²,   −xs/ρ²,   0    )
∂el/∂(xs,ys,zs) = ( −xs·zs/(r²ρ),  −ys·zs/(r²ρ),  ρ/r² )
```

Then chain through the (linear, constant) frame rotation:

```
∂h/∂p = J_station · M          (2×3) = (2×3)(3×3)
H     = [ ∂h/∂p   0₂ₓ₃ ]        (2×6)
```

Derive both rows yourself before checking against the above — atan2
differentiation is a five-minute exercise and you will trust the filter
more for having done it. Measurement noise: R = diag(σ_θ², σ_θ²) with
σ_θ = 0.5 mrad from D3's error budget; later you will scale R by tracker
confidence, but not in this lesson.

### The update, and the one trap in it

```
y = z − h(x⁻)          innovation  (wrap the az component to [−π, π]!)
S = H P⁻ Hᵀ + R
K = P⁻ Hᵀ S⁻¹
x = x⁻ + K y
P = (I − K H) P⁻       (Joseph form (I−KH)P⁻(I−KH)ᵀ + KRKᵀ if P misbehaves)
```

The trap is the angle wrap: an aircraft crossing az = ±180° will produce
a 2π innovation and launch your estimate into the next county unless you
normalize y[0].

### Initialization: two rays, closed form

Before the filter exists there is no x to linearize around. The first
frame where A and B both report angles gives two rays
p = s_A + t_A û_A and p = s_B + t_B û_B (unit vectors from az/el via the
inverse of the model above). They do not intersect; find the closest
points. With w = s_B − s_A and c = û_A·û_B:

```
t_A = (w·û_A − c·(w·û_B)) / (1 − c²)
t_B = (c·(w·û_A) − w·û_B) / (1 − c²)
p₀  = ½ (s_A + t_A û_A + s_B + t_B û_B)
```

Initialize position at p₀, velocity at zero, P with large velocity
variance (e.g., σ_v = 30 m/s) and position variance from D3's
σ_range ≈ R²σ_θ/B geometry. When c → 1 the rays are parallel and 1−c²
kills you — guard it; that happens when the target sits on the A–B
baseline extension, which the lesson 13 Explore returns to.

## Doc Trace

- **SYS-001** (3D trajectory from ground sensors only) — this lesson is
  the first end-to-end demonstration of it, on twin data.
- **SYS-002** (position accuracy) — rehearsed in sim here; the binding
  test is VT-10 in the field campaign (lesson 99).
- **D3 §Fusion concept** governs the geometry: A + B rays → position,
  error scaling σ_range ≈ R²σ_θ/B. Your Verify numbers should reproduce
  that scaling.
- **D6 §Fusion EKF** is the design being implemented: 6-state CV model,
  az/el measurements with station pose from TMATS, initialization from
  the first A+B pair. v_r, lagging, and covariance publication are D6
  items deferred to lesson 13.

## Build

All in `software/maiden/fuse.py`. *Skeleton* — you write the internals:

```python
@dataclass
class EkfConfig:
    sigma_a: float = 20.0        # m/s^2, process noise (tune in Verify)
    sigma_theta: float = 0.5e-3  # rad, per D3

class Ekf:
    def __init__(self, cfg: EkfConfig): ...
    def init_two_ray(self, za: AzEl, zb: AzEl,
                     pose_a: Pose, pose_b: Pose, t: float): ...
    def predict(self, t: float): ...          # advance to time t
    def update_azel(self, z: AzEl, pose: Pose): ...
    @property
    def state(self) -> np.ndarray: ...        # x (6,)
    @property
    def cov(self) -> np.ndarray: ...          # P (6,6)

def fuse_azel_only(samples: Iterable[StateSample],
                   stations: dict[str, Pose]) -> list[StateSample]:
    """Sort by t_utc; init on first A+B pair within one frame time;
    then predict-to-measurement, update, emit FUSED at each update."""
```

Implementation notes, in the order you will hit them:

- `azel_to_unit(az, el, pose)` and `h_azel(p, pose)` belong in `geo.py`
  or a small `fuse`-private helper — they are the same math inverted.
- Predict to each measurement's timestamp and update sequentially. Do not
  batch A and B into one stacked update yet; sequential scalar-block
  updates are equivalent and simpler to debug.
- Emit a FUSED `StateSample` (source `"FUSED"`, `pos_enu`, `vel_enu`,
  `cov`) after each update, per the IF-4 contract.
- Keep every matrix explicitly shaped; a silent (6,) vs (6,1) broadcast
  is the classic NumPy Kalman bug.

Also write `software/tests/test_fuse_azel.py` (see Verify) and a small
plot script `scripts/plot_fused.py` (truth E/N/U and fused E/N/U vs time,
plus 3D track overlay) — matplotlib, saved to `results/lesson12/`.

## Verify

- **Jacobian test.** `test_jacobian_azel`: random states and poses,
  compare your analytic H against central finite differences; agreement
  to 1e-6 relative. This test is non-negotiable — every EKF bug report in
  history starts with a hand-derived Jacobian.
- **Init test.** Two synthetic rays from a known point with zero noise
  recover it to numerical precision; with 0.5 mrad noise at 150 m and a
  75 m baseline, error is order σ_range from the D3 formula.
- **Twin run, A+B only, clean.** Twin with noise on but dropouts off:
  run `fuse_azel_only`, interpolate twin truth to fused timestamps,
  record position RMS. With σ_θ = 0.5 mrad, B = 75 m, R ≈ 150 m, the D3
  scaling predicts sub-meter; record *your* measured number in
  `results/lesson12/rms.txt`. Velocity will be mediocre — angles only
  observe velocity through differencing, which is exactly why lesson 13
  exists.
- Tune σ_a: sweep 5/10/20/40 m/s² and record RMS for each; keep the
  winner in `EkfConfig` with a comment citing this sweep.

## Explore

- **Reproduce D3's scaling law.** Regenerate the twin with B = 25 m and
  B = 150 m. Plot measured position RMS vs baseline against
  σ_range = R²σ_θ/B. D3 promises ~3× degradation at 25 m — does your
  filter agree?
- **Filter vs geometry.** Per-frame two-ray triangulation (your
  initializer, run every frame) vs the EKF, same data. Compare RMS and
  smoothness. The gap *is* the value of the process model.
- **Break it on purpose.** Comment out the az innovation wrap and script
  a twin pass that crosses behind Station A. Watch the divergence, then
  restore the wrap. You will never forget it again.
- **Singer model.** Replace white acceleration with exponentially
  correlated acceleration (τ ≈ 2 s). Does it beat the tuned white-noise Q
  on the twin's loop segments?

## Checkpoint

- `pytest software/tests/test_fuse_azel.py` passes, including the
  finite-difference Jacobian test.
- `fuse_azel_only` on the clean twin produces a FUSED track with position
  RMS recorded in `results/lesson12/`, consistent with the D3 geometry
  scaling (order 1 m or better at the nominal layout).
- The fused-vs-truth plot exists and shows no divergence through the full
  twin sequence, including the az-wrap crossing.
- You can state from memory why the filter needs the angle wrap, and what
  σ_a you chose and why.
