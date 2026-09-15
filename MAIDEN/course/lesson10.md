# Lesson 10 — Video Tracker I: Candidates [desk]

*Where we are.* The geometry chain is proven: given a pixel, you can say
where in the sky it points. Now you have to *find* the pixel. D5's risk
register puts this problem at the top — R1: a small aircraft against a
bright sky is the highest-rated technical risk in the project — and the
mitigation it prescribes is the one you'll execute: twin-generated imagery
early, so the tracker is built and measured against ground truth long
before the first field frame exists. This lesson grows the twin a
renderer, then builds the candidate-generation front half of `maiden.track`.
Lesson 11 turns candidates into tracks.

## Objectives

- Extend the twin with `twin/render.py`: synthetic station video with a
  gradient sky, optional sun disc, and the aircraft as a blob of
  *physically correct* pixel size — closing the "frames later" gap
  lesson 07 declared.
- Build the candidate generator: temporal-median sky model, frame
  differencing, morphology, connected components.
- Compute per-candidate features — area, contrast, motion coherence —
  that lesson 11's detector will score.
- Measure candidate recall against twin truth at the SW-002 floor
  (targets ≥ 6 px) and build the metrics harness that VT-15 will reuse.

## Concepts

### How big is the target, actually

Lesson 09 gives the answer in one line: a 1.5 m span at range R subtends
`span/R` radians ≈ `fx·span/R` pixels. Numbers to keep loaded:

```
  lens        fx      @150 m   @300 m   @415 m
  60° (A,C)  ~1663     17 px     8 px     6 px
  35° (B)    ~3050     31 px    15 px    11 px
```

So SW-002's "≥ 6 px" floor corresponds to roughly the far edge of the
pattern box for the wide lenses — the requirement and the geometry agree,
which is worth noticing. Below ~6 px, a foam aircraft is a handful of
gray pixels distinguishable from a bird mostly by kinematics, which is
the tracker's job (lesson 11), not the detector's.

### Why classical candidates before any learned detector

D6 sketches a two-stage tracker: cheap candidate proposal, then a
detector to confirm. The proposal stage exploits what is *always* true of
this problem: the sky background changes slowly (minutes — clouds) while
the target changes fast (frame to frame), and the camera is on a tripod,
not a gimbal. That makes background subtraction nearly ideal:

```
  frames ──> temporal median (N≈25, strided) ──> |frame − median|
         ──> threshold (k·σ of residual)     ──> open/close morphology
         ──> connected components            ──> candidates (u, v, area, …)
```

A temporal *median* (not mean) ignores the target's own transit through a
pixel; a per-pixel σ makes the threshold adapt to sky gradient and sensor
noise. Morphological opening kills single-pixel noise; closing heals a
target the differencing split in two. Everything here is O(pixels) and
runs comfortably faster than 30 fps on the processing host — measure it,
because SYS-011's 10-minute report budget spends most of its time in
video.

The sun is the R1 sting: a sun disc in frame saturates pixels, blooms,
and drags the local σ up until real targets sit below threshold. You will
render it on purpose and watch recall dip in that window. The classical
mitigations (mask saturated regions, per-region thresholds) go in
Explore; the honest lesson is *knowing where the dip is*, with numbers.

### Features that separate aircraft from junk

For each connected component, compute now (cheaply) what lesson 11 scores:

- **area** in px and bbox — compared against the expected size from
  range (when a track exists to supply range, a later refinement).
- **contrast** — mean |residual| inside the component over local σ.
- **motion coherence** — displacement of the component's centroid vs.
  the nearest candidate in the previous frame: aircraft move smoothly at
  tens of px/frame; noise twinkles in place; insects streak.

### The renderer is a model, and says so

`twin/render.py` is not a graphics engine: gradient sky + Gaussian-blurred
ellipse for the airframe + optional sun disc + per-pixel Gaussian noise.
That is enough to exercise every stage above with exact ground truth, and
*not* enough to claim VT-15 field performance — the lesson text and D6
both say the learned detector waits for labeled field frames. State the
model's limits in its docstring; honesty about synthetic data is a
DO-254-flavored habit MAIDEN keeps.

## Doc Trace

- **SW-002** sets the target spec (az/el with confidence, ≥ 6 px, bright
  sky); this lesson builds the front half and the measurement harness.
- **VT-15** is the eventual verdict (recall ≥ 90 %, false tracks ≤
  1/min); today's twin-based numbers are its rehearsal and its CI proxy —
  recorded as such in `results/VT-15/twin/`, never conflated with the
  field subset D7 calls for.
- **D5 risk R1** — this lesson *is* the register's mitigation row
  ("twin-generated training data early"); the sun-crossing recall dip you
  will measure is the risk, quantified. The narrower-lens-on-B and
  polarizer trials in that row are hardware mitigations for lesson 20.
