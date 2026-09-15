# Lesson 15 — CI & the HIL Harness [desk]

*Where we are.* Every piece of the software track now exists: twin,
ingest, tracker, fusion, validation. What doesn't exist is the machinery
that keeps them working while you spend the next two months soldering.
D5's answer is the merge point of the two tracks: continuous integration
that replays the twin set — and, once lesson 20 delivers it, a recorded
bench HIL set — on every commit, failing the build if fusion accuracy
regresses. This is SW-005, and it is the difference between "it worked in
November" and "it works". This lesson also installs the D5 configuration-
management discipline you'll live under for the rest of the course.

## Objectives

- Stand up a GitHub Actions workflow: lint + unit tests + twin replay +
  regression gate on every push.
- Centralize the SYS-002/003/004 thresholds in one versioned config
  consumed by both CI and `maiden validate`.
- Design the HIL-set interface now (dataset arrives in lesson 20) with
  identical replay semantics and an explicit, loud skip while absent.
- Run the VT-18 drill: an injected fusion bug must turn the build red,
  with evidence filed.
- Adopt the D5 tagging and change-control discipline in the repo.

## Concepts

### What CI is for, here

The SEMP's twin-first strategy has a failure mode: software "done" in
October silently rots while you debug op-amps in November, and you
discover it at the field in December with three stations, one good
weather window, and a broken EKF. SW-005 exists to close that hole. The
principle: **the replay is the same command you run by hand** — CI is
just a machine that never forgets to run it. If the CI path and the human
path diverge, the CI path is decoration.

### The canonical twin set, and caching honestly

The regression gate needs fixed inputs. Define the canonical set as
(seed, twin config) — e.g., seeds 1001–1003, `--imperfect` — and let CI
regenerate it, cached. The cache key must include a hash of
`software/maiden/twin/` *source*, not just the seed: a cached dataset
from an older twin silently tests the wrong thing, which is worse than a
slow build. When the twin changes, the set regenerates, and — important —
the expected metrics may legitimately move. That is not a regression;
that is why thresholds are absolute (the SYS numbers), not
golden-file diffs of last week's RMS.

### One home for the thresholds

SYS-002/003/004 values are defined in D2 and nowhere else — but code
can't read an HTML table. Compromise, per the course's document
discipline: `config/thresholds.yaml` holds the numeric values, each line
carrying its requirement ID and a comment that D2 is the authority:

```yaml
# Values transcribed from D2 SyRS; D2 is the authority. A change here
# without a matching D2 revision is a process violation (D5 change control).
SYS-002: {pos_rms_m: 1.0, at_range_m: 150}
SYS-003: {vel_rms_mps: 1.0}
SYS-004: {continuity: 0.95}
```

`maiden validate` (lesson 14) and the CI gate both read this file. When
D2's TBD on tightening these (RTK decision) resolves, one commit touches
D2 and this file together — that's the D5 rule, mechanized.

### The HIL half, designed before it exists

The HIL set is a directory of *recorded bench Station 1 data* — real
radar IF from the bench, looped video, real TMATS — that lands in
lesson 20. Its contract: `data/hil/` looks exactly like a session
directory (same layout the twin writes, same layout the field will
produce), so `maiden validate --session data/hil/` and the CI replay need
zero special cases. HIL differs from twin in one way only: no truth file,
so the checks are structural and statistical (files ingest, tracker runs,
fusion converges, channel rates match IF-1) rather than residual-based.
Until lesson 20: the CI job checks for the directory and **skips with a
visible notice** — the theremin course's rule that skips are explicit,
never silent, applies to CI jobs too.

### VT-18: prove the alarm rings

An untested regression gate is a smoke detector with no battery. VT-18's
procedure (per D7: inspection, "inject a fusion bug on a branch") is a
drill you actually perform: branch, sabotage the filter in a plausible
way — transpose a Jacobian block, drop the v_r update, off-by-one the
epoch grid — push, and watch CI fail on the SYS-002/003/004 thresholds.
Capture the red run (log excerpt or screenshot) into `results/VT-18/`,
note the bug injected and which threshold caught it, delete the branch.
Do it once now and once more after any major CI change.

### Tags and releases

