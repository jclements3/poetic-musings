# Lesson 09 — Camera Geometry & Calibration [desk/bench]

*Where we are.* Ingest can now hand the pipeline tracker samples — but the
tracker doesn't exist yet, and before it can, you need the mathematics
that turns a pixel coordinate into a direction in the field frame. That
chain — pixel → undistorted ray → camera frame → station frame → az/el —
is this lesson, along with the procedure that measures its parameters: the
checkerboard intrinsics calibration you will run at every deploy. The
machine-vision cameras may not have arrived; a webcam is enough to make
the entire procedure muscle-memory today.

## Objectives

- Derive the pinhole model (fx, fy, cx, cy) from first principles and the
  Brown radial distortion terms (k1, k2) that D4's TMATS template carries.
- Implement `maiden/camera.py`: a `CameraModel` built from TMATS
  `C\MAIDEN\CAM` attributes, with `px_to_azel(u, v, pose)` and its
  inverse `azel_to_px` (the twin's renderer and the validator both want
  the forward direction).
- Run OpenCV `calibrateCamera` on a printed checkerboard with a webcam;
  achieve and *verify* reprojection error on held-out poses, against the
  VT-07 criterion (≤ 0.5 px).
- Write the calibration script that emits ready-to-paste TMATS attribute
  lines, closing the loop file-ward.
- Walk the full D6 survey-and-calibration procedure on paper and connect
  each step to the code or requirement it serves.

## Concepts

### The pinhole model, honestly

A camera maps a 3-D point in the *camera frame* (X right, Y down, Z out
the lens) to a pixel:

```
  u = fx * (X/Z) + cx        fx, fy : focal length in pixel units
  v = fy * (Y/Z) + cy        cx, cy : principal point (≈ image center)
```

fx in pixels is just focal-length-in-mm divided by pixel-pitch-in-mm.
Sanity numbers for MAIDEN's cameras (1920 px wide): a 60° horizontal FOV
lens gives fx ≈ 1920 / (2 tan 30°) ≈ 1663; the D4 template's example
fx = 1820 is a slightly narrower ~56°. Station B's 35° lens lands near
fx ≈ 3050 — that factor of ~1.8 in pixel scale at range is exactly why D6
puts the narrow lens on the baseline station.

Real lenses bend: radial distortion moves a point from ideal normalized
radius r to r·(1 + k1·r² + k2·r⁴). Brown's model with two k's is plenty at
these fields of view. Distortion is applied in *normalized* coordinates
(x = X/Z, y = Y/Z), before the fx/cx scaling — get the order wrong and
your corners calibrate but your sky doesn't.

Going the direction MAIDEN needs — pixel to ray — inverts this:
normalize (u,v) by the intrinsics, *undistort* (iteratively; k1 r² is not
analytically invertible, three fixed-point iterations converge fine),
and you have a unit-scalable ray (x, y, 1) in the camera frame.

### From camera frame to az/el

The station's `Pose` (lesson 01) supplies heading; the radar/camera rail
supplies boresight elevation. Rotate the camera-frame ray into the local
ENU frame:

```
  ray_enu = R_z(-heading) · R_x(boresight_el) · P · ray_cam
```

where P is the fixed permutation taking camera axes (right/down/out) to
(east-ish/up-ish/north-ish) before the pose rotations. Then, **pinned
convention for the whole project**:

- `az_deg` — azimuth of the ray, *clockwise from true north*, in the
  station's local ENU frame: `az = atan2(E, N)`.
- `el_deg` — elevation above the local horizontal: `el = asin(U)` for a
  unit ray.

This is what IF-4 means by "station-frame azimuth," what lesson 11 emits,
and what the lesson-12 EKF measurement model inverts. Write the convention
as a docstring in `camera.py` and cite it from `state.py`.

### Why 0.5 px is the number that matters

D3's error budget runs on σ_θ ≈ 0.5 mrad. At fx ≈ 1663, one pixel is
1/1663 rad ≈ 0.6 mrad — so the *calibration* must be good to better than a
pixel or it, not the tracker, becomes the accuracy floor. Hence GS-005 and
VT-07's ≤ 0.5 px reprojection on *held-out* poses: reprojection error on
the poses you fit is flattery; hold-out is measurement.

## Doc Trace

- **GS-005** (intrinsics ≤ 0.5 px) is this lesson's core; **VT-07**
  verifies it — bench, checkerboard, hold-out. Practice runs with a
  webcam go in `results/VT-07/practice/`; the real cameras get the
  formal run in lesson 20.
- **GS-004** (survey ≤ 0.1 m, heading ≤ 0.2°) enters through `Pose`: the
  az/el this lesson computes is only as good as the heading it rotates
  by. VT-06 is field-only (lesson 20/99), but the D6 procedure is walked
  here so the code and the procedure grow up together.
- The TMATS `C\MAIDEN\CAM\*` attribute names are IF-2 contract; the
  calibration script emits them byte-exact.
- D3's σ_range ≈ R²·σ_θ/B budget is the *reason* for all of it; Explore 2
  makes you feel that lever.

## Build

**`software/maiden/camera.py`** — complete module, and it stays small:

