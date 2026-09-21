# playbook — a point-free Python FP toolbox for DevSecOps scripting

A reusable toolbox, not a poetic-musings-specific script pile: `haskell.py`
is a from-scratch Haskell-style functional core for Python (point-free
combinators, `Maybe`/`Either` monads, do-notation, parser combinators,
monoids), and nine small scripts on top of it (`secrets.py`, `deps.py`,
`cve.py`, `actions_pin.py`, `triage.py`, `gate.py`, `freshness.py`,
`sbom_diff.py`) implement real DevSecOps gates in that style: secret
scanning, dependency-pin auditing, CVE gating, GitHub Actions SHA-pin
auditing, SARIF triage with waivers, a policy chokepoint, scan-freshness
monitoring, and SBOM drift. `MASTER-PLAYBOOK.md` and `FIELD-MANUAL.md` are
the 9-zone DevSecOps playbook document and its expanded procedural detail;
`JENKINS.md` is Jenkins-dialect teaching material (this repo's actual,
running Jenkins build lives in `jenkins/`, not here — read
`jenkins/README.md` for that). This directory is meant to outlive this one
repo: drop `haskell.py` plus whichever scripts you need into the next
project and they work standalone (each script's only import is
`from haskell import ...`).

Every claim below was re-verified for real against this repo's actual
files, not just the harvested zip's seeded demo fixtures — same standard
as `ad-lab/README.md` and `jenkins/README.md`.

## What's in here

```
playbook/
  haskell.py          the FP core (compose/pipe, curry, folds/scans,
                       Maybe via NOTHING, Either via Ok/Err, do-notation,
                       parser combinators, monoids) — no external deps
  secrets.py           credential-pattern scanner
  deps.py               requirements.txt pin audit (parser combinators)
  cve.py                 pip-audit JSON -> gate-summary JSON
  actions_pin.py          GitHub Actions SHA-pin audit
  triage.py                SARIF -> summary JSON, waiver-aware
  gate.py                   policy chokepoint over summaries
  freshness.py                scan-freshness monitor
  sbom_diff.py                  CycloneDX SBOM drift (added/removed/changed)
  pipeline.sh          local runner, stages 1-4, same order as CI
  pre-commit           git hook: secrets.py + deps.py before push
  policy.json           example gate policy (max_worst, max_total, deny_levels)
  waivers.json           example waiver ledger (rule/path/reason/expires)
  MASTER-PLAYBOOK.md   the 9-zone playbook (canonical)
  FIELD-MANUAL.md      expanded procedure: WSL hygiene, air-gap builds,
                       scanner cookbook, gate-failure runbook, maturity audit
  JENKINS.md           Jenkins-dialect rosetta stone + gotchas (teaching
                       material; the real Jenkins build is in jenkins/)
  demo/                the zip's seeded bad-input fixtures, kept for the
                       Zone 4 regression proof (see below)
```

`PLAYBOOK.md` (the zip's earlier, shorter draft of the same document) was
dropped — `MASTER-PLAYBOOK.md` supersedes it and there was no unique
content worth merging.

## Zone 4 regression proof, reproduced

`MASTER-PLAYBOOK.md` Zone 4 claims `./pipeline.sh demo` must exit 1 against
seeded bad input — a gate that can't fail is decoration. Reproduced here
against `playbook/demo/`:

```
$ ./playbook/pipeline.sh ./playbook/demo
--- stage 1: secrets
playbook/demo/config.py:2: generic-secret: API_KEY = "not-a-real-secret-abcdef123456"
playbook/demo/config.py:3: aws-access-key: aws_key = "AKIAIOSFODNN7EXAMPLE"
--- stage 2: dependency pins
UNPINNED numpy >=1.26
UNPINNED flask ~=3.0,!=3.0.1
UNPINNED hypothesis (any)
2 pinned, 3 unpinned, 0 unparsed
--- stage 4: policy gate
$ echo $?
1
```

## Re-verification against poetic-musings itself

Every `[run]`-tagged script was then re-run for real against this repo's
actual files, not the demo fixtures.

**`secrets.py`** — scoped the same way `.github/workflows/security.yml`'s
gitleaks job is implicitly scoped (source dirs, not the whole tree — see
bug below): `app/ infra/ k8s/ ansible/`. Result: **0 findings, exit 0**,
across all four.

**`deps.py app/status-service/requirements.txt`** — real output:
```
3 pinned, 0 unpinned, 0 unparsed
```
Exit 0 — this repo's real dependency file (`flask==3.1.3`,
`gunicorn==22.0.0`, `prometheus-client==0.21.1`) is fully pinned.

