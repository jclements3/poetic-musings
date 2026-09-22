# Chapter 5 — Zone 5: SECURE

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone is the whole point of "DevSecOps"

Take the word apart: Dev-Sec-Ops. Security sits in the middle on purpose. Not
bolted onto the end after Dev builds it and Ops ships it — folded into the
loop, running on every commit, before a human ever has to remember to ask for
it. That is the entire pitch of the discipline, and it is also the part most
easily faked on a resume, because "security is embedded in our pipeline" is
a sentence anyone can write. The only way to tell the difference between a
team that means it and a team that's decorating a diagram is to ask: show me
the last real finding your gates caught, and show me the fix.

This chapter is going to do that, repeatedly, with commands and commit-level
specifics, because that's the only kind of security chapter worth reading in
a DevSecOps book. It will also be the most careful chapter in the book about
labeling what's proven against a real system and what's course knowledge
never deployed here — because in security, that distinction isn't pedantic,
it's the whole job. A resume line that implies a tool is running when it
isn't is a fireable kind of dishonest in this field, not a rounding error.

**The cost curve, briefly, because it's the argument for all of this.** A
hardcoded credential caught by a pre-commit hook costs you a re-typed line.
The same credential caught by gitleaks in CI costs you a failed pipeline and
a five-minute fix. The same credential caught in a security audit six months
after it shipped costs you a credential rotation, an incident report, and
possibly a disclosure obligation. The same credential caught by an attacker
costs you the rest of your career explaining what happened. Every zone in
this book front-loads cost. This one front-loads it hardest, because the
alternative to shifting left here isn't "slower," it's "a different kind of
incident."

Concretely, that means: the 7-gate pipeline described below runs on *every*
push and PR to `main` (`.github/workflows/security.yml`, triggers `on: push`
/ `pull_request` / a weekly `cron: "0 6 * * 1"` to catch newly-disclosed CVEs
against code that hasn't changed). It's not a monthly audit. It's not a
pre-release checklist. It's a standing gate a developer meets on every single
merge, which means the median time between "vulnerability introduced" and
"vulnerability caught" is measured in minutes, not months. That's the shift.

---

## 2. CIS vs. STIG — precisely, because interviewers ask this on purpose

This is a real, common interview trap, and it's worth getting exactly right
rather than approximately right, because "approximately right" is what gets
weeded out.

**CIS Benchmark** (Center for Internet Security) is a **vendor-neutral,
industry-consensus** hardening baseline. It's produced by a nonprofit through
a community consensus process, covers a wide range of platforms (Linux
distros, Kubernetes, cloud providers, browsers), and is the baseline most
commercial and cloud-native shops reach for by default because it isn't tied
to any one customer or contract. `kube-bench` (used in this repo) implements
the **CIS Kubernetes Benchmark** — it doesn't invent its own opinions, it
scores a cluster against CIS's published control numbers (`1.2.17`,
`4.1.1`, etc.).

**DISA STIG** (Security Technical Implementation Guide, from the Defense
Information Systems Agency) is **not** a general industry baseline — it is
**the specific, DoD-mandated compliance standard**. It exists because the
Department of Defense needs a single, authoritative, auditable hardening
spec that every system under its purview is measured against, with legal and
contractual weight behind it (ATO — Authority to Operate — processes cite
STIG findings directly). This job posting (GMD DevSecOps Engineer, Valkyrie
Enterprises) names STIG **by name**: "STIG evaluation, analysis,
implementation." That is not interchangeable language with "CIS Benchmark."
If you say "we run CIS so we're STIG-compliant" in an interview for a DoD
contractor role, you have just told the panel you don't understand the
requirement you're being hired to meet.

**They are complementary, not interchangeable, and both matter here:**

| | CIS Benchmark | DISA STIG |
|---|---|---|
| Authority | Center for Internet Security (nonprofit, consensus) | Defense Information Systems Agency (DoD) |
| Scope | Vendor-neutral, broad platform coverage | DoD systems; profile per specific OS/product |
| Contractual weight | Industry best practice, often a SOC2/audit input | Mandatory for DoD ATO; legally binding in that context |
| Tooling used here | `kube-bench` (CIS Kubernetes Benchmark) | `oscap`/OpenSCAP against DISA's own SCAP Security Guide (SSG) content |
| What's scored in this repo | A live `kind` cluster's control plane | A real UBI8/RHEL8 filesystem via SCAP content |
| Real result | 62 PASS / 11 FAIL | 67 PASS / 51 FAIL / 286 N/A / 5 notchecked |

Both scans in this repo are real and both are honestly scored — see §4 and
§5 for the specifics. The point to internalize for the interview and for the
job: CIS gives you a general-purpose hardening posture; STIG gives you the
specific, auditable artifact a DoD ATO reviewer will ask for. A mature
program runs both, for different reasons, against different targets, and
never conflates one for the other in a report.

---

## 3. The 7-gate CI pipeline, tool by tool

