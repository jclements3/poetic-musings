# maiden09 — Maneuver primitives [desk]

**Sprint goal.** Build the twin's five maneuver primitives — level leg,
loop, roll, stall turn, Immelmann — as parametric geometry with continuous
position and speed, plus the seam-asserting `concat`.

**Depends on:** maiden02 (`maiden.geo` rotation helpers), maiden08
(`Event` from `maiden.state`).

**Read first:** lesson06.md §Concepts (*Geometry, not aerodynamics — and
why that's enough*, *The primitives*) and the guidance paragraph after the
`model.py` skeleton in §Build. Skip §Imperfections and `sportsman()` —
those are maiden10.

## Tasks

- [x] Create `software/maiden/twin/model.py` from the lesson skeleton:
      `DT = 0.01`, the `Truth` dataclass (t, pos_enu, vel_enu, att_rpy,
      events), and the `Imperfections` dataclass (knobs wired but may be
      inert until maiden10 uses them).
- [x] Implement `level_leg` (trapezoidal speed profile) and `loop`
      (vertical-plane circle; support the `ovality` knob even if unswept).
      Build each in a local frame (+x along entry heading) and
      rigid-transform into the field frame with `maiden.geo`.
- [x] Implement `roll` (line + roll-angle slew), `stall_turn` (up-line,
      bleed to v_min ≈ 2 m/s, turnaround arc, down-line), and `immelmann`
      (half `loop` + half `roll` — by composition, not copy-paste).
- [x] Derive `vel_enu` analytically per primitive (no finite differencing
      of your own positions), and `att_rpy` from the path frame per the
      lesson's convention.
- [x] Implement `concat` with seam asserts: position gap < 1 mm, speed gap
      < 0.1 m/s at every joint.
- [x] Start `software/tests/test_twin_model.py` with per-primitive checks:
      loop start/end within 2 m and coplanar path; roll holds altitude and
      heading; stall turn's speed floor lands only inside its window.

## Done when

- All five primitives return `Truth` at 100 Hz and the per-primitive
  pytest cases pass.
- `concat` of any two primitives with matched entry/exit state passes its
  own seam asserts; a deliberately mismatched pair trips them (keep that
  as a test).
- An Immelmann is built from the loop and roll primitives — zero
  duplicated arc math.

## Doc trace

SW-004 (truth half, in progress) · D6 §Digital twin · box geometry
deferred to maiden10 · feeds maiden10–13, lesson 23 labels.