```python
@dataclass(frozen=True)
class CameraModel:
    fx: float; fy: float; cx: float; cy: float
    k1: float = 0.0; k2: float = 0.0

    @classmethod
    def from_tmats(cls, cam_attrs) -> "CameraModel": ...

    def undistort(self, u, v) -> tuple[float, float]:
        """pixel -> normalized, distortion removed (3 fixed-point iters)."""

    def px_to_ray_cam(self, u, v) -> np.ndarray:
        """unit ray in camera frame (X right, Y down, Z out)."""

def px_to_azel(model, pose, u, v) -> tuple[float, float]:
    """THE convention: az clockwise from true north, el above horizontal."""

def azel_to_px(model, pose, az_deg, el_deg) -> tuple[float, float] | None:
    """Forward projection; None if the ray is behind the camera."""
```

Vectorize with NumPy from the start (arrays of u, v in, arrays out) — the
tracker calls this per frame and the twin per truth sample.

**`software/maiden/tools/calibrate.py`** — the calibration script:

1. Capture: grabs frames from a cv2.VideoCapture device on keypress,
   saves to a session directory (aim for ~20 captures of a printed 9×6
   checkerboard: fill the frame, tilt in both axes, reach the corners).
2. Fit: `cv2.findChessboardCorners` + `cornerSubPix` +
   `cv2.calibrateCamera` with the distortion model clamped to k1, k2
   (`CALIB_FIX_K3 | CALIB_ZERO_TANGENT_DIST` — match what TMATS can
   carry, or extend IF-2; don't silently fit parameters you then drop).
3. Hold out: fit on a random 3/4 of captures, reproject the held-out 1/4
   through your *own* `CameraModel` (not OpenCV's projector — this
   cross-checks your distortion-order convention against OpenCV's),
   report RMS and max reprojection error.
4. Emit: print the six `C\MAIDEN\CAM\*:value;` lines ready for the
   station's TMATS, plus a JSON sidecar under `config/` versioned per
   station serial (D5 CM: calibration files versioned per serial).

**`software/tests/test_camera.py`**:

- Round-trip: random az/el within the FOV → `azel_to_px` → `px_to_azel`
  recovers them to < 1e-6 deg with zero distortion, < 1e-3 deg with the
  template's k1 = −0.112 (the undistort iteration tolerance).
- Convention anchors: with heading 0 and boresight_el 0, the principal
  point maps to az 0 (north), el 0; heading 90 maps it to az 90 (east).
  These two asserts are cheap and will save you from a season of
  mirrored fields.
- TMATS loop: `CameraModel.from_tmats(parse(template).cam)` reproduces
  the template's numbers.

### The field procedure this code serves

Read the D6 survey-and-calibration procedure now, as the operator you
will be in lesson 20: tripod and mark; 5-min GNSS average (→ survey
attributes, GS-004); landmark heading sight through the rail (→ `Pose`
heading — the 0.2° budget is ~3.5 mrad, seven times your pixel, which is
why it gets a *second* landmark check); 12 checkerboard poses (→ this
lesson's script); corner-reflector boresight walk (→ radar, lesson 16).
Each step feeds an attribute your code just learned to consume.

## Verify

- `pytest software/tests/test_camera.py` — green, including both
  convention anchors.
- Webcam calibration run: hold-out RMS reprojection reported by your
  script. A decent webcam and careful captures land well under 0.5 px;
  if you're above it, more poses at the frame corners is almost always
  the fix. Log the run — captures, JSON, reported error — to
  `results/VT-07/practice/`. **Observe on bench** when the real cameras
  arrive: repeat and log formally (lesson 20 schedules it).
- Feed the emitted TMATS lines through lesson 03's parser and lesson 08's
  `describe()` — the `CameraModel` that comes back out must equal the one
  the script fitted.

## Explore

1. **Break the distortion order.** Apply distortion after the fx scaling
   instead of before, refit, and look at where the hold-out error
   concentrates (frame corners). This is the classic silent-convention
   bug; know its signature.
2. **Feel the D3 lever.** With `azel_to_px`, compute the pixel
   displacement at 150 m of a 0.1 m survey error versus a 0.2° heading
   error, for both the 60° and 35° lenses. Which term dominates the
   σ_range ≈ R²·σ_θ/B budget? Write the answer into a comment in
   `config/field/rcrc.yaml` — it is the justification for GS-004's split.
3. **k2 or not k2.** Refit your webcam with k2 fixed to zero. Does
   hold-out error change materially at your FOV? D4 carries k2 either
   way; the question is whether *lesson 20's* formal calibration should
   fight for it. Note your finding for future-you.

## Checkpoint

- `pytest software/tests/test_camera.py` passes; the az/el convention
  anchors are among the asserts.
- Your calibration script runs end-to-end on a webcam and emits valid
  IF-2 attribute lines that round-trip through the TMATS parser.
- A practice calibration with hold-out reprojection error, logged under
  `results/VT-07/practice/` — number known, not guessed.
- You can state from memory: the az/el convention, why 0.5 px ≈ the
  0.5 mrad budget, and which of survey position vs. heading error hurts
  fusion more.
