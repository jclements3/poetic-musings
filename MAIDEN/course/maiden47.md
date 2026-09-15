# maiden47 — Logger Build & Bench Log [bench]

**Sprint goal.** Bring up the H743 as a log-only truth instrument, write
the `maiden log-inspect` tool, retire VT-08, and make the GNSS/RTK
decision with its document commits.

**Depends on.** maiden30 (H743 + M10/F9P on hand). Independent of the
station sprints — can run in parallel with maiden40–46.

**Read first.** Lesson 21: *A flight controller that doesn't fly
anything*, *GNSS grade and the RTK question*, and Build steps 1–3 and 6.

**Tasks**

- [ ] Flash ArduPlane; set the log-only parameter set (`LOG_DISARMED = 1`,
      `LOG_BITMASK` covering GPS/IMU/BARO/ATT, `GPS_RATE_MS = 100`, EK3
      running); save as `config/aircraft/<airframe>/logger.param` —
      parameters are calibration data under D5 CM.
- [ ] Write `software/maiden/convert/inspect.py` with the
      `maiden log-inspect FILE.bin` CLI: per-stream message count, mean
      rate, largest gap, plus VIBE clip counts, via pymavlink. (This is
      deliberately the first file in `convert/` — maiden49 grows the
      package around it.)
- [ ] Decide the power tap (flight-pack BEC vs. dedicated 1S); confirm on
      the bench that a supply transient doesn't kill the log; add a
      voltage check to the preflight card draft.
- [ ] **VT-08:** 10-minute bench log, GNSS antenna at a window or
      outdoors, then a restrained motor run-up segment; run
      `maiden log-inspect` and commit the report to `results/VT-08/`.
- [ ] Lesson 21 Explore 1: 30-minute stationary log; histogram GPS
      scatter against D3's 1–3 m consumer-GPS note and SYS-002's 1.0 m —
      quantify how much residual budget the *truth's* error eats.
- [ ] **Decide GNSS/RTK** (F9P + base on the large airframe vs. M10-only)
      and commit the decision: D2 (SYS-002/003 thresholds confirmed or
      tightened, closing D2's TBD) with the affected D7 rows in the same
      commit, per D5 change control; note the scatter analysis in the
      commit message.
- [ ] Fill D8's row for VT-08.

**Done when**

- VT-08 pass: GPS ≥ 10 Hz, IMU ≥ 100 Hz, baro ≥ 10 Hz, largest gap < 3×
  nominal period, zero IMU clips during run-up — report in
  `results/VT-08/` (**observe on bench**).
- `logger.param` and `maiden log-inspect` committed and working against a
  real `.bin`.
- The RTK decision is a merged D2+D7 commit; the D6 "option decision by
  Sep" TBD is addressed or explicitly scheduled to maiden48's weigh-in.

**Doc trace.** AB-001; VT-08; D6 "Airborne 6-DOF truth logger", D4 IF-3
(ATT = EKF attitude), D1 S3; D2 TBD closure; D5 risk R5.
