# Appendix — The Wheel: What Does Not Need To Be Reinvented

Every recipe below is real, working code that already exists in `playbook/`
in this repo — not pseudocode written for the book. Every script imports
from a single shared library, `playbook/haskell.py`: a from-scratch,
zero-dependency, Haskell-style functional core for Python — point-free
combinators, a `Maybe` type (`NOTHING`), an `Either` type (`Ok`/`Err`
tuples), do-notation for both, parser combinators, and monoids. The goal of
this appendix is simple: the next time you need to write a small DevSecOps
script — parse a config file, gate a build on a policy, diff two JSON
documents, triage scanner output — you should not start from a blank file.
You should open this appendix, find the closest recipe, and adapt it.

Every real verification number cited here (pass/fail counts, exit codes,
idempotency proof) is reproduced from `playbook/README.md`, which
re-verified every script against this repo's own real files, not just the
toolkit's seeded demo fixtures. If you want the full verification log,
that file is the source of record — this appendix is the *use* reference,
that file is the *proof* reference.

```
playbook/
  haskell.py       the FP core — import from this, don't reinvent it
  secrets.py deps.py cve.py actions_pin.py   Zone 5 (Secure) plays
  triage.py gate.py                          Zone 5 (Secure) plays
  freshness.py                               Zone 8 (Operate & Observe) play
  sbom_diff.py                               Zone 9 (Evidence & Govern) play
  pipeline.sh pre-commit policy.json waivers.json   glue + config
```

---

## Part A — The Core: `haskell.py`, grouped by what it replaces

You do not need to memorize all of this. You need to know it exists, know
roughly where to look, and `import` it. Every entry below is a real,
working one-liner from `playbook/haskell.py`.

### A.1 — Instead of writing a loop, compose functions

```python
from haskell import compose, pipe, curry, flip, identity, const

# compose reads right-to-left, like math: f(g(x))
double_then_str = compose(str, lambda x: x * 2)
double_then_str(21)                    # "42"

# pipe reads left-to-right, like a shell pipeline — usually more readable
pipe(21, lambda x: x * 2, str)         # "42"

# curry turns f(x, y) into f(x)(y) — useful for partial application
add = curry(lambda a, b: a + b)
add_five = add(5)
add_five(10)                            # 15

# flip swaps argument order — handy when a library's arg order fights you
subtract = lambda a, b: a - b
flip(subtract)(3, 10)                   # 7  (10 - 3)
```

**Instead of reinventing:** a chain of `x = step1(x); x = step2(x); x =
step3(x)` re-assignment. `pipe(x, step1, step2, step3)` is the same thing,
without the mutable variable, and it reads as a pipeline because it *is*
one.

### A.2 — Instead of `if x is None: return None` scattered everywhere: `Maybe`

```python
from haskell import NOTHING, bind, fromMaybe, mapMaybe, catMaybes, isJust

# NOTHING is a real object (falsy, printable) standing in for "no value" —
# not None, specifically so you can't confuse "no value" with "value is None"
lookup_port = lambda cfg, key: cfg.get(key, NOTHING)

port = lookup_port({"host": "db"}, "port")   # NOTHING
fromMaybe(5432, port)                         # 5432 — real default, no None-check

# mapMaybe: map a function that might fail, keep only the successes
def parse_int_or_nothing(s):
    return int(s) if s.isdigit() else NOTHING

mapMaybe(parse_int_or_nothing, ["1", "x", "3", "y", "5"])   # [1, 3, 5]
```

**Instead of reinventing:** `result = f(x); if result is not None: ...`
chains three levels deep. `bind(x, f)` short-circuits automatically the
moment anything returns `NOTHING` — this is exactly the pattern
`deps.py`/`secrets.py` use to skip blank/comment lines without an explicit
`if` at every step (see A.6 below).

### A.3 — Instead of `try/except` at every call site: `Either`

