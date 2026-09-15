# maiden23 — Two-station fusion run [desk]

**Sprint goal.** Drive the maiden22 filter over twin A+B data end to end,
tune the process noise, and show fused position tracking twin truth at the
accuracy D3's geometry predicts.

**Depends on.** maiden22 (Ekf core), maiden12 (twin .ch10 sessions),
maiden15 (ingest round-trip).

**Read first.** lesson12.md — *Build* (the `fuse_azel_only` skeleton and
implementation notes), *Verify*, and *Explore*. The scaling-law and
break-it exercises are part of this sprint, not optional garnish.

## Tasks

- [x] Implement `fuse_azel_only(samples, stations)`: sort by `t_utc`,
      init on the first A+B pair within one frame time, then
      predict-to-measurement and update sequentially (no stacked
      batching), emitting a FUSED `StateSample` (source `"FUSED"`,
      `pos_enu`, `vel_enu`, `cov`) after each update.
- [ ] Write `scripts/plot_fused.py`: truth vs fused E/N/U vs time plus a
      3D track overlay, saved to `results/lesson12/`.
- [x] Run the clean twin (noise on, dropouts off), A+B only; interpolate
      truth to fused timestamps; record position RMS in
      `results/lesson12/rms.txt`.
- [x] Tune σ_a: sweep 5/10/20/40 m/s², record RMS per setting, keep the
      winner in `EkfConfig` with a comment citing the sweep.
- [x] Explore — scaling law: regenerate the twin at B = 25 m and
      B = 150 m; plot measured RMS vs baseline against σ_range = R²σ_θ/B
      and check D3's promised ~3× degradation at 25 m.
- [x] Explore — break it on purpose: disable the az innovation wrap,
      script a pass crossing behind Station A, watch the divergence,
      restore the wrap.

## Done when

- `fuse_azel_only` on the clean twin yields position RMS recorded in
  `results/lesson12/`, consistent with the D3 scaling (order 1 m or
  better at the nominal R ≈ 150 m, B = 75 m layout).
- The fused-vs-truth plot shows no divergence through the full twin
  sequence, including the az-wrap crossing.
- The σ_a sweep results are committed and the chosen value documented.
- Velocity RMS is honestly mediocre — angles only, per the lesson; that
  gap is maiden24's motivation, not a bug.

## Doc trace

SYS-001 first demonstrated end-to-end (twin data); SYS-002 rehearsal
(VT-10 binds only in the field, lesson 99); D3 §Fusion concept scaling
verified by the baseline sweep.

---
**Build note (executed).** Clean A+B run: pos RMS 0.520 m, vel RMS
2.974 m/s (angles-only mediocrity as predicted). σ_a sweep
5→1.201 / 10→21.945 / 20→0.520 / 40→0.548 m: the σ_a=10 outlier is a real
gating death-spiral episode (over-confident filter gates good
measurements after the stall turn and diverges) — kept in rms.txt as a
cautionary datum. Baseline sweep and the az-wrap drill are automated in
`software/tests/test_fuse_pipeline.py`; plots regenerate from that suite
into `results/lesson12/`, so no separate `scripts/plot_fused.py` was
written (box left unticked; add it if a standalone script is wanted).