D5 names the tags: `v0.1-basic-plan` (the document set you started from —
tag the repo's initial docs state retroactively if you didn't in
lesson 00), `v0.2-prototype` (end of this course, all bench VTs passed),
`v1.0-field-demo` (after lesson 99). Documents and code release
together: a tag is only laid on a commit where the docs match the build.

## Doc Trace

- **SW-005** — implemented in full for the twin set; the HIL replay
  interface is in place with the dataset explicitly TBD until lesson 20
  (this closes the design; the data closes the requirement).
- **VT-18** — executed as the drill above; evidence in `results/VT-18/`.
- **D5 §How the hardware and software tracks merge** — this lesson is
  that section made real: HIL CI is the merge point.
- **D5 §Configuration management** — tags, the one-repo layout, and the
  requirement-change-is-one-commit rule are adopted here as working
  practice.

## Build

1. **Workflow** — `.github/workflows/ci.yml`. *Skeleton:*

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: {python-version: "3.11"}
      - run: pip install -e software[dev]
      - run: ruff check software
      - run: pytest software/tests -q
  replay:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # cache key: twin source hash + seeds (see Concepts — do not cheat)
      - uses: actions/cache@v4
        with: {path: data/twin-ci, key: twin-${{ hashFiles('software/maiden/twin/**') }}-s1001-1003}
      - run: python scripts/replay.py --twin data/twin-ci --hil data/hil
```

2. **The replay driver** — `scripts/replay.py`: generate-or-load the
   canonical twin sessions, run ingest → fuse → validate on each, apply
   the gate from `config/thresholds.yaml`, exit nonzero on any breach;
   then the HIL block (structural checks or loud skip). This same script
   is your local pre-push habit: `make replay`.
3. **Thresholds config** — `config/thresholds.yaml` as above; refactor
   lesson 13/14 code to read it (remove the hardcode-with-TODO you left
   in lesson 13).
4. **Makefile** — `make lint test replay ci` targets so the human path
   and the CI path are literally the same commands.
5. **Tags** — lay `v0.1-basic-plan` on the initial-docs commit if
   missing. `v0.2-prototype` waits for the end of lesson 24 + bench VTs.

Note on runtime: the tracker's render-heavy synthetic-video path
(lesson 10–11) can dominate CI time. Acceptable per SW-005: replay the
twin's message-level az/el channel (Ch 5) through fusion in the fast job,
and run the full video-path test on a nightly schedule instead — both
jobs exist, the fast one gates merges. Document the split in the
workflow file; a coverage cap nobody can see is how pipelines rot.

## Verify

- `make ci` passes locally from a clean clone (delete `data/twin-ci`
  first — prove the regeneration path, not just the cache).
- Push to GitHub; the workflow goes green; the HIL job reports its skip
  visibly in the log.
- **The VT-18 drill**, per Concepts: inject, push, observe red, file
  evidence in `results/VT-18/`, clean up. The gate must fail on a
  threshold breach, not on a crash — if your bug crashes the pipeline
  instead, pick a subtler bug; VT-18 is about the *accuracy* gate.
- Corrupt one value in `thresholds.yaml` (e.g., pos_rms 0.0) and confirm
  the gate reads the file (build fails); revert.

## Explore

- **Cache poisoning.** Deliberately weaken the cache key to seed-only,
  change the twin's noise model, and observe CI pass when it should
  fail. Restore the source-hash key. Now you've *seen* why it's there.
- **Threshold margin report.** Extend `replay.py` to print percent
  margin to each threshold, not just pass/fail — a build that passes
  with 2% margin deserves different attention than one at 60%. Consider
  failing on margin collapse (>50% margin loss vs the last tag).
- **Seed sensitivity.** Run seeds 1001–1010 locally. How much does pos
  RMS vary run-to-run? If the spread approaches your margin, three CI
  seeds are too few — decide with data, not vibes.

## Checkpoint

- CI runs on every push: lint, unit tests, twin replay, threshold gate;
  the HIL job skips loudly pending lesson 20.
- `config/thresholds.yaml` is the single numeric home for
  SYS-002/003/004 values; validate and CI both read it.
- VT-18 evidence exists in `results/VT-18/`: the injected bug, the red
  run, the threshold that caught it.
- `make ci` and the GitHub workflow execute the same scripts.
- `v0.1-basic-plan` is tagged; you can state what `v0.2-prototype` will
  require before it may be laid.