```python
from haskell import Ok, Err, bindE, sequenceE, traverseE, partitionEithers

def load_json(path):
    import json
    try:
        return Ok(json.loads(open(path).read()))
    except Exception as e:
        return Err(str(e))

results = [load_json(p) for p in ["a.json", "b.json", "missing.json"]]
oks, errs = partitionEithers(results)
# oks   = [the two successfully parsed dicts]
# errs  = ["missing.json: [Errno 2] No such file or directory: ..."]
```

This is **exactly** the pattern `gate.py`'s `load()` function uses (see
Part B.6) — every file load returns `Ok(data)` or `Err(message)`, and the
caller never needs a bare `try/except` because `traverseE`/`sequenceE`
propagate the first failure automatically.

**Instead of reinventing:** a `try/except` block around every file read,
with a different error-handling story each time. One `load()` helper,
reused everywhere, with errors as real values instead of control flow.

### A.4 — Instead of a hand-rolled parser: parser combinators

```python
from haskell import doP, rx, lit, alt, sepBy, many, runParser

# a parser for "key=value" pairs separated by commas, e.g. "a=1,b=2,c=3"
key   = rx(r"[a-zA-Z_]+")
value = rx(r"[0-9]+", int)          # conv=int — the parser returns an int directly

@doP
def pair():
    k = yield key
    _ = yield lit("=")
    v = yield value
    return (k, v)

pairs = sepBy(pair(), lit(","))
runParser(pairs, "a=1,b=2,c=3")
# Ok([("a", 1), ("b", 2), ("c", 3)])
```

This exact pattern — `rx` for regex tokens, `lit` for literal characters,
`doP` for sequencing, `sepBy` for comma-separated lists — is precisely how
`deps.py` parses `requirements.txt` lines (`numpy>=1.26,!=1.26.1`) into
structured `(name, [specs])` tuples instead of splitting strings by hand
and hoping edge cases don't bite. See Part B.2 for the real version.

**Instead of reinventing:** regex-and-`.split()` spaghetti that breaks the
first time the input has a form you didn't anticipate. A parser combinator
either consumes valid input and returns a real error otherwise — the
failure mode is explicit, not silent.

### A.5 — Instead of manual dictionary-counting loops: monoids

```python
from haskell import Sum, mconcat, foldMap, fromListWith, add

# count findings by severity without a hand-rolled counter dict
findings = [{"level": "error"}, {"level": "error"}, {"level": "warning"}]
fromListWith(add, [(f["level"], 1) for f in findings])
# {"error": 2, "warning": 1}

# mconcat: reduce a list into one value using a (empty, combine) pair
mconcat(Sum, [1, 2, 3, 4])              # 10
```

This is the exact mechanism `triage.py` and `cve.py` use to build their
`by_level` and `top_rules` summaries (see Part B.5/B.3) — no manual
`if key in d: d[key] += 1 else: d[key] = 1` boilerplate.

### A.6 — do-notation: sequencing that bails out on the first failure

```python
from haskell import doM, doE, NOTHING

@doM   # Maybe-flavored do-notation
def first_valid_port(cfg):
    raw = yield cfg.get("port", NOTHING)
    n   = yield (int(raw) if str(raw).isdigit() else NOTHING)
    return n if 0 < n < 65536 else NOTHING
```

Read this top to bottom like an imperative function — each `yield` is a
step that can fail. The moment any step yields `NOTHING`, everything after
it is skipped automatically and the whole function returns `NOTHING`. This
is the `secrets.py`/`triage.py` pattern for "get this field, or bail out
cleanly" without a pyramid of nested `if` statements. `doE` is the same
idea for `Either` — see `gate.py`'s `inputs()` function in Part B.6.

---

## Part B — The 8 Real Scripts, One Recipe Each

Every recipe below is quoted directly from the real file in `playbook/`.
Adapt the pattern, don't just run the script — the point of this appendix
is that you can lift 10-20 lines out of any of these and have a working
starting point for a *new* problem in five minutes instead of an hour.

### B.1 — Zone 5 (Secure): scan a tree for leaked secrets — `secrets.py`

```python
PATTERNS = [
    ("aws-access-key", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("private-key",    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("github-token",   re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
]

hits = lambda path: lambda pair: mapMaybe(
    lambda pn: dict(rule=pn[0], file=str(path), line=pair[0],
                    text=pair[1].strip()[:80]) if pn[1].search(pair[1]) else NOTHING,
    PATTERNS)
```