- The renderer closes the gap explicitly deferred in lesson 07's
  Checkpoint; the Ch 2 video channel it writes follows IF-1.

## Build

**`software/maiden/twin/render.py`** (skeleton):

```python
@dataclass
class RenderConfig:
    width: int = 1920; height: int = 1080; fps: int = 30
    sky_top: float = 0.55; sky_horizon: float = 0.95   # luminance 0..1
    noise_sigma: float = 0.01
    sun_azel: tuple[float, float] | None = None        # None = no sun
    span_m: float = 1.5

def render_session(truth, station, model, pose, cfg) -> Iterator[Frame]:
    """Frame = (t_utc, image uint8 HxW, truth_px: (u, v, size_px) | None).
    Projects each truth sample with azel_to_px (lesson 09); target drawn
    as a blurred ellipse of size fx*span/R px; truth_px is the label."""
```

Wire it into the twin CLI: `maiden twin --render A` writes station A's
Ch 2 video (H.264 via imageio/pyav, IPTS per frame per IF-1) and a
`labels_A.npz` of per-frame truth pixels. Rendering three stations at
1080p30 is slow-ish; rendering only-when-asked keeps lesson 07's fast
path fast.

**`software/maiden/track/candidates.py`** (skeleton):

```python
@dataclass
class Candidate:
    u: float; v: float; area: int; bbox: tuple[int, int, int, int]
    contrast: float; coherence: float | None   # None on first sighting

class SkyModel:
    """Rolling temporal median + per-pixel sigma over N strided frames."""
    def update(self, image): ...
    def residual(self, image) -> np.ndarray: ...

def propose(residual, sigma, *, k=4.0, min_area=3) -> list[Candidate]:
    """threshold -> morphology (open 3x3, close 5x5) -> components."""
```

Use OpenCV for the morphology and `connectedComponentsWithStats`; keep
the sky model in NumPy so its behavior is inspectable. Coherence gets
filled by a one-frame memory of candidate centroids (nearest-neighbor
displacement); leave the plumbing simple — lesson 11 replaces it with
real gating from the Kalman tracks.

**`software/maiden/track/metrics.py`** — the harness both tracker lessons
share: given per-frame candidates (later: tracks) and `labels_*.npz`,
report recall vs. target size bins (≥ 6 px, 4–6 px, < 4 px), false
candidates per frame, and a recall-vs-time trace that makes the
sun-crossing dip visible.

**`software/tests/test_candidates.py`**: unit tests on synthetic arrays
(a known blob on flat sky is proposed; a blob below `min_area` is not;
σ-adaptive threshold tracks a doubled noise floor), plus one end-to-end
twin sequence with recall asserted ≥ 0.95 at ≥ 6 px in *clean-sky*
conditions — the CI-cheap subset.

## Verify

- `pytest software/tests/test_candidates.py` — green.
- Full run: render a twin Sportsman session for station A (clean sky) and
  run the harness. On the renderer's easy imagery, candidate recall at
  ≥ 6 px should be effectively 1.0 and false candidates ≪ 1 per frame —
  if not, the pipeline has a real bug (thresholding in the wrong units
  and morphology erasing small targets are the usual two).
- Sun run: re-render with `sun_azel` placed on the sequence's path
  (lesson 07's sun-crossing option) and plot the recall-vs-time trace.
  There *will* be a dip; record its depth and width in
  `results/VT-15/twin/` — that number is R1 made visible, and lesson 11
  inherits the job of shrinking it.
- Throughput: time the candidate stage on 1080p30 input; note frames/sec
  in the same results file (SYS-011 will ask).

## Explore

1. **Saturation mask.** Mask pixels within the sun's bloom (residual
   permanently high, or raw value ≥ 250) out of both σ estimation and
   proposal. How much of the recall dip returns? This is the first R1
   mitigation and it's ten lines.
2. **Median depth N.** Sweep the sky-model depth (9, 25, 75 frames).
   Short memories absorb the aircraft into the background on slow
   flybys (watch recall on the level-leg segments); long memories lag
   cloud motion. Pick a value and defend it in the docstring.
3. **Bird test.** Add a second, smaller mover to the renderer with
   flapping-style jittery motion. Does the coherence feature separate it
   from the aircraft, or does that separation have to wait for
   kinematics in lesson 11? Write down what you see — it sets honest
   expectations for field false-alarm rates.

## Checkpoint

- `maiden twin --render A` produces Ch 2 video frames plus a labels file,
  and the rendered target's pixel size matches the fx·span/R prediction
  (spot-check three ranges).
- `pytest software/tests/test_candidates.py` passes; clean-sky recall at
  ≥ 6 px ≈ 1.0 on the twin sequence.
- The sun-crossing recall dip is measured and logged in
  `results/VT-15/twin/`, with the plot.
- The metrics harness runs from one command and will accept tracks (not
  just candidates) without structural change — lesson 11 depends on it.
