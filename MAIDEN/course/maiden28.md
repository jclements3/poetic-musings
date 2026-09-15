# maiden28 — CI workflow [desk]

**Sprint goal.** Stand up the SW-005 machinery: GitHub Actions running
lint, unit tests, and the canonical twin replay with an absolute-threshold
regression gate — with the human path and the CI path being literally the
same commands.

**Depends on.** maiden27 (`gate()`, `maiden validate`), maiden12 (twin
CLI + seeds). The HIL dataset it also replays arrives in maiden45 — until
then that job skips loudly.

**Read first.** lesson15.md — *Concepts* "What CI is for, here", "The
canonical twin set, and caching honestly", "One home for the thresholds",
and "The HIL half, designed before it exists", then *Build*.

## Tasks

- [x] `config/thresholds.yaml`: the single numeric home for
      SYS-002/003/004 values, each line carrying its requirement ID and
      the comment that D2 is the authority (a change here without a
      matching D2 revision is a D5 change-control violation).
- [x] Refactor maiden25's hardcode-with-TODO and maiden27's gate to read
      the thresholds file.
- [x] `scripts/replay.py`: generate-or-load the canonical twin set
      (seeds 1001–1003, `--imperfect`), run ingest → fuse → validate per
      session, apply the gate, exit nonzero on any breach; then the HIL
      block — structural checks on `data/hil/` or a **visible** skip
      notice while it's absent.
- [x] `.github/workflows/ci.yml` per the lesson skeleton: test job
      (ruff + pytest) and replay job, cache keyed on
      `hashFiles('software/maiden/twin/**')` + seeds — source hash, not
      seed-only; a stale-twin cache tests the wrong thing.
- [x] Split fast vs full: the merge-gating job replays the twin's Ch 5
      message-level az/el through fusion; the render-heavy video path
      runs on a nightly schedule. Document the split in the workflow
      file.
- [x] `Makefile`: `make lint test replay ci` — same scripts CI runs.
- [ ] Lay the `v0.1-basic-plan` tag (orchestrator: state-changing git) on the initial-docs commit if maiden01
      didn't.
- [x] Prove regeneration: delete `data/twin-ci`, run `make ci` from a
      clean clone, watch the set rebuild.

## Done when

- CI runs on every push: lint, unit tests, twin replay, threshold gate;
  the workflow is green on GitHub and the HIL job's skip is visible in
  the log.
- `config/thresholds.yaml` is the only place SYS-002/003/004 numbers
  appear in code-readable form; validate and CI both read it (corrupting
  a value to 0.0 fails the build — try it, then revert).
- `make ci` and the GitHub workflow execute the same scripts.
- `v0.1-basic-plan` is tagged; you can state what `v0.2-prototype`
  requires (end of maiden57 + bench VTs) before it may be laid.

## Doc trace

SW-005 implemented for the twin set (HIL interface designed, dataset TBD
→ maiden45); D5 §How the hardware and software tracks merge, §CM (tags,
one-repo layout, requirement-change-is-one-commit). The alarm test —
VT-18 — is maiden29.

---

**Execution notes (maiden28, desk).** thresholds.yaml is the single home
(validate.py + test_fuse_pipeline.py read it; fuse.py docstring updated);
replay.py generates/caches seeds 1001-1003 keyed on twin source hash with
MANIFEST.json re-verification, prints signed percent margins per SYS
threshold (thin-margin note < 5%), and skips HIL loudly. `make ci` =
lint+test+replay, identical to the workflow. Real first run: all seeds
PASS (pos ~0.22-0.24 m, vel 0.909-0.952 m/s, continuity 1.0); corrupt-
threshold check went red and was restored byte-identically; regeneration
proven from a deleted cache. NOT done here: the v0.1-basic-plan tag and
the on-GitHub green run (state-changing git is the orchestrator's; tag +
push noted for it). GHDL firmware sims documented as dev-machine/nightly
work, not merge-gating.

**Orchestrator note (push-scope workaround).** The push credential lacks
GitHub's `workflow` scope, so `ci/github-ci.yml` is parked outside
`.github/workflows/`. To activate Actions: `gh auth refresh -h github.com
-s workflow`, then `git mv ci/github-ci.yml .github/workflows/ci.yml`,
commit, push. `make ci` runs the identical gate locally meanwhile.
