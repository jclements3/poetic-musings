# Chapter 9 — Evidence & Govern

*Zone 9 of 9, and the capstone of this book. Where the previous eight zones
do the engineering — plan, develop, build, secure, provision, deploy,
operate — this zone is where that engineering activity either becomes
accreditation evidence, or evaporates.*

## 1. Why this zone matters, and why it's last

Every zone before this one produces an *action*: a secret gets caught
before it's pushed, a dependency gets pinned, a container gets scanned, a
Kubernetes cluster gets hardened against a benchmark, a host gets STIG
scanned. `MASTER-PLAYBOOK.md` frames Zone 9 in one line worth quoting
directly, because it is this chapter in miniature: this is the zone that
turns "engineering activity" into "accreditation evidence." An action that
happened but was never recorded, dated, and made retrievable might as well
not have happened, from the point of view of an auditor, a new hire trying
to understand what's actually running, or your own future self trying to
answer "wait, did we fix that?" six months from now.

Zone 9 is last in the numbering for a reason that isn't arbitrary. Zones
1–8 are about doing the work — writing code securely, building it,
scanning it, provisioning infrastructure, deploying it, operating it. Zone
9 doesn't do any new engineering work of its own; it sits downstream of
all eight other zones and asks the same question of each one: *can you
prove that happened, on demand, without a fire drill?* If the answer is
no, everything upstream is unverifiable — not necessarily false, but
unverifiable, which for audit and accreditation purposes amounts to the
same thing. A control that isn't documented and retrievable does not
exist for an Authorizing Official reviewing a package for an Authority to
Operate (ATO) decision. This isn't bureaucratic theater; it's how DoD-style
Risk Management Framework (RMF) accreditation actually works, and if
you're reading this book because you're studying for a role like GMD
DevSecOps Engineer at a place like Valkyrie Enterprises, "an auditor asks
to see it" is not a hypothetical future problem. It is the job description.

This is also the zone that most cleanly separates "we did DevSecOps" from
"we can prove we did DevSecOps." Those are different claims, and a
DevSecOps engineer who cannot tell a program manager or an assessor which
one they're making is going to have a bad time in this industry. So the
house rule inherited from the rest of this book — brutally honest,
evidence-based, name every gap plainly, never invent a statistic or claim
a verification that didn't happen — is not incidental to a chapter about
evidence. It *is* the chapter's subject matter, applied recursively to
itself. Everything in this chapter, including the worked examples, follows
that rule; where this repo has a real gap (and it has several), this
chapter says so by name rather than rounding it up to "done."

## 2. SBOM — Software Bill of Materials

A **Software Bill of Materials (SBOM)** is a structured, machine-readable
inventory of every component that went into a built artifact: every
direct dependency, every transitive dependency, often down to the exact
version and package hash, plus enough metadata (license, supplier,
package URL) to answer questions about the artifact without re-deriving
them from source. The standard formats are **CycloneDX** (OWASP-governed,
JSON or XML) and **SPDX** (Linux Foundation-governed); this repo's tooling
targets CycloneDX.

The reason an SBOM matters is almost entirely about the question it lets
you answer in seconds instead of days: **"are we affected by CVE-X?"**
Without an SBOM, that question means grepping through Dockerfiles,
requirements files, and lockfiles across however many services you run,
hoping you didn't miss a transitive dependency three layers deep. With an
SBOM archived per release, it's a `grep` or a query against a container
catalog. This is the practical payoff of supply-chain security: Log4Shell
and the `xz` backdoor were both "does this specific component, at this
specific version, exist anywhere in our shipped software" questions, and
organizations with SBOMs answered them in hours; organizations without
them spent days on archaeology while the exposure window stayed open.

**Generating one with Syft** (Anchore's open-source SBOM generator, and
the tool `security.yml` in this repo actually runs via
`anchore/sbom-action`):

```
syft app/status-service -o cyclonedx-json > sbom.json
```

That produces a CycloneDX JSON document listing every Python package
`status-service`'s container pulls in, with versions and package URLs
(`pkg:pypi/flask@3.1.3`, etc.).

