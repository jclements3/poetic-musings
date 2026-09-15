# maiden16 — Camera model [desk]

**Sprint goal** — Turn a pixel coordinate into a direction in the field
frame: implement `maiden/camera.py` with the project's pinned az/el
convention, tested and TMATS-connected.

**Depends on** — maiden02 (`Pose`, rotation helpers), maiden05 (TMATS
parser for `C\MAIDEN\CAM` attributes), maiden08 (`state.py`, which will
cite the convention docstring).

**Read first** — lesson09.md: *The pinhole model, honestly*, *From camera
frame to az/el*, *Why 0.5 px is the number that matters*, and the
`camera.py` block in *Build*.

## Tasks

- [x] Implement `software/maiden/camera.py`: frozen `CameraModel`
      dataclass (fx, fy, cx, cy, k1, k2) with `from_tmats`,
      `undistort` (3 fixed-point iterations), and `px_to_ray_cam`.
- [x] Implement `px_to_azel(model, pose, u, v)` and
      `azel_to_px(model, pose, az_deg, el_deg)` (returns `None` behind
      the camera), vectorized with NumPy from the start.
- [x] Write the pinned-convention docstring — az clockwise from true
      north (`atan2(E, N)`), el above local horizontal (`asin(U)`) — and
      add the cross-reference from `state.py`.
- [x] Write `software/tests/test_camera.py`: round-trip az/el↔px
      (< 1e-6 deg undistorted, < 1e-3 deg with the template's
      k1 = −0.112), the two convention anchors (heading 0 → principal
      point at az 0/el 0; heading 90 → az 90), and the TMATS loop
      (`CameraModel.from_tmats(parse(template).cam)` reproduces the
      template's numbers).

## Done when

- `pytest software/tests/test_camera.py` passes, convention anchors
  included.
- `azel_to_px` ∘ `px_to_azel` round-trips within the stated tolerances
  with distortion on.
- The convention docstring exists in `camera.py` and is cited from
  `state.py`.

## Doc trace

GS-005 (core), GS-004 (heading enters via `Pose`), IF-2
(`C\MAIDEN\CAM\*` names are contract), IF-4 ("station-frame azimuth" =
this convention), D3 §Fusion concept (σ_θ budget), VT-07 (verified in
maiden17).

**Build notes (executed).** 7 tests green
(`software/tests/test_camera.py`), incl. both convention anchors, a
boresight-el anchor, behind-camera None/NaN, and the TMATS loop against
the D4 template values. Cross-checked numerically against
`twin.sensors.azel_from_pos` (agreement < 1e-6 deg). Deviation: the
convention cross-reference *from* `state.py` is NOT yet added —
`state.py` was outside this sprint's allowed files; orchestrator to add
one docstring line citing `maiden.camera`'s convention block.
