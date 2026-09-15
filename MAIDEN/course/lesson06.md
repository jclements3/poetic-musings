# Lesson 06 — Digital Twin I: The Flight Model [desk]

*Where we are.* The plumbing exists: files, TMATS, time, and the IF-4
waist everything flows through. What does not exist is data. No station is
built, no aircraft instrumented, and per the SEMP that stays true for
months — which is exactly why D6 specifies a digital twin: a scripted
Sportsman flight whose truth *you* author, so fusion and scoring are
exercised long before the first real flight. This lesson builds the twin's
first half, the flight model: a kinematic script that flies an ideal (or
deliberately imperfect) Sportsman sequence through the pattern box and
emits 100 Hz truth arrays plus maneuver-boundary Events. Lesson 07 will
push this truth through sensor models into real `.ch10` files.

## Objectives

- State honestly what the twin models and what it does not.
- Build maneuver primitives — level leg, loop, roll, stall turn,
  Immelmann — as parametric geometry with continuous position and speed.
- Compose them into a Sportsman sequence flown inside D1's pattern box.
- Emit `pos_enu`, `vel_enu`, `att_rpy` at 100 Hz plus ground-truth
  maneuver Events for lesson 23's training labels.
- Prove physical sanity with pytest and one plot you actually look at.

## Concepts

### Geometry, not aerodynamics — and why that's enough

Be clear about the modeling level, because pretending otherwise poisons
every conclusion drawn from twin data. This is a *kinematic script*: the
aircraft is a point that follows curves you define, with attitude derived
from the path. There is no lift, no stall, no propwash. That would be
disqualifying if the twin's job were to predict how aircraft fly. Its job
(D6 §Digital twin) is to exercise the *measurement and estimation*
pipeline: geometry seen from three station poses, corrupted by noise you
inject, recovered by the EKF you'll write. For that, path realism matters
(curvature, speeds, g-levels must be plausible so filter tuning
transfers) and aerodynamic fidelity does not. Real validation against
real flight happens in lesson 99; the twin never substitutes for it.

### The primitives

Everything is built from arcs and lines in a vertical or horizontal
plane, traversed with a smooth speed profile:

- **Level leg.** Straight line at constant altitude, trapezoidal speed
  profile (accelerate, hold, decelerate) so velocity is continuous into
  the next figure.
- **Loop.** A circle of radius r in the vertical plane containing the
  current heading. Constant speed v gives centripetal acceleration
  a = v²/r; a Sportsman loop at 25 m/s with r = 40 m pulls ~1.6 g on top
  of gravity — keep total under ~4 g or the sanity tests should complain.
- **Roll.** Straight line, heading and altitude held, roll angle slewed
  0→360° at a constant roll rate over the leg's duration.
- **Stall turn.** Vertical up-line, speed bleeding to near zero
  (trapezoid down to v_min ≈ 2 m/s), a yaw pivot represented as a
  tight-radius turnaround arc, vertical down-line regaining speed.
- **Immelmann.** Half loop up, then half roll to upright: reuse the loop
  and roll primitives — composition is the point of primitives.

Attitude comes from the path frame: yaw from the horizontal velocity
direction, pitch from the climb angle, roll from the primitive's script
(zero in legs and loops, slewing in rolls). This is exactly the "ATT is
the EKF attitude" honesty D4 applies to real logs — the twin's `att_rpy`
is *consistent with* the path, not dynamically derived.

### Imperfections

An ideal sequence scores 10s, which makes it useless for testing a scorer.
D6 calls for *adjustable imperfections*: parameters that warp the ideal —
loop radius varying sinusoidally with phase (egg-shaped loop), heading
drift during a roll, entry/exit altitude mismatch, the whole sequence
displaced off the box center line. Build them as small, named knobs from
the start; lesson 23 will sweep them to generate labeled training data,
and lesson 99 compares their deduction signatures against real judges.

## Doc Trace

- **Implements:** the truth-generation half of SW-004.
- **Governed by:** D6 §Digital twin; box geometry and dimensions from D1
  §Operating site (pattern box ~150 m out, ±60° from center).
- **Verified by:** VT-17's first half — "run twin" — completed in lesson
  07 when the files exist; today's sanity tests are its groundwork.
- **Feeds:** lesson 07 (sensor projection), lesson 13 (EKF residuals vs
  twin truth), lesson 23 (training labels from the Events you emit today).

## Build

### `software/maiden/twin/model.py`  *(skeleton — the bodies are yours)*

