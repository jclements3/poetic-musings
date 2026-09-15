# Lesson 01 — The Field Frame [desk]

*Where we are.* The repo exists and imports. Before any sensor is read or
any file parsed, MAIDEN needs its coordinate system — because every product
of this system (fused tracks, residuals, scores, field-rule flags) is
expressed in one local frame: ENU meters with origin at Station A's survey
mark, north along the survey heading reference (D4 IF-4). This lesson
builds `maiden/geo.py`, the module every later lesson leans on, and
captures the RCRC site geometry in a config file. Geodesy is one of those
subjects where a sign error survives for months; we kill that risk today
with known-answer tests.

## Objectives

- Derive LLA→ECEF→ENU from first principles and implement it in
  `maiden.geo` with the pinned interface `enu_from_lla(origin_lla, lla)`.
- Implement the `Pose` dataclass (`pos_enu`, `heading_deg`,
  `boresight_el_deg`) used for stations from lesson 07 onward.
- Write `config/field/rcrc.yaml` holding the surveyed site geometry.
- Prove the math with known-answer, round-trip, and flat-earth-limit
  tests.

## Concepts

### The ellipsoid

WGS-84 models Earth as an oblate ellipsoid:

```
a  = 6378137.0 m              semi-major axis (equatorial radius)
f  = 1/298.257223563          flattening
b  = a(1-f)                   semi-minor axis
e² = f(2-f) = 6.69437999014e-3   first eccentricity squared
```

Geodetic latitude φ, longitude λ, height h convert to Earth-Centered
Earth-Fixed (ECEF) via the prime-vertical radius of curvature:

```
N(φ) = a / sqrt(1 - e²·sin²φ)

X = (N + h)·cosφ·cosλ
Y = (N + h)·cosφ·sinλ
Z = (N·(1-e²) + h)·sinφ
```

The `(1-e²)` on Z is where hand-rolled implementations go wrong: the
ellipsoid's normal does not pass through the center, so the Z term uses a
shortened radius. Your tests will catch it if you drop it — that is the
point of the tests.

### ECEF → local ENU

Given an origin (φ₀, λ₀, h₀) with ECEF vector **r₀**, the East-North-Up
components of a point with ECEF **r** are a rotation of the difference:

```
d = r − r₀

| E |   | −sinλ₀           cosλ₀           0     |   | dX |
| N | = | −sinφ₀·cosλ₀    −sinφ₀·sinλ₀    cosφ₀ | · | dY |
| U |   |  cosφ₀·cosλ₀     cosφ₀·sinλ₀    sinφ₀ |   | dZ |
```

This is exact (no small-angle assumption); the flat-earth approximation
`E ≈ (λ−λ₀)·(N+h)·cosφ₀`, `N ≈ (φ−φ₀)·(M+h)` is only a test oracle here.
Over the ~300 m extent of the pattern box the two agree to millimeters,
which is exactly the check we will write.

### From ENU to the field frame

D4 IF-4: "ENU with origin at Station A survey point, north from the survey
heading." Geodetic ENU already points N at true north; the *survey
heading* enters as each station's `Pose.heading_deg` — the azimuth its
sighting rail reads at deployment (D6 survey procedure, step 3). A
station-frame azimuth measurement `az` therefore maps to field azimuth
`az + heading_deg`. We keep the field frame aligned to true north and put
the heading in the pose, because that is what the TMATS record carries
(`C\MAIDEN\SURVEY\HDG_DEG`, lesson 03) and it keeps one convention for all
three stations.

Why survey precision matters this much: D3's error law σ_range ≈ R²·σ_θ/B.
A 0.2° heading error at 150 m is 0.52 m of cross-range bias — half the
entire SYS-002 budget — before the filter even starts. GS-004's 0.1 m /
0.2° numbers are not caution; they are arithmetic.

## Doc Trace

- **D4 IF-4** — defines the field frame this module implements; the
  convention is set once here and consumed by every downstream module.
- **GS-004** — survey accuracy; this lesson builds the math that makes the
  survey numbers meaningful. The field procedure and VT-06 come with the
  station build (lesson 20).
- **D1 §Operating site** — source of the site coordinates captured in
  `config/field/rcrc.yaml`.
- **D3 §Fusion concept** — the R²/B scaling that motivates the precision.

## Build

**File: software/maiden/geo.py**

