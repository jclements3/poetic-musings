# maiden19 — Candidate pipeline [desk]

**Sprint goal** — Build the candidate-generation front half of
`maiden.track` — temporal-median sky model through connected components —
plus the metrics harness, and measure recall against twin truth including
the sun-crossing dip.

**Depends on** — maiden18 (rendered frames + labels).

**Read first** — lesson10.md: *Why classical candidates before any
learned detector*, *Features that separate aircraft from junk*, and the
`candidates.py` / `metrics.py` blocks in *Build*.

## Tasks

- [x] Implement `software/maiden/track/candidates.py`: `SkyModel`
      (rolling temporal median + per-pixel σ over N≈25 strided frames,
      NumPy so it stays inspectable) and
      `propose(residual, sigma, k=4.0, min_area=3)` — threshold →
      morphology (open 3×3, close 5×5, OpenCV) →
      `connectedComponentsWithStats` → `Candidate(u, v, area, bbox,
      contrast, coherence)`.
- [x] Fill `coherence` from a one-frame memory of candidate centroids
      (nearest-neighbor displacement); keep it simple — maiden20 replaces
      it with real gating.
- [x] Implement `software/maiden/track/metrics.py`: recall vs. target
      size bins (≥ 6 px, 4–6 px, < 4 px), false candidates per frame, and
      a recall-vs-time trace — structured so it accepts tracks later
      without change (maiden21 depends on that).
- [x] Write `software/tests/test_candidates.py`: known blob proposed,
      sub-`min_area` blob not, σ-adaptive threshold tracks a doubled
      noise floor, plus the CI-cheap end-to-end: clean-sky twin recall
      ≥ 0.95 at ≥ 6 px.
- [x] Sun run: re-render with the sun on the path, plot the
      recall-vs-time trace, and log dip depth and width to
      `results/VT-15/twin/`.
- [x] Time the candidate stage on 1080p30 input; note frames/sec in the
      same results file (SYS-011 will ask).

## Done when

- `pytest software/tests/test_candidates.py` passes.
- Clean-sky candidate recall at ≥ 6 px ≈ 1.0, false candidates ≪ 1/frame
  on twin imagery (if not, suspect threshold units or morphology erasing
  small targets).
- The sun-crossing dip is measured, plotted, and logged in
  `results/VT-15/twin/` with throughput noted — twin evidence, labeled as
  such.

## Doc trace

SW-002 (front half + harness), VT-15 (twin rehearsal / CI proxy — never
conflated with the field subset), D5 risk R1 (the dip, quantified),
SYS-011 (throughput note).

**Build notes (executed).** All green; evidence
in `results/VT-15/twin/candidates.md` + `recall_trace.png` (real runs,
seed 0): clean-sky recall ≥6 px **0.985**, false/frame 0.00; sun-on-path
recall 0.901 with windowed recall bottoming at **0.43** during the disc
crossing (R1 quantified). Throughput 1080p single core: sky update
112 ms/f (amortized ~37 ms/f at stride 3), residual+propose 8.8 ms/f
(114 fps) — 30 fps overall needs ROI-around-tracks or downscaled
proposal, noted for maiden20. Median depth n=25/stride 3 defended in the
docstring; end-to-end test runs at 960×540 with intrinsics scaled
(quarter-res puts the whole flight below the 6 px bin — resolution and
fx scale together or size bins lie).