**The reusable idea:** a list of `(rule_name, compiled_regex)` pairs, and
one `mapMaybe` call that turns "does this line match any pattern" into a
list of structured findings, with no findings collapsing to an empty list
for free (not a special case). Add a new secret pattern by adding one
tuple to `PATTERNS` — nothing else in the file changes.

**Real, verified result (from `playbook/README.md`):** scoped to
`app/ infra/ k8s/ ansible/`, **0 findings, exit 0**. Whole-tree run flagged
a real false positive on `ad-lab/seed-objects.sh`'s
`--password="${ADMIN_PASSWORD}"` — the fix was operational (scope the
scan to source directories), not a regex patch. Document that class of
false positive rather than special-casing it in the pattern.

```bash
python3 playbook/secrets.py app/ infra/ k8s/ ansible/
```

### B.2 — Zone 5 (Secure): parse and audit a `requirements.txt` — `deps.py`

```python
name    = rx(r"[A-Za-z0-9][A-Za-z0-9._-]*")
op      = rx(r"==|~=|>=|<=|!=|<|>")
version = rx(r"[A-Za-z0-9.*+!_-]+")

@doP
def spec():
    f = yield op
    v = yield version
    return f + v

@doP
def req():
    n  = yield name
    _  = yield opt(extras)
    ss = yield sepBy(spec(), lit(","))
    return (n, ss)

pinned = lambda r: any(s.startswith("==") for s in r[1])
```

**The reusable idea:** a real grammar (`req := name extras? (spec (,
spec)*)?`) expressed as three small parsers composed with `doP`, instead
of `.split("==")` and hoping the line never has extras or multiple
constraints. `pinned()` is a one-line policy check on top of a correctly
parsed structure — swap it for any other policy without touching the
parser.

**Real, verified result:** `app/status-service/requirements.txt` →
**`3 pinned, 0 unpinned, 0 unparsed`**, exit 0 (flask==3.1.3,
gunicorn==22.0.0, prometheus-client==0.21.1).

```bash
python3 playbook/deps.py app/status-service/requirements.txt
```

### B.3 — Zone 5 (Secure): turn `pip-audit` JSON into a gate-ready summary — `cve.py`

```python
rows_of = lambda audit: concatMap(
    lambda d: [dict(rule=v["id"], level="error", file=f"{d['name']}=={d['version']}",
                    fix=",".join(v.get("fix_versions", [])) or "none")
               for v in d.get("vulns", [])],
    audit.get("dependencies", []))
```

**The reusable idea:** `concatMap` flattens "for each dependency, for each
vulnerability in that dependency" into one flat list of findings in a
single expression — the nested-loop-and-append pattern collapses to one
line. This exact shape (flatten a list of lists produced by mapping over
an outer list) reappears in `triage.py`'s SARIF `runs → results` flattening
too.

**Real, verified result:** a live `pip-audit -r
app/status-service/requirements.txt -f json` fed to `cve.py` produced
`{"total": 0, ...}` — "No known vulnerabilities found," matching
`pip-audit`'s own output.

```bash
pip-audit -r app/status-service/requirements.txt -f json -o out.json
python3 playbook/cve.py out.json > cve.summary.json
```

### B.4 — Zone 5 (Secure): audit GitHub Actions for unpinned versions — `actions_pin.py`

```python
USES = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
OK   = re.compile(r"@[0-9a-f]{40}$")     # a full 40-char commit SHA

def flag(path):
    def line(pair):
        m = USES.match(pair[1])
        if not m: return NOTHING
        ref = m.group(1)
        if ref.startswith(LOCAL) or OK.search(ref): return NOTHING
        return (str(path), pair[0], ref)
    return line
```

**The reusable idea:** a closure (`flag(path)` returns `line`, which
closes over `path`) so `mapMaybe` can be handed a single-argument function
while still knowing which file it's scanning — a common pattern any time
you need per-file context inside a per-line check.