All seven gates live in one workflow file: `.github/workflows/security.yml`.
It runs as seven independent jobs (parallel, not sequential), each scoped
with a `contents: read` default and elevated only where an upload needs it
(`security-events: write` for the SARIF-uploading jobs). Every job has a
graceful skip path (`if [ ! -d app ]; then ... exit 0`) so the pipeline
doesn't fail on a repo that hasn't grown that artifact yet — a pattern worth
stealing for any repo where the security workflow is added before all the
code it will eventually cover exists.

### 3.1 Gitleaks — secrets detection

**What it catches**: hardcoded credentials, API keys, tokens, private key
material — via a combination of regex pattern rules for known secret shapes
(AWS keys, Stripe tokens, JWTs, etc.) *and* Shannon-entropy scoring for
generic high-entropy strings that don't match a known vendor pattern.

**What it doesn't catch**: secrets that are already correctly externalized
(environment variables, injected at runtime) — by design, since there's
nothing to flag. It also can't catch a secret that's been base64'd or
otherwise obfuscated past its entropy threshold without a specific rule for
that shape.

**Real command**:
```bash
gitleaks detect --source . --verbose
```
In CI it runs as `gitleaks/gitleaks-action@v2` with `fetch-depth: 0` (full
git history, not just the working tree — gitleaks scans commits, so a
secret committed and later deleted is still a finding unless history is
rewritten).

**Real finding in this repo**: gitleaks correctly flagged a seeded demo
fixture. `playbook/demo/config.py`'s original placeholder secret happened to
match the literal Stripe key shape (`sk` + `_live_` + a token suffix) that
gitleaks' built-in `stripe-access-token` rule detects — and it fired, for
real, in this repo's actual CI. That's not a false positive on gitleaks'
part; the fixture accidentally produced a real Stripe-shaped string. The fix
was changing the fixture's value to something that still exercises the
*other*, simpler `secrets.py` script's regex (see §7) without colliding with
any real vendor's key format. Worth internalizing: a "test" secret that
looks plausible enough to be a good test fixture is also plausible enough to
trip a real scanner. That's a feature, not a bug, in how gitleaks is tuned.

### 3.2 Bandit — Python SAST

**What it catches**: Python-specific insecure code patterns — `eval()`/
`exec()` on untrusted input, `subprocess` calls with `shell=True`, weak
hashing (`md5`/`sha1` for security purposes), hardcoded `bind` to
`0.0.0.0`, insecure deserialization (`pickle.loads`), SQL string
concatenation, and more, organized by CWE and severity.

**What it doesn't catch**: logic bugs, authorization flaws, anything that
requires understanding business intent rather than syntactic pattern
matching. Bandit is a linter for known-bad *shapes*, not a security
reasoning engine.

**Real command** (exactly what CI runs):
```bash
bandit -r app -f sarif -o .scan-out/bandit.sarif --exit-zero
bandit -r app -ll -x '**/tests/**'
```
Note the two-pass structure: the first pass always succeeds and produces a
SARIF file for upload (`--exit-zero`), the second pass is the actual gate
(`-ll` = only medium/high confidence-and-severity, excluding test files) and
its exit code decides pass/fail.

**Real result in this repo**: clean. `bandit -r app -f sarif --exit-zero`
against `app/status-service` reports zero findings, matching the
independently-run Jenkins mirror of the same pipeline (`jenkins/README.md`:
"No issues identified"). Worth being honest about what "clean" proves here —
the app is a small status service; a clean bandit run on a small, simple
codebase is a much weaker signal than a clean run on a large one. Don't
oversell a small green checkmark.

### 3.3 Syft — SBOM generation

**What it catches**: nothing, by itself — Syft doesn't scan for
vulnerabilities, it **inventories**. It walks a filesystem or image and
produces a Software Bill of Materials (SBOM), a structured list of every
package, its version, and its origin. The SBOM is the *input* other tools
(pip-audit, Trivy, Grype) consume to actually find CVEs.

**Why it matters on its own**: an SBOM is the artifact you hand an auditor
or a downstream consumer so they can answer "are we affected by CVE-2024-
whatever" the moment it's disclosed, without re-scanning your entire build
history. It's also the artifact `sbom_diff.py` (Zone 9, evidence) consumes
to show component drift release-to-release — the supply-chain changelog.

**Real command** (as run in CI, via `anchore/sbom-action@v0`):
```bash
syft app/status-service -o cyclonedx-json=sbom-status-service.cdx.json
```

**Honest gap**: this repo's own `sbom_diff.py` (Zone 5/9 toolbox script)
has never been run against a real SBOM of this repo's own containers — Syft
isn't installed in the environment that toolbox was verified in, so
`sbom_diff.py` was only proven against seeded demo fixtures. The CI
pipeline's own Syft step is real and runs on every push; the *drift-diffing*
of two of its outputs is the un-taken next step.

### 3.4 pip-audit — dependency CVE scan (SCA)