**SBOM diffing as a supply-chain changelog.** A single SBOM is a snapshot;
the more operationally useful artifact is the *diff* between two SBOMs —
the previous release's and the current one's. That diff answers "what
changed in our supply chain between v1.2 and v1.3" the same way a code
diff answers what changed in source: added components (new attack
surface), removed components (shrinking attack surface, worth noting),
and changed components (version bumps, some of which fix CVEs and some of
which introduce them). `MASTER-PLAYBOOK.md` lists `sbom_diff.py` under
Zone 9 as a `[run]`-tagged play — a script that was actually executed, not
just planned — and its job is exactly this: CycloneDX component drift
between two SBOMs, reported as added/removed/changed.

**This repo's honest gap, worth citing as a teaching example.** Per
`playbook/README.md`, `sbom_diff.py` was verified for real, but only
against the repo's seeded demo fixtures (`sbom-old.json`/`sbom-new.json`),
correctly reporting 1 added, 1 removed, 1 changed component. It was *not*
verified against a real CycloneDX SBOM of this repo's own
`app/status-service` container, because `syft` is not installed in the
verification environment (not on `PATH`). `security.yml` already runs
`anchore/sbom-action` in CI, so real SBOMs of this repo's own container
exist somewhere in that pipeline's artifact history — wiring
`sbom_diff.py` to two of them (current release vs. previous) is the
natural next step, named as a next step, not done here.

The distinction that gap illustrates is worth internalizing as a general
principle for this whole zone: **"the tool works" and "the tool was
verified against this environment" are different claims, and conflating
them is exactly the kind of overclaim this book refuses to make.**
`sbom_diff.py`'s diff logic is demonstrably correct against known-good
fixtures. Whether it behaves correctly against a real, messy, 40-component
CycloneDX document from an actual container build is a separate, still-open
question. A resume or a status report that said "SBOM diffing: done" without
that caveat would be lying by omission. `playbook/README.md` says it plainly
instead — "Honest gap, not silently skipped" — which is the entire discipline
of this zone, applied to a two-line tool.

## 3. Waiver ledgers done right

Every scanning gate in a real pipeline eventually produces a finding that
someone, correctly, decides not to fix right now — a low-severity issue in
a vendored file you don't control, a CVE with no available patch and no
reachable exploit path, a false positive the scanner can't be tuned around.
The wrong way to handle that is a blanket suppression: an
`# nosec`/`.trivyignore`/inline-comment that silences the finding forever,
with no record of who approved it, why, or when it should be revisited.
That pattern is a security anti-pattern for a specific reason: **suppressed
findings accumulate silently and never expire**, and eighteen months later
nobody remembers which of the forty suppressions in a codebase were
genuinely reviewed risk acceptances and which were someone unblocking a
build at 11pm and forgetting to come back.

The disciplined alternative is a **waiver ledger**: a structured record
(this repo's is `playbook/waivers.json`) where each entry requires, at
minimum, four fields — **rule** (which specific check is being waived),
**path** (which specific file/resource it applies to, not a blanket "all
findings of this type"), **reason** (a human-readable justification an
auditor can read and evaluate), and **expiry** (a date after which the
waiver stops applying). `triage.py`, this repo's SARIF-to-summary script,
is waiver-aware — it cross-references findings against the ledger and
reports a `waived:` count in every summary, so waived findings are visible
in the output, not hidden from it.

**Why expiry dates matter, specifically.** An accepted risk from eighteen
months ago is not the same accepted risk today. The threat landscape
changes (a CVE with no known exploit gets a public PoC), the codebase
changes (the file the waiver applied to gets refactored and the waiver's
`path` field silently stops matching anything, or worse, starts matching
something it was never reviewed against), and the person who approved the
original waiver may have left the team. A waiver with no expiry date is a
permanent, unreviewed exception — which is functionally identical to no
gate existing at all for that rule/path combination, except it *looks*
like governance because there's a ledger entry.

**Auto-reactivation of expired waivers as a design principle.**
`MASTER-PLAYBOOK.md` lists this explicitly: expired waivers reactivate
automatically. The design principle behind that default matters more than
the specific mechanism — a waiver ledger's *default* behavior on expiry
must be "the finding comes back and blocks the gate again," not "the
waiver silently stays in effect until someone notices." The failure mode
this prevents is exactly the failure mode blanket suppression creates: a
risk acceptance that was time-boxed on paper but permanent in practice
because nobody built the mechanism that makes the time-box actually bind.
A waiver ledger that requires a human to notice expiry and manually
re-flag the finding is a ledger that will, eventually, have overdue
entries nobody caught — auto-reactivation is what makes the expiry field
mean something rather than being decorative.

## 4. Evidence retention policy

The waiver ledger and SBOM diffing are evidence that gets *generated*.
Retention is the separate, easy-to-skip discipline of making sure that
evidence still exists and is retrievable when someone needs it — which is
never when you're generating it, and always later, under time pressure.

**What to keep**, per `MASTER-PLAYBOOK.md`'s Zone 9 entry: SARIF (the
structured static-analysis output format most scanners in this book's
pipeline emit), SBOMs, and scan summaries — archived per run.