```python
"""Scripted Sportsman flight model. Kinematic, not aerodynamic. SW-004."""
from dataclasses import dataclass, field
import numpy as np
from maiden.state import Event

DT = 0.01                        # 100 Hz truth

@dataclass
class Imperfections:
    loop_ovality: float = 0.0    # 0 = round; 0.1 = radius varies +-10%
    roll_drift_deg: float = 0.0  # heading drift across a full roll
    alt_mismatch_m: float = 0.0  # exit vs entry altitude error
    center_offset_m: float = 0.0 # sequence displaced along the box

@dataclass
class Truth:
    t: np.ndarray                # (N,) seconds from sequence start
    pos_enu: np.ndarray          # (N, 3)
    vel_enu: np.ndarray          # (N, 3)
    att_rpy: np.ndarray          # (N, 3) degrees
    events: list[Event] = field(default_factory=list)

def level_leg(p0, heading_deg, length_m, v0, v1, alt) -> Truth: ...
def loop(p0, heading_deg, radius_m, v, ovality=0.0) -> Truth: ...
def roll(p0, heading_deg, length_m, v, drift_deg=0.0) -> Truth: ...
def stall_turn(p0, heading_deg, upline_m, v_entry) -> Truth: ...
def immelmann(p0, heading_deg, radius_m, v, drift_deg=0.0) -> Truth: ...

def concat(parts: list[Truth]) -> Truth:
    """Join parts; assert C0 position and C0 speed continuity at seams."""
    ...

def sportsman(imp: Imperfections = Imperfections(), seed: int = 0) -> Truth:
    """The sequence, flown in the box: takeoff leg, upwind entry,
    loop, roll, stall turn, immelmann, level legs between, landing
    approach. Emits MANEUVER_START/MANEUVER_END Events with
    data={"maneuver": name} at every boundary."""
    ...
```

Guidance, not code: build every primitive in a local frame (start at
origin, fly along +x) and rigid-transform into the field frame with
lesson 01's rotation helpers — that keeps the trigonometry in one place.
Differentiate positions *analytically* per primitive (you know the curve;
don't finite-difference and then fight the noise you created). In
`concat`, assert seam continuity: position gap < 1 mm, speed gap
< 0.1 m/s — a fencepost in a time array shows up here first, exactly like
the theremin sequencer's off-by-one did.

Place the sequence per D1: box center ~150 m north of Station A's
eventual position (use the origin for now — station poses enter in
lesson 07), maneuvering altitude 30–120 m, speeds 15–35 m/s.

## Verify

`software/tests/test_twin_model.py` — the physics police:

- **Speed.** `norm(vel_enu, axis=1)` within [2, 40] m/s everywhere
  (the 2 m/s floor only inside the stall-turn window — find it via the
  Events, which incidentally tests the Events).
- **G-limit.** Finite-difference `vel_enu` to acceleration, add gravity,
  assert |a| ≤ 4 g everywhere.
- **Continuity.** Max position step between consecutive samples
  ≤ 1.5 × v_max × DT.
- **Loop closure.** From the loop's Events, take its samples; assert
  start/end positions within 2 m and the path's vertical-plane fit
  residual small (points should be coplanar).
- **Box containment.** Horizontal positions within D1's box (150 m ± the
  box depth, ±60° wedge) for the whole scored sequence.
- **Determinism.** Two calls with the same seed produce identical arrays.

Then the eyeball check — make a plot and *look at it*:

```bash
python -m maiden.twin.plot     # you write this: 3D path + plan view,
                               # maneuver boundaries marked from Events
```

A loop should look round, the stall turn like a hairpin, the sequence
centered. No captured output to match; your eyes are the instrument here,
and they are better at "that loop is a potato" than any assert.

## Explore

1. **Turn the knobs.** Generate `ovality=0.15` and overlay against the
   ideal loop. Can you see it at plot scale? Estimate the radius-variance
   number lesson 23's rubric will compute for it.
2. **Wind.** Add a constant wind-drift vector to the whole sequence (real
   pilots correct for it; your point-mass doesn't). Which sanity tests
   fire? What does that tell you about scoring in wind (D1 caps scored
   sessions at 15 kt)?
3. **A second sequence.** Script the student-pilot rectangular circuit
   from S2 (D1) out of legs and quarter-turn arcs. How much new code did
   composition require? That ratio is the primitives' report card.

## Checkpoint

- `sportsman()` returns 100 Hz `Truth` passing every sanity test;
  `pytest software/tests/test_twin_model.py` is green.
- Events bracket every maneuver with correct names and times.
- The plot exists, has been looked at, and the loop is not a potato.
- Imperfection knobs demonstrably deform the path.
- Same seed → identical output (lesson 15's CI will depend on this).