**Real, verified, HONEST finding:** **21 real `uses:` lines are
tag-pinned, not SHA-pinned** (`actions/checkout@v4`,
`gitleaks/gitleaks-action@v2`, etc.), exit 1 — a genuine open gap in this
repo's own workflows, reported and left unfixed by design (out of scope
for the integration task that ran it). This is what an honest scan looks
like: it found a real problem and the book says so.

```bash
python3 playbook/actions_pin.py .github/workflows/*.yml
```

### B.5 — Zone 5 (Secure): triage any SARIF file, waiver-aware — `triage.py`

```python
SEV  = [("error", 3), ("warning", 2), ("note", 1), ("none", 0)]
rank = lambda lvl: fromMaybe(0, lookup(lvl, SEV))

active = lambda today: lambda w: w.get("expires", "9999") >= today
waived = lambda ws: lambda r: any(
    w["rule"] == r["rule"] and r["file"].startswith(w.get("path", "")) for w in ws)

out, rows = partition(waived(ws), mapMaybe(row, concatMap(
    lambda run: run.get("results", []), runs)))
```

**The reusable idea:** waivers are just data (`{"rule", "path", "reason",
"expires"}`), and `active()` + `waived()` compose into a single
`partition()` call that splits findings into "waived" and "still active"
— an **expired** waiver stops matching automatically (the `expires`
string comparison), so a stale exception silently starts counting again
instead of silently staying suppressed forever. This is the exact
mechanism behind Zone 9's "waivers reactivate automatically" principle.

**Real, verified result:** a real `bandit -r app -f sarif` output fed to
`triage.py` → `{"total": 0, "worst": 0}` — "No issues identified," matching
Jenkins build #7's independently-verified result.

```bash
bandit -r app -f sarif -o bandit-real.sarif --exit-zero
python3 playbook/triage.py bandit-real.sarif playbook/waivers.json
```

### B.6 — Zone 5 (Secure): one policy chokepoint over N summaries — `gate.py`

```python
def load(p):
    try:
        return Ok((p, json.loads(Path(p).read_text())))
    except (OSError, json.JSONDecodeError) as e:
        return Err(f"{p}: {e}")

@doE
def inputs(argv):
    pol  = yield load(argv[0])
    sums = yield traverseE(load, argv[1:])
    return (pol[1], sums)
```

**The reusable idea:** `load()` never raises — every failure becomes a
real `Err` value. `traverseE` then loads a whole list of files and, the
instant ANY of them fails, short-circuits with that one error instead of a
partial result or a confusing stack trace three files deep. `main()`
reads `r[0] == "err"` once and knows the entire input phase either fully
succeeded or fully failed — no partial state to reason about.

**Real, verified: all three exit codes confirmed for real, not just on
demo fixtures:**
- `gate.py policy.json bandit-real.summary.json` → `GATE PASS`, exit 0
- `gate.py policy.json demo/bandit.summary.json` → `GATE FAIL`
  (`worst severity 3 > 2`, `2 'error' finding(s) denied by policy`), exit 1
- `gate.py policy.json /nonexistent.json` → error to stderr, exit 2

```bash
python3 playbook/gate.py playbook/policy.json bandit-real.summary.json
echo "exit: $?"
```

### B.7 — Zone 8 (Operate & Observe): catch scans that silently stopped running — `freshness.py`

```python
age = lambda p: (p, (now - p.stat().st_mtime) / 3600)
stale, fresh = partition(lambda pa: pa[1] > max_h, map_(age, map(Path, paths)))
```

**The reusable idea:** the failure mode this guards against isn't "the
scan found something bad" — it's "the scan stopped running weeks ago and
nobody noticed because the last summary still says clean." A file's own
mtime is a real, cheap signal for "is this evidence actually current."
`partition()` splits into stale/fresh in one pass — the same combinator
used throughout this toolkit (B.2, B.5), reused for a completely different
problem, which is the entire point of a small, general core.

**Real, verified result:** two real summaries just produced by other
scripts in this same session → `OK ... (0.0h)` for both, exit 0.

