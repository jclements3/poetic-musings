# maiden01 — Repo, environment, first green test [desk]

**Sprint goal.** Stand up the MAIDEN repository with the D5-CM layout, an
installable Python package, and a passing test suite, tagged as the start
of the build.

**Depends on.** Nothing — this is sprint one. (Python 3.11+ on the machine.)

**Read first.** lesson00.md — all of it, especially *Why the repo layout is
part of the design* and *The document set, in reading order*.

## Tasks

- [ ] `git init` in `/home/clementsj/projects/maiden` (skip if the repo
      already exists — it does if the course itself was committed); create
      `software/maiden`, `software/tests`, `firmware/`, `hardware/`,
      `config/tmats`, `config/field`, `data/`, `results/` per lesson 00
      §Build.
- [ ] Write `.gitignore` (venv/caches, `data/*` except `data/README.md`,
      FPGA build products) and `data/README.md` exactly per lesson 00.
- [ ] Write `software/pyproject.toml` (numpy dep, pytest/ruff dev extras)
      and `software/tests/test_smoke.py`.
- [ ] Create the venv, `pip install -e "software[dev]"`, run `pytest` and
      `ruff check software`.
- [ ] Do the reading pass over docs/ in D0's order (extraction goals per
      lesson 00 §The document set); note where requirements, tests, and
      interfaces live.
- [ ] Run lesson 00 Explore 3 (drop a dummy `data/.../x.ch10`, a
      `results/VT-01/note.md`) and confirm the ignore rules behave.
- [ ] First commit; tag `v0.0-course-start`.

## Done when

- `pytest software/tests` → 1 passed; `ruff check software` clean.
- `python -c "import maiden"` succeeds from the activated venv.
- `git check-ignore -v data/x.ch10` cites the `.gitignore` rule;
  `results/` paths are *not* ignored.
- `git tag` lists `v0.0-course-start` and `git status` is clean.
- You can answer lesson 00's Checkpoint questions without looking
  (requirements → D2, tests → D7, requirement-change commits touch D2 +
  affected D6/D7 rows).

## Doc trace

D5 §Configuration management (layout, tags, data rules) · D0 §Conventions.
No VT verified; every later VT depends on this reproducibility scaffold.
