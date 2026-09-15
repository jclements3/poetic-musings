# maiden02 — The field frame [desk]

**Sprint goal.** Implement the D4 IF-4 field frame — exact WGS-84
LLA→ECEF→ENU — as `maiden/geo.py`, capture the RCRC site geometry in
config, and prove the math with known-answer tests.

**Depends on.** maiden01.

**Read first.** lesson01.md §Concepts (*The ellipsoid*, *ECEF → local
ENU*, *From ENU to the field frame*) and §Build.

## Tasks

- [x] Write `software/maiden/geo.py`: `ecef_from_lla`, `enu_from_lla`
      (pinned signature `enu_from_lla(origin_lla, lla)`), and the frozen
      `Pose` dataclass (`pos_enu`, `heading_deg`, `boresight_el_deg`) —
      complete file given in lesson 01 §Build; type it, don't paste it,
      and narrate the `(1-e²)` Z term to yourself as you do.
- [x] Write `config/field/rcrc.yaml`: site block, `field_origin` = Station
      A survey mark (34.6851710, -86.5922440, 183.2), Station A
      heading 12.4° / boresight 8.0°, explicit `null`s for B and C,
      `pattern_box` block. Add `pyyaml` to pyproject and reinstall.
- [x] Write `software/tests/test_geo.py` — the three tests specified in
      lesson 01 §Build: known-answer (1° longitude oracle from the
      formula), flat-earth agreement ≤ 5 mm within 300 m, origin/symmetry.
- [x] REPL sanity check: point 150 m due north of Station A returns
      ENU ≈ (0, 150, 0) within centimeters.
- [x] Explore 1 (drop the `(1-e²)`) — measured: ~0.5 m Up error at 150 m,
      not the predicted ~135 m; the ellipsoid error mostly cancels in the
      ENU *difference* (the ~24 km absolute-Z error cancels between origin
      and point). Still fails the known-answer test, which is the point.
      Put back. Explore 2 run too: 0.2° B-heading error moves the fix
      1.21 m at 150 m (D3 law predicts 1.05 m — same order).
- [ ] Commit: `geo: field frame per D4 IF-4 + RCRC site config`.

## Done when

- `pytest software/tests/test_geo.py` passes all three tests;
  `ruff check software` clean.
- `rcrc.yaml` parses (`yaml.safe_load`) and carries Station A's values
  with B/C explicitly null awaiting the Phase 0 survey.
- You can state from memory: frame origin, axis convention, where a
  station's heading lives, and why 0.2° of heading ≈ 0.5 m of cross-range
  at 150 m (D3's R²σ_θ/B law).

## Doc trace

D4 IF-4 (field frame definition) · GS-004 (survey precision this math
makes meaningful; VT-06 executes at maiden44) · D1 §Operating site ·
D3 §Fusion concept.
