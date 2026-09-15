# maiden11 — Sensor models [desk]

**Sprint goal.** Project twin truth through the three station Poses into
per-station az/el and v_r streams with defensible noise, dropouts, a
sun-crossing outage, and deliberately unaligned sample rates.

**Depends on:** maiden02 (`Pose`), maiden10 (truth to observe).

**Read first:** lesson07.md §Concepts (*From truth to measurement*, *Noise
you can defend*) and the `sensors.py` skeleton in §Build. The az/el
convention is pinned in lesson09.md (az clockwise from true north, el
above local horizontal) — use it here so the tracker and EKF agree later.

## Tasks

- [x] Create `software/maiden/twin/sensors.py` from the skeleton:
      `observe(truth, pose, *, rng, dropout_p, outage)` yielding
      `(t, az_deg, el_deg, conf)` at 30 Hz and `(t, v_r, snr)` at 50 Hz.
- [x] Implement the geometry: rotate d = p − s into the station frame by
      survey heading; az/el per the pinned convention; v_r = v·û with
      positive = receding.
- [x] Inject the lesson's calibrated noise: σ_θ = 0.5 mrad Gaussian on
      angles with conf ∈ [0.5, 1.0] tied to an SNR proxy; σ = 0.15 m/s on
      v_r. Keep both as named module constants with their provenance
      comments (D3 assumption; half of VT-04's criterion).
- [x] Add per-station Bernoulli dropouts plus the scripted multi-second
      Station B sun-crossing outage.
- [x] Keep tracker (30 Hz) and radar (50 Hz) clocks unaligned to each
      other and to the 100 Hz truth — no convenient time grids.
- [x] pytest spot check: target dead on Station A's boresight at known
      range receding at 10 m/s, zero noise → az ≈ 0, el ≈ boresight,
      v_r ≈ +10.

## Done when

- The boresight spot-check test passes with zero injected noise.
- With noise on, sample histograms match the declared σ values (a test
  asserts std within [0.7×, 1.3×] of nominal over a full sequence).
- The Station B outage and dropouts are visible in the stream (test counts
  gaps against the declared rates).
- All noise/dropout parameters are named constants with provenance
  comments — nothing magic.

## Doc trace

SW-004 · D3 Figure 2 geometry · D6 §Digital twin noise/outage clauses ·
feeds maiden12 (files) and maiden13 (Monte-Carlo).