**For how long, and why the retention period isn't uniform.**
`MASTER-PLAYBOOK.md` states the policy as two tiers: **30 days in CI**
(every pipeline run's artifacts — enough to debug a recent failure or
answer "what did last Tuesday's build actually scan," but not meant to be
an eternal archive of every commit's transient CI output) and
**per-release, forever** (the SBOM, SARIF summary, and gate result for
anything that actually shipped). The reasoning behind the split is
practical, not arbitrary: CI runs against every PR, including ones that
get abandoned, force-pushed over, or superseded within hours — retaining
all of that forever is mostly noise. A *release*, by contrast, is a
durable claim about what's running in production, and the question "what
did we know about this release's security posture, and when did we know
it" doesn't have a 30-day shelf life. A real incident six months from now
is going to ask exactly that question, and "we don't have the scan output
anymore, it aged out of CI retention" is not an answer an incident
responder or an auditor will accept.

**This repo's real, committed examples of evidence retention done right**
— not claimed, actually checked into version control where anyone can
retrieve them without re-running anything:

- **`stig/scap-results.xml.gz`, `stig/scap-report.html`,
  `stig/fail-rules.txt`** — the full machine-readable OpenSCAP results
  (gzipped, 17MB raw / 1.3MB compressed), the full human-readable HTML
  report with every rule's DISA rationale text, and the plain list of the
  51 failing rule IDs from a real `oscap` DISA STIG evaluation against a
  RHEL 8 (UBI8) filesystem. This is genuinely retrievable evidence: someone
  asking "did rule X pass on the STIG scan" doesn't need to re-run
  OpenSCAP — the answer is sitting in `stig/scap-report.html` right now.
- **`k8s/cis-benchmark/kube-bench-report.txt`** — the full output of a
  real `kube-bench` v0.9.4 run against a live `kind` cluster (62 PASS, 11
  FAIL, 48 WARN), committed as a text file rather than only described in
  prose.
- **`jenkins/build-7-console.txt`** — the actual console log of Jenkins
  build #7, an honest **FAILURE** (a real CRITICAL `trivy config` finding
  in `infra/terraform/modules/azure-platform/main.tf` — a storage account
  with no `network_rules` block, defaulting to `Allow`), archived as a
  real artifact rather than summarized as a rounded-up "pipeline works."

These three are worth sitting with as a set, because they demonstrate the
same discipline three different ways: a STIG scan's evidence is a
compressed XML blob plus a human-readable report, a CIS benchmark's
evidence is a plain-text tool log, and a CI pipeline's evidence is a
console transcript that records a *failure*, not just a success. None of
them are summaries written after the fact from memory. All three answer
"what did we know and when" without requiring anyone to re-run anything or
trust an unsupported claim.

## 5. Reading this repo's own JOB.html as a Zone 9 artifact

`JOB.html`, this repo's own requirement-mapping page for the target job
posting, is itself a Zone 9 artifact — a state-of-the-union report,
structured the way a real audit-readiness document should be: one row per
requirement, a status badge, and a link to where the evidence actually
lives. It is worth reading as a worked example rather than just as
supporting material, because its `OVERALL_BLUF` constant is a genuinely
honest BLUF (Bottom Line Up Front) in the military/contracting sense — a
single paragraph meant to be read first, that doesn't hedge and doesn't
inflate.