**What it catches**: known CVEs in installed Python dependencies, matched
against the Python Packaging Advisory Database (PyPA's own vulnerability
feed, itself sourced partly from OSV).

**What it doesn't catch**: vulnerabilities in code you wrote yourself
(that's bandit's job), or in packages that don't have a published advisory
yet (zero-days by definition don't show up here).

**Real command**:
```bash
pip-audit -r app/status-service/requirements.txt -f json -o pip-audit-results.json
```

**Real finding, not staged**: this is the chapter's headline catch. An early
run of pip-audit against this app's live `requirements.txt` found a genuine
disclosed Flask CVE — a missing `Vary: Cookie` header, a real cache-
poisoning-adjacent class of bug where a response that varies by session
cookie can be cached and served to the wrong user if the cache doesn't know
to vary on that header. The fix was mechanical once found: bump `flask`
3.0.3 → 3.1.3. That's the shape of a shift-left win in one sentence — a
scanner caught a real, disclosed vulnerability in a dependency before it
ever reached a user, and the fix was a version bump, not an incident.

Current state, re-verified live against this repo's real, pinned
requirements (`flask==3.1.3`, `gunicorn==22.0.0`, `prometheus-client==0.21.1`):
```
$ pip-audit -r app/status-service/requirements.txt -f json
"No known vulnerabilities found"
```
Clean, for now — which is exactly why this runs on a weekly cron as well as
every push: the code doesn't change on Monday morning, but the CVE database
does.

### 3.5 Trivy — container image scan

**What it catches**: known CVEs in everything baked into a built container
image — OS packages from the base image, language-runtime packages, and
(depending on config) IaC misconfigurations and secrets, though this repo
uses it specifically for the image-scan role.

**What it doesn't catch**: anything not present in the image at scan time,
or vulnerabilities not yet in Trivy's vulnerability DB (it needs periodic DB
updates to stay current, which the GitHub Action handles automatically).

**Real command** (as run in CI via `aquasecurity/trivy-action@v0.24.0`):
```bash
trivy image --format sarif --severity HIGH,CRITICAL --ignore-unfixed \
  --exit-code 1 status-service:ci
```

**Real finding, not staged, and the more interesting one**: Trivy caught **6
real CVEs baked into the base `python:3.12-slim` image's own bundled `pip`**
— not this repo's application code, not even the app's direct dependencies,
but vulnerabilities in the packaging tool (`pip`/`setuptools`/`wheel`)
sitting unused inside the *runtime* image. This is exactly the class of
finding a team that "only scans their own code" misses, because the app
never imports `pip` — it's dead weight from the base image that Trivy caught
by scanning the actual shipped artifact rather than the source tree. The
fix was to strip `pip`, `setuptools`, and `wheel` out of the runtime image
entirely (multi-stage build: install with pip in a build stage, copy only
the resulting site-packages into a runtime stage that never has pip
installed). Smaller attack surface, smaller image, and a class of CVE that
literally cannot recur because the tool that had it is gone.

That's the lesson to carry into an interview: Trivy's value over pip-audit
alone is that it scans the *artifact*, not the *manifest* — it catches
things that never appear in `requirements.txt` at all.

### 3.6 tfsec — IaC scan for Terraform (and its 2024 absorption into Trivy)

**What it catches**: Terraform misconfigurations against a large rule set —
public S3 buckets, overly-permissive security groups, missing encryption at
rest, IAM wildcard policies, missing flow logs, and so on.

