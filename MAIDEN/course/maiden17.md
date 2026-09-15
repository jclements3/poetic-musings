# maiden17 — Calibration drill [bench]

**Sprint goal** — Build the calibration script and run a real webcam
checkerboard calibration to the VT-07 standard, so the field procedure is
muscle-memory before the machine-vision cameras arrive.

**Depends on** — maiden16 (`CameraModel`, `px_to_azel`). No ordered parts:
any webcam and a printed 9×6 checkerboard qualify — this bench sprint is
never blocked by the maiden30 order.

**Read first** — lesson09.md: the `tools/calibrate.py` steps in *Build*,
*The field procedure this code serves*, and *Verify*.

## Tasks

- [ ] Implement `software/maiden/tools/calibrate.py`:
      capture-on-keypress to a session directory (~20 captures — fill the
      frame, tilt both axes, reach the corners).
- [ ] Fit with `cv2.findChessboardCorners` + `cornerSubPix` +
      `calibrateCamera`, distortion clamped to k1/k2
      (`CALIB_FIX_K3 | CALIB_ZERO_TANGENT_DIST` — fit only what TMATS
      carries).
- [ ] Hold-out check: fit on 3/4 of captures, reproject the held-out 1/4
      through your **own** `CameraModel` (cross-checks the
      distortion-order convention against OpenCV's); report RMS and max
      reprojection error.
- [ ] Emit the six `C\MAIDEN\CAM\*:value;` TMATS lines plus a JSON
      sidecar under `config/`, versioned per station serial (D5 CM).
- [ ] Run the drill on your webcam; log captures, JSON, and the reported
      error to `results/VT-07/practice/`.
- [ ] Round-trip: feed the emitted TMATS lines through the maiden05
      parser (and maiden14's `describe()` once it exists) and assert the
      recovered `CameraModel` equals the fitted one.
- [ ] Walk the D6 survey-and-calibration procedure on paper, mapping each
      step to the attribute it feeds (prep for maiden44).

## Done when

- The script runs capture → fit → hold-out → emit end-to-end on a webcam.
- Hold-out RMS reprojection ≤ 0.5 px (VT-07 criterion; more corner poses
  is the usual fix if above), logged with evidence in
  `results/VT-07/practice/` — practice run, clearly labeled; the formal
  run on real cameras is maiden44.
- Emitted TMATS lines round-trip through the parser byte-consistently.

## Doc trace

GS-005, VT-07 (practice evidence now, formal at maiden44), GS-004
(procedure walk-through), IF-2, D5 §CM (per-serial calibration files),
D6 §Survey and calibration procedure.