```python
"""Field frame: WGS-84 LLA -> ECEF -> local ENU (D4 IF-4).

Origin of the field frame is Station A's survey mark; axes are geodetic
East-North-Up. Station survey headings live in Pose, not in the frame.
"""
from dataclasses import dataclass

import numpy as np

WGS84_A = 6378137.0
WGS84_F = 1.0 / 298.257223563
WGS84_E2 = WGS84_F * (2.0 - WGS84_F)


def ecef_from_lla(lla) -> np.ndarray:
    """(lat_deg, lon_deg, alt_m) -> ECEF [X, Y, Z] meters."""
    lat, lon, h = np.radians(lla[0]), np.radians(lla[1]), lla[2]
    sin_lat, cos_lat = np.sin(lat), np.cos(lat)
    n = WGS84_A / np.sqrt(1.0 - WGS84_E2 * sin_lat**2)
    return np.array([
        (n + h) * cos_lat * np.cos(lon),
        (n + h) * cos_lat * np.sin(lon),
        (n * (1.0 - WGS84_E2) + h) * sin_lat,
    ])


def enu_from_lla(origin_lla, lla) -> np.ndarray:
    """Exact ENU meters of `lla` relative to `origin_lla`."""
    lat0, lon0 = np.radians(origin_lla[0]), np.radians(origin_lla[1])
    d = ecef_from_lla(lla) - ecef_from_lla(origin_lla)
    sin_p, cos_p = np.sin(lat0), np.cos(lat0)
    sin_l, cos_l = np.sin(lon0), np.cos(lon0)
    rot = np.array([
        [-sin_l,          cos_l,          0.0],
        [-sin_p * cos_l, -sin_p * sin_l,  cos_p],
        [ cos_p * cos_l,  cos_p * sin_l,  sin_p],
    ])
    return rot @ d


@dataclass(frozen=True)
class Pose:
    """A station's surveyed pose in the field frame (D4 IF-2 survey group)."""
    pos_enu: tuple          # (E, N, U) meters
    heading_deg: float      # sighting-rail azimuth, true north = 0, CW +
    boresight_el_deg: float = 0.0
```

**File: config/field/rcrc.yaml**

```yaml
# RCRC site geometry (D1 operating site; survey values per D4 IF-2 example).
# Phase 0 survey supersedes these numbers; update this file + station TMATS
# together, never one without the other.
site:
  name: RCRC
  address: 4100 Leeman Ferry Rd
  approx_lla: [34.685, -86.592]

field_origin:            # Station A survey mark = field-frame origin
  lla: [34.6851710, -86.5922440, 183.2]

stations:
  A:
    lla: [34.6851710, -86.5922440, 183.2]
    heading_deg: 12.4
    boresight_el_deg: 8.0
  B:                     # ~75 m along the flight line; placeholder until survey
    lla: null
    heading_deg: null
  C:                     # near active threshold; placeholder until survey
    lla: null
    heading_deg: null

pattern_box:
  center_range_m: 150
  half_angle_deg: 60
```

Add `pyyaml` to `software/pyproject.toml` dependencies and reinstall
(`pip install -e "software[dev]"`).

**File: software/tests/test_geo.py** — write these three tests yourself;
the oracles are given:

1. *Known answer:* at φ₀ = 34.685°, one degree of longitude is
   `Δλ · (N(φ₀)+h) · cosφ₀` ≈ 91,671 m of East (compute the oracle in the
   test from the formula, don't hardcode a rounded number tighter than it
   deserves). `enu_from_lla` of a point 0.001° east must match the
   flat-earth value within 0.02 m.
2. *Flat-earth agreement:* random points within 300 m of the origin —
   exact ENU vs. flat-earth approximation agree within 5 mm. This bounds
   the error of intuition-level reasoning about the pattern box.
3. *Origin and symmetry:* `enu_from_lla(o, o)` is (0,0,0) to 1e-9;
   swapping origin/point negates E and N to first order (assert within
   1 mm over a 100 m displacement — the curvature residual).

## Verify

- `pytest software/tests/test_geo.py` passes all three tests.
- Sanity number to compute once in a REPL and eyeball: Station A to a
  point 150 m due north (add 150/111,132 ≈ 0.00135° latitude) comes back
  as ENU ≈ (0, 150, 0) within centimeters.
- `ruff check software` still clean; commit as
  `geo: field frame per D4 IF-4 + RCRC site config`.

## Explore

1. **Drop the (1−e²).** Remove it from `ecef_from_lla`'s Z term and watch
   which tests fail and by how much. The failure is ~135 m of Up at this
   latitude — invisible in E/N over short baselines, which is exactly why
   untested geodesy code survives until someone trusts altitude.
2. **Quantify GS-004.** Perturb Station B's assumed position by 0.1 m and
   heading by 0.2° in a two-ray triangulation sketch (two poses, rays to a
   point at 150 m; solve the crossing). How much does the fix move?
   Compare with D3's σ_range formula. Keep the script; it becomes part of
   your lesson-12 intuition.
3. **Close a TBD path.** The rcrc.yaml `pattern_box` block is where D2's
   SYS-010 TBD ("field-rule geometry digitized during Phase 0 survey")
   will land as polygons. Sketch the schema you'd want for
   `no_fly_polygons` now, as a comment in the file — lesson 24 consumes
   it.

## Checkpoint

- `maiden.geo.enu_from_lla` and `Pose` exist with the pinned signatures;
  `pytest software/tests/test_geo.py` passes.
- `config/field/rcrc.yaml` exists with Station A's survey values and
  explicit nulls for B and C awaiting the Phase 0 survey.
- You can state from memory: field frame origin, axis convention, where a
  station's heading lives, and why 0.2° of heading is ~0.5 m at the
  pattern box.
