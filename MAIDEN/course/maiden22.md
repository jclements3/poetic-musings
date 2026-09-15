# maiden22 — EKF core [desk]

**Sprint goal.** Build the extended Kalman filter's mathematical core —
predict, az/el update, and the two-ray initializer — with every Jacobian
proven against finite differences before it touches twin data.

**Depends on.** maiden02 (Pose, field frame), maiden08 (StateSample),
maiden21 (tracker az/el semantics). Desk only.

**Read first.** lesson12.md — all of *Concepts* ("Estimation in one
paragraph" through "Initialization: two rays, closed form") and the
*Build* implementation notes. Derive the az/el Jacobian rows and the
two-ray closed form by hand before opening the editor; the lesson insists
and it is right to.

## Tasks

- [x] Derive ∂az/∂(xs,ys,zs) and ∂el/∂(xs,ys,zs) on paper; check against
      lesson 12's "The Jacobian, fully" section.
- [x] Add `azel_to_unit(az, el, pose)` and `h_azel(p, pose)` helpers
      (in `geo.py` or a `fuse`-private module — same math, inverted).
- [x] Implement `EkfConfig` and the `Ekf` class in
      `software/maiden/fuse.py`: `predict(t)` (CV model F, white-accel Q
      per axis), `update_azel(z, pose)` with the az innovation wrapped to
      [−π, π], `state` / `cov` properties.
- [x] Implement `init_two_ray(za, zb, pose_a, pose_b, t)` with the
      closed-form closest-points solution and the 1−c² parallel-ray guard;
      seed P from σ_v = 30 m/s and the D3 σ_range ≈ R²σ_θ/B geometry.
- [x] Write `software/tests/test_fuse_azel.py::test_jacobian_azel`:
      analytic H vs central finite differences over random states and
      poses, 1e-6 relative agreement.
- [x] Write the init test: zero-noise rays recover a known point to
      numerical precision; 0.5 mrad noise at 150 m / 75 m baseline gives
      error of order the D3 σ_range.
- [x] Keep every matrix explicitly shaped — no silent (6,) vs (6,1)
      broadcasts.

## Done when

- `pytest software/tests/test_fuse_azel.py` passes, including the
  finite-difference Jacobian test (non-negotiable) and both init cases.
- The az innovation wrap is implemented and you can say why it exists.
- `Ekf` conforms to the lesson 12 skeleton so maiden23's driver can use
  it unchanged.

## Doc trace

SYS-001, SYS-002 (sim rehearsal only — VT-10 binds in the field);
D3 §Fusion concept; D6 §Fusion EKF (v_r, lagging, covariance publication
deferred to maiden24–25).

---
**Build note (executed).** `software/maiden/fuse.py` Ekf core; both
Jacobians FD-verified to 1e-6; init recovers a known point to 1e-9 m
(zero noise) and to D3's σ_range order (0.5 mrad, 150/75 m); parallel-ray
guard tested on the baseline extension; az-wrap trap unit-tested. Joseph
form throughout; every matrix explicitly shaped.