```bash
python3 playbook/freshness.py 48 bandit-real.summary.json cve.summary.json
```

### B.8 — Zone 9 (Evidence & Govern): diff two SBOMs for supply-chain drift — `sbom_diff.py`

```python
comps = lambda s: dict(mapMaybe(
    lambda c: (c["name"], c.get("version", "?")) if "name" in c else NOTHING,
    s.get("components", [])))

added   = sortOn(str, b.keys() - a.keys())
removed = sortOn(str, a.keys() - b.keys())
changed = sortOn(str, [(k, a[k], b[k]) for k in a.keys() & b.keys() if a[k] != b[k]])
```

**The reusable idea:** two CycloneDX SBOMs reduced to `{name: version}`
dicts, then plain Python set algebra (`-` for difference, `&` for
intersection) does the entire diff — no bespoke tree-walking. This is the
"supply-chain changelog" MASTER-PLAYBOOK.md's Zone 9 section names: what
got added, removed, or bumped between two releases, answerable from stored
artifacts instead of memory.

**Honest gap:** verified only against the toolkit's seeded demo fixtures
(1 added / 1 removed / 1 changed, correctly reported) — **not** re-run
against a real SBOM of this repo's own containers, because `syft` wasn't
installed in the environment that did the integration work. Documented as
an open gap rather than silently skipped or faked.

```bash
syft app/status-service -o cyclonedx-json > sbom-new.json
python3 playbook/sbom_diff.py sbom-old.json sbom-new.json
```

---

## Part C — The Pre-Commit Hook, End to End

`playbook/pre-commit` wires B.1 (`secrets.py`) and B.2 (`deps.py`)
together as a real git hook — the fastest, cheapest gate in the whole
pipeline, running locally before anything ever reaches CI.

**Real, verified twice:** an isolated scratch repo (blocks a staged AWS
key, exit 1; passes a clean tree, exit 0) — then installed for real at
this repo's own `.git/hooks/pre-commit`, scoped to
`app/ infra/ k8s/ ansible/ playbook/*.py`, confirmed clean against the
real working tree (`3 pinned, 0 unpinned, 0 unparsed`, exit 0).

```bash
cp playbook/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
# now try it:
echo 'aws_key = "AKIAIOSFODNN7EXAMPLE"' >> scratch.py
git add scratch.py && git commit -m "test"   # blocked, exit 1
```

---

## Part D — Zone Cross-Reference

| Zone | Real plays from this toolkit | Chapter |
|---|---|---|
| 1 — Plan & Source | (process-bound, no script — see Chapter 1) | `chapter-01-plan-and-source.md` |
| 2 — Develop | `pre-commit` hook (Part C) | `chapter-02-develop.md` |
| 3 — Build | `pipeline.sh` (stages 1-4, mirrors CI order) | `chapter-03-build-and-test.md` |
| 4 — Test | `pipeline.sh demo` regression proof (must exit 1) | `chapter-03-build-and-test.md` |
| 5 — Secure | `secrets.py` `deps.py` `cve.py` `actions_pin.py` `triage.py` `gate.py` | `chapter-05-secure.md` |
| 6 — Provision | (Terraform/Ansible — see Chapter 6; no playbook script) | `chapter-06-provision.md` |
| 7 — Deploy & Orchestrate | (Kubernetes/AD — see Chapter 7; no playbook script) | `chapter-07-deploy-and-orchestrate.md` |
| 8 — Operate & Observe | `freshness.py` | `chapter-08-operate-and-observe.md` |
| 9 — Evidence & Govern | `sbom_diff.py`, `waivers.json` (Part B.5's waiver logic) | `chapter-09-evidence-and-govern.md` |

Zones 1, 6, and 7 don't have a `playbook/` script of their own — that's
honest, not a gap in the toolkit. Those zones are about process
(branch protection), infrastructure (Terraform/Ansible), and orchestration
platforms (Kubernetes/AD) respectively — the *doing* happens in real
tools this book's chapters teach directly, not in a Python script. The
toolkit's job is the zones where small, composable scripts are genuinely
the right tool: parsing, gating, triaging, diffing structured data.