**A real, current fact to know**: **tfsec was deprecated as a standalone
project in 2024** — Aqua Security (tfsec's maintainer, also Trivy's
maintainer) folded tfsec's rule engine into Trivy itself, under `trivy
config`. The standalone `tfsec` binary and its GitHub Actions
(`aquasecurity/tfsec-action`, `tfsec-sarif-action`) still work and are still
what this repo's `security.yml` uses today, but they're in maintenance mode,
not active development — new rules land in `trivy config` first. A team
picking this up fresh in 2026 should plan to migrate this job to `trivy
config` rather than treating `tfsec` as the long-term tool; this repo hasn't
made that migration yet, which is itself worth naming as a small, known,
low-urgency modernization gap rather than pretending tfsec is the
permanent answer.

**Real command** (current, as run in CI):
```bash
tfsec infra/terraform --exclude aws-iam-no-policy-wildcards
```
**Real command** (the forward-looking equivalent):
```bash
trivy config infra/terraform
```

**Real, honest suppression in this repo**: one rule,
`aws-iam-no-policy-wildcards`, is excluded repo-wide via `--exclude`, with
the justification documented directly in the workflow file's comment and
per-occurrence in `iam.tf`/`network.tf`: every flagged case is a
`"${arn}/*"` or `"${arn}:*"` suffix scoped to one specific named resource
(an S3 bucket ARN, a CloudWatch log group ARN) — object/stream-level AWS
permissions syntactically require that wildcard suffix; it is not an
account- or service-wide wildcard. This is the right way to suppress a
scanner rule: named, justified, documented in more than one place, and
narrow (excludes one rule ID, not the whole scan).

### 3.7 kube-linter — Kubernetes manifest policy scan

**What it catches**: policy-level Kubernetes misconfigurations at the
manifest level — missing resource limits, running as root, missing
liveness/readiness probes, missing PodDisruptionBudgets, hostPath mounts,
privilege escalation allowed, and more. It's a *static* linter — no cluster
needed.

**What it doesn't catch**: admission-time or runtime issues (that's
`kubectl apply --dry-run=server` and the cluster's own admission
controllers, one layer up the Zone 7 pre-deploy chain: kubeconform → kube-
linter → dry-run → apply, cheapest check first).

**Real command**:
```bash
kube-linter lint k8s/
```

**Real finding in this repo**: 6 real kube-linter findings, fixed with
anti-affinity rules and PodDisruptionBudget eviction-policy changes — not
staged, not left open. This is a genuine before/after: the manifests in
`k8s/` today reflect the fixed state.

### 3.8 CodeQL — semantic static analysis

**What it catches**: CodeQL is GitHub's semantic code analysis engine — it
builds a queryable database of a codebase's data flow and control flow and
runs queries against it (taint tracking from an untrusted source to a
dangerous sink, for example). It's a materially deeper analysis than
bandit's pattern-matching: bandit asks "does this line look like a known-bad
shape," CodeQL asks "can untrusted input actually reach this sink through
any path in this codebase."

**What it doesn't catch**: it's still static analysis — no runtime state,
no knowledge of what an attacker can actually reach given real network
topology or auth. It complements bandit rather than replacing it; this repo
runs both, with all SARIF output (bandit's, Trivy's, tfsec's) centralized
into GitHub's code scanning view via `github/codeql-action/upload-sarif@v3`,
so findings from four different tools land in one dashboard instead of four
disconnected reports.

---

## 4. Applied to poetic-musings: real findings, not staged ones

The point of this section is to teach the reasoning, not just recite the
catches — because the actual job is going to be doing this against a system
you've never seen before, with no README to read first.

**The Flask CVE reasoning**: a version-pinned dependency
(`flask==3.0.3`) is not the same claim as "this dependency has no known
issues." Pinning gives you reproducibility, not safety — a pinned version
can have a CVE disclosed against it the day after you pin it, and nothing
about the pin itself will tell you. That's why `pip-audit` runs on every
push *and* on a weekly cron against unchanged code: the code is static, the
CVE database isn't. When pip-audit flags a dependency, the triage question
is always the same: is this CVE in a code path this app actually exercises,
and is there a fixed version available. Here, yes and yes — bump and done.
When the answer to the first question is "no, we don't use that code path,"
the honest move is a documented, expiring waiver (see `waivers.json` /
`triage.py` in the playbook toolbox), not silence.

**The base-image pip CVE reasoning**: this is the more instructive one to
carry forward, because it generalizes. The question to ask of *any* base
image is not "what does my `requirements.txt` say" but "what is actually
present in the shipped artifact, including things I never asked for."
`python:3.12-slim` ships pip because pip is how you'd install packages into
that image in the first place — but a *runtime* image that already has its
dependencies baked in during a build stage has no further use for pip, and
every unused tool in a runtime image is attack surface with zero offsetting
benefit. The general pattern: multi-stage build, install/build in stage
one, copy only site-packages (and the app) into a minimal runtime stage
that never installs the package manager at all. Re-run Trivy after that
change; the CVE count for those 6 findings goes to zero because the
vulnerable package is no longer present, not because it was patched.

**The STIG 51 real fails, root-caused for a system you've never seen
before** (the general method, demonstrated against this repo's real scan):

1. **PAM password/account policy fails** (`pam_faillock`, `pam_pwhistory`,
   `pam_pwquality` — `dcredit`, `lcredit`, `minclass`, `maxrepeat`, etc.).
   Root cause: a base OS image ships PAM in its *default* configuration,
   because password-complexity and lockout policy is a site-specific
   hardening decision, not something a vendor can bake in without knowing
   your organization's password policy. Reproduce the reasoning on any
   unfamiliar RHEL/CentOS box: `cat /etc/security/pwquality.conf` and
   `cat /etc/pam.d/system-auth` — if those still hold vendor defaults, the
   box will fail the same STIG rules, for the same reason, regardless of
   what application runs on it.
2. **Crypto policy fails** (`configure_crypto_policy`, SSH cipher/MAC
   hardening). Root cause: RHEL's system-wide crypto policy defaults to a
   general-compatibility setting, not `FIPS` or `DISA_STIG`. Check with
   `update-crypto-policies --show`; the STIG-compliant fix is
   `update-crypto-policies --set DISA_STIG` (or `FIPS` where that's the
   actual requirement) — one command, but it changes what TLS/SSH ciphers
   the whole box will negotiate, so it's not something to run blind on a
   box with live traffic without checking compatibility first.
3. **RPM integrity fails** (`rpm_verify_hashes`, `rpm_verify_ownership`,
   `gpgcheck_local_packages`). Root cause: package-manager-level integrity
   verification isn't enforced by default. Check with `rpm -Va` (verifies
   installed package files against RPM's recorded hashes/ownership) and
   `cat /etc/dnf/dnf.conf` / `/etc/yum.conf` for `gpgcheck=1`. These
   controls exist to catch tampered packages and post-install file
   modification — exactly the kind of thing that matters on a system
   handling classified or mission-critical workloads.

The pattern across all three categories, and the thing to actually carry
into the job: **none of these are bugs in the base image.** A minimal,
unopinionated base OS image doing minimal, unopinionated things is
*correct* vendor behavior. STIG failures on a fresh image are the expected,
honest starting state — the finding isn't "this image is broken," the
finding is "this image has not yet been through a hardening pass," and the
scan's entire value is telling you precisely which 51 rules that pass has to
touch, by rule ID, instead of guessing.

---

## 5. DISA STIG in depth

**OpenSCAP / `oscap`** is the open-source engine that evaluates a system
against SCAP (Security Content Automation Protocol) content — a standardized,
machine-readable format (XCCDF for the checklist structure, OVAL for the
individual technical checks) that lets a scan be reproducible, versioned,
and vendor-neutral in its *mechanics* even when the *content* it's loaded
with is a specific vendor's or agency's standard.

**SCAP Security Guide (SSG)** is the content project that actually writes
the checklists — DISA publishes STIG profiles as SSG content for the OSes
it covers (RHEL family primarily); other organizations publish CIS profiles
the same way, in the same datastream format, which is why a single content
file can contain rules belonging to several different profiles (STIG, CIS,
PCI-DSS) and a scan run selects just one profile's subset via an XCCDF
profile ID.

**XCCDF profiles** are the selectable subset of rules within a datastream.
This repo's real scan selected `xccdf_org.ssgproject.content_profile_stig`
— "DISA STIG for Red Hat Enterprise Linux 8" — out of `ssg-rhel8-ds.xml`,
which also contains rules for other profiles never selected here (scored as
`notselected`, not failures — 1,163 of them in this repo's real datastream,
correctly excluded from the 409-rule STIG scope actually evaluated).

**Real command sequence, as actually run to produce this repo's scan**
(`stig/README.md`):
```bash
# Get a real RHEL8 filesystem (no subscription required)
docker create --name ubi8tmp registry.access.redhat.com/ubi8/ubi:latest
docker export ubi8tmp | tar -x -C ./ubi8-root
docker rm ubi8tmp

