# Lesson 21 — Airborne Truth Logger [bench]

*Where we are.* The ground segment is built (lesson 20) and the software
pipeline scores twin flights end to end. What MAIDEN cannot yet do is
*prove itself*: SYS-002/003/004 are verified against 6-DOF truth, and truth
comes from an instrumented aircraft — yours, only during validation
(D1 scenario S3). This lesson builds that instrument: a flight controller
that never controls anything, strapped to the CG, logging GNSS, IMU, and
baro at rates the EKF residuals can lean on. Lesson 22 teaches its logs to
speak Ch. 10.

## Objectives

- Configure a Matek H743 running ArduPlane as a *log-only* device: no
  outputs, no arming dependence, EK3 attitude running, AB-001 rates met.
- Choose GNSS per airframe: M10 on the pattern ship, F9P/RTK option on the
  larger sport airframe — and act on D2's TBD about tightening SYS-002/003
  if RTK flies.
- Build the mount: 3D-printed CG cradle with foam isolation; verify the
  isolation with the IMU's own log.
- Weigh the installed system against AB-003 and retire VT-13.
- Bench-log 10 minutes and retire VT-08 with a message-rate inspection
  script you write against pymavlink.

## Concepts

### A flight controller that doesn't fly anything

D6 Option 1 is deliberately unclever: an autopilot board is the cheapest
integrated GNSS+IMU+baro logger with mature logging firmware, so run
ArduPlane and simply never let it touch a servo. The parameter strategy:

- **Log always:** `LOG_DISARMED = 1` — logging starts at power-up, no
  arming, no RC link required. (A safety switch or none: there is nothing
  to make safe.)
- **Log the right messages:** `LOG_BITMASK` must enable at least GPS,
  IMU, BARO, and ATT/attitude. Bit meanings move between firmware
  versions — set it from the ground station UI's named checkboxes, then
  *verify measured rates with the VT-08 script* rather than trusting any
  table (this course included).
- **Rates:** AB-001 wants GPS ≥ 10 Hz, IMU ≥ 100 Hz, baro ≥ 10 Hz. GPS
  rate is a GNSS receiver setting (`GPS_RATE_MS = 100`; confirm the M10
  actually delivers 10 Hz with your constellation config — some configs
  cap at 5 Hz with all constellations enabled). IMU logging at ≥ 100 Hz
  may require the fast/raw IMU logging option on your firmware version;
  again, the VT-08 script is the arbiter, not the wiki.
- **Attitude:** leave EK3 running. The ATT messages are the EKF's fused
  roll/pitch/yaw — that is the "ATT is the EKF attitude" note in D4
  IF-3's table, and it is what `att_rpy` on TRUTH StateSamples means.
  Honesty consequence for D8: attitude truth is itself an estimate, good
  to a degree or two, so attitude residuals in lesson 14's tables are
  informative, not gating — SYS-002/003/004 gate on position, velocity,
  and continuity only.

### GNSS grade and the RTK question

D2 carries a TBD: SYS-002/003 thresholds were set loose enough for
consumer GNSS truth (1–3 m — the D3 margin note) and should tighten if
RTK flies. The two-airframe plan from D6/D7 resolves it: the larger sport
airframe carries an F9P with a base station (RTK: centimeter truth; the
1.0 m RMS requirement is then genuinely testable), the small pattern ship
carries the M10 and eats the looser truth. Decide now, because lesson 99's
campaign plan and the D2 revision both hang on it. Whatever you decide is
a D2 commit per D5 change control — requirement changes are commits
touching D2 plus the affected D7 rows, in the same commit.

### Mass, CG, and vibration

