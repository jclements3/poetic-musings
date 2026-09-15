# maiden21 — Track management & metrics [desk]

**Sprint goal** — Finish `maiden.track`: TENTATIVE/CONFIRMED/COASTING
track management, an honest `conf`, emission as StateSamples and Ch 5
packets, and the VT-15 rehearsal numbers on twin imagery.

**Depends on** — maiden20 (detector + `kalman2d`), maiden14/15 (ingest,
for the Ch 5 round-trip), maiden08 (`StateSample`).

**Read first** — lesson11.md: *Track management and the meaning of
`conf`*, *What twin numbers prove*, and the `tracker.py` / `emit.py`
blocks in *Build*.

## Tasks

- [x] Implement `software/maiden/track/tracker.py`: `StationTracker`
      with the state machine — TENTATIVE –(M of N, e.g. 3 of 5)→
      CONFIRMED –(miss)→ COASTING –(hit)→ CONFIRMED, dead after K ≈ 15
      consecutive misses; parameters in `TrackerCfg`, defaults = your
      tuned values.
- [x] Define `conf` ∈ [0, 1] as a bounded function of recent detector
      scores, track age, and frames-since-hit, monotonically decreasing
      while coasting; document it in the module docstring (fusion
      de-weights by it; D9's "wide band ≠ bad pilot" story traces here).
- [x] Implement `software/maiden/track/emit.py`: TrackOut →
      `StateSample(t_utc, source=station.id, az_deg, el_deg, conf)` via
      `px_to_azel`, and → Ch 5 packets via `payloads.TRACKER` — one code
      path, two sinks; only CONFIRMED (and flagged COASTING) tracks emit.
- [x] Write `software/tests/test_tracker.py`: state-machine units with
      scripted hit/miss sequences; conf monotone while coasting; the
      emission round-trip (track a twin sequence → write Ch 5 packets →
      `maiden.ingest.load` → ingested az/el/conf equal emitted); and the
      CI floor: clean-sky recall ≥ 0.90 at ≥ 6 px.
- [x] Sun-crossing run: compare track-level recall against maiden19's
      candidate-level trace; log dip depth, coast duration, and
      reacquisition delay to `results/VT-15/twin/`.
- [x] False-track pressure test: raised renderer noise + a jittery
      second mover; measure false confirmed tracks/min against VT-15's
      ≤ 1/min line, logged **with** the noise settings.

## Done when

- `pytest software/tests/test_tracker.py` passes, Ch 5 round-trip
  through a real Ch. 10 file included.
- Twin metrics logged in `results/VT-15/twin/`: recall ≥ 0.90 at ≥ 6 px,
  false tracks ≤ 1/min, sun-window numbers — each labeled twin evidence,
  field column open until the campaign.
- `TrackerCfg` defaults are tuned values with their sweeps committed, and
  you can state what `conf` means mechanically.

## Doc trace

SW-002 (completed in structure; field-grade verification stays open),
VT-15 (twin rehearsal + CI subset handed to maiden28), IF-1 Ch 5, IF-4,
D5 risk R1 (coasting is the software half of the mitigation).

---

**Execution notes (maiden21, desk).** All tasks done; 7 tracker tests
green including the Ch 5 round-trip through a real .ch10 (az/el to 1e-4°,
conf to 1e-6). Measured twin-rehearsal numbers (results/VT-15/twin/
tracks.md + track_recall_trace.png, TrackerCfg defaults): clean-sky track
recall ≥6px **0.985** (target ≥0.90); sun crossing **0.951** with the
candidate-level windowed dip 0.43 recovering to 0.77 at track level —
coasting bridged it, 16 coasted frames, reacquisition 0.03 s after dip
minimum (D5 R1 evidence); false tracks **0.00/min** over the full 1.0-min
session at 3× renderer noise (noise-only: renderer has no bird model —
lesson 10 Explore 3 stays open). conf is mechanically score_ema ×
age_ramp × 0.85^frames_since_hit, documented in tracker.py; the coasted-
emission decision (emit with decaying conf, not silence) is written into
emit.py's docstring per lesson 11 Explore 2. Explore 1 ran as the NIS
whiteness unit test; Explore 3 (two-target swap) not run — noted, Phase 2.
All evidence twin-only; VT-15's field column stays open.