# Evaluate offline against that filesystem
OSCAP_PROBE_ROOT=./ubi8-root oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --results scap-results.xml \
  --report scap-report.html \
  ssg-rhel8-ds.xml
```
Two version-specific snags worth knowing before you hit them cold: this
version of `oscap` has no `--chroot` flag (a newer CLI addition) — the
offline-root equivalent is the `OSCAP_PROBE_ROOT` environment variable, as
above; and `openscap-scanner` doesn't exist as an installable package name
on Ubuntu 22.04 (only 24.04/`noble`) — on 22.04 the `oscap` binary ships
inside `libopenscap8` itself.

**The natural next step — this repo's biggest still-open real gap**: this
scan has **not been remediated**. It shows the unremediated baseline only.
The next step is either `oscap xccdf eval --remediate` (applies fixes
directly, rule by rule, during the same scan run) or, more suitable for a
fleet rather than a single box, an Ansible role built from SSG's own
published remediation content (SSG ships Ansible and Bash remediation
scripts alongside its check content, generated from the same rule
definitions). The expected before/after: re-scanning after remediation
should show the 51 FAILs drop toward 0, with any remaining fails explained
individually (some rules genuinely can't apply to a container filesystem
rather than a booted host — see the honest gaps below). That before/after
comparison is the actual deliverable a real STIG compliance pipeline
produces, and it is the single most concrete, resume-honest thing to build
next in this repo if asked to extend it.

**Also worth naming plainly**: this scan targets a RHEL8 base image (UBI8),
not this repo's own application containers, which are Debian/Ubuntu-based.
That's not a shortcut — there is no official DISA STIG content for Ubuntu
(Canonical's own SSG packages ship CIS profiles for Ubuntu, not STIG), so
scanning UBI8 with DISA's real RHEL8 STIG content is the only way to run a
correctly-labeled DISA STIG evaluation in this environment, rather than
mislabeling a CIS-Ubuntu scan as STIG. Precision about what a scan is
actually measuring is exactly the discipline this whole chapter is arguing
for.

---

## 6. Course-only tools, taught honestly

Every tool below is covered in Module 6 (SonarQube) and Module 7 (Security
Tools) of the underlying training program, and every one of them is a real,
important, widely-deployed tool a working DevSecOps engineer needs to know.
**None of them is installed or run anywhere in this repository.** That
sentence is not a disclaimer buried once — it's the operating rule for this
whole section, restated per tool, because blurring "I've used this in a
course lab" with "I've run this in production against real findings" is
exactly the kind of resume inflation this book refuses to do, and exactly
the kind of claim a competent interviewer will probe until it cracks.

### 6.1 SonarQube — *not deployed in this repo — course knowledge*

SonarQube is a code-quality and security static-analysis platform that
centralizes findings across a codebase into **Quality Gates** — a
pass/fail threshold on metrics like code coverage, duplicated lines,
maintainability rating, and security hotspots. The mechanism that makes it
a real CI gate (not just a dashboard) is its webhook: SonarQube posts the
gate result back to the CI system after analysis completes, and the CI job
polls or waits on that webhook to decide whether to block the merge. Setup
spans local Docker, Kubernetes, or a managed instance; **Quality Profiles**
define which rules apply per language, and **branch analysis** (a paid-tier
feature in Community Edition, free in Developer Edition) lets a feature
branch see its own gate status before merge rather than only on `main`.
Typical invocation from CI:
```bash
sonar-scanner \
  -Dsonar.projectKey=status-service \
  -Dsonar.sources=app/status-service \
  -Dsonar.host.url=$SONAR_HOST_URL \
  -Dsonar.login=$SONAR_TOKEN
