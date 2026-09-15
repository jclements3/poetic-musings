# Lesson 00 — Orientation & the Repo [desk]

*Where we are.* You have a released document set (docs/D0–D9, Rev 0.1), a
head full of theremin-course skills, and no repository. By the end of this
lesson the MAIDEN repo exists with the layout every later lesson assumes, a
Python package that imports, a test suite that passes (with one trivially
green test), and a tag marking the start of the build. Nothing here is
glamorous; all of it is load-bearing. The D5 SEMP's configuration-management
rules are not aspirational prose — they are the reason a February field-demo
result will be reproducible from raw data plus a tagged commit.

## Objectives

- Initialize the MAIDEN git repository with the canonical directory layout
  from CURRICULUM.md and a `.gitignore` that enforces the D5 data rules.
- Stand up Python 3.11+ in a venv with a `pyproject.toml` that installs
  `maiden` as an editable package (numpy, pytest, ruff).
- Run `pytest` green on a placeholder test and `ruff check` clean.
- Make the first commit and tag it `v0.0-course-start`.
- Read the document set in D0's prescribed order and know where every kind
  of fact lives (requirements → D2, tests → D7, interfaces → D4).

## Concepts

### Why the repo layout is part of the design

D5 §Configuration management specifies one Git repository with
`firmware/`, `software/`, `hardware/`, `docs/`, and `config/` — documents
and code release together, tagged at each milestone. The course adds
`data/` and `results/` with sharply different rules:

- **`data/`** — raw field sessions, one directory per date. Raw `.ch10` is
  *never modified* and derived products are *regenerable* from raw + tagged
  code (D5's words). Raw capture files are large binaries; they do not
  belong in git history. So `data/` is git-ignored except for a README
  stub, and the archive lives on disk (and your backup drive). If you later
  want raw data under version control, git-lfs is the tool — but for a
  single-person project, an ignored directory plus a checksum manifest is
  simpler and honest.
- **`results/`** — VT evidence: small result sheets, plots, logs. These
  *are* committed, with the code that produced them. This directory is
  D8's evidence trail; treat a commit touching `results/VT-nn/` as signing
  a test report.

### The document set, in reading order

D0 gives the order; here is what to extract on this pass:

1. **D1 ConOps** — who MAIDEN serves and the four scenarios. S1 (pattern
   practice) is the product; S3 (validation flight) is how it earns trust.
2. **D3 Architecture** — the block diagram you are about to spend six
   months implementing. Note the fusion-error scaling law σ_range ≈
   R²·σ_θ/B; it justifies half the requirements you'll meet.
3. **D5 SEMP** — phases, the twin-first strategy (software track runs on
   synthetic data while hardware iterates), the risk register. R9 is you.
4. **D2 SyRS+RTM** — skim every requirement ID once. You will cite these
   constantly and restate them never.
5. **D4 ICD** — the four interfaces. IF-4 (StateSample) is the spine of
   the software; IF-1/IF-2 define what your recorder writes.
6. **D6 Design** — how each block is built. The course follows it, and
   audits it where it deserves auditing.
7. **D7 V&V Plan** — the test matrix. Each lesson's Verify section points
   into it.

D8 and D9 are templates/drafts filled later; know their shape.

### Conventions that start now

Requirement IDs (SYS-002) live in D2 only; test IDs (VT-10) in D7 only.
Commits that change a requirement touch D2 *and* the affected D6/D7 rows in
the same commit — that is D5's change-control rule, and lessons that hit
design friction (lesson 17, notably) will exercise it for real.

## Doc Trace

- **D5 §Configuration management** — repo structure, tags, data rules;
  this lesson implements them literally.
- **D0 §Conventions** — ID discipline, TBD marking, documents released
  together; adopted as repo law from the first commit.
- No requirement is verified here; every later VT depends on the
  reproducibility this lesson sets up.

## Build

All commands from `/home/clementsj/projects/maiden` (the repo root — the
directory that already contains `docs/` and `course/`).

**Initialize and lay out:**

```bash
git init   # no-op if the repo already exists (it does if the course
           # itself arrived by commit); harmless either way
mkdir -p software/maiden software/tests firmware hardware \
         config/tmats config/field data results
touch software/maiden/__init__.py
```

**File: .gitignore**

```
# environments and caches
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/

# raw field data: archived on disk, never in git (D5 data rules)
data/*
!data/README.md

# FPGA build products (theremin house rules)
firmware/**/build/
*.ghw
```

**File: data/README.md**

```
Raw field sessions, one directory per date (YYYYMMDD/). Raw .ch10 is never
modified; derived products are regenerable from raw + tagged code (D5).
This directory is git-ignored; keep a checksum manifest per session and an
offline backup.
```

**File: software/pyproject.toml**

```toml
[project]
name = "maiden"
version = "0.0.0"
description = "MAIDEN: Moving Artificial Intelligence Data Evaluator Notary"
requires-python = ">=3.11"
dependencies = ["numpy"]

[project.optional-dependencies]
dev = ["pytest", "ruff"]

[tool.setuptools.packages.find]
include = ["maiden*"]

[tool.ruff]
line-length = 88
```

**File: software/tests/test_smoke.py**

```python
def test_package_imports():
    import maiden  # noqa: F401
```

**Environment:**

```bash
python3 --version          # must be 3.11+
python3 -m venv .venv
source .venv/bin/activate
pip install -e "software[dev]"
```

Put the venv activation in your shell habit, not your `.bashrc` — same
reasoning as the theremin course's `fpga` alias: explicit environments,
no global shadowing.

**First commit and tag:**

```bash
git add -A
git commit -m "MAIDEN repo scaffold: layout per D5 CM, Python package, CI-ready tests"
git tag v0.0-course-start
```

## Verify

- `pytest software/tests` exits 0 with 1 passed.
- `ruff check software` reports no issues.
- `git status` is clean; `git tag` lists `v0.0-course-start`.
- `python -c "import maiden"` succeeds from an activated venv anywhere in
  the repo.
- `git check-ignore data/somefile.ch10` names the ignore rule (create no
  such file; the command reports what *would* be ignored — actually it
  needs the path argument only, so run
  `git check-ignore -v data/x.ch10` and confirm the `.gitignore` line is
  cited).

## Explore

1. **Read the risk register (D5) against the repo.** For each of R1–R9,
   note which directory the mitigation will live in. R9 (schedule) has no
   directory; its mitigation is the lesson ordering you are following.
2. **Trace one requirement end to end on paper.** Take SYS-002: find its
   row in D2, the design element in D6, the test in D7, and the table in
   D8 where its result will land. That four-hop walk is the EIA-632
   traceability thread, and you will automate parts of it in lesson 15.
3. **Break the ignore rules.** Drop a dummy `data/20260101/x.ch10` and
   confirm `git status` stays clean; then try `results/VT-01/note.md` and
   confirm it is *not* ignored. If either behaves otherwise, fix
   `.gitignore` now, not in November.

## Checkpoint

- The repo is git-initialized with the CURRICULUM layout; first commit
  made; `v0.0-course-start` tagged.
- `pytest software/tests` passes and `ruff check software` is clean in a
  Python ≥3.11 venv with `maiden` installed editable.
- `data/` is ignored (README stub excepted); `results/` is tracked.
- You can answer, without looking: where do requirements live? where do
  test definitions live? what two things must a requirement-change commit
  touch?