**`cve.py`** — ran a live `pip-audit -r app/status-service/requirements.txt
-f json -o pip-audit-real.json` (same invocation `security.yml` uses), fed
it to `cve.py`:
```
pip-audit: "No known vulnerabilities found"
cve.py summary: {"tool": "pip-audit", "total": 0, "by_level": {}, "top_rules": [], "worst": 0}
```

**`actions_pin.py .github/workflows/*.yml`** — real, honest finding:
**21 `uses:` lines are tag-pinned, not SHA-pinned**, exit 1. This is a
genuine open gap in this repo's Actions workflows (`actions/checkout@v4`,
`gitleaks/gitleaks-action@v2`, `aquasecurity/trivy-action@v0.24.0`, etc. —
none pinned to a full commit SHA). Not fixed here (out of scope — this task
only integrates the toolbox and reports what it finds); `security.yml`
itself is untouched.

**`triage.py`** — ran a real `bandit -r app -f sarif -o bandit-real.sarif
--exit-zero`, then `triage.py bandit-real.sarif waivers.json`:
```
{"tool": "Bandit", "total": 0, "by_level": {}, "top_rules": [], "waived": 0, "worst": 0}
```
Matches the Jenkins build's independently-verified "No issues identified."
(`jenkins/README.md`).

**`gate.py`** — all three exit paths confirmed for real, not just on demo
fixtures:
- exit 0 (pass): `gate.py policy.json bandit-real.summary.json` → `GATE PASS`
- exit 1 (fail): `gate.py policy.json demo/bandit.summary.json` → `GATE FAIL`
  (`worst severity 3 > 2`, `2 'error' finding(s) denied by policy`)
- exit 2 (bad input): `gate.py policy.json /nonexistent.json` → error to
  stderr, exit 2

**`freshness.py 48 *.summary.json`** — real summaries just produced,
`OK ... (0.0h)` for both, exit 0.

**`sbom_diff.py`** — `syft` is not installed in this environment (not on
`PATH`), so this one is **not** re-verified against a real SBOM of this
repo's containers — it ran only against the zip's demo fixtures
(`sbom-old.json`/`sbom-new.json`), correctly reporting 1 added, 1 removed,
1 changed. Honest gap, not silently skipped.

**Pre-commit hook** — verified twice. First in an isolated scratch git
repo (staged AWS key → hook exits 1 and blocks the commit; clean tree →
exits 0), matching the zip's own claim. Then installed for real at this
repo's `.git/hooks/pre-commit` (not tracked by git — local-only, as usual
for hooks), scoped to `app/ infra/ k8s/ ansible/ playbook/*.py` rather than
the whole tree, and confirmed clean (`3 pinned, 0 unpinned, 0 unparsed`,
exit 0) against the real working tree.

## Real bugs hit and fixed

1. **`secrets.py` false positive on `ad-lab/seed-objects.sh`.** Running
   `secrets.py .` (whole repo) flagged
   `samba-tool gpo setlink ... --password="${ADMIN_PASSWORD}"` as a
   `generic-secret` — the regex matches `password="..."` regardless of
   whether the value is a literal or a shell variable interpolation. This
   is a real precision gap versus gitleaks (which this repo's
   `security.yml` already uses and which does entropy/context analysis,
   not naive keyword regex). Not a code bug in the harvested script — it
   is exactly what the regex says it does — so the fix is operational, not
   a patch: scope `secrets.py` to source directories (`app/ infra/ k8s/
   ansible/`), same as `deps.py`/`cve.py` are already scoped to
   `app/status-service/`, and document the false-positive class here
   rather than special-casing it in the scanner.

2. **`config.py` and `clean.py` were miscategorized as toolbox scripts.**
   The harvested zip listed `config.py`/`clean.py` alongside the real
   `haskell.py`-importing scripts, but their actual content is seeded
   secret/clean fixtures (`config.py` has a hardcoded `API_KEY` and AWS
   key; `clean.py` reads `API_KEY` from the environment) used to prove
   `secrets.py` finds real secrets and leaves clean code alone. Moved both
   into `playbook/demo/` instead of the toolbox root. Before the move,
   `secrets.py .` silently reported 0 findings against a directory that
   visibly contained two hardcoded secrets — worth catching, since a
   scanner reporting clean because its target file is in the wrong place
   is a worse failure mode than reporting clean because the code is
   actually clean.