```
This repo's real coverage of the *same job* SonarQube would do — centralized
findings, CI-blocking gates — is instead the 7-gate pipeline plus CodeQL in
§3, which is broader in scanner diversity (secrets, SCA, container, IaC,
k8s policy) than SonarQube's code-quality focus alone, but does not do
SonarQube's specific job of code *quality* metrics (duplication,
maintainability, coverage trending). They're complementary, not
substitutes, and this repo genuinely has one and not the other.

### 6.2 OWASP Dependency-Check and OWASP ZAP — SAST/SCA vs. DAST, *not deployed here — course knowledge*

**OWASP Dependency-Check** is a Software Composition Analysis (SCA) tool —
the same job class as pip-audit, but multi-ecosystem (Java, .NET, JS,
Python) and sourced against the National Vulnerability Database rather than
PyPA's advisory feed specifically. Where this repo already has a real
Python-specific SCA gate (pip-audit), Dependency-Check would be the tool of
choice for a polyglot codebase this one isn't.

**OWASP ZAP** (Zed Attack Proxy) is fundamentally different in kind, and
this distinction is a second real interview trap worth being precise about:
everything in §3 (bandit, CodeQL) is **SAST** — Static Application Security
Testing, analyzing source code or binaries without running them. ZAP is
**DAST** — Dynamic Application Security Testing, it drives a *running*
application over HTTP (spidering it, then actively attacking it — injection
probes, XSS payloads, auth bypass attempts) and finds what only manifests at
runtime: reflected XSS that a static scan can miss because the vulnerable
sink is reached through a code path SAST didn't trace, misconfigured
security headers, session-handling flaws. Typical baseline scan:
```bash
docker run -t zaproxy/zap-stable zap-baseline.py -t https://target-app -r report.html
```
This repo has zero DAST coverage — no running instance of the app is ever
attacked as part of CI. That's a real, nameable gap for any web-facing
service, worth flagging honestly rather than implying the 7 static gates in
§3 cover what only a DAST tool can find.

### 6.3 Prowler — AWS security posture, *not deployed here — course knowledge*

Prowler is an open-source AWS (and multi-cloud, in newer versions) security
posture scanner — it evaluates a live AWS account against CIS AWS
Foundations Benchmark controls, plus its own broader rule set, checking
things static IaC scanning like tfsec fundamentally cannot: IAM users with
console access and no MFA, S3 buckets that are public *right now* regardless
of what Terraform says they should be, CloudTrail actually enabled and
logging, root account usage. That's the key conceptual distinction from
tfsec: **tfsec scans the IaC source before it's applied; Prowler scans the
live account after everything (including manual console changes, drift,
and anything applied outside Terraform) has taken effect.** A mature
program needs both, for the same reason SAST and DAST are both needed — one
catches what's written, the other catches what's actually true. Typical
invocation:
```bash
prowler aws --compliance cis_2.0_aws
```
This repo's `infra/terraform` is scanned by tfsec pre-apply; nothing scans
the live AWS account state post-apply. Named honestly as a gap, not glossed.

### 6.4 Dockle — Docker image linting, *not deployed here — course knowledge*

Dockle checks a built container image against CIS Docker Benchmark and
Dockerfile best-practice rules — running as root by default, missing
`HEALTHCHECK`, unnecessary `setuid`/`setgid` bits, secrets left in image
layers, `latest` tag usage. It's a different layer than Trivy: **Trivy asks
"does this image contain a package with a known CVE," Dockle asks "was this
image built the right way."** A clean Trivy scan and a Dockle-flagged image
(running as root, no HEALTHCHECK) can coexist — zero known CVEs today, still
structurally risky. Typical invocation:
```bash
dockle status-service:ci
```
Not run anywhere in this repo's pipeline. The multi-stage build described in
§3.5/§4 (stripping pip from the runtime image) happens to also be the kind
of improvement Dockle would specifically reward, but that was driven by the
Trivy finding, not a Dockle scan.

### 6.5 HashiCorp Vault — dynamic secrets, *not deployed here — course knowledge*

Vault's core idea is worth understanding precisely because it's a genuinely
different model from everything else in this chapter, not just a
"secrets storage" product: rather than storing a static credential that
CI reads out of an environment variable (a `GITHUB_TOKEN` secret, a static
DB password), Vault can **issue short-lived, dynamically-generated
credentials on demand** — a database plugin that creates a brand-new
Postgres user with a 15-minute TTL for the duration of one CI job, then
revokes it automatically. The security property that buys: even a fully
leaked credential from that job is worthless within 15 minutes, and there's
never a long-lived static secret sitting in a CI variable for gitleaks-class
scanning to have to catch in the first place — the entire class of "secret
leaked from a CI log or environment dump" shrinks because the secret that
would have leaked no longer has a meaningful lifetime. Typical CI-side flow:
```bash
vault write auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID
vault read database/creds/status-service-readonly
```
This repo's real secrets posture is entirely static: pinned `requirements.txt`
values, GitHub Actions `secrets.*` (also static, injected as environment
variables), and the toolbox's own `secrets.py`/gitleaks catching static
secrets that leak into source. There is no dynamic-secret issuance anywhere
in this repo. See §7 for why that gap matters and what closing it would
look like.

---

## 7. Secrets management done right

**Why hardcoded secrets keep happening, structurally**: it's always the
path of least resistance during development. `os.environ.get("API_KEY")`
requires setting up an environment; `API_KEY = "abc123"` requires nothing,
runs immediately, and gets committed by the same `git add .` that commits
everything else once a developer forgets to remove it before pushing. No
amount of policy documentation stops this reliably — the only thing that
works is a gate that catches it mechanically before it merges, which is
exactly why gitleaks runs on every push in this repo rather than being a
line item in a security wiki nobody reads.

**Two real approaches in this repo, honestly compared.** `secrets.py`
(this repo's own point-free-Python toolbox script, `playbook/secrets.py`)
uses a simple keyword + quoted-string regex: something shaped like
`API_KEY = "<12+ char string>"` gets flagged as a `generic-secret`.
Gitleaks uses a much larger, maintained rule set of vendor-specific key
*shapes* (AWS `AKIA...`, Stripe `sk_live_...`, GitHub PATs, JWTs) plus
Shannon-entropy scoring for generic strings that don't match a known
pattern. The honest comparison: **gitleaks catches more and is more
precise** — it distinguishes a real AWS key from a random 12-character
string by its actual structure, and entropy scoring means it can flag a
truly random secret even with no matching vendor pattern. `secrets.py`'s
regex is *transparent and hackable* — the entire detection logic is a few
lines of readable Python anyone on the team can extend for an org-specific
naming convention gitleaks has no rule for, with no external tool
dependency. Different tradeoffs, not a strict ranking: gitleaks for
breadth and precision in CI, a hand-rolled scanner for something a team
needs full control over.

**The real false-positive this comparison exposed** (from
`playbook/README.md`, not hidden): running `secrets.py`'s naive
keyword-regex against this repo's whole tree flagged
`ad-lab/seed-objects.sh`'s `samba-tool gpo setlink ...
--password="${ADMIN_PASSWORD}"` as a `generic-secret` — because the regex
matches `password="..."` regardless of whether the quoted content is a
literal value or a shell variable interpolation (`${ADMIN_PASSWORD}` isn't
a secret, it's a reference to one). That's not a code bug — the regex does
exactly what it says — it's a real, named precision gap versus gitleaks,
which does enough context/entropy analysis to not flag a variable
interpolation as a literal secret. The operational fix applied here wasn't
patching the regex, it was scoping the scanner to source directories
(`app/ infra/ k8s/ ansible/`) rather than the whole tree, and documenting
the false-positive class plainly rather than special-casing it away. That's
the right instinct in general: when a simple tool has a known, named
limitation, either scope around it or replace it with the more precise
tool — don't quietly patch the simple tool into false confidence.

**Vault's dynamic-secret model as the mature end state**: everything in this
section so far is about catching a *static* secret that already leaked.
Vault's model removes the target: if a credential is regenerated per-job
with a 15-minute TTL, there is no long-lived static value sitting in a repo,
a CI variable, or a log for a scanner to have to catch in the first place.
That's a genuinely different security posture, not just a bigger scanner —
it's the difference between "we have good alarms" and "there's nothing left
to set off the alarm." This repo has the alarms (gitleaks + secrets.py) and
does not have the dynamic-secret architecture; that's a real, named
maturity gap, not a course footnote.

---

## 8. Day-one checklist for this zone

1. **Find every scanning gate already in place.** Read every CI/CD
   workflow file end to end (`.github/workflows/*.yml`, any Jenkinsfile,
   GitLab CI config) — don't trust a README's summary of what runs; the
   workflow file is ground truth. Note trigger conditions (push only? PR
   only? scheduled?) and whether each gate actually fails the build or
   only reports (`--exit-zero`, `continue-on-error: true`).
2. **Run each gate manually once, locally, against the real codebase**, not
   a toy input — `gitleaks detect --source .`, `bandit -r <app-dir> -ll`,
   `pip-audit -r <requirements>`, `trivy image <built-tag>`, `tfsec
   <tf-dir>`, `kube-linter lint <k8s-dir>` — to see the real output format,
   real exit codes, and real runtime before you ever have to debug a CI
   failure under time pressure.
3. **Check for suppressed or ignored findings and audit whether the
   justification still holds.** Grep for `# nosec`, `#tfsec:ignore:`,
   `--exit-zero`, `--exclude`, `.trivyignore`, `--ignore-unfixed`, waiver
   files. For each one found, confirm the original justification (this
   repo's `aws-iam-no-policy-wildcards` exclusion is a good example of what
   "justified" looks like: narrow, named, explained in more than one
   place) — a suppression with no comment, no owner, and no expiry is a
   silent hole, not a documented decision.
4. **Identify what's not scanned yet.** Cross-reference the running gates
   against the full threat surface: is there a running service with no
   DAST coverage (§6.2)? A cloud account with no post-apply posture scan
   (§6.3)? A host-level compliance standard the job requires (STIG, §5)
   that's never been run, or run once and never remediated? Write the gap
   list down explicitly — it's the single most useful artifact for
   prioritizing the next quarter's security work, and it's also exactly
   what an interviewer wants to hear you can produce cold.
5. **Confirm SARIF centralization actually works.** Findings scattered
   across six tools' native output formats don't get triaged; findings
   landing in one dashboard do. Verify each SARIF-producing job actually
   uploads (`github/codeql-action/upload-sarif@v3` or equivalent) and that
   the `category:` field is unique per tool so results don't overwrite each
   other in the code scanning view.

---

## 9. Troubleshooting quick-reference

| Symptom | Likely cause | What to do |
|---|---|---|
| A scanner action fails with a rate-limit / 403 from an upstream registry or advisory feed | GitHub Actions runners share IP ranges; unauthenticated calls to Docker Hub, PyPI advisory APIs, or GHCR can hit shared rate limits, especially on scheduled/cron runs that fire across many repos at once | Authenticate the pull (`GITHUB_TOKEN` for GHCR, a scoped PAT or Docker Hub token for Docker Hub); retry with backoff; check the tool's own rate-limit docs before assuming it's a real outage |
| A scanner flags a true false positive | The finding is real syntactically but not exploitable in context (this repo's `aws-iam-no-policy-wildcards` case, §3.6) | Document a **narrow, named, justified** suppression at the point of the finding — `#tfsec:ignore:aws-iam-no-policy-wildcards` inline in the `.tf` file, or `# nosec B101` for bandit — never a blanket `--exclude` or `--exit-zero` on the whole tool. Explain *why* in a comment next to the suppression, not just in a commit message that will scroll away |
| A scan passes when it clearly shouldn't | Scope/path misconfiguration — the scanner ran, found nothing, because it was pointed at the wrong directory, not because the target is clean | This is the real `secrets.py` lesson from `playbook/README.md`: `config.py`/`clean.py` demo fixtures were briefly miscategorized into the toolbox root, and `secrets.py .` silently reported 0 findings against a directory that visibly contained two hardcoded secrets — a scanner reporting clean because its target is in the wrong place is *worse* than reporting clean because the code is actually clean, because it looks identical in a summary. Always sanity-check a suspiciously clean result by re-running with a deliberately obvious planted finding first |
| Findings from different tools don't line up in one place / hard to triage | SARIF not centralized, or `category:` collision overwriting one tool's results with another's in GitHub code scanning | Confirm every SARIF-producing job uploads via `github/codeql-action/upload-sarif@v3` with a distinct `category:` (this repo uses `bandit-python-sast`, `trivy-container`, `tfsec-iac`) — SARIF (Static Analysis Results Interchange Format) is the common JSON schema that makes this centralization possible across tools that otherwise have nothing in common in their native output |
| A CVE finding can't be fixed immediately (no patched version yet, or a breaking upgrade) | Legitimate accepted-risk scenario | Don't silence it — record it in a waiver ledger with a reason and an **expiry date** (this repo's `waivers.json` / `triage.py` pattern), so it resurfaces automatically for re-review rather than being suppressed forever by accident |

---

Zone 5's recipes — the largest recipe section in this book, one entry per
tool above with copy-paste commands, expected output shapes, and common
failure modes — live in the book's toolkit appendix.