AB-003's 60 g exists because of risk R5: a pattern ship trims differently
with a lump on it, and validation flights must be representative flying.
Budget lines to weigh (yours will differ — weigh, don't copy): H743
board, GNSS puck + cable, power tap (BEC from the flight pack, or its own
1S), cradle, foam, straps. The cradle: 3D-printed, mounts at the CG,
IMU axes aligned with airframe axes (record the mounting rotation in the
cradle's CAD and in `config/aircraft/` — lesson 22's converter needs it).

Foam isolation is not optional decoration. Log-only or not, a hard-mounted
IMU on a glow/electric airframe clips, and clipped accelerometers corrupt
EK3's attitude — your attitude truth. The check is free: ArduPilot logs
clipping counts (VIBE messages); the VT-08 script prints them, and the
acceptance is zero clips during a bench motor run-up.

### Option 2, written down like an engineer

D6 names a fallback: a standalone GNSS+IMU logger if Option 1 busts 60 g
on the pattern ship. Decision criteria, so the choice is mechanical, not
agonized: Option 1 loses if (a) installed mass > 60 g on the pattern
ship's scale, or (b) the pattern ship's CG can't be restored with the
cradle at the designated bay. If either trips: fly Option 1 on the large
airframe only, put a `.ubx`-logging M10 (D4 IF-3 already lists the pyubx2
path) on the pattern ship, accept GPS-only truth there, and record the
whole decision as commits to D6 and D7 per D5 change control. Attitude
residuals then simply have no truth on pattern-ship flights — D8's tables
get a dash, not a fudge.

## Doc Trace

- **Implements:** AB-001 (rates), AB-003 (mass) — the airborne segment of
  D3.
- **Governed by:** D6 "Airborne 6-DOF truth logger" (Option 1/Option 2,
  cradle, Sep decision), D4 IF-3 (which log messages the converter
  expects), D1 S3 (the operational scenario this hardware exists for).
- **Verified by:** VT-08 (rates and content, bench) and VT-13 (installed
  mass, inspection) — both retired here. AB-002 (time convertibility) is
  lesson 22's.
- **Closes:** the D6 "option decision by Sep" TBD and (by explicit
  revision) D2's RTK TBD on SYS-002/003.
- **Risks:** R5 (mass/CG — mitigated by budget and the fly-large-first
  campaign order in D7).

## Build

1. **Bench bring-up.** H743 + M10 on the bench, ArduPlane flashed, USB
   power. Set the log-only parameter set; save it as
   `config/aircraft/<airframe>/logger.param` — parameters are calibration
   data and live in CM like intrinsics do (same D5 rule as lesson 20's
   per-serial files).
2. **The VT-08 script.** Write `software/maiden/convert/inspect.py` (CLI:
   `maiden log-inspect FILE.bin`): open the DataFlash log with pymavlink,
   and for each of GPS/IMU/BARO/ATT print message count, mean rate,
   largest gap, plus VIBE clip counts. This is deliberately the first
   file in `convert/` — lesson 22 grows the package around it, and you
   will run it after every campaign flight per D7's flight card.
3. **Power tap.** Decide flight-pack BEC vs. dedicated 1S; either way,
   brownout during a hard maneuver kills a truth log mid-flight, so add
   the logger's supply to the preflight card (voltage check) and confirm
   the H743's log survives an input transient on the bench.
4. **Cradle.** CAD + print the CG cradle with foam interface; record
   mounting rotation in `config/aircraft/`. Install in the large airframe
   first (D7 flies truth on the larger airframe first — R5 again).
5. **Weigh-in.** Scale photo of the complete installed kit (logger, GNSS,
   tap, cradle, foam, straps, cable).
6. **Decide GNSS/RTK** and make the D2/D6/D7 commits described above.
7. **Preflight card.** One laminated card: power on → GPS 3D fix + sat
   count → log file incrementing → clap in front of Station A (the D7
   flight-card sync event) → fly. Add the post-flight half: pull SD, run
   `maiden log-inspect`, note anomalies.

## Verify

**VT-08 — logger rates and content.** 10-minute bench log with GNSS
antenna at a window or outdoors, then a motor run-up segment (airframe
restrained). Pass = GPS ≥ 10 Hz, IMU ≥ 100 Hz, baro ≥ 10 Hz, no gaps
(largest gap < 3× nominal period per stream), zero IMU clips during
run-up. **Observe on bench**; commit the `maiden log-inspect` report to
`results/VT-08/`.

**VT-13 — installed mass.** Weigh the full installed kit. Pass = ≤ 60 g.
**Observe on bench**; scale photo and itemized table to `results/VT-13/`.

## Explore

1. **Truth of the truth.** Park the logger stationary for 30 minutes and
   histogram GPS position scatter. Compare against the D3 margin note's
   1–3 m consumer-GPS figure and against SYS-002's 1.0 m — with M10-only
   truth, how much of the residual budget is the *truth's* error? Write
   the answer into your D2 RTK decision commit message.
2. **Clock preview.** Find the GPS time fields in the GPS messages and
   the relationship to the log's internal microsecond timestamps —
   lesson 22 builds AB-002 on exactly this pair; sketch the mapping now.
3. **Vibration A/B.** Bench run-up with and without the foam interface;
   compare VIBE levels and clip counts. Keep both logs — the pair is your
   evidence if anyone (including future-you) proposes hard-mounting to
   save 4 g.
4. **Design friction, small:** D4 IF-3 says the converter's TMATS names
   "airframe, logger serial, mass, and mount position" — but nothing yet
   assigns airborne serials. Extend lesson 20's serial scheme
   (MAIDEN-AB-001…) and `config/aircraft/` schema, and fold it into D4/D6
   per D5 change control.

## Checkpoint

- A powered H743 + M10 kit logs from power-up with no RC, no arming, and
  `config/aircraft/<airframe>/logger.param` is committed.
- `maiden log-inspect` exists, runs against a real `.bin`, and its VT-08
  report (all rates met, no gaps, zero clips) is in `results/VT-08/`.
- Installed kit weighed; VT-13 evidence in `results/VT-13/` at ≤ 60 g —
  or the Option 2 fallback is invoked with its D6/D7 commits made.
- The GNSS/RTK decision is committed to D2 (thresholds confirmed or
  tightened) with matching D7 rows.
- Preflight/post-flight card printed and in the field case.
- D8's rows for VT-08 and VT-13 are filled.
