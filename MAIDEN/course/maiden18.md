# maiden18 — Twin frame renderer [desk]

**Sprint goal** — Grow the twin a renderer so tracker work has
ground-truthed imagery: gradient sky, optional sun disc, and the aircraft
as a blob of physically correct pixel size.

**Depends on** — maiden12 (`maiden twin` CLI to extend), maiden16
(`azel_to_px` does the projecting).

**Read first** — lesson10.md: *How big is the target, actually*, *The
renderer is a model, and says so*, and the `twin/render.py` block in
*Build*.

## Tasks

- [x] Implement `software/maiden/twin/render.py` per the lesson skeleton:
      `RenderConfig` (1920×1080@30, sky gradient, `noise_sigma`,
      `sun_azel`, `span_m = 1.5`) and
      `render_session(truth, station, model, pose, cfg)` yielding
      `(t_utc, image, truth_px)` frames — target drawn as a
      Gaussian-blurred ellipse of `fx·span/R` px, `truth_px` as the label.
- [x] State the model's limits in the docstring (good enough to exercise
      the pipeline with exact truth; not evidence of field performance —
      the learned detector waits for labeled field frames).
- [x] Wire `maiden twin --render A`: writes station A's Ch 2 H.264 video
      (IPTS per frame per IF-1) plus `labels_A.npz` of per-frame truth
      pixels; rendering stays opt-in so maiden12's fast path stays fast.
- [x] Spot-check target pixel size at three ranges against the
      `fx·span/R` prediction (≈17 px at 150 m, 8 px at 300 m, 6 px at
      415 m for the 60° lens).

## Done when

- `maiden twin --render A` produces Ch 2 video frames plus the labels
  file on a full Sportsman session.
- The three-range pixel-size spot-check matches prediction.
- A sun-crossing render (`sun_azel` on the sequence's path) works —
  maiden19 measures its effect.

## Doc trace

SW-002 (the imagery its tracker is measured on), D5 risk R1
("twin-generated training data early" — this sprint is that row), IF-1
Ch 2, closes the frames gap lesson 07's Checkpoint deferred.

**Build notes (executed).** Renderer + labels
delivered; 5 tests green (`test_render.py`). Deviations, all documented
in `render.py`'s docstring: (1) Ch 2 carries one **JPEG per frame**
(dtype 0x40, IPTS = RTC), not H.264 TS — no encoder on the desk machine;
the real recorder (maiden41) owns H.264. (2) Video goes to a separate
`VIDEO_<st>_*.ch10` beside maiden12's station files, leaving the fast
path untouched (`--render A` opt-in; full session = 80 s, 221 MB,
validates TMATS-first with 62 time + 1857 video packets). (3) Sun is
drawn LAST so saturation clips the target — that ordering is the R1
mechanism, found when the first sun run showed no recall dip.
Single-camera label coverage in the scored window is 33% — D1's box is
±60° vs the 60° lens; full coverage is the 3-station union's job (test
asserts the honest number).