As of this writing, `OVERALL_BLUF` reads, in full:

> "This sprint cycle, the DevSecOps effort has delivered verified
> capability across all required areas: **1) Infrastructure as Code
> (Terraform)** — full environments stand up from code in minutes,
> verified against a live AWS account; **2) Container orchestration
> (Kubernetes)** — hardened to the restricted standard, no root,
> default-deny networking, 62 benchmark checks passed; **3) CI/CD
> automation (GitHub Actions, GitLab CI, Jenkins)** — same pipeline in
> three vendors, caught a live dependency vulnerability on first run and a
> real Terraform misconfiguration on Jenkins; **4) Hybrid cloud (AWS,
> Azure)** — AWS proven end-to-end, Azure built to identical standard;
> **5) Identity & directory services (Samba4 AD)** — real domain stood up,
> verified by live login and credential pull; **6) Compliance & hardening
> (DISA STIG)** — scored DoD baseline, 67 pass / 51 fail of 409 rules,
> each traceable; **7) Pipeline security scanning (SAST, SCA,
> container/IaC scans)** — seven layered scans on every change, caught
> real vulnerabilities including in the base image; **8) Developer
> environments (Coder)** — server deployed live and healthy; **9)
> Configuration management (Ansible)** — idempotence proven cold: one run
> to correct, zero on rerun. Remaining items queued pending approval: live
> Azure apply, Azure DevOps pipelines, Windows client + SCCM, STIG
> remediation, Coder templates."

Read that closely and notice what it's actually doing. It states a real
number for the STIG result (67 pass / 51 fail of 409 rules) rather than
"STIG compliant" or "STIG work completed." It states a real number for the
Kubernetes benchmark (62 checks passed) rather than "hardened." It names a
*specific* real finding the pipeline caught (a live dependency
vulnerability, a real Terraform misconfiguration on Jenkins) rather than
"security scanning works." And critically, it ends with an explicit,
named punch list of what is *not* done — "Remaining items queued pending
approval: live Azure apply, Azure DevOps pipelines, Windows client +
SCCM, STIG remediation, Coder templates" — rather than quietly omitting
those nine words and letting the reader assume everything is finished.

**Contrast that with what a dishonest state-of-the-union would look
like**, because the contrast is the actual teaching point: "DevSecOps
implementation is complete across all required domains, with robust
security controls in place and continuous monitoring operational." That
sentence is grammatically identical in shape to a real BLUF and contains
zero verifiable claims — no numbers, no named tool, no named gap, no way
for a reader to check any part of it against evidence. It would pass a
skim. It would not survive five minutes of an assessor asking "show me."
`OVERALL_BLUF`'s actual text survives that, because every clause in it
points at something checkable: a rule count, a benchmark score, a specific
misconfiguration, a specific missing piece. That checkability — not the
optimism or pessimism of the tone — is what makes it a real Zone 9
artifact instead of a marketing paragraph.

## 6. DevSecOps maturity models

A maturity model gives a team a vocabulary for answering "how good is our
DevSecOps practice, really" without either false modesty or hand-waving.
`playbook/FIELD-MANUAL.md` §8 gives a practical four-level checklist for
this repo's own practice, worth using as a general template:

- **L1 — Scan.** Secrets scanning, SAST, and dependency auditing run on
  every PR, plus a weekly cron for drift. This is the floor: automated
  detection exists, even if nothing downstream of it is disciplined yet.