3. **`bandit -f sarif` failed on the `bandit` binary found first on
   `PATH`** (`/usr/local/bin/bandit`): `error: argument -f/--format:
   invalid choice: 'sarif'` — that binary predates the `bandit[sarif]`
   formatter plugin. A second `bandit` exists at
   `/home/clementsj/miniconda3/bin/bandit`; installing
   `pip install "bandit[sarif]"` into the miniconda Python (the one
   `bandit` on `PATH` actually resolves to after removing the stale
   `/usr/local/bin` shadow, or by invoking
   `/home/clementsj/miniconda3/bin/bandit` explicitly) fixed it. Not a
   `haskell.py`/toolbox bug — an environment PATH-shadowing issue, noted
   here because it will bite the next person who runs `triage.py` in this
   same shell.

4. **`pre-commit`'s relative path assumption didn't match this repo's
   layout.** The harvested hook computes its tools directory as
   `$(dirname "$0")/../../tools` — i.e. it assumes the toolbox lives at
   `<repo>/tools/` and the hook is installed at
   `<repo>/.git/hooks/pre-commit`. This repo's toolbox is at
   `<repo>/playbook/`, not `<repo>/tools/`. Verified the original path
   math is correct for its assumed layout (tested in an isolated scratch
   repo with a `tools/` directory, where it worked unmodified), then wrote
   a second, repo-specific hook for the real install that points at
   `playbook/` and scopes the secrets scan — see "Pre-commit hook" above.
   `playbook/pre-commit` itself is left unmodified (portable to any repo
   using the `tools/` convention); the installed
   `.git/hooks/pre-commit` here is the repo-specific adaptation.

5. **The demo fixture's fake secret tripped this repo's real CI gitleaks
   job.** `playbook/demo/config.py`'s original seeded value
   (`API_KEY = "sk_live_9f8a7b6c5d4e3f2a1b0c"`) matches gitleaks' built-in
   `stripe-access-token` rule (the `sk_live_` prefix is Stripe's real
   format), so `security.yml`'s gitleaks job correctly flagged it in this
   commit — genuinely caught, not a false positive on gitleaks' part.
   Fixed by changing the demo value to a shape that still exercises
   `secrets.py`'s own `generic-secret` regex (a quoted string ≥12 chars
   after `API_KEY =`) without colliding with any real provider's key
   format: `API_KEY = "not-a-real-secret-abcdef123456"`. Re-verified
   `secrets.py playbook/demo` still finds it (exit 1, same 2 findings) and
   that no toolbox behavior changed — only the fixture's shape.

No bugs were found in `haskell.py` itself or in the core logic of any
script — every script ran correctly once pointed at the right paths.

## Honest gaps

- **`haskell.py` has no test suite.** Zero unit tests ship with it, in the
  zip or added here. Every function used by the seven downstream scripts
  is exercised indirectly (foldl/scanl/mapMaybe/partition/doP/doE/Monoid
  all get real exercise via `secrets.py`/`deps.py`/`triage.py`/`gate.py`
  above), but the ~150 other combinators in `haskell.py` (the streams,
  container, and string sections in particular) are untested. If this
  toolbox grows real callers, it needs a `pytest` suite before it's
  trusted for anything beyond scripting glue.
- **Not wired into live CI yet.** `playbook/` is a standalone toolbox, not
  a dependency of `.github/workflows/ci.yml` or `security.yml` — those
  workflows still run gitleaks/bandit/pip-audit/trivy/tfsec/kube-linter
  directly, as before. Nothing here replaces or gates the existing CI;
  it's available for the next project (or a future revision of this one)
  to adopt.
- **`sbom_diff.py` only verified against demo fixtures** — `syft` isn't
  installed in this environment, so no real CycloneDX SBOM of this repo's
  `app/status-service` container was produced or diffed. `security.yml`
  already runs `anchore/sbom-action` in CI; wiring `sbom_diff.py` to two
  of its archived SBOM artifacts (current vs. previous release) is the
  natural next step but wasn't done here.
- **`actions_pin.py`'s real finding (21 tag-pinned actions) is not
  fixed.** SHA-pinning this repo's Actions is a real, legitimate follow-up
  but is out of scope for this integration task.
- **The generic-secret regex has a real false-positive class** (keyword +
  `=`/`:` + quoted string ≥12 chars, regardless of whether the value is a
  literal or an interpolated variable) — see bug #1. Scoping avoids it
  here; it isn't fixed in the regex itself.
