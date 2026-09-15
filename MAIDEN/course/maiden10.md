# maiden10 — The Sportsman script [desk]

**Sprint goal.** Compose the primitives into `sportsman()` flying inside
D1's pattern box, emitting 100 Hz truth plus maneuver-boundary Events, and
prove physical sanity with the physics-police test suite and a plot you
actually look at.

**Depends on:** maiden09.

**Read first:** lesson06.md §Concepts (*Imperfections*), the `sportsman()`
docstring in §Build, and all of §Verify.

## Tasks

- [x] Implement `sportsman(imp, seed)` in `twin/model.py`: takeoff leg,
      upwind entry, loop, roll, stall turn, Immelmann, level legs between,
      landing approach — placed per D1 (box center ~150 m north of the
      origin, altitude 30–120 m, speeds 15–35 m/s).
- [x] Emit `MANEUVER_START`/`MANEUVER_END` Events with
      `data={"maneuver": name}` at every boundary.
- [x] Wire the `Imperfections` knobs so they demonstrably deform the path
      (loop_ovality, roll_drift_deg, alt_mismatch_m, center_offset_m).
- [x] Complete `software/tests/test_twin_model.py` per the lesson's
      physics-police list: speed ∈ [2, 40] m/s (floor only inside the
      stall-turn Event window), |a + g| ≤ 4 g, step continuity
      ≤ 1.5·v_max·DT, loop closure ≤ 2 m + coplanarity, box containment,
      seed determinism.
- [x] Write `python -m maiden.twin.plot` (3D path + plan view, boundaries
      marked from Events) and look at it.
- [x] Explore 1 at minimum: overlay `ovality=0.15` against the ideal loop
      and note the visible difference.

## Done when

- `pytest software/tests/test_twin_model.py` is green in full.
- Events bracket every maneuver with correct names and times (a test walks
  Event pairs and checks nesting/order).
- The plot exists, has been eyeballed, and the loop is not a potato.
- Same seed → identical arrays (this is what maiden28's CI cache keys on).

## Doc trace

SW-004 (truth half complete) · D6 §Digital twin · D1 §Operating site ·
feeds maiden11 (sensors), maiden25 (EKF residuals), maiden51/52 (labels).