- **L2 — Gate.** A single policy chokepoint (this repo's `gate.py`) that
  all scan summaries flow through, waivers with expiry (Section 3 above),
  and a dirty-fixture regression test — proof the gate can actually fail,
  not just pass by construction. This is where "we scan things" becomes
  "we block things," which is the real inflection point most teams that
  claim DevSecOps never actually cross.
- **L3 — Supply chain.** SHA-pinned GitHub Actions (not tag-pinned, which
  is mutable and spoofable), pinned and bot-bumped dependencies, an SBOM
  generated per release, signed artifacts. This is where supply-chain
  integrity — not just "our code is clean" but "the things we built our
  code *from* are provably the things we think they are" — becomes a
  gated property instead of an assumption.
- **L4 — Operate.** Hardening baselines (STIG/CIS) automated and
  continuously scored, scan freshness monitored (an automated check that
  the *last* scan wasn't stale — this repo's `freshness.py`), incident
  response roles named ahead of time rather than improvised during an
  incident, and SBOM-driven blast-radius lookup (Section 2's "are we
  affected by CVE-X" answered from stored data, in minutes).

**A practical self-assessment has to be quantified, not vibes-based**, and
this repo's own zone-coverage table from `MASTER-PLAYBOOK.md` is a worked
example of doing that honestly:

| Zone | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Plays | 2 | 2 | 4 | 2 | 7 | 3 | 2 | 3 | 4 |
| Executed | 0 | 1 | 2 | 1 | 6 | 0 | 1 | 1 | 2 |

**29 plays, 14 executed** — just under half, stated as a number rather than
rounded up to "most of the playbook is done" or rounded down to "not much
is done." Two zones (1 and 6) show zero executed plays, and
`MASTER-PLAYBOOK.md` names *why* rather than leaving the zero
unexplained: Zone 1 is process-bound (planning/sourcing controls that need
an organizational process to execute against, not a script) and Zone 6 is
credential-bound (needs real cloud credentials this environment doesn't
have). Naming the reason a number is zero is exactly the difference
between an honest maturity self-assessment and a scorecard that just looks
bad with no context.

Applying the L1–L4 ladder to this repo honestly: it clears L1 cleanly
(secrets/SAST/deps scanning genuinely runs and genuinely catches things —
see Chapter 5). It clears most of L2 — `gate.py` is a real chokepoint with
a proven fail path, and the waiver ledger design is sound — but the
toolbox that implements it (`playbook/`) is explicitly **not wired into
live CI** (`.github/workflows/ci.yml` and `security.yml` still call
gitleaks/bandit/pip-audit/trivy/tfsec/kube-linter directly), which is a
real L2 gap, not a passed checkbox. It's partway into L3: SBOMs are
generated in CI (`anchore/sbom-action`) but `actions_pin.py` found a real,
unfixed gap — **21 `uses:` lines tag-pinned, not SHA-pinned**, across this
repo's GitHub Actions workflows — so "supply chain" is aspirational, not
achieved, on that specific dimension. L4 is real in pieces (STIG and CIS
scans exist and are scored, `freshness.py` works) but not continuous — these
are one-time scans, not a running monitored baseline. That's the honest
answer: **this repo sits at a strong L1, a partial L2, and a partial L3**,
with real L4 building blocks that aren't yet operating continuously. A
maturity self-assessment that can't produce a sentence that specific isn't
actually an assessment.

## 7. Audit readiness in practice

What does an auditor, a new manager doing a 90-day review, or a security
review board actually ask for? In practice, some version of these
questions, almost always with a deadline measured in hours or days, not
weeks:

- "Show me the SBOM for what's currently running in production."
- "Show me the most recent vulnerability scan and its results, with dates."
- "Show me every currently-waived finding, who approved it, and when it
  expires."
- "Show me your compliance baseline (STIG/CIS) scan and the delta from
  100%."
- "Show me evidence that your pipeline actually blocks bad changes, not
  just that it runs."

A well-run Zone 9 answers every one of those from stored evidence, in
minutes: `syft <target> -o cyclonedx-json` output already archived
per-release answers the first; the archived SARIF/summary from the last CI
run (or `stig/scap-report.html` / `k8s/cis-benchmark/kube-bench-report.txt`
for baseline questions) answers the second and fourth; `playbook/waivers.json`
plus `triage.py`'s `waived:` count answers the third directly, field by
field; and `playbook/README.md`'s reproduced `pipeline.sh demo` run
(exit 1 against seeded bad input, real command transcript included)
answers the fifth — a gate that can't fail on demand is decoration, and
this repo proves its gate can fail, on the record.

A poorly-run Zone 9 answers the same five questions with "let me get back
to you" and then spends the next several days reconstructing what should
have been sitting in an archive the whole time — pulling old build logs
out of CI systems that may have already rotated them past retention,
asking whoever wrote a suppression six months ago whether they remember
why, re-running scans that should already have results on file. The
difference between those two experiences is not talent or effort; it's
entirely whether Sections 2–4 of this chapter were actually practiced
before the question got asked.

## 8. The quarterly re-audit discipline

`MASTER-PLAYBOOK.md`'s own scope statement contains a line worth taking
as seriously as any technical claim in this book: **"no fixed document
survives tool churn... re-audit this document against the QRG
quarterly."** That is this repo's own stated practice for itself, and it
names a real Zone 9 failure mode that has nothing to do with scanners or
ledgers: **documentation rot**. A playbook, a runbook, a compliance
mapping, or a maturity self-assessment that was accurate the day it was
written and has not been checked against reality since is not evidence —
it's a historical document wearing evidence's clothing. Tools get
upgraded, actions get renamed, a script that worked against last quarter's
`syft` version silently breaks against this quarter's, a waiver that was
supposed to expire slips past its date because nobody re-ran the ledger
check. None of those are exotic failures; they are the default outcome of
leaving any document unattended for a fixed period of time.

The discipline that prevents it is unglamorous and exactly what the
sentence says: **re-check the whole 9-zone playbook against current
reality on a fixed cadence**, not "whenever someone remembers" or "before
the next audit." That means literally re-running the commands
`playbook/README.md` documents — `secrets.py`, `deps.py`, `cve.py`,
`actions_pin.py`, `triage.py`, `gate.py`, `freshness.py` — against the
current state of the repo, not trusting that last quarter's "0 findings,
exit 0" is still true. It means checking whether `syft` is finally
installed in the verification environment, closing the SBOM-diff gap from
Section 2 instead of letting it become permanent by default. It means
re-reading `actions_pin.py`'s 21-finding result and asking whether the
number has changed, not assuming it's still 21 because nobody looked. The
quarterly cadence matters because it's frequent enough to catch drift
before it compounds into a full-blown "our documentation describes a
system that no longer exists," and infrequent enough to be sustainable
rather than becoming its own burden. A maturity model that isn't itself
re-audited on a cadence is exactly the kind of thing Section 6 warns
against: a number stated once and never checked again is a vibe wearing a
number's clothing.

## 9. Tying the book together

Step back across all nine zones and one honest question repeats at every
stage, in a different costume each time: **did this actually happen, and
can I prove it?** Zone 1 (Plan & Source) asks it of requirements and
architecture decisions. Zone 2 (Develop) asks it of code review and secure
coding practice. Zone 3 (Build & Test) asks it of the build pipeline
itself — did this artifact actually get built from this source, verifiably.
Zone 4 (Secure) asks it of every scanner — did the gate actually run, and
can it actually fail. Zone 5 (Provision) asks it of infrastructure-as-code
— does the environment that exists match the code that describes it. Zone
6 (Deploy & Orchestrate) asks it of the deployment itself — is what's
running actually what was intended to ship. Zone 7 (the seventh zone in
this book's numbering, Operate & Observe) asks it of production — is the
system's real behavior visible, or just assumed healthy. And Zone 9,
finally, asks the question of *all the other zones at once*: can the
answers to all of the above be produced on demand, from stored evidence,
without reconstruction?

That's why Zone 9 is the capstone rather than just another item on the
list. It isn't a ninth independent discipline sitting next to the other
eight — it's the discipline that determines whether the other eight were
real. A team can run flawless scans in Zone 4 and still fail an audit in
Zone 9, if the scan results aren't retained. A team can build a technically
excellent Terraform module in Zone 5 and still fail Zone 9, if nobody can
show when it was last validated against drift. Zone 9 is where the rest of
this book either pays off — because the evidence was captured honestly and
retained deliberately, the way `stig/`, `k8s/cis-benchmark/`, and
`jenkins/build-7-console.txt` demonstrate it was captured in this repo —
or reveals itself as theater, because the actions were real but nobody
kept the receipts.

## 10. Day-one checklist for this zone

1. **Find out what evidence retention policy, if any, currently exists.**
   Ask directly: where do scan results go after a CI run finishes, and for
   how long are they kept? If the honest answer is "they age out with the
   CI job and nobody archives releases separately," that's the first gap
   to close — see Section 4's 30-day/per-release-forever split.
2. **Ask to see the most recent audit or compliance report, and check its
   age.** A STIG or CIS report from fourteen months ago being presented as
   "current" is a documentation-rot problem (Section 8), not a compliance
   win — check the date on it before believing the number.
3. **Find where SBOMs are stored, if they exist at all.** Ask specifically
   whether they're generated per build (noise) or per release (signal),
   and whether anyone has ever actually diffed two of them to answer a
   real "are we affected by CVE-X" question, or whether that capability is
   theoretical.
4. **Check for any waivers with no expiry date.** This is a concrete,
   fast, high-value red flag to look for on day one — open the waiver
   ledger (or grep for `nosec`/`.trivyignore`/inline suppression comments
   if there's no structured ledger yet) and count how many suppressions
   have no expiry field at all. Every one of those is an unreviewed,
   effectively-permanent risk acceptance hiding behind what looks like
   governance.
5. **Ask who owns the quarterly re-audit, and when the last one happened.**
   If the honest answer is "nobody" or "we've never done one," that's the
   single highest-leverage process gap to raise, because it's the gap that
   lets every other gap in this checklist go undetected indefinitely.
6. **Pull one real finding through the whole chain, start to finish** — a
   scan result, through the gate, through the waiver ledger if waived,
   into retained evidence — and confirm each handoff actually produces a
   retrievable artifact. If any link in that chain is "trust me, it
   happened," that's the specific spot to fix first.

## 11. Troubleshooting quick-reference

| Situation | What to do |
|---|---|
| An auditor asks a question with no stored evidence to answer it | Say so directly — "we don't have that evidence retained" is a correct, defensible answer; fabricating or reconstructing-from-memory a plausible-looking answer is not. Then close the retention gap (Section 4) so the same question has a real answer next time. |
| A waiver with an expired date is still silently suppressing a finding | Treat it as a broken control, not a paperwork oversight — auto-reactivation (Section 3) should have caught this; audit why it didn't (ledger not re-checked on a cadence, or the reactivation logic itself isn't wired into the gate), fix the mechanism, and re-run the gate against the now-unwaived finding. |
| An SBOM diff shows an unexpected new component | Treat it as a real supply-chain investigation, not noise to dismiss: identify what introduced it (direct dependency bump vs. a transitive dependency someone upstream added), whether it was reviewed by anyone, and whether it has known CVEs before assuming it's benign. |
| A maturity self-assessment doesn't match what an external scan finds | Trust the external scan and correct the self-assessment, not the other way around — a maturity model is only useful if it's falsifiable by evidence; a team that adjusts the scan's credibility instead of the self-assessment has turned the maturity model into theater, which is exactly the failure mode this whole chapter exists to prevent. |

---

The title of this book is "The Wheel — What Does Not Need To Be
Reinvented," and this final chapter is where that title earns its keep
most literally. Nothing in Zone 9 is exotic: SBOMs, waiver ledgers, a
retention policy with two tiers, a four-level maturity ladder, a quarterly
re-check. None of it required inventing a new methodology — every piece of
it is a well-worn wheel that RMF assessors, SOC 2 auditors, and every
mature engineering org before you have already built and rebuilt. What
this book's own appendix toolkit (`playbook/`) and this repo's real
artifacts (`stig/`, `k8s/cis-benchmark/`, `jenkins/`) demonstrate across
all nine chapters is that the hard part was never inventing the wheel — it
was assembling the pieces correctly, running them for real instead of
describing them, and being honest in writing about which parts actually
turned and which parts are still sitting half-bolted-on. That's the whole
discipline this book teaches, condensed into one zone: don't reinvent the
wheel, don't just claim you rolled it — put it on the ground, push it, and
keep the receipt.
