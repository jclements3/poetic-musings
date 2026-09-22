# The Wheel

### What Does Not Need To Be Reinvented

*A complete DevSecOps study book — the 9 zones, real evidence, and a
toolkit — built for the GMD DevSecOps Engineer role (Valkyrie Enterprises,
Job ID 4472), and for every project after it.*

---

## How to use this book

This book has three layers, and they're meant to be read in a specific
order depending on what you need at the moment:

1. **The nine zone chapters** (1-9) are the *teaching* layer. Each one
   stands alone — read them in order once, front to back, to build the
   full mental model; come back to any single one later as a reference
   when you need to go deep on just that zone.
2. **The appendix, "The Wheel"** is the *toolkit* layer — real, working,
   point-free Python recipes built on `playbook/haskell.py`, organized by
   zone, meant to be copied and adapted rather than written from scratch
   the next time you need a small script to parse something, gate
   something, or triage something.
3. **This book itself lives inside a real, working portfolio repo**
   (`poetic-musings`) that you can open alongside any chapter and see the
   actual files, actual command output, and actual bugs-hit-and-fixed
   behind every claim. Nothing in here is theoretical unless the chapter
   says so explicitly.

Every chapter follows the same honest discipline this whole repo is built
on: **real commands and real numbers where they exist, gaps named
plainly, nothing claimed as "verified" that wasn't actually verified.**
Where a topic is genuinely course knowledge rather than something proven
in this repo (SonarQube, Nexus, Azure DevOps, ELK, HashiCorp Vault, Istio),
every chapter says so explicitly, at the point where it comes up — not
buried in a footnote. You should walk into an interview or a first week
on the job able to say, precisely, "this I've built and verified myself,
this I understand and can speak to but haven't hands-on-proven yet" — and
mean it, for every single tool in this book.

---

## Day One at Valkyrie — Orientation

You are the **GMD DevSecOps Engineer**, supporting GM's Digital
Acquisition & Infrastructure team, architecting and scaling the DevSecOps
environment inside the Integrated Digital Data Environment (IDDE). This
section is the condensed version of everything below: what's actually
proven, what to do first, and where to look when something breaks.

### What you're walking in with (the honest inventory)

Quoting the real, current summary from this repo's own dashboard
(`JOB.html`), unedited:

> This sprint cycle, the DevSecOps effort has delivered verified
> capability across all required areas: **1) Infrastructure as Code
> (Terraform)** — full environments stand up from code in minutes,
> verified against a live AWS account; **2) Container orchestration
> (Kubernetes)** — hardened to the restricted standard, no root,
> default-deny networking, 62 benchmark checks passed; **3) CI/CD
> automation (GitHub Actions, GitLab CI, Jenkins)** — same pipeline in
> three vendors, caught a live dependency vulnerability on first run and a
> real Terraform misconfiguration on Jenkins; **4) Hybrid cloud (AWS,
> Azure)** — AWS proven end-to-end, Azure built to identical standard;
> **5) Identity & directory services (Samba4 AD)** — real domain stood
> up, verified by live login and credential pull; **6) Compliance &
> hardening (DISA STIG)** — scored DoD baseline, 67 pass / 51 fail of 409
> rules, each traceable; **7) Pipeline security scanning (SAST, SCA,
> container/IaC scans)** — seven layered scans on every change, caught
> real vulnerabilities including in the base image; **8) Developer
> environments (Coder)** — server deployed live and healthy; **9)
> Configuration management (Ansible)** — idempotence proven cold: one run
> to correct, zero on rerun.

**Named, not hidden, remaining gaps:** live Azure apply, Azure DevOps
pipelines, a Windows client + SCCM, STIG remediation (the baseline is
scored, the fixes aren't applied yet), and Coder workspace templates. Plus
course-only knowledge you should brush up but haven't hands-on-proven:
SonarQube, Nexus, ELK, HashiCorp Vault, Istio service mesh.

This is not a weakness to hide in an interview or on the job — it's
exactly the kind of precise, falsifiable inventory a DevSecOps engineer is
supposed to be able to produce about *any* environment they inherit,
including someone else's. Practicing it on your own portfolio first is
the whole point.

### Week One: Evaluate, Set Up, Do the Job

A concrete, zone-by-zone first-week sequence. Each item points to the
chapter that teaches the "how":

1. **Evaluate the situation** (Zones 1, 8, 9 — Chapters 1, 8, 9): find
   every pipeline file, every scan gate, every dashboard that already
   exists before you touch anything. Read `freshness.py`'s pattern
   (Appendix B.7) and ask "when did each of these last actually run
   successfully" before trusting any of it. Ask for the current waiver
   ledger and check for silently-expired entries (Appendix B.5, Chapter
   9 §4).
2. **Set things up** (Zones 2, 6 — Chapters 2, 6): get a working
   development environment (Coder or equivalent) and confirm your own
   `terraform plan` / `ansible-playbook --check` run clean against the
   current state before you change anything — drift you didn't cause is
   not drift you want to be blamed for.
3. **Do the job** (Zones 3, 4, 5, 7 — Chapters 3, 5, 7): ship changes
   through the same gated pipeline everyone else does, never around it.
   Know the CI/CD dialect(s) in actual use (this book covers all four:
   GitHub Actions, GitLab CI, Jenkins, Azure DevOps) and the full 7-gate
   security scanning stack cold.
4. **Fix things / troubleshoot** (Zone 8 — Chapter 8): when something
   breaks, the four-question triage framework in Chapter 8 §6 (Blast
   radius → What changed → Which layer → Fastest safe rollback) is not
   optional reading — it is the fastest path back to a working system
   under pressure, and it's already fully worked out. Use it.
5. **Accomplish your duties, provably** (Zone 9 — Chapter 9): every
   control you implement needs evidence an auditor can find without
   asking you. STIG scans, SBOMs, waiver expiries — if it isn't archived
   and retrievable, it didn't happen, no matter how sure you are that it
   did.

### The one thing to internalize before anything else

**A gate that cannot fail is decoration.** Every real control in this
book — every scanner, every policy check, every pipeline stage — was
proven to actually catch something before it was trusted. Chapter 3 §8
covers this directly (the "dirty-fixture regression" principle), and it
should become a reflex: the first time you stand up a new check anywhere,
prove it can say no before you believe it when it says yes.

---

## Table of Contents

| # | Zone | Chapter |
|---|---|---|
| — | Front Matter & Day One Orientation | this file |
| 1 | Plan & Source | `chapter-01-plan-and-source.md` |
| 2 | Develop | `chapter-02-develop.md` |
| 3/4 | Build & Test | `chapter-03-build-and-test.md` |
| 5 | Secure | `chapter-05-secure.md` |
| 6 | Provision | `chapter-06-provision.md` |
| 7 | Deploy & Orchestrate | `chapter-07-deploy-and-orchestrate.md` |
| 8 | Operate & Observe (+ full triage framework) | `chapter-08-operate-and-observe.md` |
| 9 | Evidence & Govern | `chapter-09-evidence-and-govern.md` |
| A | Appendix — The Wheel (toolkit) | `APPENDIX-TOOLKIT.md` |


---


# Chapter 1 — Zone 1: PLAN & SOURCE

## 1. Why this zone matters

Every DevSecOps pipeline, no matter how many scanners it bolts on, has one
root of trust: the source tree. If a bad commit lands on `main` — a leaked
key, a dependency downgrade, a policy file edited without review — every
downstream zone inherits that mistake and then obediently builds,
containerizes, deploys, and monitors it. Zone 2 (Develop) can run the best
pre-commit hooks in the world; Zone 3 (Build) can run three CI dialects in
parallel; none of it matters if Zone 1 lets the wrong commit onto the
protected branch in the first place.

This is why Zone 1 is the "poster child" zone in any serious DevSecOps
maturity model: it's cheap to get right and catastrophic to get wrong.
Branch protection rules, PR review, and policy-as-code are not bureaucratic
friction bolted onto engineering — they are the actual security control.
A `trivy` scan that runs in CI but can be bypassed by a direct push to
`main` with `--no-verify` is theater. The gate is only a gate if the branch
rules make it unavoidable, which is exactly the framing this repo's own
playbook uses (`playbook/MASTER-PLAYBOOK.md`, Zone 1).

Everything you do in later zones assumes Zone 1 held. Learn it first,
learn it cold, because it's the zone every auditor and every incident
postmortem checks first: "who could have pushed this, and did anyone
review it?"

## 2. Core concepts

**Version control, distributed vs. centralized.** Centralized systems
(old-school Subversion/CVS/Perforce) keep one canonical history on a
server; every operation — commit, log, blame — is a network round trip.
Git is distributed: every clone is a full copy of the repository's entire
history. This has consequences you'll use daily:

- You can commit, branch, stash, and review history completely offline.
- There is no single "the repo" until you agree on one by convention
  (usually a hosted `origin` remote — GitHub, GitLab, Azure Repos).
- Merging is cheap and local, which is what makes feature branches and
  pull requests practical at scale.

**Working directory, staging area, repository.** Git has three states a
change can be in, and almost every beginner Git confusion traces back to
not knowing which one you're in:

- **Working directory** — the files on disk as you're editing them.
- **Staging area / index** — `git add` copies a snapshot of a file into
  the index. This is Git's "what will go into the next commit" scratch
  space, and it's the thing that makes partial commits (`git add -p`)
  possible.
- **Repository (`.git` history)** — `git commit` takes what's staged and
  writes it permanently into the object database as a new commit.

**The object model, in plain language.** Git's entire history is a
content-addressed graph of four object types, all identified by the
SHA-1 (or SHA-256 on newer repos) hash of their contents:

- **Blob** — the raw contents of a file, nothing else (no filename, no
  permissions).
- **Tree** — a directory listing: maps names to blobs (files) and other
  trees (subdirectories), plus modes.
- **Commit** — a pointer to one tree (the full snapshot of the repo at
  that point), one or more parent commits, and metadata (author,
  committer, message, timestamp).
- **Tag** — a named, optionally signed pointer to a commit (annotated
  tags are their own object; lightweight tags are just a ref).

Branches and `HEAD` are not objects — they're just files under `.git/refs`
holding a commit SHA. `git branch feature/x` literally writes a 40-character
hash into a text file. This is why branches are so cheap in Git compared
to older systems: creating one is a single file write, not a directory
copy.

```bash
# see the object model directly
git cat-file -p HEAD              # the commit object: tree, parent, message
git cat-file -p HEAD^{tree}        # the tree object: file names -> blob hashes
git rev-parse HEAD                 # the commit SHA that "main" currently points to
cat .git/refs/heads/main           # literally the same SHA, as a file
```

Understanding this model demystifies almost every "scary" Git operation —
reset, rebase, cherry-pick — because they're all just rewriting which
commit a ref points to, or replaying commits to build new ones. Nothing
is magic; it's a graph of immutable snapshots and some pointers.

## 3. Git command mastery

### Everyday commands

```bash
git status                  # what's staged, unstaged, untracked
git diff                    # unstaged changes vs. the index
git diff --staged           # staged changes vs. HEAD
git add path/to/file         # stage a file
git add -p                   # stage hunks interactively
git commit -m "message"      # commit staged changes
git commit --amend           # rewrite the most recent commit (local only, see §3 revert/reset)
git log --oneline --graph --all   # compact visual history across all branches
git log -p -- path/to/file        # full patch history for one file
```

### Branching

```bash
git branch                       # list local branches
git branch -a                    # list local + remote-tracking branches
git switch -c feature/thing      # create and switch to a new branch (modern)
git checkout -b feature/thing    # same, older spelling
git branch -d feature/thing      # delete a merged branch (safe)
git branch -D feature/thing      # force-delete an unmerged branch (destructive)
git push -u origin feature/thing # push and set upstream tracking
```

### Merge vs. rebase — and when to use which

Both integrate changes from one branch into another, but they produce
different history shapes and have different rules about safety.

**Merge** creates a new commit with two parents, preserving both
branches' history exactly as it happened:

```bash
git switch main
git merge feature/thing
```

Use merge when: the branch is shared with others, has already been
pushed and reviewed, or you want an honest record of when integration
happened (this is why release branches are typically merged, not
rebased).

**Rebase** replays your branch's commits one at a time on top of a new
base, producing a linear history with no merge commit:

```bash
git switch feature/thing
git rebase main
git push --force-with-lease         # required: rebase rewrites commit SHAs
```

Use rebase when: the branch is still private/local (not yet pushed, or
pushed only by you), and you want a clean, linear, bisectable history
before opening a PR. The rule that keeps rebase from becoming an
incident: **never rebase a branch other people have already pulled from
and built on** — you'll rewrite SHAs out from under them and every
downstream clone diverges. `--force-with-lease` (never bare `--force`)
is the safety valve: it refuses to push if the remote branch has commits
you haven't seen, which stops you from clobbering someone else's work.

### Stash and pop

```bash
git stash                    # shelve working-directory + staged changes
git stash push -m "wip: auth refactor"   # named stash, easier to find later
git stash list                # see all stashed sets
git stash pop                 # reapply the most recent stash and drop it
git stash apply stash@{2}     # reapply a specific stash without dropping it
git stash drop stash@{0}      # discard a stash without applying it
```

Use case: you're mid-change, need to switch branches to fix something
urgent, and don't want a half-done commit polluting history.

### Cherry-pick

```bash
git cherry-pick <sha>              # apply one specific commit onto the current branch
git cherry-pick <sha1>..<sha2>     # apply a range (exclusive of sha1)
git cherry-pick -n <sha>           # apply but don't auto-commit (stage only)
```

Common real use: a hotfix landed on `main` and needs to also go onto a
long-lived `release/2.4` branch without merging all of `main`'s other
unreleased work.

### Tags

```bash
git tag v1.4.0                              # lightweight tag
git tag -a v1.4.0 -m "release 1.4.0"        # annotated tag (real object, has message/author)
git push origin v1.4.0                       # tags don't push automatically
git push origin --tags                       # push all local tags
git tag -d v1.4.0 && git push origin :refs/tags/v1.4.0   # delete local + remote
```

Use annotated tags for anything that represents a release — they're real
objects with their own metadata and can be GPG-signed (`git tag -s`),
which matters for supply-chain provenance.

### Squash

Squashing collapses many small commits into one before merging, trading
granular WIP history for a clean, reviewable single change per PR.

```bash
# during interactive rebase
git rebase -i HEAD~5
# in the editor, change "pick" to "squash" (or "s") on all but the first commit

# or, the common PR-merge convention:
git merge --squash feature/thing
git commit -m "Add auth refactor (#142)"
```

Most hosted platforms (GitHub, GitLab) offer "squash and merge" as a PR
merge button — this is the same operation, done for you at merge time,
and it's the default a lot of teams pick specifically so `main`'s
history reads as one commit per reviewed change.

### Resolving a merge conflict — walked step by step

Conflicts happen when two branches changed the same lines and Git can't
pick a winner automatically. Here's the real sequence:

```bash
git switch main
git merge feature/thing
# Auto-merging app/config.py
# CONFLICT (content): Merge conflict in app/config.py
# Automatic merge failed; fix conflicts and then commit the result.
```

1. **See what's conflicted:**
   ```bash
   git status
   # both modified:   app/config.py
   ```
2. **Open the file.** Git has inserted conflict markers:
   ```
   <<<<<<< HEAD
   TIMEOUT = 30
   =======
   TIMEOUT = 60
   >>>>>>> feature/thing
   ```
   Everything between `<<<<<<< HEAD` and `=======` is what's on your
   current branch; everything between `=======` and `>>>>>>> feature/thing`
   is what's coming in.
3. **Decide the resolution** — pick one side, combine both, or write
   something new. Delete the markers entirely; don't leave any `<<<<<<<`
   behind (this is the single most common mistake — a leftover marker
   silently becomes a syntax error or a permanently-wrong constant).
4. **Stage the resolved file and finish the merge:**
   ```bash
   git add app/config.py
   git commit    # opens with a pre-filled "Merge branch ..." message
   ```
5. **If it's a rebase instead of a merge**, the loop is per-commit:
   ```bash
   git add app/config.py
   git rebase --continue
   # or bail out entirely and go back to before the rebase started:
   git rebase --abort
   ```

Tooling shortcut: `git mergetool` launches a configured 3-way diff tool
(`vimdiff`, `meld`, VS Code's built-in merge editor) instead of hand-editing
markers — worth setting up once (`git config --global merge.tool vscode`) if
you resolve conflicts often.

### Revert vs. reset — and real consequences

These get confused constantly and picking the wrong one on a shared
branch causes real incidents.

**`git revert`** creates a *new* commit that undoes a previous commit's
changes. History is not rewritten — safe on any branch, including
`main`, including branches other people have pulled.

```bash
git revert <sha>          # undo one commit, prompts for a message
git revert --no-commit <sha1> <sha2>   # stage multiple reverts, commit once
```

**`git reset`** moves the branch pointer (and optionally the index and
working directory) to a different commit — it rewrites history. Three
modes, in increasing order of how much it destroys:

```bash
git reset --soft  HEAD~1   # move branch pointer back; keep changes staged
git reset --mixed HEAD~1   # (default) move pointer back; keep changes, unstaged
git reset --hard  HEAD~1   # move pointer back; DISCARD changes entirely
```

- `--soft`: "I want to redo this commit's message or split it up" — your
  edits are sitting in the staging area, nothing is lost.
- `--mixed`: your edits are back in the working directory, unstaged —
  nothing lost, but you'll need to `git add` again.
- `--hard`: your edits are gone. Not stashed, not recoverable through
  normal means. This is the one that causes "I just lost three hours of
  work" incidents.

**The rule that matters most:** never `reset` (in any mode) or force-push
a branch that other people have already pulled or built on — you've now
rewritten public history, and everyone else's clone silently diverges.
`revert` is the safe tool for anything already shared; `reset` is only
safe on commits that are still private to you.

Recovery from an accidental `--hard`: Git usually hasn't actually deleted
anything yet — the old commit is still in the object database until
garbage collection runs.

```bash
git reflog                 # local log of every place HEAD has pointed, even "lost" commits
git reset --hard <sha-from-reflog>   # restore it
```

The reflog is your safety net for almost every "I think I just destroyed
my work" panic — it's local-only (not pushed, not shared) and typically
retains entries for 90 days by default.

### Detached HEAD recovery

`HEAD` is normally a pointer to a branch name, which points to a commit.
Checking out a specific commit (or a tag) instead of a branch name
"detaches" `HEAD` — it now points directly at a commit, with no branch
attached:

```bash
git checkout <sha>
# You are in 'detached HEAD' state...
```

Any commits you make here are real commits, but nothing points to them
once you switch away — they become unreachable and eventually
garbage-collected. Recovery is simple as long as you do it *before*
switching away:

```bash
git switch -c rescue-branch     # turn the current detached state into a real branch
```

If you already switched away and lost track of it, `git reflog` again —
find the SHA you were on, then `git switch -c rescue-branch <sha>`.

## 4. Branching strategies

**Trunk-based development.** Everyone commits small, frequent changes
directly to `main` (or through very short-lived branches, often merged
same-day), gated by feature flags for anything not ready to ship. Fits
teams with strong CI, strong automated test coverage, and a culture of
small PRs — it's the strategy most compatible with continuous deployment
and is what most high-velocity SaaS shops actually run today.

**GitFlow.** Long-lived `develop` and `main` branches, plus dedicated
`feature/*`, `release/*`, and `hotfix/*` branches with a defined
merge order between them. Heavier ceremony, but gives you a clean
model for teams that ship versioned releases on a schedule (not
continuous deploy) — think embedded software, regulated on-prem
products, anything with a real "release train." It fell out of fashion
for web SaaS specifically because the ceremony fights continuous
delivery, but it's still the right fit where "cut release 2.4, patch it
independently of ongoing 2.5 work" is a real requirement.

**Feature-branch workflow (GitHub Flow).** The middle ground most teams
actually use: `main` is always deployable, every change happens on a
short-lived `feature/*` branch, opens a PR, gets reviewed, and merges
back into `main` (often squashed). No `develop` branch, no formal release
branches — releases are just tags off `main`. This is the default
assumption behind branch-protection tooling on GitHub/GitLab/Azure Repos.

**Corporate branching strategy.** In practice, "corporate" branching
strategy is rarely one of the textbook models verbatim — it's usually
feature-branch-plus-PR layered with organization-specific rules:
mandatory ticket-ID branch naming (`JIRA-1234-fix-auth`), required status
checks before merge, CODEOWNERS-based required reviewers per directory,
a `release/*` branch per quarter for change-freeze windows, and a
separate `hotfix/*` path that's allowed to skip the normal sprint cadence
but still requires the same security gates. The through-line across all
of these: the branching model is a policy decision, and the branch
protection rules are how that policy gets *enforced* rather than just
documented in a wiki nobody reads.

## 5. GitHub vs. GitLab vs. Azure Repos

All three do the same fundamental job — host the repo, gate merges,
run review — but differ in ways that matter day to day:

| | GitHub | GitLab | Azure Repos |
|---|---|---|---|
| Review unit | Pull Request (PR) | Merge Request (MR) | Pull Request (PR) |
| Native CI | GitHub Actions (`.github/workflows/*.yml`) | GitLab CI (`.gitlab-ci.yml`), tightly integrated | Azure Pipelines (`azure-pipelines.yml`), separate product under same org |
| Branch protection config | Settings → Branches → protection rules; required status checks, required reviews, CODEOWNERS | Settings → Repository → Protected branches + Push rules; more granular per-role (Maintainer/Developer) push rights | Branch policies under Repos → Branches; build validation, required reviewers, work-item linking |
| Review culture | Heavy reuse of required-check bots, suggested-changes inline, draft PRs | Merge trains for batch-testing multiple MRs before merge, approval rules per file path | Tight coupling to Azure Boards work items; PR can require a linked work item |
| Self-hosted option | GitHub Enterprise Server | GitLab self-managed (very common in regulated shops) | Azure DevOps Server (on-prem) |
| Typical enterprise fit | Fastest-moving OSS-adjacent shops | Shops wanting one integrated platform (CI+registry+security dashboard) in-house | Shops already standardized on Microsoft/Azure tooling |

The practical skill that transfers across all three: read the PR/MR diff
like a reviewer, not just a rubber stamp — check for scope creep beyond
the stated change, verify tests were added or updated, verify the
security gate actually ran and is green (not just "pending" or skipped),
and check who approved vs. who's required to approve per CODEOWNERS/branch
policy. The button labels differ; the discipline doesn't.

## 6. Policy as code and branch protection

"Policy as code" means the rules governing what's allowed into `main`
are themselves versioned, reviewed files — not settings buried in a web
UI that nobody can diff or audit. This repo's own `playbook/policy.json`
and `playbook/waivers.json` are a working example: gate thresholds and
exception ledger both live as JSON, changed only through the same PR
process as application code.

What that looks like in practice, per `playbook/MASTER-PLAYBOOK.md`
Zone 1:

- **A waiver PR must contain**: the rule being waived, the path it
  applies to, the reason, and an expiry date. No expiry date, no
  waiver — a permanent exception is a policy change wearing a waiver's
  clothes, and it should go through the harder review path instead.
- **Reviewer checklist for a waiver**: is the expiry ≤ 90 days out? does
  the stated reason name an actual compensating control (not just "we'll
  fix it later")? An expiry date without a real justification is a
  snooze button, not risk management.
- **Loosening policy (raising a threshold, removing a deny-rule) is an
  org decision, not an individual one** — it requires two approvals, not
  one. This is the same principle as a four-eyes financial control:
  one engineer proposing a change to what's enforced should never also
  be the sole approver of that change.

Branch protection is the mechanism that makes any of this non-optional:

- Require the security pipeline to be green before merge is allowed.
- Disallow force-push to `main` (prevents silently rewriting reviewed
  history).
- Disallow direct commits to `main` (forces everything through a
  reviewed PR, including the policy files themselves).
- Require a minimum number of approvals, and ideally CODEOWNERS-based
  routing so security-relevant paths (`policy.json`, `Dockerfile`,
  `infra/terraform/`) always get a security-aware reviewer, not just
  whoever's next in the rotation.

The core insight worth internalizing: a scanning tool that produces a
report nobody is forced to read is not a control. Branch protection
converts "the scan ran" into "the scan ran and blocked the merge until
it was clean or explicitly, auditable, time-boxed waived." That
conversion — advisory to enforced — is the entire point of this zone.

## 7. Applied to poetic-musings — what's real here, what's a gap

Being honest about the state of this repo's own Zone 1 matters more than
describing the ideal, because the gap itself is instructive.

**What's real:**

- `playbook/MASTER-PLAYBOOK.md` documents the Zone 1 plays, but both are
  explicitly tagged `[proc]` in this repo's own tagging convention — not
  `[run]`. `[proc]` means process-bound: a documented practice and
  intent, not something that was executed and verified the way the
  `[run]` items are (e.g., the pre-commit hook, which was verified twice
  — once in an isolated scratch repo, once installed for real). Calling
  a `[proc]` item "verified" or "proven" would be exactly the kind of
  overclaim this repo's own house style forbids.
- The CI wiring that *would* enforce a review gate is real and exercised:
  `.github/workflows/ci.yml` and `.gitlab-ci.yml` trigger on push and
  pull-request to `main`, and `JOB.html`'s own CI/CD row documents real
  runs — GitHub Actions caught five genuine problems on its first run,
  and a real self-hosted Jenkins build (`jenkins/`, build #7) caught an
  actual CRITICAL Terraform misconfiguration. That's a real, working
  automated gate wired to the branch.

**What's an honest gap:**

- This is, in practice, a solo repository worked mostly directly on
  `main`. The tooling supports a feature-branch-plus-PR-review workflow
  (GitHub's branch protection settings, required status checks,
  CODEOWNERS) but that flow has not actually been exercised day to day
  here the way it would be on a team. There's no evidence in this repo
  of a sustained cadence of feature branches opened, reviewed by a
  second person, and merged via protected-branch rules — because there
  hasn't been a second reviewer.
- The waiver-ledger discipline described in Zone 1 (`waivers.json` with
  expiry + compensating-control review, two-approval policy loosening)
  is documented as intended practice but has not been exercised against
  a real waiver request that went through actual PR review with a
  second human approver, for the same reason: no second reviewer in this
  repo's actual git history.

The lesson to carry into a real job, not just this repo: tooling capability
and exercised process are two different claims, and conflating them is
exactly the failure mode this zone exists to prevent. On a real team,
before trusting that "we have branch protection" means anything, check
whether it has actually been exercised — pull the last 20 merged PRs and
see if any of them were ever blocked, reviewed by someone other than the
author, or had a status check fail and get fixed before merge. If the
answer is no, the protection is configured but unproven, same as this
repo's `[proc]` tag says out loud.

## 8. Day-one checklist for this zone

On a new DevSecOps engagement, in the first week, actually go do these —
don't take anyone's word that they're already handled:

1. **Pull the branch protection rules for every long-lived branch**
   (`main`, `release/*`) and read them literally — required status
   checks, required approval count, whether force-push and direct
   commits are actually disabled, not just "supposed to be."
   `gh api repos/:owner/:repo/branches/main/protection` (GitHub) or
   the equivalent GitLab/Azure API — don't just eyeball the UI, capture
   it so you can diff it later.
2. **Find out who can bypass the rules.** Admins can often override
   branch protection by default on GitHub unless "include administrators"
   is explicitly checked. Same category of question on GitLab (Maintainer
   push rights) and Azure Repos (bypass policy permissions). Get the
   actual list of people/service accounts with bypass rights — it's
   almost always larger than anyone expects.
3. **Check who has force-push rights**, anywhere, on any protected
   branch, and why.
4. **Verify the CI triggers actually fire on PR, not just on push to
   `main` after merge.** A pipeline that only runs post-merge is not a
   gate — it's a fire alarm after the fire.
5. **Pull the last 15-20 merged PRs and check**: was there a second
   human reviewer, did any status check ever fail and block a merge
   until fixed, is there a pattern of the same one or two people
   approving everything (a rubber-stamp culture)?
6. **Find the policy-as-code files, if any exist** (`policy.json`,
   `OWASP` baseline configs, `.github/CODEOWNERS`) and check they're
   under the same PR review requirement as application code — not
   editable by a lone admin outside of review.
7. **Check for a waiver/exception ledger.** If findings get suppressed
   anywhere (`.gitleaksignore`, `# nosec`, `#tfsec:ignore`, SARIF
   baseline files), is there a paper trail with reason + expiry, or are
   suppressions silent and permanent?
8. **Confirm the default branch is actually the protected one** — it's
   a common drift for a repo to be renamed/reorganized and the
   protection rule left pointed at a now-stale branch name.
9. **Test the gate, don't trust the gate.** Open a throwaway branch,
   commit something the security scan should catch (a fake but
   plausible-looking secret pattern, an unpinned dependency), open a PR,
   and confirm it actually blocks. If nobody can show you it's ever
   failed a real PR, you don't actually know it works.

## 9. Troubleshooting quick-reference

| Symptom | Cause | Fix |
|---|---|---|
| `git pull` fails: "Your local changes would be overwritten" | Uncommitted local edits conflict with incoming changes | `git stash`, then `git pull`, then `git stash pop` — or commit first |
| `git push` rejected: "Updates were rejected because the remote contains work that you do not have" | Someone else pushed since your last fetch; histories diverged | `git pull --rebase` (preferred for a linear history) or `git pull` (merge), resolve any conflicts, then push again |
| `git push` rejected after a rebase you intended | Remote branch has commits your rewritten history doesn't include | `git push --force-with-lease` — never bare `--force` on anything shared |
| Merge conflict markers (`<<<<<<<`) in a file | Two branches changed the same lines | Edit the file, remove markers, choose/combine the resolution, `git add`, then `git commit` (merge) or `git rebase --continue` (rebase) |
| Accidentally committed a secret, not yet pushed | Credential staged/committed locally only | `git reset --soft HEAD~1` (undo the commit, keep files), remove the secret, recommit — or `git commit --amend` if it's the tip |
| Accidentally committed and **pushed** a secret | Credential now in shared history, possibly already cloned by others | Rotate the credential immediately (this matters more than the git surgery) — then `git filter-repo` (or BFG Repo-Cleaner) to strip it from history, force-push, and have every clone re-fetch. Treat as an incident, not a git puzzle |
| Detached HEAD after checking out a tag or SHA | Checked out a commit, not a branch | `git switch -c rescue-branch` before switching away, to keep any new commits reachable |
| Need to undo a commit already on a shared/public branch | Public history — must not be rewritten | `git revert <sha>` — creates a new undo commit, safe for anyone who already pulled |
| Need to undo a commit that's still only local/private | Private history — safe to rewrite | `git reset --soft/--mixed/--hard HEAD~1` as appropriate, or `git commit --amend` |
| "fatal: not a git repository" | Wrong working directory, or `.git` missing/corrupted | `cd` to the actual repo root; if `.git` is genuinely gone, re-clone — don't try to reconstruct it by hand |
| Lost commits after a `reset --hard` or a bad rebase | Object still exists, just unreferenced | `git reflog`, find the pre-disaster SHA, `git reset --hard <sha>` or `git switch -c recovery <sha>` |
| Wrong branch, made commits there by mistake | Committed to `main` instead of a feature branch | `git branch feature/correct-branch` (creates it pointing at current HEAD), then `git reset --hard origin/main` on the original branch to back it out |
| Cherry-pick conflict | The target branch doesn't have the context commit(s) the pick depends on | Resolve like a merge conflict, `git add`, then `git cherry-pick --continue`, or `git cherry-pick --abort` to bail |

---

Zone 1 command recipes, cheat-sheet form, live in this book's toolkit
appendix — this chapter is the teaching pass, the appendix is the thing
you actually keep open in a second terminal tab.


---


# Chapter 2 — Zone 2: DEVELOP

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone matters

"Works on my machine" gets filed under CI/CD failures — Zone 3, BUILD — as if the
problem starts when a pipeline runs. It doesn't. By the time a build breaks in CI,
the actual failure already happened days or weeks earlier, in Zone 2, when a
developer's laptop quietly diverged from everyone else's: a different Python patch
version, a global `pip install` that shadowed the project's pinned dependency, a
Node toolchain that resolved `package-lock.json` differently, a locally-modified
`.env` nobody else has. CI just makes the divergence visible. Zone 2 is where it was
created.

This is toolchain drift, and it's a silent productivity killer precisely because it
doesn't show up as an incident. It shows up as friction: the fifteen minutes a new
hire spends fighting `node-gyp`, the afternoon someone loses because their local
Maven build pulls a different transitive dependency than the one pinned in CI, the
recurring "huh, it works when I run it" Slack thread. None of that gets a
postmortem. It just taxes every day, forever, until someone standardizes the
environment.

A DevSecOps engineer's job in this zone is not to write more application code. It's
to make the development environment itself a reproducible, version-controlled
artifact — so that "works on my machine" stops being a meaningful sentence, because
everyone's machine is close enough to identical that the distinction collapses. That
also means Zone 2 is a security boundary, not just a convenience: an unmanaged
laptop with unpinned dependencies, no pre-commit secret scanning, and stale
credentials cached from six months ago is a bigger attack surface than most people
account for when they draw the pipeline diagram starting at "push to git."

## 2. Standardized dev workspaces

The traditional fix for toolchain drift is a very long onboarding wiki page:
"install Python 3.11.4 exactly, use nvm not the system Node, run this shell script,
if step 7 fails try X." This works until the wiki page goes stale, which is
immediately.

The actual fix is to stop asking developers to reconstruct an environment from
instructions and instead hand them the environment itself, already built. There are
two dominant approaches:

**Containerized dev environments (Coder, Gitpod, GitHub Codespaces).** A control
plane provisions a workspace — a container or VM — from a declarative template. The
developer opens a browser or connects an IDE over SSH, and the workspace is already
correctly configured: right language runtime, right CLI tools, right internal certs,
right VPN-adjacent network access. Critically, the *template* is the artifact under
version control, not tribal knowledge. When the toolchain needs to change org-wide
(new SDK version, a mandated linter, an updated base image with a patched CVE), you
edit the template once and every future workspace inherits it. This also gives you
a security control you don't get from laptops: source code and credentials for a
project can live entirely inside the managed workspace rather than scattered across
personal machines with unknown patch levels and unknown local exfiltration paths.

**Devcontainers (VS Code Dev Containers, `devcontainer.json`).** A lighter-weight,
local-first version of the same idea: the project repo itself carries a
`.devcontainer/devcontainer.json` plus a Dockerfile, and the IDE builds and attaches
to that container locally instead of running on bare metal. You lose the
"provision on demand from a central control plane" property — it's still the
developer's own machine doing the building and running — but you gain something
important for free: the environment definition lives *in the repo*, next to the
code it builds, reviewed in the same pull requests. For a small team without the
appetite to run a Coder deployment, a devcontainer is usually the highest
leverage-per-effort move available.

The two aren't mutually exclusive. Coder itself can provision workspaces that are
just devcontainers running remotely — the declarative definition and the
centrally-managed provisioning are separate concerns that compose.

Either way, the property you're buying is the same one continuous integration gave
you for builds: a known-good, reproducible starting state, checked into version
control, that a human doesn't have to remember how to reconstruct.

## 3. Applied to poetic-musings: the real Coder deployment

`poetic-musings/coder/` is not a config file that was never run — it's a genuine,
self-hosted Coder instance, and it's worth walking through exactly what "genuine"
means here, because the honesty of the claim is the teaching point.

Bringing it up is the same as any real deployment:

```
cd coder
docker compose up -d
```

This starts the official, unmodified `ghcr.io/coder/coder:latest` image with its
built-in PostgreSQL, listening on `http://localhost:7080`. And it was actually
checked, not just declared running:

```
$ curl -s -o /dev/null -w '%{http_code}' http://localhost:7080/
200
$ curl -s http://localhost:7080/healthz
200
$ curl -s http://localhost:7080/api/v2/buildinfo
{"version":"v2.37.2+eb69e27", ...}
```

Three different endpoints, three different kinds of evidence: a login page that
actually renders (200, not a connection refused), a dedicated health check (200),
and a build-info API returning real, specific version data that couldn't have been
faked without also faking a working Coder binary. That's a genuinely proven claim:
the control plane runs, is reachable, and is a real Coder server.

Now the honest gap, stated exactly as it should be stated in a real engineering
handoff: **no workspace template was authored.** Coder's entire value proposition —
turning a declarative template into an on-demand, provisioned dev environment for a
developer to work in — has not been exercised here. What's proven is that the
server that *would* do that provisioning is alive and correctly configured. What's
unproven is the thing an actual developer cares about: "can I click a button and
get a working dev environment for this project." Those are different claims, and
conflating them is exactly the kind of overstatement this book's house style
forbids. If you inherited this deployment for real work, your first task wouldn't
be "verify Coder runs" — that's done — it would be writing a Terraform template
(container or VM, whichever fits your provisioner) and doing the one test that
actually matters: have a second person, who didn't build the server, spin up a
workspace from it and get real work done in under five minutes.

This is a useful pattern to internalize for your own audits, not just this repo's:
"control plane proven, full workflow not yet" is a completely normal, completely
honest state for infrastructure to be in. The failure mode isn't being in that
state — it's describing it as "we have dev environments" when what you actually
have is a server that could someday host them.

## 4. Pre-commit hooks done right

A pre-commit hook runs locally, on the developer's machine, before a commit is
allowed to complete. Its entire value proposition is speed and immediacy: catch a
mistake in the two seconds before it becomes a commit, not the two minutes before it
becomes a CI failure, and definitely not the two days before it becomes an incident.

That speed requirement is also the design constraint. A pre-commit hook has to run
on every single commit, for every developer, without becoming annoying enough that
people start reaching for `--no-verify`. That means:

**Belongs in a pre-commit hook:**
- Fast, local, deterministic checks — regex-based secret scanning, linting the
  files actually staged, dependency-pin format checks, formatting (`black`,
  `prettier`)
- Anything that only needs the file contents already on disk, no network call

**Does not belong in a pre-commit hook:**
- Full CVE/SCA scans against a live vulnerability database (`pip-audit`,
  `trivy`) — network-dependent, slow, and belongs in CI where it runs once per
  push, not once per commit
- SAST tools that need a full project build or take more than a couple of
  seconds
- Anything that can silently fail closed if a developer is offline, because
  a hook a developer can't work around gets bypassed with `--no-verify`, which is
  strictly worse than not having the check

`playbook/pre-commit` in this repo is a working, worked example of getting that
split right. Its entire body:

```bash
#!/usr/bin/env bash
# zone 2: pre-commit gate -- secrets + pins before anything leaves the workstation.
TOOLS="$(cd "$(dirname "$(readlink -f "$0")")/../../tools" 2>/dev/null && pwd)"
[ -n "$TOOLS" ] || TOOLS="tools"
python3 "$TOOLS/secrets.py" . || exit 1
[ -f requirements.txt ] && { python3 "$TOOLS/deps.py" requirements.txt || exit 1; }
exit 0
```

Two checks, both local, both fast: `secrets.py` (a regex-based credential scanner,
part of the `haskell.py`-based FP toolbox described in `playbook/README.md`) and
`deps.py` (a parser-combinator pin audit over `requirements.txt`). Nothing here
touches the network. Nothing here runs `pip-audit` or a real vulnerability
database — that's `cve.py`, and it lives in CI, not in this hook, exactly per the
"slow scans belong in CI" rule above.

It was verified, not just written, twice:

- **In an isolated scratch repo**: a staged fake AWS access key made the hook
  exit 1 and block the commit; a clean tree made it exit 0.
- **Installed for real** at this repo's own `.git/hooks/pre-commit` (local-only,
  not tracked by git — that's normal for hooks; if you want it enforced
  org-wide rather than per-developer, see the day-one checklist in §8), scoped
  to `app/ infra/ k8s/ ansible/ playbook/*.py` rather than the whole tree, and
  confirmed clean against the real working tree: `3 pinned, 0 unpinned, 0
  unparsed`, exit 0.

Install it the same way in any repo that ships `playbook/`:

```
cp playbook/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

One nuance worth internalizing: `secrets.py`'s regex approach has real, documented
precision limits. Run whole-repo instead of scoped, it flagged
`ad-lab/seed-objects.sh`'s `samba-tool gpo setlink ... --password="${ADMIN_PASSWORD}"`
as a `generic-secret` — the pattern matches `password="..."` regardless of whether
the value is a literal or a shell variable interpolation, a false positive a tool
like gitleaks (which tokenizes more carefully) wouldn't produce. That's why the
real installed hook is scoped to source directories rather than the whole tree.
It's not a reason to distrust the tool; it's a reason to know what it's actually
checking, which is exactly the "name gaps plainly" standard this book holds itself
to.

## 5. Workspace hygiene, especially cross-platform (WSL) gotchas

Even with a standardized workspace, day-to-day friction shows up at the edges —
and nowhere more than for developers on Windows via WSL. `playbook/FIELD-MANUAL.md`
§7.1 documents these as a real table, not theory, because they're the kind of thing
that eats a genuine hour before anyone thinks to check line endings. A standardized
Coder or devcontainer workspace supersedes most of this table by moving the actual
work into a Linux container regardless of the host OS — but until that's in place,
this table *is* the workspace standard, and it's worth knowing even once you have
Coder, because someone's host tooling (git, editor) still touches the repo.

**Line endings (CRLF vs LF).** Windows-side edits introduce `\r\n`. The first
symptom is almost never "line endings are wrong" — it's `bash\r: command not
found` when a shell script that worked yesterday suddenly doesn't, or a diff that
shows every line in a file as changed because line endings flipped underneath the
content. Fix at the repo level, not per-developer:

```
# .gitattributes
* text=auto eol=lf
```

```
git config core.autocrlf input
```

**Repo location: ext4 home vs `/mnt/c`.** WSL2 mounts the Windows filesystem
through a 9P network-filesystem-like layer (DrvFs). A git repo living under
`/mnt/c/Users/...` pays for every single filesystem operation — every `git status`,
every compile, every `node_modules` install — crossing that boundary. The fix is
blunt and non-negotiable: **clone the repo into the Linux side's ext4 home
(`~/projects/...`), never under `/mnt/c`.** Builds have been observed 10-50x
slower on `/mnt/c`, compounded further if Windows Defender is also actively
scanning the mounted path on every file write. If Defender must run, exclude
`\\wsl$` paths from real-time scanning.

**Clock drift after sleep.** WSL2 runs a lightweight VM with its own clock, and
that clock can drift noticeably after a laptop sleeps and resumes — enough to
break TLS handshakes and Kerberos ticket validation, which are both
timestamp-sensitive. Symptom: `apt`/`pip` start failing with cert errors, or a
Kerberos-backed auth suddenly rejects a previously-valid ticket, right after
resuming from sleep. Fix: `sudo hwclock -s` to force a resync, or on recent WSL
versions, `wsl --shutdown` from PowerShell and reopening the terminal.

**Phantom file-mode changes.** Files under `/mnt/c` show up as mode 777 because
DrvFs doesn't carry real POSIX permissions, which makes `git status` show
constant, meaningless mode-change noise. Fix in `/etc/wsl.conf`:

```
[automount]
options = "metadata,umask=022"
```

— or, again, just keep the repo off `/mnt/c` entirely, which fixes this and the
performance problem in one move.

**DNS breaking on VPN.** WSL2's auto-generated `resolv.conf` fights corporate VPN
clients that expect to own DNS resolution. Fix in `/etc/wsl.conf`:

```
[network]
generateResolvConf = false
```

then hand-write a static `/etc/resolv.conf`.

**Docker not available inside WSL.** This is almost always the Docker Desktop
WSL-integration toggle, not a broken install — Docker Desktop → Settings →
Resources → WSL Integration, and enable the specific distro.

None of these are exotic. They're the kind of thing every WSL-using engineer hits
in their first month and then forgets they ever had to learn, which is exactly why
they belong in a written table instead of oral tradition.

## 6. Build tools primer

You don't need to be a build-tool expert to be a working DevSecOps engineer, but
you do need to read a `pom.xml` or `package.json` well enough to know what a
pipeline is actually doing when it runs `mvn package` or `npm ci` — because that's
usually where a security-relevant surprise (an unpinned dependency, a postinstall
script, a plugin pulling from an unexpected registry) actually lives.

### Maven (Java)

A Maven project is described entirely by `pom.xml` — the Project Object Model.
Skeleton:

```xml
<project>
  <groupId>com.example</groupId>
  <artifactId>my-service</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
      <version>3.2.0</version>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

Maven's build runs through a fixed **lifecycle** of phases, each one depending on
the ones before it — `validate → compile → test → package → verify → install →
deploy`. Running a phase runs every phase before it too. The commands you'll
actually type:

```
mvn compile    # compile sources only
mvn test       # compile + run unit tests
mvn package    # compile + test + produce the jar/war
mvn install    # package + install into the local ~/.m2 repo for other local projects
mvn verify     # package + run integration checks (often where security plugins hook in)
```

Dependencies resolve from repositories (Maven Central by default, or an internal
Nexus/Artifactory mirror — worth checking `settings.xml` for exactly which). Note
the same lesson as `playbook`'s `deps.py`: a version like `3.2.0` is pinned, a
range like `[3.0,4.0)` is not, and unpinned Maven dependencies drift the same way
unpinned `requirements.txt` lines do.

### NPM (Node.js)

`package.json` is the equivalent contract:

```json
{
  "name": "my-frontend",
  "version": "1.0.0",
  "scripts": {
    "build": "vite build",
    "test": "vitest run",
    "lint": "eslint ."
  },
  "dependencies": {
    "react": "18.2.0"
  },
  "devDependencies": {
    "vitest": "1.2.0",
    "eslint": "8.56.0"
  }
}
```

`dependencies` ship in the production bundle; `devDependencies` (test runners,
linters, bundlers) don't. `npm run <script>` executes anything under `scripts` —
`npm run build`, `npm run test`. `npm install` resolves against the semver ranges
in `package.json` and writes the exact resolved tree to `package-lock.json`;
`npm ci` is the one you want in CI and in any reproducible build, because it
installs *exactly* what the lockfile says, refuses to touch `package.json`, and
fails outright if the two are out of sync — the NPM equivalent of enforcing pins.

### Tomcat and multi-tier deployment

For Java web apps, `mvn package` with `packaging: war` produces a `.war` archive
that Tomcat serves by dropping it into `$CATALINA_HOME/webapps/` — Tomcat
auto-explodes and deploys it on startup or via its manager API. Multi-tier
projects (a Node or Python or .NET app tier talking to a Postgres, MySQL, or
MongoDB data tier) are the norm rather than the exception in real DevSecOps work,
and the build-tool layer only ever covers the app tier — the database is a
separate, usually containerized, dependency the build doesn't touch.

## 7. Python for DevOps scripting — the practical subset

Most day-to-day DevSecOps scripting doesn't need a Python expert — it needs
someone fluent in a fairly small, practical subset: reading and writing files,
parsing JSON, calling a REST API, and talking to a cloud SDK.

**Datatypes and functions**, the load-bearing basics:

```python
scan_result = {"tool": "trivy", "findings": 3, "worst": "HIGH"}  # dict
findings = ["CVE-2024-1234", "CVE-2024-5678"]                    # list
threshold = 2                                                    # int

def worst_exceeds(result: dict, max_allowed: str) -> bool:
    levels = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
    return levels[result["worst"]] > levels[max_allowed]
```

**File handling** — the pattern you'll write constantly is "read a scan tool's
output, extract what matters, write a summary":

```python
import json

with open("trivy-report.json") as f:
    report = json.load(f)

summary = {"total": len(report["Results"])}

with open("summary.json", "w") as f:
    json.dump(summary, f, indent=2)
```

CSV shows up for inventory/audit data (asset lists, IAM user exports):

```python
import csv

with open("iam_users.csv", newline="") as f:
    for row in csv.DictReader(f):
        if row["mfa_enabled"] == "false":
            print(f"no MFA: {row['user']}")
```

**Calling REST APIs** — the standard shape for talking to a scanner's API, a
ticketing system, or a webhook:

```python
import requests

resp = requests.get(
    "https://api.example.com/v1/findings",
    headers={"Authorization": f"Bearer {token}"},
    timeout=10,
)
resp.raise_for_status()
findings = resp.json()
```

**Cloud SDKs — boto3 (AWS)** is the one you'll reach for most as a DevSecOps
engineer doing anything AWS-adjacent — inventory audits, checking security group
rules, enumerating S3 bucket policies:

```python
import boto3

ec2 = boto3.client("ec2")
for sg in ec2.describe_security_groups()["SecurityGroups"]:
    for rule in sg["IpPermissions"]:
        for ip_range in rule.get("IpRanges", []):
            if ip_range["CidrIp"] == "0.0.0.0/0":
                print(f"open to the world: {sg['GroupId']} port {rule.get('FromPort')}")
```

The same shape covers `docker-py` (talking to the Docker daemon's API instead of
shelling out to the `docker` CLI) and `kubernetes-client` (listing pods, reading
deployment status, automating rollouts) — a client object, a method call, a
Python-native object back instead of text to parse.

**A first look at point-free / functional style.** `playbook/haskell.py` and the
nine scripts built on it (`secrets.py`, `deps.py`, `cve.py`, and the rest — see
Chapter 5) take a different approach than the imperative style above: functions
composed from smaller functions (`compose`, `pipe`), `Maybe`/`Either` types
standing in for `None`/exceptions, parser combinators instead of hand-rolled
string parsing. The short version of why that's worth knowing even at the "small
script" level this chapter covers: a function built by composing two or three
smaller, pure functions is trivially unit-testable in isolation — you're not
mocking a REST call and a database and a file write to test one `if` statement,
because the logic and the I/O are separate functions. That separation is also what
let every script in `playbook/` be re-verified against this repo's *real* files
(not just seeded demo fixtures) with a one-line invocation each — `deps.py
app/status-service/requirements.txt`, `cve.py` fed real `pip-audit` JSON — because
the core logic never assumed anything about where its input came from. Full depth
on this style — the monad implementations, the do-notation, why it composes better
than exceptions for a gate pipeline — is Zone 5 and Zone 9's territory, and the
book's toolkit appendix.

## 8. Day-one checklist for this zone

1. **Confirm pre-commit hooks are actually installed**, not just present in the
   repo. A hook file sitting in `playbook/pre-commit` or `hooks/pre-commit`
   does nothing until it's copied to `.git/hooks/pre-commit` and made
   executable — and that copy is per-clone, per-developer, not something `git
   clone` does for you. Check: `ls -la .git/hooks/pre-commit` on a few
   teammates' machines, not just your own.
2. **Decide if hook enforcement needs to be org-wide, not per-developer.** A
   local-only hook is bypassable (`git commit --no-verify`) and simply absent on
   any clone where nobody ran the `cp`/`chmod` step. If that's not acceptable,
   the same checks belong duplicated as a required CI job — belt and suspenders,
   not "either/or."
3. **Inventory who's on WSL, or otherwise cross-platform**, before it becomes a
   support fire. A five-minute `.gitattributes` fix (§5) prevents every one of
   the CRLF-pollution incidents that otherwise show up as "why did this PR touch
   400 files."
4. **Audit what dev-environment standardization actually exists** versus what's
   documented as existing. Apply the same standard this chapter applied to
   `coder/`: is there a running, reachable control plane (verify it, don't take
   the README's word for it), and separately, is there an actual provisionable
   template a new developer can use today? Those are two different checkboxes.
5. **Check `.gitattributes` is present and correct** in every actively-developed
   repo, not assumed from one repo to the next.
6. **Verify build-tool dependency pinning** — `requirements.txt`, `pom.xml`
   versions, `package-lock.json` — the same "pinned vs range" question this
   chapter and Zone 5's `deps.py` both care about, because an unpinned
   dependency is a reproducibility problem in Zone 2 and a supply-chain risk in
   Zone 5 simultaneously.
7. **Confirm secret-scanning coverage matches reality.** If `secrets.py` (or
   equivalent) is scoped to specific directories rather than the whole tree,
   know why — and know what's *not* covered by that scope.

## 9. Troubleshooting quick-reference

| Problem | Likely cause | Fix |
|---|---|---|
| Pre-commit hook doesn't fire at all | Never copied into `.git/hooks/`, or not `chmod +x` | `cp playbook/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit` |
| Hook fires but everyone routes around it | Local-only enforcement, `--no-verify` used habitually | Duplicate the same checks as a required CI job |
| Every file in a PR shows as changed | CRLF/LF mismatch from a Windows-side editor | `.gitattributes`: `* text=auto eol=lf`; `git config core.autocrlf input`; renormalize with `git add --renormalize .` |
| `bash\r: command not found` on a script that "worked yesterday" | CRLF crept into a shell script | Same `.gitattributes` fix; re-save the file with LF endings |
| Git operations (`status`, `checkout`, builds) unexpectedly slow | Repo living on a network/mounted filesystem — WSL `/mnt/c`, an NFS home, a synced cloud-drive folder | Move the repo to local/native disk (WSL: ext4 home, not `/mnt/c`) |
| TLS/cert or Kerberos errors right after resuming from sleep | VM clock drift (WSL2 especially) | `sudo hwclock -s`, or `wsl --shutdown` and reopen |
| `git status` shows constant phantom mode changes | DrvFs reporting mode 777 for everything under `/mnt/c` | `/etc/wsl.conf` `[automount] options="metadata,umask=022"`, or move off `/mnt/c` |
| Python script works for one dev, `ModuleNotFoundError` for another | No virtualenv, or a global `pip install` masking the pinned version | Always work inside a venv: `python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt` |
| `npm install` resolves different versions than teammates get | `npm install` used where `npm ci` should be | `npm ci` in any reproducible build — installs exactly what `package-lock.json` says, fails if it's stale |
| Maven pulls an unexpected/newer transitive dependency | Version range instead of an exact pin in `pom.xml` | Pin exact versions; `mvn dependency:tree` to see what's actually resolving |
| DNS breaks the moment the VPN connects (WSL) | Auto-generated `resolv.conf` fighting the VPN client | `/etc/wsl.conf` `[network] generateResolvConf=false` + static `resolv.conf` |
| `docker` command not found inside WSL despite Docker Desktop running | WSL integration not enabled for that distro | Docker Desktop → Settings → Resources → WSL Integration |

---

Concrete recipes for this zone — the exact `.gitattributes` block, a starter
`devcontainer.json`, the Coder template this chapter's honest gap calls for, and
copy-pasteable Maven/NPM/Python snippets — live in the book's toolkit appendix.


---


# Chapter 3 — Zones 3 & 4: Build and Test

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why these zones matter together

Zone 3 (BUILD) and Zone 4 (TEST) get one chapter, not two, because splitting
them lies about how pipelines actually work. A build stage that compiles or
packages code and hands it to a gate that can't fail isn't a safety net —
it's decoration with a green checkmark glued on. And a test suite that never
runs inside the build pipeline is just documentation nobody enforces. The
two zones are one machine: BUILD produces the artifact, TEST decides whether
that artifact is allowed to move.

The operating principle for this whole chapter, lifted directly from
`playbook/MASTER-PLAYBOOK.md` Zone 4:

> A gate that cannot fail is decoration.

That single sentence is why this repo keeps a directory of deliberately
broken input (`playbook/demo/`) whose entire job is to make the pipeline
fail on command, and why the real Jenkins build documented later in this
chapter is allowed to end in `FAILURE` instead of being quietly patched
until it went green. If you can't point to the run where the gate caught
something real — or at minimum the seeded fixture where it caught something
fake on purpose — you don't know if the gate works. You only know it hasn't
failed *yet*.

Build without test discipline just ships broken things faster. A CI
pipeline that lints and packages but never runs a test suite, or runs one
that can never turn red, has made deployment *faster*, not *safer*. Speed
without a working gate is how you get to production quicker with the same
bugs you'd have shipped by hand — just automated.

---

## 2. CI/CD mechanics, dialect by dialect

Every CI system answers the same four questions: what triggers a run, what
units of work exist, how are those units ordered/dependent, and what
happens on success or failure. The syntax differs enormously; the shape
underneath does not. This section teaches the syntax of all three dialects
this repo actually runs, using its real files.

### 2.1 GitHub Actions

A GitHub Actions workflow is a YAML file under `.github/workflows/`. This
repo has two: `ci.yml` (lint + test) and `security.yml` (the five security
gates). Anatomy, using the real `ci.yml`:

```yaml
name: CI Build/Lint/Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install ruff
      - run: ruff check app

  python-tests:
    runs-on: ubuntu-latest
    needs: lint-python        # <-- explicit dependency edge
    steps: [...]
```

Key mechanics worth internalizing:

- **`on:`** is the trigger block. `push`/`pull_request` scoped to `main`
  keeps every commit and every PR gated; `security.yml` additionally adds a
  `schedule: cron: "0 6 * * 1"` trigger — a weekly re-scan that catches
  newly-disclosed CVEs against code that hasn't changed. This is a detail
  people skip and shouldn't: a dependency can go from clean to vulnerable
  with zero commits on your side.
- **`permissions:`** at the workflow level defaults every job's
  `GITHUB_TOKEN` to least-privilege (`contents: read`); jobs that need more
  (e.g. `security-events: write` to upload SARIF to code scanning) declare
  it explicitly at the job level. This is the GitHub Actions equivalent of
  not running your build as root.
- **`concurrency:`** with `cancel-in-progress: true` means a new push to the
  same ref cancels the in-flight run for the old one — you stop burning
  runner minutes on commits nobody cares about anymore.
- **`jobs.<id>.needs:`** is how you build a DAG instead of a flat list.
  `python-tests` needs `lint-python`, so it won't even start if lint fails.
  Each of the five jobs in `security.yml` (secrets-scan, sast-python,
  sbom-and-dependency-scan, container-scan, iac-scan, k8s-manifest-scan) has
  no `needs:` between each other — they run in parallel, each independently
  gating the merge. That's intentional: these are different failure modes,
  and none of them should block the others from reporting.
- **`steps:`** are the actual work, either `uses:` (a reusable Action from
  the marketplace, pinned here by tag — `actions/checkout@v4`,
  `aquasecurity/trivy-action@v0.24.0`) or `run:` (raw shell). Every
  security-relevant step in `security.yml` follows the same guard pattern —
  check the target exists first, `if:` gate the step, otherwise print a
  skip notice to `$GITHUB_STEP_SUMMARY` — so the pipeline stays safe to run
  even before `app/`, `infra/terraform`, or `k8s/` exist.
- **Fail conditions are explicit, not implicit.** `bandit -r app -ll` on its
  own would exit non-zero on medium+ severity findings and fail the step by
  default — but the pipeline captures that into `BANDIT_FAILED` first so it
  can print a step-summary message before failing loud. `trivy-action` takes
  `exit-code: "1"` directly as an input. Nothing here is "well it probably
  fails somehow" — every gate's fail path was written on purpose.

### 2.2 GitLab CI

`.gitlab-ci.yml` is a single file at the repo root; GitLab has no per-job
files the way Actions has per-workflow files. Anatomy, from this repo's real
file:

```yaml
stages:
  - lint
  - test
  - security

default:
  interruptible: true

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .cache/pip

workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_PIPELINE_SOURCE == "schedule"

lint-python:
  stage: lint
  image: python:3.12-slim
  script:
    - pip install ruff
    - ruff check app *.py

python-tests:
  stage: test
  image: python:3.12-slim
  needs: ["lint-python"]
  script: [...]
```

Differences from Actions that matter in practice:

- **`stages:`** is a named, ordered list (`lint`, `test`, `security`); every
  job declares which stage it belongs to, and stages run in that order by
  default — GitLab's version of the `needs:` DAG, but coarser-grained. You
  can still use `needs:` between individual jobs (as `python-tests` does
  against `lint-python`) to fast-track dependencies within or across
  stages, bypassing strict stage ordering.
- **`image:`** replaces `runs-on:` + manual tool installs — GitLab jobs run
  inside a container you name directly, which is why `secrets-scan` can
  just say `image: zricethezav/gitleaks:latest` and skip installing
  anything. `container-scan` uses `docker:24-dind` with a `services:
  [docker:24-dind]` sidecar to get an isolated Docker-in-Docker daemon —
  notably *not* the host-socket approach this repo's own Jenkins setup
  uses (see §4's honest gaps).
- **`rules:` / `exists:`** replace Actions' `if: steps.x.outputs.found`
  pattern with something declarative: `iac-scan` runs only `if:` `exists: -
  infra/terraform/**/*` matches, no separate "check for directory" step
  needed. Cleaner, but it means the guard logic lives in GitLab-specific
  syntax instead of portable shell — worth knowing if you ever need to read
  the guard condition outside GitLab's own UI.
- **`workflow: rules:`** at the top level controls whether a pipeline runs
  *at all* for a given trigger — this repo's file explicitly opts into
  merge-request pipelines, main-branch pushes, and scheduled runs, and
  implicitly excludes everything else (e.g. pushes to arbitrary feature
  branches with no open MR).
- **Managed template alternative, noted honestly inline**: this file's own
  header comment says GitLab.com ships free auto-detecting
  `Jobs/SAST.gitlab-ci.yml` / `Secret-Detection.gitlab-ci.yml` /
  `Dependency-Scanning.gitlab-ci.yml` / `Container-Scanning.gitlab-ci.yml`
  templates that would need zero custom script — this repo deliberately
  reimplements the same five scans with explicit tool invocations instead,
  specifically so the GitHub and GitLab pipelines stay line-for-line
  comparable as a teaching artifact. In a real job, you'd very likely reach
  for the managed templates first and only hand-roll when you need a tool
  they don't cover.

### 2.3 Jenkins

Jenkins is the odd one out in three ways: it's self-hosted (you run and
maintain the controller), its pipeline syntax is Groovy-flavored DSL rather
than plain YAML, and — critically — it has **no equivalent of GitHub's
marketplace Actions**. Every `uses: gitleaks/gitleaks-action@v2` becomes
literal shell you write and maintain yourself. That's both Jenkins'
strength (total control, no vendor lock-in, no marketplace supply chain to
audit) and its liability (you own every install script, every version pin,
every "why did this break" — see the bug list in §3).

Declarative Jenkinsfile anatomy, from this repo's real
`jenkins/Jenkinsfile`:

```groovy
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
    }

    stages {
        stage('Checkout') {
            steps {
                sh '''
                    set -eu
                    rm -rf repo
                    git clone file:///workspace repo
                '''
            }
        }

        stage('Lint (ruff)') {
            steps {
                dir('repo') {
                    sh '''
                        set -eu
                        python3 -m venv .venv
                        . .venv/bin/activate
                        pip install -q ruff
                        ruff check app
                    '''
                }
            }
        }
        // ... Test, Secrets scan, SAST, SBOM, Dependency scan,
        //     Container scan, IaC scan, K8s manifest scan
    }

    post {
        always {
            archiveArtifacts artifacts: 'repo/sbom-status-service.cdx.json,repo/pip-audit-results.json',
                              allowEmptyArchive: true
        }
    }
}
```

Mechanics:

- **`pipeline { agent any }`** is the declarative top level — `agent any`
  means "run on whatever executor is available," which in this repo's setup
  is the single built-in node (see the "honest gaps" in §4 — no separate
  agents were stood up).
- **`stages { stage(...) { steps { ... } } }`** nests three levels deep.
  Each `stage` is a named unit shown in the Jenkins UI's stage view — the
  same visual granularity as a GitHub Actions job, but all stages live in
  one linear pipeline run by default rather than being independently
  triggerable jobs.
- **`sh '''...'''`** blocks are raw shell, and `set -eu` at the top of every
  one is load-bearing: without it, a command failing partway through a
  multi-line block wouldn't stop the stage. (§3's bug #4 is exactly what
  happens when `set -eu` interacts badly with a tool's nonstandard exit
  code.)
- **`post { always { ... } }`** is Jenkins' equivalent of GitHub's `if:
  always()` step guard — it runs regardless of whether earlier stages
  passed or failed, used here to archive the SBOM and dependency-audit JSON
  even on a failed build (which is exactly what happened on build #7 — the
  IaC stage failed, but SBOM/pip-audit artifacts from the earlier passing
  stages still got archived).
- **The plugin ecosystem, both ways.** Jenkins' actual pipeline execution
  engine, Git integration, and workflow step DSL are all plugins
  (`workflow-aggregator`, `git`, `workflow-job` in this repo's setup) —
  which means Jenkins can do almost anything with the right plugin
  installed, but also means "Jenkins broke" is very often "a plugin version
  broke," and plugin versions here were installed unpinned via the update
  center by name — a real, named supply-chain gap (see §4).

### 2.4 Azure DevOps — the fourth CI/CD dialect

Azure DevOps is not exercised anywhere in this repo. Say that plainly up
front, because it matters for how you read the rest of this subsection:
everything below is course knowledge for the job requirement, not something
`poetic-musings` has proven end-to-end the way the GitHub Actions, GitLab
CI, and Jenkins sections above were built and run for real. The honest
status, straight from `infra/terraform/README.md`: this repo's Terraform
provisions across **both AWS and Azure**, but "the AWS side has been
applied for real, against a personal free-tier AWS account, verified
against the live API, and torn down with proof" — while "the Azure side
remains written-and-validated-only (no Azure subscription available at
build time)." `terraform validate` and `fmt -check` pass against
`modules/azure-platform/` (a resource group, ACR, storage account, AD
integration notes), and — as §4 of this chapter demonstrates — `trivy
config` finds a real CRITICAL misconfiguration in that same module. But no
`terraform apply` has ever run against a live Azure subscription from this
repo, no Azure Pipeline has ever executed, and no Azure DevOps organization
exists for this project. Treat the rest of this subsection as what you need
to know for the job requirement, clearly separated from what this repo has
verified.

**How Azure DevOps differs from a "traditional" CI/CD setup.** GitHub
Actions, GitLab CI, and Jenkins each give you one thing (Actions: a hosted
runner platform bolted onto a specific Git host; GitLab CI: a runner
platform bolted onto GitLab's own Git host; Jenkins: an independent
automation server you point at *any* Git host). Azure DevOps is a full
suite: source control (Azure Repos), pipelines (Azure Pipelines), package
management (Azure Artifacts), planning boards, and test plans, all under
one organization, with tight native integration into the rest of Azure
(AKS, ACR, Azure AD/Entra ID) the way GitHub Actions has tight native
integration into GitHub's own ecosystem. The practical implication: an
Azure-DevOps-native pipeline that deploys to AKS has fewer moving parts to
wire up than a GitHub Actions workflow doing the same thing against AKS,
because auth and resource discovery are closer to first-class.

**Azure Repos.** Git-based, same fundamental model as GitHub/GitLab — pull
requests, branch policies (the Azure DevOps term for GitHub's branch
protection / GitLab's merge request approval rules), required reviewers,
and build validation policies that block a PR merge until a named pipeline
run passes. The PR workflow itself (branch, push, open PR, review, gate,
merge) is functionally identical to what this repo already does on GitHub
— the vocabulary and UI differ, the mechanics don't.

**Azure Pipelines: classic vs YAML.** This is the distinction actually
worth understanding, because it's a real historical/practical split you'll
hit in the field. **Classic pipelines** are built through Azure DevOps' web
UI — a series of point-and-click task configuration screens, with the
resulting pipeline definition stored as an opaque object in the Azure
DevOps project itself, not as a file in your repo. **YAML pipelines** are a
single `azure-pipelines.yml` file committed to the repo root (or wherever
you point the pipeline at), structurally close to what GitHub Actions and
GitLab CI already do — version-controlled, diffable, reviewable in the same
PR as the code change it affects. A minimal YAML pipeline, shaped like this
repo's `ci.yml`/`.gitlab-ci.yml` lint-then-test flow:

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

stages:
  - stage: Lint
    jobs:
      - job: LintPython
        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.12'
          - script: pip install ruff
          - script: ruff check app

  - stage: Test
    dependsOn: Lint
    jobs:
      - job: PytestRun
        steps:
          - script: |
              pip install -r app/status-service/requirements.txt pytest
              pytest app/status-service -q
```

The shape is recognizable: `trigger:` is Actions' `on:`, `pool:` picks the
runner image the way `runs-on:` does, `stages:`/`jobs:`/`steps:` nest the
same three levels GitLab's `stages:` + implicit job-per-block does, and
`dependsOn:` is the same DAG-edge concept as Actions' `needs:` or GitLab's
`needs:`. `task:` references a versioned, marketplace-style reusable step
(Azure DevOps' equivalent of a GitHub Action) — `UsePythonVersion@0` is
conceptually identical to `actions/setup-python@v5`. **Why YAML is the
modern default**, and the reason a real job posting will assume you write
YAML pipelines, not classic ones: YAML pipelines live in source control,
which means pipeline changes go through the same PR review, the same
history, and the same rollback mechanism as application code — a classic
pipeline's configuration is invisible to `git blame` and invisible to a PR
diff, so nobody reviewing a code change can see that the deploy behavior
also changed. Microsoft's own guidance and current tooling investment has
tracked this same conclusion; classic pipelines still exist for backward
compatibility with older Azure DevOps projects, not as the recommended path
for new work.

**Azure Artifacts.** Azure DevOps' built-in package repository — feeds for
NuGet, npm, Maven, Python (pip/twine-compatible), and universal packages,
scoped per-organization or per-project. A pipeline publishes a build output
to a feed (`twine upload` / `npm publish` pointed at an Azure Artifacts feed
URL with a pipeline-scoped auth token) and downstream pipelines or
developers consume from it the same way they'd consume from PyPI or npmjs,
except privately and inside your org's network boundary. Functionally this
is Microsoft's answer to the same problem Nexus solves (§6, next) — the
practical difference is Azure Artifacts is scoped to Azure DevOps
specifically, while Nexus is platform-agnostic and self-hostable anywhere.

**Service Principal authentication.** A Service Principal is Azure AD's
(now Entra ID's) mechanism for giving a non-human identity — a pipeline —
scoped, non-interactive credentials to act against Azure resources, the
direct analog of an AWS IAM role assumed by a CI runner, or a GCP service
account key. In practice: you register an App Registration in Entra ID,
create a Service Principal from it, grant it a scoped role assignment
(ideally on a specific resource group, not the subscription root — the same
least-privilege discipline this repo's `infra/terraform/modules/aws-
platform` applies with its "least-priv IAM role"), and store its client
ID/secret (or, better, a federated workload identity credential requiring
no stored secret at all) as an Azure DevOps **Service Connection**. The
pipeline then references that Service Connection by name in any
`AzureCLI@2` or `AzureWebApp@1`/`KubernetesManifest@1` task, and Azure
DevOps injects the credential at run time — conceptually identical to how
`aws-actions/configure-aws-credentials` injects a role-assumed AWS session
into a GitHub Actions job, just under Azure's naming.

**Deploying to AKS or Azure Web Apps from a pipeline.** The two most common
deploy targets, and the pattern is the same shape both times: authenticate
via the Service Connection, then hand off to a target-specific task.

```yaml
- stage: DeployAKS
  dependsOn: Test
  jobs:
    - job: KubectlApply
      steps:
        - task: KubernetesManifest@1
          inputs:
            action: deploy
            connectionType: 'azureResourceManager'
            azureSubscriptionConnection: '<service-connection-name>'
            azureResourceGroup: '<resource-group>'
            kubernetesCluster: '<aks-cluster-name>'
            manifests: 'k8s/**/*.yaml'
```

For Azure Web Apps, `AzureWebApp@1` takes a package (a zip, or a container
image reference for a Web App for Containers target) and a Service
Connection, and handles the deploy-slot swap internally — no separate
`kubectl`-equivalent step needed since App Service manages the runtime.
Both patterns rest on the same foundation: the Service Connection is the
trust boundary, and everything downstream of it inherits that identity's
scope. If this repo ever did apply its Azure Terraform module for real and
wire a pipeline to it, this is the exact shape that pipeline would take —
but as of today, that's a described path, not a run one.

---

## 3. Applied to poetic-musings: three real dialects, one real pipeline logic

The point of running the *same* logic through three dialects isn't
redundancy for its own sake — it's that the underlying stage order (lint →
test → security gates) has to survive translation, and translating it is
where real bugs hide. GitHub Actions and GitLab CI both came up clean
because they build on managed runners with BuildKit, standard tool
availability, and marketplace Actions doing the tedious "detect + install +
run + format output" work for you. Jenkins, self-hosted from the official
`jenkins/jenkins:lts-jdk17` base image with nothing but the CLI tools added,
had to earn every one of those assumptions back by hand. Seven real bugs,
in the order they were hit, from `jenkins/README.md`:

1. **`trivy` install script silently failed.** The upstream
   `contrib/install.sh` for `v0.57.1` exited 1 with no useful error — no
   `.deb` asset existed for that tag under the expected filename pattern.
   Fixed by installing a specific, current `.deb` release directly
   (`trivy_0.74.0_Linux-64bit.deb`).

2. **`docker.sock` permission denied.** The container-scan stage's `docker
   build` failed even with the socket bind-mounted, because the `jenkins`
   user inside the agent image wasn't in a group matching the host socket's
   GID. Fixed with a `DOCKER_GID` build arg and `usermod -aG ${DOCKER_GID}
   jenkins`.

3. **Legacy Docker builder rejected the app's own Dockerfile.** `COPY app.py
   gunicorn.conf.py .` (multiple sources, directory destination) is valid
   BuildKit syntax. GitHub Actions' `docker build` uses BuildKit by default,
   so this never surfaced there. Jenkins' plain `docker-ce-cli` used the
   legacy builder. First attempt (`DOCKER_BUILDKIT=1` alone) still failed —
   "buildx component is missing" — because the CLI plugin wasn't installed.
   Actual fix: add `docker-buildx-plugin` to the image's apt install list.

4. **`pytest` exit code 5 ("no tests ran") under `set -eu`.** An early
   Jenkinsfile draft ran `pytest` unconditionally once `requirements.txt`
   was found; `ci.yml` checks for an actual `tests/` dir or `test_*.py`
   files first. `set -eu` turned pytest's benign "nothing collected" exit
   into a hard pipeline failure. Fixed by copying `ci.yml`'s existence check
   verbatim.

5. **Full-repo `gitleaks detect` diverged from GitHub's `gitleaks-action`
   result.** A naive `--source . --no-git` scan found 5 "leaks" — all
   entropy false positives (`generic-api-key` matching hex hashes) inside
   vendored KiCad binary caches under an unrelated part of the repo, not
   flagged by GitHub's pinned Action version on the same commit. Resolved
   by scoping the Jenkins scan to `app`, `infra`, `k8s` — the same
   footprint every other stage in the pipeline actually touches.

6. **CSRF crumb + session cookie required for every REST call**, even with
   `useSecurity: false` (Jenkins ships `useCrumbs: true` regardless). Every
   `curl` needed a crumb fetched *and replayed with the same cookie jar*
   (`-b cookies.txt -c cookies.txt`) — a crumb fetched without a persisted
   session gets rejected even though the crumb string itself is correct.

7. **Jenkins CLI refused to connect** (`Jenkins URL is not configured`)
   because the controller's root URL wasn't set. Rather than configure that
   just to use the CLI, plugin installs and job creation went through the
   HTTP `/scriptText` Groovy console and REST endpoints instead — works
   identically, no root URL needed.

None of these are exotic. They're the ordinary tax of self-hosting: BuildKit
availability, socket permissions, install-script fragility, exit-code
semantics, scan-scope drift between tool versions, and auth plumbing that a
managed platform (GitHub, GitLab) quietly handles for you. That tax is real
and it's the honest argument for *why* teams pay for managed CI even when
Jenkins is free to install — the labor didn't disappear, it moved from
"configuring a marketplace Action" to "debugging a Docker socket GID."

---

## 4. The Jenkins build that failed for the right reason

Build #7 of the `devsecops-pipeline` job ran to completion in 53.8 seconds
and archived a real console log (`jenkins/build-7-console.txt`). Stage by
stage:

| Stage | Result |
|---|---|
| Checkout | pass |
| Lint (ruff) | pass — `All checks passed!` |
| Test (pytest) | pass (skipped — no test suite exists yet under `app/status-service`, matching `ci.yml`) |
| Secrets scan (gitleaks) | pass — `no leaks found` across `app`, `infra`, `k8s` |
| SAST (bandit) | pass — `No issues identified.` |
| SBOM (syft) | pass — CycloneDX SBOM generated |
| Dependency scan (pip-audit) | pass — `No known vulnerabilities found` |
| Container scan (trivy image) | pass — HIGH/CRITICAL clean |
| **IaC scan (trivy config)** | **fail — 1 real CRITICAL finding** |
| K8s manifest scan (kube-linter) | not reached (upstream failure) |

**Overall result: FAILURE, honestly, on a real finding — not a fudged
green.** `trivy config` (Aqua's maintained successor to `tfsec`, which was
archived) flagged `infra/terraform/modules/azure-platform/main.tf:23-51`:

```
AZU-0012 (CRITICAL): No network rules defined and default action allows access.
The default_action for network rules should come into effect when no
other rules are matched. The default action should be set to Deny.
```

This is a genuine gap: the `azurerm_storage_account.platform` resource has
no `network_rules` block, so the implicit default is `Allow` — public
network access to the storage account by default. It's real, it's
unaddressed, and it was left that way on purpose, because fixing it
silently would have destroyed the teaching value of the run: a pipeline
that caught something.

**Why GitHub Actions' `iac-scan` job didn't catch it.** `security.yml`
runs `tfsec` against the same `infra/terraform` directory, on the same
commit. `tfsec` simply doesn't have a rule for this — it uses a
Terraform-only, narrower ruleset, and by the time this exercise ran, `tfsec`
had already been archived by its own maintainer (Aquasec) in favor of
`trivy config`, which draws on Aqua's actively-maintained, broader Rego
policy set covering providers and rules `tfsec` never got around to. Same
target directory, same commit, two different tools, two different results
— and the narrower tool is the one wired into the "official" GitHub
pipeline today.

**The lesson, stated plainly: tool coverage is not uniform, and a passing
gate only tells you what that specific tool checks for.** A pipeline that
runs one IaC scanner and calls the infrastructure "scanned" has actually
scanned it against one Rego policy set's opinion of good practice, not
against all known misconfiguration classes. Defense in depth across
dialects and tools isn't redundancy theater — it's how this exact CRITICAL
finding got caught at all. If this repo only had `security.yml`'s `tfsec`
job, `AZU-0012` would still be sitting there, invisible, behind a green
checkmark.

The practical takeaway for a working DevSecOps engineer: when you inherit a
pipeline with exactly one scanner per category, ask what that scanner
*doesn't* cover before you trust its silence. "Passing" and "safe" are not
the same claim.

---

## 5. Docker build fundamentals

Everything in Zone 3's container-scan and Zone 4's container-gate stages
operates on an image, so the Dockerfile that produces it deserves real
attention. This repo's `app/status-service/Dockerfile` is a working,
production-shaped example — multi-stage, non-root, minimal attack surface.

```dockerfile
# syntax=docker/dockerfile:1

########################
# Stage 1: build deps  #
########################
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

########################
# Stage 2: runtime     #
########################
FROM python:3.12-slim AS runtime

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /install /usr/local

RUN python3 -m pip uninstall --yes pip setuptools wheel 2>/dev/null; \
    rm -rf /usr/local/lib/python3.12/site-packages/pip* \
           /usr/local/lib/python3.12/site-packages/setuptools* \
           /usr/local/lib/python3.12/site-packages/wheel* \
           /usr/local/bin/pip*

WORKDIR /app
COPY app.py gunicorn.conf.py .
COPY STATUS.md /data/STATUS.md

ENV STATUS_MD_PATH=/data/STATUS.md \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)" || exit 1

CMD ["sh", "-c", "mkdir -p \"$PROMETHEUS_MULTIPROC_DIR\" && exec gunicorn --config gunicorn.conf.py --bind 0.0.0.0:8080 --workers 2 --threads 2 app:app"]
```

**Multi-stage builds.** `FROM python:3.12-slim AS builder` and a second
`FROM python:3.12-slim AS runtime` share the same base image but produce two
different filesystems. Only `COPY --from=builder /install /usr/local`
carries anything across the boundary. The build toolchain (pip's own
transient state, any compiler artifacts) never lands in the image that
ships — the runtime stage doesn't even keep pip, setuptools, or wheel
around afterward. This is the direct answer to "why is my image so big": if
you `RUN pip install` in a single-stage Dockerfile, every layer of build
tooling stays in the final image whether you use it at runtime or not.
Multi-stage builds let you pay that cost once, in a stage nobody ships.

**ADD vs COPY.** `COPY` does exactly one thing: copies files/directories
from the build context into the image, no side effects. `ADD` does that
*plus* auto-extracts local tar archives and can fetch remote URLs directly
into the image — behavior that's convenient exactly once and a supply-chain
foot-gun every other time (a URL fetched at build time isn't pinned by
hash, isn't reviewed, and isn't visible in a `git diff`). The rule that
holds in practice: default to `COPY`; reach for `ADD` only for the narrow
local-tar-extraction case, never for a remote URL. This Dockerfile uses
`COPY` exclusively — correctly, since it has no archives to unpack.

**ENTRYPOINT vs CMD.** `CMD` sets the default command and is fully
overridable at `docker run` time (`docker run image some-other-command`
replaces it entirely). `ENTRYPOINT` sets a command that *always* runs;
anything passed at `docker run` time is appended as arguments to it rather
than replacing it. This Dockerfile uses `CMD` alone, as a shell-form string
(`sh -c "mkdir -p ... && exec gunicorn ..."`), which is the right call here:
the container's one job is to run gunicorn, and the `mkdir -p` step before
`exec` is necessary because the Prometheus multiprocess directory has to
exist before gunicorn's workers start writing to it, while `exec` (not a
bare `gunicorn ...` command) ensures gunicorn replaces the shell as PID 1
rather than running as a child of it — the difference between signals
(`SIGTERM` on `docker stop`) reaching gunicorn directly versus getting
swallowed by an orphaned shell.

**Layer caching.** Docker caches each instruction's resulting layer and
reuses it on a rebuild if the instruction and its inputs haven't changed.
This Dockerfile's `COPY requirements.txt .` happens *before* `COPY app.py
gunicorn.conf.py .` specifically so that changing application code doesn't
invalidate the (slow) `pip install` layer — only a `requirements.txt`
change does. Get the ordering backwards (`COPY . .` early, dependency
install late) and every code change forces a full dependency reinstall on
every build. This is the single highest-leverage Dockerfile ordering habit
to teach: **things that change rarely go first, things that change often go
last.**

**Build args vs env vars.** A `ARG` (build arg) is available only during
the `docker build` — it's not present in the running container unless
explicitly copied into an `ENV`. This repo's `jenkins/docker-compose.yml`
uses exactly this pattern for `DOCKER_GID` (bug #2 in §3): it's a value the
*build* needs (to add the `jenkins` user to the right group), not a value
the *running application* needs, so it stays a build arg. `ENV`, by
contrast (as used here for `STATUS_MD_PATH`, `PYTHONUNBUFFERED`,
`PROMETHEUS_MULTIPROC_DIR`), persists into the running container and is
visible to the process and anyone who `docker inspect`s the image — never
put a secret in `ENV` for that reason; it's baked into the image layer
history and visible to anyone with pull access.

---

## 6. Nexus — artifact repository management

Like Azure DevOps, Nexus is not deployed anywhere in `poetic-musings`. This
repo has no `nexus/` directory, no `docker-compose.yml` standing one up,
and no pipeline stage publishing to one — the SBOM/dependency-audit
artifacts this repo's pipelines produce (`sbom-status-service.cdx.json`,
`pip-audit-results.json`) are archived as CI run artifacts (`archiveArtifacts`
in the Jenkinsfile, `upload-artifact` in `security.yml`), which is a
fundamentally different thing from publishing a *reusable, versioned
package* to a repository other builds pull from. What follows is course
knowledge for the job requirement, stated as such.

**What artifacts are, and why they need a dedicated repository.** An
artifact is any built, versioned, reusable binary output — a Maven `.jar`,
an npm package, a Python wheel, a Docker image, a generic tarball. The
naive approach — build it fresh in every pipeline that needs it, or pass it
between CI jobs as a transient run artifact the way this repo does with its
SBOM/audit output — breaks down as soon as more than one consumer needs the
*same* artifact at a *pinned* version: a downstream service that depends on
`internal-lib==2.3.1` needs to fetch exactly that version, reproducibly,
indefinitely, not "whatever the CI cache still happens to have." A
dedicated artifact repository gives you three things transient CI storage
doesn't: durable retention independent of any one pipeline run, a stable
resolvable URL/coordinate scheme consumers can pin against, and access
control separate from your CI system's own permissions.

**Nexus's repository types: hosted, proxy, group.** This three-way split is
the core concept to actually understand, not just recite:

- **Hosted** — a repository *you* own and push artifacts into directly;
  this is where your own team's Maven/npm/Docker builds get published.
  Typically split into a `releases` hosted repo (immutable once published —
  you cannot silently overwrite a version) and a `snapshots` hosted repo
  (mutable, for in-development builds), mirroring Maven's own
  release/snapshot convention.
- **Proxy** — a cached mirror of an external repository (Maven Central,
  npmjs, Docker Hub, PyPI). The first request for a given package version
  pulls it from upstream and caches it locally; every subsequent request
  (from any consumer inside your network) is served from Nexus's cache, not
  the public internet. This is both a performance win (no repeated
  internet round-trips) and a resilience/security win — if the public
  registry has an outage, or a package gets pulled/yanked upstream, your
  build still has that exact bytes-identical version cached.
- **Group** — a single virtual repository URL that aggregates multiple
  hosted and proxy repositories behind one endpoint, resolved in a defined
  order. A team typically points its build tooling at exactly one group
  repository (e.g. `maven-public`) rather than configuring separate
  upstream URLs per tool, and Nexus internally figures out whether a given
  request should be served from the internal hosted releases repo, the
  internal snapshots repo, or the Maven Central proxy cache.

**Setting up Nexus locally via Docker.** The standard path is Sonatype's
official image:

```bash
docker run -d -p 8081:8081 --name nexus \
  -v nexus-data:/nexus-data \
  sonatype/nexus3
```

First boot takes a minute or two to initialize; the generated admin
password lands in `/nexus-data/admin.password` inside the container
(`docker exec nexus cat /nexus-data/admin.password`), and the setup wizard
forces a password change and a choice between "allow anonymous access" and
requiring auth for reads — the anonymous-access default is convenient for a
local lab, wrong for anything shared. Note the parallel to this repo's own
`jenkins/README.md`: it's the exact same "official base image, unsecured by
default for local exercise, don't leave it that way in production" pattern
already documented there for Jenkins itself.

**Understanding Nexus structure.** Once running, repositories are managed
under Administration → Repositories, each one configured as hosted/proxy/
group per the categories above, with a repository *format* (maven2, npm,
docker, pypi, raw, etc.) chosen at creation — a single Nexus instance
commonly hosts one group repo per ecosystem your org uses (a Maven group, an
npm group, a Docker group) rather than one Nexus deployment per language.

**Publishing Maven and npm artifacts from a CI/CD pipeline.** For Maven,
the target hosted repository is declared in `pom.xml`'s `<distributionManagement>`
block, with credentials supplied via CI secrets into `settings.xml` (never
committed in plaintext):

```xml
<distributionManagement>
  <repository>
    <id>nexus-releases</id>
    <url>https://nexus.example.internal/repository/maven-releases/</url>
  </repository>
</distributionManagement>
```

```bash
mvn deploy -DskipTests
```

For npm, a project or org-level `.npmrc` points the registry at the Nexus
npm hosted repo and an auth token, then `npm publish` behaves exactly as it
would against the public npm registry:

```
registry=https://nexus.example.internal/repository/npm-hosted/
//nexus.example.internal/repository/npm-hosted/:_authToken=${NEXUS_NPM_TOKEN}
```

```bash
npm publish
```

Either way, the pipeline shape is identical to what this repo already does
for its *scan* outputs — build, then push a versioned artifact to a fixed
location — except Nexus is that fixed location instead of a CI run's
transient artifact storage, and the version published there is expected to
be pullable months or years later, not just for the lifetime of one CI run.

**Nexus as a private Docker registry.** A Nexus `docker` -format hosted
repository serves exactly the same protocol a registry like Docker Hub,
ACR, or ECR does — `docker login`, `docker push`, `docker pull` all work
unmodified against it, just pointed at Nexus's registry endpoint (typically
a separate port, since Docker's registry protocol needs its own listener
distinct from Nexus's web UI port). This is the same role this repo's
Terraform `aws-platform` module already provisions with ECR, and the same
role the (unapplied) `azure-platform` module provisions with ACR — Nexus is
a third, self-hostable option for the identical job, worth knowing
specifically because a team not on AWS or Azure managed-registry offerings
will very plausibly run Nexus (or Harbor) for this instead.

**Cleanup and retention policies.** Left unmanaged, a Nexus instance grows
without bound — every snapshot build, every proxy-cached dependency version
ever requested, sitting on disk forever. Nexus's cleanup policies let you
define retention rules per repository (e.g. "delete snapshot components not
downloaded in 30 days," "keep only the last N versions of a given
component," "remove components older than X days") and schedule them as a
recurring task rather than leaving disk growth to become someone's 2am
incident. This is the direct package-repository analog of this book's Zone
8 scan-freshness discipline (`playbook/freshness.py` — catching monitoring
that's silently gone stale): a retention policy that's configured but never
actually scheduled to run is exactly as decorative as a gate that's written
but never wired into a required check.

---

## 7. Build tools and artifact flow

The pattern across all three dialects is the same feed chain: a language
build tool produces an installable/runnable artifact, that artifact gets
wrapped into a container image, and the container image is what the
security gates actually scan.

```
requirements.txt (pip)  ─┐
                          ├─► docker build ─► status-service:ci image ─┐
app.py / gunicorn.conf   ─┘                                            │
                                                                        ▼
                                                    trivy image (HIGH/CRITICAL gate)
                                                    syft (SBOM of image contents)
```

In this repo the build tool is `pip` against `app/status-service/
requirements.txt` (Zone 2's build-tools primer covers Maven/npm/pip in
general — this chapter only needs the one fact that matters here: whatever
manifest the build tool consumes is also exactly what `pip-audit` and
`syft` consume downstream, so a dependency pin gap at the manifest level is
a gap the SBOM and CVE scan inherit too). The Dockerfile's `COPY
requirements.txt .` followed by `pip install --prefix=/install` is the
literal build step; everything after that — `docker build`, `trivy image`,
`syft app/status-service -o cyclonedx-json` — operates on the *result* of
that build, not on source code directly. This is why `sbom-and-dependency-
scan` in `security.yml` runs `syft` against `app/status-service` (the
source tree with its manifest) while `container-scan` runs `trivy` against
the *built image* — two different artifacts in the same chain, each scanned
by the tool suited to that stage.

---

## 8. The testing discipline: gates that can fail

A gate you have never watched fail is a gate you are trusting on faith. The
"dirty-fixture regression" principle (Zone 4, `MASTER-PLAYBOOK.md`) is the
concrete practice that turns that faith into evidence: keep a fixture with
known-bad input committed to the repo, and periodically run the pipeline
against it to prove the gate still rejects it.

This repo does exactly that with `playbook/demo/`, reproduced verbatim from
`playbook/README.md`:

```
$ ./playbook/pipeline.sh ./playbook/demo
-- stage 1: secrets
playbook/demo/config.py:2: generic-secret: API_KEY = "not-a-real-secret-abcdef123456"
playbook/demo/config.py:3: aws-access-key: aws_key = "AKIAIOSFODNN7EXAMPLE"
-- stage 2: dependency pins
UNPINNED numpy >=1.26
UNPINNED flask ~=3.0,!=3.0.1
UNPINNED hypothesis (any)
2 pinned, 3 unpinned, 0 unparsed
-- stage 4: policy gate
$ echo $?
1
```

Two seeded secrets, three unpinned dependencies, exit code 1. That's not
incidental — it's the proof artifact. If you ran the same pipeline against
`playbook/demo/` and got exit 0, you'd know immediately that a gate broke,
*before* it silently stopped catching real findings in production code.
`gate.py`'s three exit paths (0 pass, 1 fail, 2 bad input) are each
independently verified against both the demo fixture and this repo's real
scan output — not just asserted, run and observed.

**pytest fundamentals**, as used across all three dialects here: every
pipeline's test stage follows the same three-part guard —

```bash
if [ -d app/status-service/tests ] || find app/status-service -name 'test_*.py' | grep -q .; then
  pip install pytest
  pytest app/status-service -q
else
  echo "No test suite found under app/status-service yet; skipping."
fi
```

This is a real, named honest gap in this repo, stated openly in `ci.yml`,
`.gitlab-ci.yml`, and the Jenkinsfile alike: **there is no test suite yet
under `app/status-service`.** All three pipelines are written correctly —
they'd run pytest and gate on its exit code the moment tests exist — but
right now the "Test" stage is a no-op on every dialect. That's worth calling
out precisely because it's easy for a pipeline diagram to look complete
while one of its boxes does nothing. Bug #4 from §3 (`pytest` exit code 5
under `set -eu`) is what happens when that guard is missing or wrong: an
empty test suite becomes a hard pipeline failure instead of a documented
skip.

**Property-based testing with Hypothesis**, noted in `MASTER-PLAYBOOK.md`
Zone 4 and listed as an (unpinned, in the demo fixture) dependency: the
discipline here is that Hypothesis *complements*, never *replaces*,
example-based tests. A hand-written pytest case asserts "this specific
input produces this specific output" — useful, readable, cheap to write,
but only as good as the examples you thought to write. A Hypothesis test
instead asserts a *property* ("for all valid inputs of this shape, this
invariant holds") and Hypothesis generates hundreds of inputs, including
edge cases a human wouldn't think to write by hand — empty strings, unicode,
integer boundaries, deeply nested structures — actively trying to falsify
the property. The trade-off: property tests are slower to write well (you
have to articulate an actual invariant, not just an example) and slower to
run, and a failing property test gives you a generated counterexample you
still have to interpret, not a clean expected-vs-actual diff. Use
example-based tests for the specific documented behaviors and regression
cases you already know matter; add property tests for the parsers,
validators, and pure functions where "does this hold for all inputs" is
the actual question — `playbook/haskell.py`'s parser combinators (used by
`deps.py`'s pin-audit logic) are exactly the shape of code a property test
suite would earn its keep on.

---

## 9. Day-one checklist for these zones

When you inherit a repo's CI/CD setup — new job, new team, or just an
unfamiliar codebase — work this list before trusting anything the pipeline
badge tells you:

1. **Find and read every pipeline file in the repo.** Don't assume there's
   one. This repo alone has four: `.github/workflows/ci.yml`,
   `.github/workflows/security.yml`, `.gitlab-ci.yml`, `jenkins/Jenkinsfile`
   — plus a local runner, `playbook/pipeline.sh`. `find . -iname
   "*.yml" -path "*workflow*" -o -iname "Jenkinsfile" -o -iname
   ".gitlab-ci.yml"` is a reasonable first pass.
2. **Identify what's actually gating merges vs advisory-only.** Read branch
   protection rules (GitHub) or merge request approval rules (GitLab)
   directly — a job existing in a YAML file does not mean it's required to
   pass. A scan that runs and reports but isn't in the required-checks list
   is advisory, not a gate, no matter how alarming its output looks.
3. **For each gate, find (or write) an intentionally-broken fixture that
   proves it can fail.** If none exists, that gate is unverified. This
   repo's `playbook/demo/` is the reference pattern — commit bad input,
   keep it in the repo, re-run against it periodically.
4. **Check exit-code handling in every shell step, not just the tool
   invocation.** A tool exiting non-zero doesn't fail a pipeline if
   something downstream swallows it (`|| true`, a missing `set -e`, a
   `continue-on-error: true` left in from debugging). `ci.yml`'s `ruff
   check app --output-format=github || true` followed immediately by a
   second, unguarded `ruff check app` is a deliberate example of this
   pattern used *correctly* — the first run reports annotations, the second
   one actually gates.
5. **Diff the tool versions/rulesets across dialects if the same category
   of scan runs in more than one place.** §4's `tfsec` vs `trivy config`
   gap is exactly this kind of drift, and it's invisible until you go
   looking.
6. **Check whether security-tool versions are pinned anywhere**
   (Dockerfile, `plugins.txt`, Action SHA pins). This repo's own honest gap
   list flags unpinned Jenkins plugins and 21 tag-pinned (not SHA-pinned)
   GitHub Actions `uses:` lines — read `playbook/README.md`'s
   `actions_pin.py` output for the concrete count before assuming Actions
   pinning is someone else's problem.
7. **Run the pipeline locally if a local runner exists** (`playbook/
   pipeline.sh`), so you can iterate without burning CI minutes or waiting
   on a shared Jenkins controller.

---

## 10. Troubleshooting quick-reference

| Symptom | Likely cause | First things to check |
|---|---|---|
| Pipeline hangs / times out | A step is waiting on interactive input, a network call has no timeout, or a Docker-in-Docker/socket setup is deadlocked | Check for missing `-y` / non-interactive flags on installers; add explicit `timeout-minutes:` (Actions) or `timeout:` (GitLab/Jenkins) to the job; check `docker.sock` mount permissions if it's a container-build step |
| A security scanner Action itself fails (not its findings — the Action) | GitHub API rate limiting on unauthenticated calls, a deprecated/removed Action version, or a marketplace Action's own upstream outage | Confirm `GITHUB_TOKEN` is passed where the Action expects it (rate-limit relief); pin to a current major version, not a version tag that's been sunset (this repo's `tfsec-action@v1.0.3` is itself a legacy tool — see §4, its maintainer archived it in favor of `trivy config`); check the Action's own repo for an open "broken" issue before assuming your config is wrong |
| Docker build cache poisoning | A cached layer holds a stale dependency or secret that should have been invalidated, usually from bad layer ordering or a shared CI cache reused across unrelated branches | Rebuild with `--no-cache` to confirm the cache is the cause; fix layer ordering so invalidation-prone instructions (source `COPY`) come after stable ones (dependency manifests) — see §5; scope CI caches per-branch/per-lockfile-hash, not globally |
| "Works in one CI dialect, fails in another" | Different base environment assumptions — BuildKit vs legacy builder (§3 bug #3), different tool versions bundled by default, different default shell/`set -e` behavior, different scan-scope defaults (§3 bug #5) | Diff the actual tool version and invocation between dialects, not just the YAML shape; check whether one dialect uses a managed Action/template that a self-hosted equivalent has to reimplement by hand (§2.3) |
| Flaky tests | Shared mutable state between tests, unseeded randomness, real network/filesystem/timing dependencies, or test order dependence | Run the suite with `pytest -p no:randomly` / a fixed seed to see if order changes the result; run the single suspect test in isolation many times (`pytest --count` or a shell loop) before blaming CI infrastructure; for property-based (Hypothesis) tests specifically, capture and pin the failing seed (`@seed(...)`) to make the failure reproducible instead of intermittent |

---

Zone 3/4 recipes — the actual shell snippets, guard patterns, and gate
scripts referenced throughout this chapter — are collected for direct reuse
in the book's toolkit appendix.


---


# Chapter 5 — Zone 5: SECURE

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone is the whole point of "DevSecOps"

Take the word apart: Dev-Sec-Ops. Security sits in the middle on purpose. Not
bolted onto the end after Dev builds it and Ops ships it — folded into the
loop, running on every commit, before a human ever has to remember to ask for
it. That is the entire pitch of the discipline, and it is also the part most
easiliy faked on a resume, because "security is embedded in our pipeline" is
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


---


# Chapter 6 — Zone 6: PROVISION

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone matters

There is a specific failure mode every infrastructure team eventually hits, and it
has a name even if nobody writes it on the whiteboard: **console drift**. Someone
needs a security group opened for a demo. They click into the AWS console, add the
rule, ship the demo, and forget. Three months later a security review finds a
0.0.0.0/0 ingress rule on port 22 that nobody can explain, attached to nobody's
pull request, described in nobody's runbook. The engineer who made it has since
left. This isn't a hypothetical — it is the default outcome of letting
infrastructure be something people *do* rather than something people *write down*.

Clicking through a cloud console is fast, which is exactly the problem. It produces
infrastructure with no diff, no reviewer, no audit trail beyond a CloudTrail event
buried in a log bucket nobody reads until after the incident. It cannot be
reproduced deterministically — ask two engineers to "set up the VPC the same way"
by hand and you will get two different VPCs, with subtly different CIDR blocks, a
forgotten route table association, an inconsistent tag. And it cannot be diffed
against intent: there is no way to ask "does what's actually running match what we
decided should be running" without manually re-clicking through every screen and
comparing by eye.

**Reproducibility is the actual point of Infrastructure as Code.** Not "it's
faster" (it often isn't, for a one-off change), not "it's trendy." The point is
that infrastructure becomes a text artifact: version-controlled, reviewable in a
pull request, diffable against the last known-good state, and re-creatable from
scratch by running the same command twice and getting the same result. That
property — same input, same output, every time — is what makes an environment
*trustworthy* in a way a console click-through never can be, and it's what makes a
security review of "what does our infrastructure actually look like" a `git diff`
instead of an archaeology project.

Zone 6 is where this happens in two distinct layers, and the distinction matters
enough that it's a standard interview question (see §6): **Terraform provisions —
it answers "does the infrastructure exist, in the shape I declared."** **Ansible
configures — it answers "is the right software deployed and running correctly on
that infrastructure, every single time I check."** Confusing the two, or trying to
make one tool do both jobs badly, is one of the most common architectural mistakes
in this zone.

## 2. Terraform deep dive

### Providers, resources, and state — precisely

Three concepts do all the work in Terraform, and getting the mental model right up
front prevents a lot of confusion later.

A **provider** is a plugin that translates Terraform's declarative HCL into API
calls against a specific platform — `aws`, `azurerm`, `google`, `kubernetes`,
`docker`. It's declared with a required version constraint (pinning matters: an
unpinned provider can silently change behavior between runs) and configured with
credentials and defaults like region:

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

A **resource** is one declared unit of infrastructure that provider knows how to
create, read, update, or destroy — a VPC, an S3 bucket, an IAM role. Each resource
block has a type and a local name (`aws_s3_bucket.artifacts`), and Terraform builds
a dependency graph from the references between them, not from the order they're
written in the file.

**State** is the part people underestimate. Terraform doesn't re-derive the world
by querying the provider fresh on every run (a few resources support partial
drift-detection refresh, but that's not the primary mechanism) — it keeps a JSON
file, `terraform.tfstate`, that maps every resource block to the real-world object
it created (an actual VPC ID, an actual ARN) and records the last-known attributes
of that object. `plan` computes a diff between three things: the HCL you wrote, the
state file's record of what was last applied, and (for supported resources) a
refreshed read of the real object. Losing the state file, or having two people run
`apply` against different copies of it, is how you get orphaned resources,
duplicate resources, or Terraform confidently trying to recreate something that
already exists. This is precisely why local state is dangerous for teams — more on
this below.

### File layout convention

There's no technical requirement Terraform enforces here, but the convention is
followed for a reason: it lets any engineer open an unfamiliar Terraform root and
know exactly where to look.

```
infra/terraform/
├── backend.tf         # where state lives (S3+DynamoDB, or azurerm equivalent)
├── providers.tf        # provider blocks + version pins
├── variables.tf          # every input variable, with type + description
├── outputs.tf              # every value exposed to callers/CI (ARNs, URLs, IDs)
├── main.tf                  # resource/module wiring — the actual shape
├── modules/
│   └── aws-platform/          # a reusable, self-contained unit
└── environments/
    ├── dev/terraform.tfvars     # dev-sized values fed into the SAME modules
    └── prod/terraform.tfvars    # prod-sized values, same code path
```

`variables.tf` and `outputs.tf` are the *interface* of a root module or child
module — what goes in, what comes out — kept separate from `main.tf` so the
interface is reviewable at a glance without reading resource logic.

### The plan → apply → destroy lifecycle

```bash
terraform init      # downloads providers, configures the backend
terraform validate  # syntax + internal consistency check, no credentials needed
terraform plan  -var-file=environments/dev/terraform.tfvars   # computes the diff, changes nothing
terraform apply -var-file=environments/dev/terraform.tfvars   # executes the diff
terraform destroy -var-file=environments/dev/terraform.tfvars # tears it all down
```

`plan` is the safety net that makes this whole model work: it is a dry run that
shows exactly what will be added, changed in place, or destroyed-and-recreated,
*before* anything happens. A disciplined team treats an unreviewed `apply` — one
nobody ran `plan` on first, or whose plan output nobody read — as a near-miss
worth a postmortem, not a normal Tuesday.

### Remote state, and why local state is dangerous for teams

If `terraform.tfstate` lives on one engineer's laptop, you get exactly the failure
mode IaC is supposed to prevent: nobody else's `plan` matches reality, two people
running `apply` in the same afternoon can clobber each other's changes with no
warning, and losing the laptop means losing the only record of what's actually
been created. The fix is a remote backend with locking:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "poetic-musings-tfstate"
    key            = "platform/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "poetic-musings-tf-locks"
    encrypt        = true
  }
}
```

The S3 bucket holds the actual state file (versioned, so a bad apply's prior state
is recoverable; SSE-encrypted, since state files routinely contain sensitive
values like database passwords in plaintext). The DynamoDB table exists for one
purpose: **locking**. When `terraform apply` starts, it writes a lock item to that
table; a second `apply` started concurrently by someone else will refuse to run
until the lock clears. Without this, two simultaneous applies race against the
same state file and corrupt it. This repo's `backend.tf` documents the exact
bootstrap commands for creating that bucket and table, and — deliberately — leaves
the backend block itself commented out, so `terraform init`/`validate` still work
in CI without requiring pre-existing AWS infrastructure or live credentials on
every PR.

The `azurerm` alternative follows the same shape, authenticating with Azure AD
instead of a shared storage account key (`use_azuread_auth = true`) — worth
knowing because a shared key is a long-lived secret sitting outside any identity
system, exactly the kind of credential a security review should flag on sight.

### Data sources

A **data source** reads information about a resource Terraform doesn't manage —
existing infrastructure created elsewhere, or a platform-computed value like the
current account ID or region:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# used later to build an ARN or scope a policy without hardcoding an account number
```

This is how you reference the current AWS account ID in an IAM policy without
typing a literal 12-digit number into source control — a small thing that prevents
a whole class of copy-paste errors when the same module runs against different
accounts.

### `terraform import`

Real environments almost never start from zero. `terraform import` lets you adopt
a resource that already exists — created by hand, by a previous tool, by a
different team — into Terraform's state, associating it with a resource block you
write to match its current real attributes:

```bash
terraform import aws_s3_bucket.artifacts poetic-musings-artifacts-prod
```

The gotcha: `import` only populates state. It does not generate the HCL for you
(newer Terraform versions can generate a starting config with `terraform plan
-generate-config-out=`, but it's not automatic in older workflows) — you still
have to write a resource block whose declared attributes match reality closely
enough that the next `plan` doesn't propose destroying and recreating the thing
you just imported. Getting that config wrong is one of the more common ways a
first `import` goes sideways.

### Provisioners — and why HashiCorp says avoid them

`local-exec` runs a command on the machine running Terraform; `remote-exec` runs a
command on the newly created resource over SSH or WinRM:

```hcl
resource "aws_instance" "app" {
  # ...
  provisioner "remote-exec" {
    inline = ["sudo apt-get update", "sudo apt-get install -y nginx"]
  }
}
```

HashiCorp's own documentation recommends provisioners as a **last resort**, and
the reasoning holds up: they step outside Terraform's declarative model into
imperative shell execution that Terraform can't reason about, can't diff, and
can't safely retry — a failed provisioner can leave a resource half-configured
with no clean way to converge back to a known state on the next apply. This is
precisely the seam where Terraform's job should end and Ansible's job should
begin (§6): provision the instance with Terraform, then hand it to Ansible — or a
purpose-built image via Packer — to actually configure the software on it.
Provisioners exist for the rare case (bootstrapping something that genuinely has
no other hook) but reaching for one by default is a design smell.

### Modules and reusability

A module is just a directory of `.tf` files with its own `variables.tf` and
`outputs.tf`, called from elsewhere with a `source` and a set of inputs:

```hcl
# main.tf (root)
module "aws_platform" {
  source       = "./modules/aws-platform"
  name_prefix  = "poetic-musings-${var.environment}"
  vpc_cidr     = var.vpc_cidr
  tags         = local.common_tags
}
```

The value isn't abstraction for its own sake — it's that the VPC/ECR/KMS/IAM shape
gets defined once, reviewed once, security-scanned once, and then every
environment that needs "one of these" calls the same module with different
inputs instead of copy-pasting HCL and letting the copies drift apart silently.

### Multi-environment strategy: workspaces vs. separate tfvars vs. separate state

Three real approaches exist, and picking the wrong one for your team size is a
common mistake:

- **Terraform workspaces** (`terraform workspace new prod`) give you multiple
  state files under one root module, switched with a CLI command. Lightweight,
  but the isolation is soft: it's easy to run a command against the wrong
  workspace by mistake because the workspace is invisible in the code itself, and
  all workspaces still share the same backend configuration and the same blast
  radius if that backend is misconfigured.
- **Separate `.tfvars` per environment, same module tree, same state backend
  config but different state *keys*** — this repo's approach
  (`environments/dev/terraform.tfvars`, `environments/prod/terraform.tfvars`)
  feeding the same root module. The environment is explicit in every command
  (`-var-file=environments/prod/terraform.tfvars`), which makes it much harder to
  apply to the wrong environment by accident, at the cost of a slightly longer
  command line every time.
- **Fully separate state, fully separate root modules per environment** — the
  heaviest option, used when environments genuinely diverge in shape (not just
  size), or when different teams own different environments and shouldn't share
  even the possibility of touching each other's state. Most reuse benefit then has
  to come from shared child modules rather than a shared root.

For small-to-mid teams, "separate tfvars, same modules, state key includes the
environment name" is the sweet spot: real isolation, real explicitness in the
command line, without the fragmentation of maintaining N independent root
modules.

### EKS cluster creation with Terraform

Standing up an EKS cluster with Terraform is a real, common task and worth naming
the shape even where this repo hasn't done it: an `aws_eks_cluster` resource
referencing a control-plane IAM role and the VPC subnets, one or more
`aws_eks_node_group` resources (or a Karpenter/Fargate profile) for compute, an
OIDC identity provider resource so pods can assume IAM roles via IRSA, and — this
is the part people get bitten by — the `aws-auth` ConfigMap (or, on current EKS,
native `aws_eks_access_entry` resources) mapping IAM principals to Kubernetes
RBAC groups, since creating the cluster is not the same as being able to
authenticate against it with `kubectl`. This is squarely Zone 6/Zone 7 overlap:
Terraform provisions the cluster and node infrastructure; what actually runs
inside it is Zone 7's territory.

## 3. Applied to poetic-musings: a real apply, a real bug, a real teardown

The AWS side of `infra/terraform/` in this repo was not just written and
`validate`d — it was applied for real, against a personal free-tier AWS account
(`us-east-2`), with 33 planned resources actually created: a VPC across two
availability zones, an ECR repository with image scanning and immutable tags, a
KMS-encrypted S3 artifacts bucket with a separate access-log bucket, a
customer-managed KMS key with rotation enabled, and a least-privilege IAM role for
CI pushes scoped to the exact ECR repo and S3 bucket ARNs the module created — not
a wildcard resource.

**The bug, in detail.** After `terraform apply` created the VPC flow-log
CloudWatch log group, it failed with:

```
Error: creating CloudWatch Logs Log Group: AccessDeniedException: The specified
KMS key does not exist or is not allowed to be used
    on modules/aws-platform/logs.tf line 12, in resource
    "aws_cloudwatch_log_group" "vpc_flow_logs":
```

The KMS key existed — `terraform validate` and `tfsec` both saw nothing wrong with
the HCL, and they were right, because nothing about the syntax or schema was
wrong. The problem was semantic and only visible at the API level: the key's
policy granted full access to the AWS account root principal (the default
Terraform generates if you don't write a custom policy), but CloudWatch Logs
encrypts log data as a *different* IAM principal — the `logs.<region>.amazonaws.com`
service principal — which the account-root statement does not cover. A customer-
managed KMS key needs an **explicit** statement authorizing that service
principal before CloudWatch Logs can use it to encrypt a log group. This is a
common enough trap that it's worth internalizing as a general rule: "account root
has full access" in a KMS key policy is not the same as "every AWS service that
might want to use this key can use it" — each service principal that needs the
key has to be named.

**The fix**, in `modules/aws-platform/kms.tf`, was a proper
`aws_iam_policy_document` with two statements instead of one — account-root
access, plus a scoped grant for the logs service principal, constrained with an
`ArnLike` condition on `kms:EncryptionContext:aws:logs:arn` so the grant only
applies to log groups in this account:

```hcl
data "aws_iam_policy_document" "platform_key" {
  statement {
    sid     = "AccountRootFullAccess"
    effect  = "Allow"
    principals { type = "AWS"; identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"] }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*",
                 "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}
```

A second `apply` with the corrected key policy succeeded. Every resource was then
independently verified against the live AWS API — not just trusted because
`apply` exited 0 — with `aws ecr describe-repositories`, `aws ec2 describe-vpcs`,
`aws s3api list-buckets`, and `aws kms describe-key`, and finally torn down
cleanly with `terraform destroy`.

**The lesson generalizes**: this is exactly the class of bug that static analysis
cannot catch, because the HCL was syntactically and schematically valid the whole
time — `tfsec` had nothing to flag, `terraform validate` had nothing to flag. It
only failed at the API layer, when a real service tried to use a real key under
real IAM semantics. That is the actual argument for applying infrastructure code
for real at least once in a disposable account, rather than trusting
`plan`/`validate`/`tfsec` as sufficient proof that the code works — they prove the
code is *well-formed*, not that it's *correct*.

**The Azure gap, stated honestly.** The `azure-platform` module is written and
passes `terraform validate` cleanly, but it has never been applied, because there
is no Azure subscription available to apply it against. Worth noting precisely
why this is a real limitation and not a cosmetic one: `terraform init` cannot even
configure the `azurerm` provider without valid credentials, because the provider
authenticates during `terraform init`/`configure` regardless of whether any
Azure resources end up being created — setting `-var enable_azure=false` does not
work around this, since the provider block itself still needs to initialize. A
validate-clean module is evidence the HCL is well-formed. It is not evidence it
works, for the same reason the KMS bug above demonstrates: correctness at the API
level can only be proven by actually calling the API. Anyone inheriting this code
should treat the Azure module as untested, not as "probably fine."

## 4. Ansible deep dive

### The agentless model, and why it matters for security posture

Ansible's defining architectural choice is that it requires no persistent agent
running on managed hosts. It connects over SSH (or WinRM for Windows), pushes a
small Python payload, executes it, and disconnects — nothing stays resident. This
is a real security-posture difference from agent-based tools: there's no
always-on daemon on every managed host that is itself an attack surface, no agent
credential to rotate or compromise, no agent version to keep patched across a
fleet. The tradeoff is that Ansible needs SSH reachability and Python on the
target, and its "push" model (a control node reaching out) doesn't scale the same
way a "pull" model does for very large, frequently-changing fleets — but for the
security posture question specifically, agentless-over-SSH is a genuinely smaller
footprint than a permanently-installed agent, and it's worth being able to state
that plainly in an interview rather than just naming the feature.

### Modules vs. ad-hoc commands

An ad-hoc command runs one module against inventory hosts directly, no playbook:

```bash
ansible all -i inventory.ini -m ping
ansible webservers -i inventory.ini -m shell -a "systemctl status nginx"
```

Useful for one-off checks. The actual unit of real work is the **module** — a
purpose-built, idempotent unit like `community.docker.docker_compose_v2`,
`ansible.builtin.copy`, `ansible.builtin.user` — versus reaching for `shell:` or
`command:` to wrap an imperative CLI call. The distinction matters for the same
reason it matters in Terraform's provisioner section: a real module knows how to
check current state and only act if it differs from desired state (the actual
mechanism behind idempotency); a raw `shell:` call is a black box that Ansible
can't reason about and that will happily re-run and "succeed" every single time
regardless of whether anything actually changed.

### Plays, playbooks, roles, collections

A **play** maps a set of hosts to a list of tasks. A **playbook** is a YAML file
of one or more plays:

```yaml
# playbook.yml
- hosts: observability
  become: true
  roles:
    - observability_stack
```

A **role** is the reusable unit — a directory structure (`tasks/`, `handlers/`,
`templates/`, `defaults/`, `vars/`) that packages a coherent piece of
configuration so it can be applied to any set of hosts without rewriting it. A
**collection** is a distributable bundle of roles, modules, and plugins,
installed like a package (`ansible-galaxy collection install
community.docker`) — the mechanism that gets you a real, maintained
`docker_compose_v2` module instead of everyone hand-rolling their own `shell:`
wrapper around `docker compose`.

### Inventory: static and dynamic

Static inventory is a plain file naming hosts and groups:

```ini
# inventory.ini
[observability]
localhost ansible_connection=local

[webservers]
web01.internal ansible_user=deploy
web02.internal ansible_user=deploy

[webservers:vars]
ansible_ssh_private_key_file=~/.ssh/deploy_key
```

Dynamic inventory replaces the static file with a script or plugin that queries a
live source of truth — the AWS EC2 API, an Azure resource group, a CMDB — at run
time, so newly launched instances are automatically in scope without anyone
hand-editing a file:

```yaml
# aws_ec2.yml — dynamic inventory plugin config
plugin: amazon.aws.aws_ec2
regions: [us-east-2]
filters:
  tag:Environment: prod
keyed_groups:
  - key: tags.Role
    prefix: role
```

```bash
ansible-inventory -i aws_ec2.yml --graph   # verify what the plugin resolves
ansible-playbook -i aws_ec2.yml site.yml
```

Static inventory is fine for a small, stable set of hosts. Dynamic inventory is
what you actually need once infrastructure is elastic — otherwise the inventory
file itself becomes another thing that silently drifts from reality, the exact
failure mode Zone 6 exists to eliminate.

### Ansible Vault

Secrets don't belong in playbooks or inventory files in plaintext — `ansible-vault`
encrypts a file (or a single string) with a password or a KMS-backed key, and
Ansible transparently decrypts it at run time:

```bash
ansible-vault create group_vars/prod/secrets.yml
ansible-vault edit group_vars/prod/secrets.yml
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
# or, non-interactively in CI:
ansible-playbook -i inventory.ini site.yml --vault-password-file .vault_pass
```

This repo's Ansible role does **not** use Vault, and that's stated plainly rather
than glossed over: the observability stack it deploys ships default
`admin/admin` Grafana credentials (documented in `observability/README.md`), so
nothing sensitive is actually being managed. That's an honest, low-stakes gap —
but it would be a real gap, not a stylistic one, the moment this playbook managed
anything with an actual credential in it, and the day-one checklist below tells
you to check for exactly that.

### Idempotency as Ansible's core promise — and how to actually verify it

Every Ansible module is supposed to be idempotent: running the same playbook
twice against the same target should produce the same end state, with the second
run reporting nothing changed. This is the property that lets you run a playbook
against a fleet on a schedule without fear, and it's also the property people
most often claim without proof. "It didn't error the second time" is not evidence
of idempotency — a module can succeed on every run while still doing real,
unnecessary work each time (restarting a service, rewriting a file with identical
content) if it isn't genuinely idempotent. The actual test is `changed=0` on a
warm rerun against unchanged desired state, which is exactly what §5 walks
through.

## 5. Applied to poetic-musings: real idempotency, proven not claimed

The `observability_stack` role in `ansible/` deploys the real Prometheus +
Grafana + status-service stack via `community.docker.docker_compose_v2`, then
verifies it end to end: it polls `status-service`'s `/healthz` until it returns
200, polls `/metrics` and asserts the real `http_requests_total` Prometheus
metric string is present in the response body (not a mocked check), and queries
Prometheus's own `/api/v1/targets` API to confirm Prometheus has actually scraped
`status-service` and marked it `health: up` — proving the metrics pipeline works
end to end, not just that a container process happens to be running.

The idempotency proof, run against genuinely different starting states and
captured to log files in the same directory:

```bash
docker compose down                             # stack fully torn down first
ansible-playbook -i inventory.ini playbook.yml -v < /dev/null
# → PLAY RECAP: ok=10  changed=1   (run-cold.txt — built/started from nothing)

ansible-playbook -i inventory.ini playbook.yml -v < /dev/null
# → PLAY RECAP: ok=10  changed=0   (run-idempotent.txt — same desired state, nothing to do)
```

That second number — `changed=0` on the warm rerun — is the actual test, and it's
worth being precise about why. `ok=10` on both runs only tells you nothing
errored; a non-idempotent playbook can produce `ok=10 changed=10` on every single
run forever and still "pass" by that measure alone, quietly rewriting files or
restarting containers it didn't need to touch every time it's invoked. `changed=0`
on the second run is what actually proves each task compared desired state
against real state and correctly concluded there was nothing to do — that's the
whole promise of Ansible, demonstrated rather than assumed.

**The real bug hit along the way**, worth including because it's a genuinely
common environment problem, not a code bug: `ansible-playbook` failed
immediately with `ERROR: Ansible requires blocking IO on stdin/stdout/stderr.
Non-blocking file handles detected`. The root cause was a non-blocking stdin pipe
in the shell that launched it — Ansible's forking model requires blocking I/O and
refuses to run otherwise. The fix was redirecting stdin from `/dev/null`
(`ansible-playbook ... playbook.yml -v < /dev/null`), which is a real, documented
Ansible constraint, not something papered over with a flag that suppresses the
check. Separately, the first `ansible-galaxy collection install
community.docker` hit a transient `504 Gateway Timeout` against Galaxy's API and
succeeded on retry — worth logging as an external-service flake, not a bug in
this repo's code, and a reminder that a fully air-gapped environment would need
that collection pre-vendored rather than fetched at run time.

**Honest gap on scope**: the target here is `localhost`
(`ansible_connection=local`), because this environment has no second machine to
manage over real SSH. The `inventory.ini` structure and role layout are written
exactly as they would be for N remote hosts, and the only change needed to point
this at a real fleet is swapping `ansible_connection=local` for SSH-reachable
hosts — but that swap has not actually been made or tested here. That's a real
limitation, named plainly rather than implied away by the fact that the mechanics
(modules, idempotency, handlers, `uri` polling) are proven for real against a
real Docker Engine.

## 6. Terraform + Ansible together

This split gets asked about directly in interviews, so it's worth being able to
answer it in one crisp sentence and then back it up: **Terraform answers "does
the infrastructure exist, in the shape I declared" — Ansible answers "is the
right software deployed and configured on it, correctly, every single time I
check."**

Concretely: Terraform creates the VPC, the EC2 instance or EKS node group, the S3
bucket, the IAM role — objects that either exist or don't, with attributes that
either match the declared config or don't. It has almost nothing to say about
what's running *inside* that EC2 instance once it boots — that's a different kind
of question, answered by a different kind of tool with a different execution
model (SSH-driven, idempotent module runs against a live OS) rather than
provider-API resource lifecycle management.

Chained in practice: Terraform provisions the instance and, via an output, hands
Ansible the IP address or a dynamic-inventory-discoverable tag; Ansible then
configures it — installs packages, renders config files from templates, starts
and enables services, and (as in this repo) verifies the result actually works
via real HTTP checks, not just "the playbook exited 0." Terraform is not built to
re-run daily against a fleet checking "is nginx still configured correctly" —
that's exactly Ansible's job, and it's the reason a mature pipeline uses both
rather than trying to stretch `local-exec`/`remote-exec` provisioners into doing
Ansible's job, or trying to make Ansible provision cloud resources it has modules
for but that Terraform's plan/state model handles far more safely.

## 7. Day-one checklist for this zone

1. Find every `.tf` file in the repo (`find . -name '*.tf'`) and read `backend.tf`
   first — before anything else, know where state lives and who can read/write it.
2. Identify the state backend concretely: which S3 bucket (or equivalent), is it
   versioned and encrypted, which DynamoDB table (or lock mechanism) backs it,
   and which IAM principals/roles can access either.
3. Run `terraform init` and `terraform plan` against the current backend and
   compare the plan's proposed changes to zero — any non-empty plan on code
   nobody touched is drift, and drift is the first thing to explain, not ignore.
4. Read every `variables.tf` for undocumented or dangerously-defaulted inputs
   (a `public_access = true` default is a review finding, not a footnote).
5. Confirm what `tfsec`/`checkov`/equivalent scanning actually runs in CI, on
   what trigger, and whether any findings are excluded — read the exclusion
   comments, don't just trust the exclusion exists for a good reason.
6. Inventory every Ansible playbook and role that exists
   (`find . -name '*.yml' -path '*playbook*'`, `ls roles/`), and for each one,
   find out when it was last run *for real* against a live target — a playbook
   nobody has run in six months is a playbook whose correctness is currently
   unverified, however clean it reads.
7. Check whether any playbook manages actual secrets, and if so, confirm
   `ansible-vault` (or an equivalent external secrets mechanism) is in use — a
   plaintext credential in `group_vars/` is a finding, immediately.
8. Confirm inventory is static or dynamic, and if dynamic, confirm the plugin
   config's filters actually scope to what you think they scope to
   (`ansible-inventory --graph` to check, before trusting it).

## 8. Troubleshooting quick-reference

| Symptom | Cause | Fix |
|---|---|---|
| `Error acquiring the state lock` that never clears | A previous `apply`/`plan` was killed (Ctrl-C, CI job cancelled, laptop closed) mid-run, leaving a stale DynamoDB lock item | Confirm nobody else is actually running Terraform right now, then `terraform force-unlock <LOCK_ID>` — never force-unlock without first verifying the lock is genuinely abandoned |
| `terraform plan` shows unexpected changes on code nobody touched | Real infrastructure drift — a console click-through, a manual `aws` CLI fix during an incident, or another tool (e.g. an autoscaler) mutating a resource Terraform also manages | Investigate before applying; decide whether to `terraform import`/update HCL to match reality, or apply to force reality back to declared state — don't blindly `apply` away someone's incident fix |
| A provider (e.g. `azurerm`) fails to initialize even for resources you don't need | The provider block authenticates during `terraform init`/`configure` regardless of whether `enable_azure`-style variables leave it with zero resources to create — `-var enable_azure=false` alone doesn't prevent the provider from trying to authenticate | Either supply valid (even minimal) credentials for every declared provider, or remove the provider block/module invocation entirely for environments that genuinely have no access to that cloud |
| `ansible-playbook` hangs or fails immediately with a stdin/blocking-IO error | Ansible requires blocking I/O on stdin/stdout/stderr; a non-blocking pipe (common in CI runners, harness shells, some terminal multiplexers) breaks its forking model | Redirect stdin explicitly: `ansible-playbook -i inventory.ini playbook.yml < /dev/null` |
| Ansible fact-gathering (`gathering: implicit`) times out against a host | Host is unreachable (network/security-group/firewall), SSH key mismatch, or Python isn't present on the target | `ansible <host> -m ping` in isolation first to isolate connectivity vs. fact-gathering; set `gather_facts: false` and gather explicitly if you don't need full facts, to fail faster and cheaper |

Zone 6 command recipes — the exact `plan`/`apply`/`import` invocations and the
Ansible idempotency-check pattern — are collected in the book's toolkit appendix
for quick reference during real work.


---


# Chapter 7 — Zone 7: Deploy & Orchestrate

## 1. Why this zone matters

Zone 6 (Infrastructure as Code) gets you a cluster: nodes exist, the control
plane answers `kubectl get nodes`, the VPC is wired, the load balancer has an
IP. None of that means an application is running, reachable, self-healing, or
safe to leave unattended. That's the entire subject of this zone: the gap
between "the platform exists" and "the workload survives contact with
reality" — a node dying at 3 a.m., a bad image rollout, a pod that leaks
memory until the kernel OOM-kills it, an attacker who compromises one
container and immediately tries to talk to every other pod in the namespace.

Deploy & Orchestrate is where you answer three questions honestly, per
workload:

1. **Does it come back if it dies?** (ReplicaSets, Deployments, restart
   policies, PodDisruptionBudgets)
2. **Can it reach, and be reached by, only what it should?** (Services,
   Ingress, NetworkPolicy, RBAC)
3. **Is the blast radius of a single compromised or misbehaving pod
   contained?** (Pod Security Standards, non-root, read-only filesystems,
   resource limits)

This repo's `k8s/` directory and `ad-lab/` are both worked answers to that
question, for two different kinds of workload — a stateless HTTP service on
Kubernetes, and identity infrastructure on Active Directory. They're treated
together in this chapter because the job posting this book maps to
(`JOB.html`) requires both, and because "deploy & orchestrate" is not a
Kubernetes-only idea — an enterprise that runs Kubernetes for its
applications is very likely also running Active Directory for its people and
endpoints, and a DevSecOps engineer who can reason about only one of those
two orchestration models is only half-useful in that environment.

---

## 2. Kubernetes architecture, precisely

A Kubernetes cluster has two kinds of machine: **control plane** nodes (the
brain) and **worker** nodes (where your containers actually run). Know this
split cold — it's the first whiteboard question in almost every Kubernetes
interview.

### Control plane components

- **`kube-apiserver`** — the only component that talks to `etcd`. Every
  `kubectl` command, every controller, every kubelet — all of them go
  through the API server. It validates and admits requests (this is where
  admission controllers like Pod Security Admission live), then persists
  the result to etcd. Stateless by design; you can run several replicas
  behind a load balancer for HA.
- **`etcd`** — a distributed, strongly-consistent key-value store. This is
  the *entire* state of the cluster: every object, every status field. If
  you lose etcd with no backup, you have lost the cluster's brain, not just
  its workloads. Back it up. `etcdctl snapshot save` is not optional in a
  real environment.
- **`kube-controller-manager`** — runs the control loops: the Deployment
  controller reconciling replica count, the Node controller marking nodes
  `NotReady` after a missed heartbeat, the ReplicaSet controller, the
  Job controller, and more. Each loop follows the same pattern: observe
  current state, compare to desired state (spec), act to close the gap.
  This reconciliation pattern is the single most important idea in
  Kubernetes and reappears verbatim in ArgoCD (§8).
- **`kube-scheduler`** — watches for Pods with no `nodeName` assigned yet,
  filters nodes by constraints (resource requests, taints/tolerations,
  affinity/anti-affinity, topology), scores the survivors, and binds the
  Pod to the winning node. It does not run anything itself — it only
  writes the binding decision back through the API server.
- **`cloud-controller-manager`** (when running on a cloud) — the piece that
  talks to the cloud provider's API: provisioning LoadBalancer-type
  Services as real cloud load balancers, attaching cloud disks for
  PersistentVolumes, tagging nodes. `kind` and bare-metal clusters don't
  have one, which is exactly why `type: LoadBalancer` Services never get
  an external IP on `kind` — there's no cloud controller to ask for one.

### Node (worker) components

- **`kubelet`** — the agent on every node. Watches the API server for Pods
  scheduled to its node, and drives the container runtime to actually start
  them. Runs liveness/readiness/startup probes and reports Pod status back
  up. If the kubelet on a node stops heartbeating, the Node controller
  eventually marks the node `NotReady` and, after a grace period, evicts
  its Pods so they get rescheduled elsewhere.
- **`kube-proxy`** — implements the Service abstraction on each node,
  programming iptables or IPVS rules so traffic to a Service's ClusterIP
  gets load-balanced across the matching Pod IPs. This is why Services
  work even though Pod IPs are ephemeral — kube-proxy keeps the mapping
  current as Pods come and go.
- **Container runtime** — `containerd` (or CRI-O), speaking the Container
  Runtime Interface (CRI) to the kubelet. Docker itself is not the runtime
  anymore in a modern cluster; `dockershim` was removed in 1.24. `kubeadm`
  installs with `containerd` are the standard local/on-prem setup path
  (TOC Module 10 item 4).

The mental model to keep: **desired state lives in etcd via the API
server; every other component is a loop that watches the API server and
tries to make reality match it.** A Deployment doesn't "deploy" anything —
it's a record the controller manager reconciles against, repeatedly,
forever.

---

## 3. Core workload objects

### Pods

The smallest deployable unit — one or more containers that share a network
namespace (same IP, `localhost` between them) and can share volumes. You
almost never create bare Pods in production; you create a controller that
creates Pods for you, because a bare Pod that dies stays dead.

### ReplicaSets and Deployments

A **ReplicaSet** guarantees N replicas of a Pod template are running,
recreating any that die. A **Deployment** manages ReplicaSets, and is what
you actually write — it adds versioned, controlled rollout semantics on top
(§7). `kubectl apply` on a Deployment with a new image creates a new
ReplicaSet and scales it up while scaling the old one down, according to the
`strategy` (default `RollingUpdate`).

This repo's `k8s/base/deployment.yaml` is a real Deployment: `replicas: 2`
at base, patched to `3` in the prod overlay
(`k8s/overlays/prod/kustomization.yaml`, a strategic merge patch on
`/spec/replicas`), demonstrating the Kustomize base/overlay pattern —
one canonical manifest, environment-specific patches, no copy-pasted YAML
drifting between dev and prod.

### StatefulSets — and when you actually need one

A Deployment's Pods are interchangeable: same template, arbitrary names,
any one can be killed and replaced by an identical twin. That's wrong for
anything that owns state tied to its identity — a database node that must
keep the *same* volume and the *same* network name across restarts because
its peers address it by that name (e.g. a MySQL replica, a Kafka broker, an
etcd member).

A **StatefulSet** gives each replica a stable, predictable identity:
`mysql-0`, `mysql-1`, `mysql-2`, each with its own PersistentVolumeClaim
that follows it across rescheduling, and a stable DNS name via a headless
Service (`mysql-0.mysql.default.svc.cluster.local`). Pods are created and
terminated in order (0, 1, 2 up; 2, 1, 0 down), which matters for
replication topologies where node 0 is often the primary.

The rule of thumb: **if losing Pod identity or swapping which volume is
attached to which replica would break the application, use a StatefulSet;
otherwise use a Deployment.** Most stateless HTTP services (this repo's
`status-service` included) never need one — state belongs in a managed
database or object store outside the cluster far more often than it belongs
in a StatefulSet, precisely because StatefulSets don't solve backup,
replication lag, or failover for you; they only solve stable identity.

### Services — ClusterIP / NodePort / LoadBalancer / ExternalName

Pod IPs are ephemeral; a Service gives a stable virtual IP and DNS name in
front of a set of Pods selected by label, with kube-proxy doing the
load-balancing.

| Type | What it does | When to use |
|---|---|---|
| `ClusterIP` (default) | Stable IP reachable only inside the cluster | Internal service-to-service traffic — this repo's `status-service` uses this |
| `NodePort` | Opens the same port on every node's IP, forwards to the Service | Quick manual/dev access, or as the substrate an Ingress/LoadBalancer sits on top of |
| `LoadBalancer` | Asks the cloud-controller-manager to provision a real external load balancer | Public-facing entry point on a real cloud cluster (does nothing useful on `kind` — no cloud controller to fulfil it) |
| `ExternalName` | Pure DNS CNAME to an external name, no proxying | Referencing an external system (a managed DB endpoint, a SaaS API) by an in-cluster name, so app code never hardcodes the external hostname |

In practice, most real ingress traffic doesn't go through
`LoadBalancer`-type Services at all — it goes through one shared Ingress
controller (§6), fronted by a single LoadBalancer Service, routing by
hostname/path to many ClusterIP Services behind it. That's cheaper than one
cloud load balancer per app.

### Secrets and ConfigMaps

Both inject configuration into Pods (as env vars or mounted files);
the difference is intent, not real encryption strength by default.
**ConfigMap** — non-sensitive config. **Secret** — intended for sensitive
values, but base64-encoded, not encrypted, at rest in etcd unless you've
explicitly turned on
[encryption at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
for the API server. Treat "it's a Secret object" as access-control
labeling, not encryption — pair it with RBAC restricting who can `get`
Secrets, and for anything truly sensitive (this book's stance, consistent
with Zone 6's guidance on secrets management) prefer an external secrets
manager (Vault, cloud KMS-backed secret store) synced in, over storing the
plaintext secret as a Kubernetes object at all.

### PersistentVolumes, PersistentVolumeClaims, StorageClasses

- **PersistentVolume (PV)** — a piece of real storage (a cloud disk, an NFS
  export, a local disk) represented as a cluster resource, provisioned
  either statically by an admin or dynamically on demand.
- **PersistentVolumeClaim (PVC)** — a Pod's request for storage ("give me
  10Gi, ReadWriteOnce"), bound to a matching PV.
- **StorageClass** — a template for *dynamic* provisioning: when a PVC
  names a StorageClass, the cluster's storage provisioner creates a
  matching PV on demand instead of requiring one to already exist. On a
  managed cloud cluster this is what turns a PVC into an actual EBS
  volume/Persistent Disk with zero manual PV authoring.

This repo's `status-service` is deliberately stateless and needs none of
this — its only volume is an in-memory `emptyDir` for `/tmp`, sized and
capped at 16Mi so a runaway write can't fill node disk. That's a real,
minimal example of "don't reach for a PVC you don't need."

---

## 4. Kubernetes security and resilience, applied for real

This is where the chapter stops being generic Kubernetes theory and walks
through what this repo actually deployed and actually scanned. Every choice
below is in `k8s/base/deployment.yaml`, `networkpolicy.yaml`, and
`pdb.yaml`, deployed live to a `kind` cluster (1 control-plane + 1 worker,
Kubernetes v1.31.0) and scanned with `kube-bench` v0.9.4.

**Restricted Pod Security Standard, non-root, no privilege escalation:**

```yaml
securityContext:            # Pod-level
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:        # Container-level, more specific wins
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: [ALL]
```

Why each line matters, plainly:

- `runAsNonRoot` / `runAsUser: 10001` — a container process running as
  root inside the container is one kernel exploit or misconfigured
  volume mount away from root *on the node*. Non-root by default means a
  compromised app process can't `chmod`, install packages, or touch
  anything outside its own UID's permissions.
- `readOnlyRootFilesystem: true` — the container's own filesystem can't
  be written to at runtime. An attacker who gets code execution inside
  the container can't drop a second-stage payload to disk, can't modify
  the app binary in place, can't persist across a Pod restart. The app
  gets exactly one writable path it actually needs (`/tmp`, mounted as
  its own size-capped `emptyDir` — see the deployment's `volumeMounts`),
  nothing more.
- `allowPrivilegeEscalation: false` — blocks `setuid`/`setgid` tricks
  that would let a process gain more privilege than it started with,
  independent of the `runAsNonRoot` setting.
- `capabilities: drop: [ALL]` — Linux capabilities are the fine-grained
  pieces root's power is split into (`NET_ADMIN`, `SYS_PTRACE`, etc.).
  Dropping all of them means even *if* something ran as root by mistake,
  it still couldn't bind privileged ports, trace other processes, or
  manipulate network interfaces. Add back only the specific capability a
  workload provably needs — this app needs none.
- `seccompProfile: RuntimeDefault` — restricts the set of syscalls the
  container can make to the runtime's default allow-list, closing off
  most kernel-level escape and exploit primitives that need an
  uncommon syscall.
- `automountServiceAccountToken: false` — this Pod never calls the
  Kubernetes API, so it doesn't get a token that could be stolen and
  used to. Least privilege applied to the identity a Pod is handed by
  default, not just the identity a human requests.

**Default-deny NetworkPolicy, then explicit allow:**

```yaml
# deny-all baseline for this Pod's ingress AND egress
podSelector:
  matchLabels: {app.kubernetes.io/name: status-service}
policyTypes: [Ingress, Egress]
---
# then: allow ingress on 8080 from anywhere in the namespace
# then: allow egress only to DNS (UDP/TCP 53)
```

Kubernetes networking is flat and any-to-any by default — every Pod can
reach every other Pod's IP directly unless a NetworkPolicy says otherwise
(and only if the CNI plugin actually enforces NetworkPolicy — not all do;
`kind`'s default CNI does). The comment in this repo's own manifest states
the reasoning plainly: *"The app makes no outbound calls of its own (it
only reads a local file), so egress is locked down hard."* That's the
right way to write a NetworkPolicy — start from what the app's actual
traffic pattern is, not from a template. A default-deny policy with no
allow rules turns a compromised pod into a dead end: it can't be reached
except on the one port it serves, and it can't reach anything except DNS
to resolve names it will never actually query.

**PodDisruptionBudget:**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 1
  unhealthyPodEvictionPolicy: AlwaysAllow
```

This governs *voluntary* disruptions — node drains for maintenance,
cluster autoscaler scale-downs, `kubectl drain` — guaranteeing at least one
healthy replica stays up while the rest churn. It does nothing for
involuntary disruption (a node crashing outright); that's what replica
count and anti-affinity are for.

**Pod anti-affinity:**

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: {matchLabels: {app.kubernetes.io/name: status-service}}
          topologyKey: kubernetes.io/hostname
```

`preferred` (soft), not `required` (hard) — the scheduler tries to spread
replicas across distinct nodes (so one node failing doesn't take out every
replica at once) but will still schedule co-located replicas rather than
leave a Pod `Pending` if the cluster is too small to spread them. On a
2-node `kind` cluster with `replicas: 2`, this is exactly the right choice
— a hard `required` rule would make the third prod replica (`replicas: 3`
in the prod overlay) permanently unschedulable on a 2-node cluster.

### The real kube-bench scan — and the distinction that matters most

`kube-bench` v0.9.4, `cis-1.24` benchmark profile, run against the live
`kind` v0.24.0 cluster (Kubernetes v1.31.0) with this repo's manifests
actually deployed and confirmed `Ready`:

```
== Summary total ==
62 checks PASS
11 checks FAIL
48 checks WARN
0 checks INFO
```

The FAILs matter less than *why* they're FAILs. All 11 are the cluster's
control plane — `--profiling` left enabled on the API server, scheduler,
and controller-manager; no audit log configured; kubelet service file
permissions and `--protect-kernel-defaults` unset. None of these are
things `k8s/base/*.yaml` has any power over — they're `kind`'s own
default, minimal, fast-to-boot control-plane configuration, the kind of
gaps a CIS-hardened managed cluster (EKS/GKE/AKS with hardened node images)
or a `kubeadm` install with an actual audit policy would close instead.

This is the single most important skill this chapter can teach beyond the
manifest syntax itself: **when a scanner reports a failure, the first
question is "is this my code, or the platform's defaults?"** Claiming
"CIS-compliant" because you wrote hardened manifests, without checking
whether the *cluster underneath* those manifests is also hardened, is
exactly the kind of unverified claim this book's house style refuses to
make. The honest version is what this repo's `cis-benchmark/README.md`
says: the manifests deploy cleanly to a real cluster and produce real,
running, network-policed workloads, and a real scanner scored the
*surrounding* control plane honestly, gaps named and attributed, not
asserted away.

The 48 WARNs are mostly `kube-bench`'s advisory §5 workload checks — Pod
Security Policies (deprecated since 1.25, superseded by Pod Security
Admission, which this repo's manifests already satisfy via the `restricted`
PSS), secrets-as-env-vars, image provenance, seccomp — the kind of checks
that need a per-workload judgment call rather than a binary pass/fail.

---

## 5. RBAC and networking

### RBAC

Kubernetes RBAC has four objects, in two pairs:

- **`Role`** (namespace-scoped) / **`ClusterRole`** (cluster-scoped) — a
  set of permitted verbs (`get`, `list`, `watch`, `create`, `update`,
  `delete`) on resource types.
- **`RoleBinding`** / **`ClusterRoleBinding`** — grants a Role/ClusterRole
  to a subject (a User, Group, or ServiceAccount).

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: status-service-prod
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: status-service-prod
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: status-service-prod
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

The least-privilege discipline: bind a `ClusterRoleBinding` with
`cluster-admin` to exactly the identities that must administer the whole
cluster (almost never a CI pipeline, almost never an application's
ServiceAccount), and default every application ServiceAccount to nothing
— this repo's Deployment goes further and turns off the token mount
entirely with `automountServiceAccountToken: false`, because the
`status-service` Pod never calls the API server at all. The audit
checklist item every real environment needs and few actually run:
`kubectl get clusterrolebindings -o json | jq` filtered for bindings to
`cluster-admin` or wildcard (`*`) verbs/resources, checked against who or
what actually needs that reach.

### Networking model

Three rules define Kubernetes networking, and they're worth memorizing
verbatim because they explain *why* NetworkPolicy is necessary at all:

1. Every Pod gets its own IP; containers within a Pod share that IP.
2. All Pods can reach all other Pods' IPs directly, cluster-wide, without
   NAT, by default.
3. Nodes can reach all Pods, and vice versa, without NAT.

Rule 2 is the one that surprises people coming from traditional network
segmentation — Kubernetes networking starts fully open, and Namespaces by
themselves provide zero network isolation. NetworkPolicy is the only object
that restricts rule 2, and it's opt-in and additive: with no NetworkPolicy
selecting a Pod, that Pod is fully open; the moment *any* NetworkPolicy
selects it for a given direction (Ingress or Egress), that direction
becomes default-deny except for what's explicitly allowed — which is
exactly the pattern this repo's `networkpolicy.yaml` uses (a deny-all
policy with no rules, immediately followed by narrow allow policies).

---

## 6. Ingress, custom domains, and TLS

A **NodePort/LoadBalancer Service per app** doesn't scale past a handful of
apps — one cloud load balancer per app is expensive and each gets its own
IP. An **Ingress controller** (nginx-ingress, Traefik, cloud-native
alternatives) is a single reverse proxy running as Pods in the cluster,
fronted by one `LoadBalancer` Service, that routes by hostname and/or path
to many backend ClusterIP Services based on `Ingress` objects:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: status-service
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [status.example.com]
      secretName: status-service-tls
  rules:
    - host: status.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: status-service
                port: {number: 80}
```

**Custom domain mapping** is just DNS: point `status.example.com`'s A/CNAME
record at the Ingress controller's external LoadBalancer IP/hostname. No
Kubernetes object does that for you — it's a DNS provider change, made once
the Ingress controller's external address is known.

**TLS the pattern used almost everywhere now**: `cert-manager` running in
the cluster, watching `Ingress`/`Certificate` objects, talking to Let's
Encrypt's ACME API to prove domain ownership (HTTP-01 challenge via a
temporary path the Ingress serves, or DNS-01 via a TXT record) and issuing
a real certificate, stored as a Secret (`status-service-tls` above) that
the Ingress controller terminates TLS with — and cert-manager renews it
automatically before the (typically 90-day) Let's Encrypt certificate
expires. This is the free, automated, industry-standard path; manually
managed certificates are the exception now, not the rule.

---

## 7. Scaling and safe rollouts

### Horizontal and Vertical autoscaling

- **HPA (HorizontalPodAutoscaler)** — adds/removes replicas based on a
  metric (CPU/memory by default, custom metrics via an adapter). Requires
  `resources.requests` to be set on the container (this repo's Deployment
  sets `cpu: 50m` / `memory: 64Mi` requests) — HPA computes utilization as
  a percentage of the *request*, so a Pod with no request has nothing to
  scale against.
- **VPA (VerticalPodAutoscaler)** — adjusts a Pod's resource
  requests/limits over time based on observed usage, instead of replica
  count. Combining HPA and VPA on the same metric is a known anti-pattern
  (they fight each other); use HPA for request-driven horizontal scale and
  VPA for right-sizing requests you set once and don't want to hand-tune.

### Rollout and rollback

```bash
kubectl set image deployment/status-service status-service=ghcr.io/jclements3/status-service:1.1.0
kubectl rollout status deployment/status-service
kubectl rollout undo deployment/status-service          # back to previous revision
kubectl rollout undo deployment/status-service --to-revision=3
```

`kubectl rollout status` blocking on the readiness probe passing is the
whole safety mechanism of a `RollingUpdate` — if the new image's Pods never
become `Ready` (bad image, crashing app, failing `/readyz`), the rollout
stalls rather than replacing every old Pod with a broken one, and
`rollout undo` reverts cleanly because the old ReplicaSet is kept around.

### Deployment strategies, honestly compared

| Strategy | How it works | Tradeoff |
|---|---|---|
| **Recreate** | Kill all old Pods, then start new ones | Downtime window, simplest, fine for dev/single-replica or when the app can't run two versions concurrently (e.g. an exclusive-lock migration) |
| **Rolling update** (Kubernetes Deployment default) | Old and new Pods coexist during the transition, old scaled down as new becomes Ready | No downtime, but both versions serve traffic simultaneously for a window — requires backward/forward-compatible API and schema during that window |
| **Blue-green** | Two full environments; switch traffic (Service selector or Ingress/DNS) atomically from old to new | Instant cutover and instant rollback (flip back), but doubles resource cost while both stacks run, and needs an explicit traffic-switch step Kubernetes doesn't do natively — usually scripted or handled by a mesh/Ingress |
| **Canary** | Route a small percentage of real traffic to the new version, watch metrics, ramp up | Catches bad releases against real traffic before full exposure, but needs weighted routing (Ingress annotations, a service mesh, or a tool like Argo Rollouts/Flagger) — plain Kubernetes Deployments don't natively support percentage-based traffic splits |

Kubernetes' native rollout mechanism is rolling update; blue-green and
canary both require something on top (an Ingress controller with weighted
routing, a service mesh, or a purpose-built controller like Argo Rollouts)
— know this distinction, because "Kubernetes does canary deployments" is a
common but imprecise claim.

---

## 8. Helm and GitOps with ArgoCD

### Helm

Helm packages a set of manifests as a versioned, templated, parameterized
**chart** — `values.yaml` supplies the parameters, `templates/*.yaml` are
manifests with Go template placeholders, and `helm install`/`upgrade`
renders and applies them, tracking each install as a numbered **release**
you can `helm rollback` by number.

```bash
helm install status-service ./chart --namespace status-service-prod \
  --set image.tag=1.1.0 --set replicaCount=3
helm upgrade status-service ./chart --set image.tag=1.2.0
helm rollback status-service 4
```

**Honest comparison to this repo's actual approach**: `k8s/` uses
Kustomize, not Helm — a `base/` of plain manifests plus `overlays/dev` and
`overlays/prod` patches (strategic-merge and JSON patches) that layer
environment-specific changes on top without templating syntax inside the
YAML. Kustomize's manifests stay valid, plain Kubernetes YAML at every
layer, which is exactly why `kubeconform` (the schema gate in Zone 5/7's
pre-deploy order) can validate them directly. Helm's templates are *not*
valid YAML until rendered (`helm template` first), so schema validation
has to run after rendering, and Helm charts pull in a templating language,
a values schema, and a release/rollback state model Kustomize doesn't have.
Helm wins when you're packaging something for many independent consumers
to parameterize (a public chart, an internal platform team distributing a
standard app pattern); Kustomize wins when it's your own app's own
manifests and you want the smallest possible layer between the YAML you
read and the YAML that gets applied. This repo picked Kustomize
deliberately for that reason — there's no packaging-for-others use case
here, just base + two overlays.

### GitOps and ArgoCD

GitOps' core claim: **git is the single source of truth for desired
cluster state**, and a controller running *inside* the cluster
continuously reconciles live state toward whatever's committed — not a CI
pipeline pushing `kubectl apply` outward.

ArgoCD implements this as an `Application` custom resource pointing at a
git repo path (raw manifests, a Kustomize overlay, or a Helm chart) and a
destination cluster/namespace. Its controller runs the same reconciliation
loop pattern as `kube-controller-manager` (§2) one level up: watch the git
repo, watch live cluster state, diff them, and either auto-sync the
difference away or flag `OutOfSync` for a human to approve. This closes a
security-relevant gap plain CI/CD leaves open — CI pipelines typically hold
a credential with `apply` rights into the cluster from *outside* it; ArgoCD
instead runs *inside* the cluster with its own scoped RBAC and pulls, so no
external CI system needs standing write access to production. It also
means someone running `kubectl edit` directly against a live Deployment
gets silently reverted back to whatever git says on the next sync — drift
is not just detected, it's corrected, which enforces "if it's not in git,
it doesn't happen" far more effectively than a policy document does.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: status-service-prod
spec:
  source:
    repoURL: https://github.com/jclements3/poetic-musings
    path: k8s/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: status-service-prod
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

`k8s/overlays/prod` as the `path` here is not hypothetical — that's this
repo's real Kustomize overlay, and it's exactly the kind of source ArgoCD
is built to point at natively, no adapter needed.

---

## 9. Service mesh, briefly (course knowledge — flagged, not run here)

**Nothing in this repo runs a service mesh.** This section is TOC-sourced
(Module 10, item 17) course breadth, not a verified deployment — flagged
explicitly per this book's house style.

A service mesh (Istio being the reference implementation) injects a
sidecar proxy (Envoy) into every Pod, intercepting all pod-to-pod traffic,
and adds three things on top of plain Kubernetes networking:

- **Traffic control** — fine-grained routing (percentage-based canary
  splits, retries, timeouts, circuit breaking) without touching
  application code, via `VirtualService`/`DestinationRule` objects —
  this is what gives you the canary traffic-splitting that plain
  Kubernetes Deployments (§7) don't do natively.
- **mTLS everywhere** — every pod-to-pod connection automatically
  encrypted and mutually authenticated, without the application knowing
  TLS exists. This is real defense in depth on top of NetworkPolicy:
  NetworkPolicy controls *which* pods can talk; mTLS ensures *what's said*
  can't be read or spoofed even if network segmentation is bypassed.
- **Observability** — uniform request-level metrics, distributed tracing,
  and access logs for every service, for free, because every request
  already passes through the sidecar.

The honest cost side: a sidecar per Pod roughly doubles the container
count and adds real memory/CPU overhead and a new class of failure mode
(the mesh's own control plane, certificate rotation, sidecar injection
webhook misfires). The rule of thumb worth stating plainly: adopt a mesh
when you have enough services that manual mTLS and manual canary tooling
per-service has become the actual bottleneck — not by default on a
handful of services, which is this repo's actual scale (one app, two
NetworkPolicies handle its real traffic pattern completely).

---

## 10. Windows/Active Directory as parallel identity infrastructure

### Why this is in a Kubernetes deploy chapter at all

The job posting behind this book (`JOB.html`) requires Active
Directory/Windows Server skills alongside Kubernetes, and that's not an
odd pairing — it's the normal shape of a real enterprise environment.
Kubernetes orchestrates *workloads*; Active Directory orchestrates
*identity* — which humans and machines exist, what groups they belong to,
what policy gets pushed to their endpoints, how Kerberos issues them
proof of who they are. An enterprise almost never runs one without the
other: the same organization running Kubernetes for its applications is
running AD (or Entra ID/Azure AD, its cloud descendant) for its employee
laptops, its internal service accounts, its VPN, and often its
Kubernetes cluster's own SSO/OIDC integration back into that same AD
tenant. Treating this as "Kubernetes vs. Windows" is the wrong frame;
the right frame is that both are orchestration and reconciliation
systems — AD's domain controller reconciles directory state the same
conceptual way `kube-controller-manager` reconciles cluster state — and
a DevSecOps engineer in this environment needs to operate both.

### This repo's real Samba4 AD work, as a worked example

`ad-lab/` proves the same "verify the mechanism for real, name what's
not covered" discipline this whole book insists on, applied to identity
infrastructure instead of container orchestration:

- **Real domain, real DC**: `poeticmusings.lab` (NetBIOS `POETICM`),
  provisioned for real with `samba-tool domain provision`, running as a
  genuine Samba4 Active Directory Domain Controller — open source, no
  Windows license, and wire-compatible with real Windows clients (a real
  Windows machine could join this domain and authenticate against it
  exactly as it would against a licensed Windows Server DC).
- **Real Kerberos**: `kinit jclements@POETICMUSINGS.LAB` against a real
  password produced a real TGT
  (`krbtgt/POETICMUSINGS.LAB@POETICMUSINGS.LAB`) with real expiry,
  confirmed with `klist` — not a diagram of how Kerberos works, an actual
  ticket.
- **Real LDAP/DNS**: OUs (`OU=IT`, `OU=Engineering`), groups
  (`DevSecOps-Admins`, `Platform-Team`), and a real user (`jclements`,
  member of `DevSecOps-Admins`) created via `samba-tool`; DNS confirmed
  externally with `dig @127.0.0.1 -p 8053 dc1.poeticmusings.lab A` and
  the `_ldap._tcp` SRV record a real client's domain-discovery process
  depends on.
- **Real GPO object**: `Password-Policy-Baseline` created with
  `samba-tool gpo create`, stored in real SYSVOL, linked to `OU=IT` with
  `samba-tool gpo setlink`, confirmed with `samba-tool gpo getlink`.

**Two real bugs, fixed for real** — worth knowing because both are classic
container/virtualization-environment AD failures, not toy problems:

1. SYSVOL provisioning failed with `NT_STATUS_ACCESS_DENIED` because
   Docker's overlay filesystem (and WSL2's backing store under it)
   doesn't reliably support the extended attributes Samba normally uses
   to store NT ACLs. Fixed with `--option="posix:eadb=..."` on `domain
   provision`, making Samba emulate those ACLs via a TDB database instead
   of real xattrs — the same category of fix as "this platform's storage
   layer doesn't support the primitive the software assumes," which is
   worth recognizing anywhere containers meet a filesystem-attribute-
   dependent service.
2. `samba-tool gpo create` failed with a DNS SRV lookup failure because
   the container's `/etc/resolv.conf` still pointed at Docker's default
   resolver, not Samba's own internal DNS server — fixed by repointing
   resolution at `127.0.0.1` once the DC's own DNS was up. This is the
   same "identity infrastructure depends on itself for DNS, and if the
   resolver isn't pointed at the DC yet, DC operations that need DNS
   fail" trap that shows up constantly in real AD deployments, not just
   lab ones.

### Honest gaps — what a real Windows Server environment adds

Stated exactly as `ad-lab/README.md` states them, because naming the gap
is the point:

- **No domain-joined Windows client.** The DC side is proven completely
  — real domain, real Kerberos, a real linked GPO object — but nothing
  has actually joined a Windows machine to this domain, so GPO
  *application* (a client pulling and enforcing the policy) is unproven;
  only GPO *object creation and linkage* is. Closing this needs a real or
  lab Windows client VM, which needs a GUI/hypervisor this lab
  environment doesn't have.
- **No policy settings authored inside the GPO.** The GPO object exists
  and is linked, but its `registry.pol` content is empty — authoring real
  settings (password complexity, lockout thresholds, screen-lock timeout)
  is normally done in the Group Policy Management Console (GPMC) from a
  Windows admin workstation with RSAT installed. That's genuinely a
  different toolchain than anything `samba-tool` gives you.
- **No MECM/SCCM or Intune.** Those manage endpoints at fleet scale —
  software deployment, patch compliance, configuration baselines — *on
  top of* an AD/Entra identity foundation. This lab proves the
  foundation; it doesn't reach into fleet management at all.
- **Single DC, no replication topology.** Production AD runs 2+ DCs for
  redundancy and site-local authentication; this is one DC, sufficient to
  prove the mechanism, not a production topology.

The transferable lesson for the interview and the job itself: know the
difference between *proving a mechanism is real* (a working KDC issuing
real tickets, a working GPO object linked to a real OU) and *proving an
enterprise-scale operational capability* (GPO settings actually enforced
fleet-wide via SCCM, multi-DC failover). Both matter; conflating them is
how claims get overstated. This book's stance throughout is: say exactly
which one you've verified.

---

## 11. Day-one checklist for this zone

1. **Map what's actually running vs. what's just defined.** `kubectl get
   deploy,po,svc,networkpolicy,pdb -A` against the real cluster, diffed
   against everything committed in the manifest repo — a manifest that
   exists in git but was never applied, or was applied and later drifted,
   is not a control, it's a document.
2. **Check NetworkPolicy coverage per namespace.** `kubectl get
   networkpolicy -A` — any namespace with workloads and zero
   NetworkPolicies is fully open by Kubernetes' default (§5); that's the
   single highest-leverage gap to close first.
3. **Audit RBAC for overly broad bindings.** `kubectl get
   clusterrolebindings -o json`, filtered for `cluster-admin` or wildcard
   verbs/resources, checked against who/what genuinely needs cluster-wide
   admin — CI ServiceAccounts and application ServiceAccounts almost
   never should have it.
4. **Confirm Pod Security Standard enforcement per namespace**, not just
   per manifest: `kubectl get ns --show-labels | grep pod-security` —
   labels on the manifest mean nothing if the namespace itself doesn't
   enforce the `restricted` (or at least `baseline`) admission level.
5. **Check every Deployment for resource requests/limits.** No
   `requests` means HPA has nothing to scale against and the scheduler
   can't bin-pack sanely; no `limits` means one runaway Pod can starve
   its node.
6. **Verify PodDisruptionBudgets exist for anything that can't tolerate
   going fully to zero replicas during a node drain or cluster
   autoscaler event.**
7. **Confirm the pre-deploy validation order is actually wired into
   CI**, not just documented: `kubeconform -summary k8s/` (schema) →
   `kube-linter` (policy) → `kubectl apply --dry-run=server` (admission)
   → apply. Each layer catches what the previous structurally can't —
   kubeconform can't catch a Pod Security Admission rejection, and a
   dry-run needs a live cluster kubeconform doesn't.
8. **For identity infrastructure**: confirm which OUs/groups actually
   have GPOs linked vs. which exist unlinked; confirm DNS for the domain
   resolves from a client's actual configured resolver, not just from
   the DC itself; confirm there's more than one DC in anything
   production-facing.

---

## 12. Troubleshooting quick-reference

| Symptom | Likely cause | First commands |
|---|---|---|
| `CrashLoopBackOff` | App exits non-zero shortly after start — bad config, missing env var/secret, failing startup dependency, OOM-killed | `kubectl logs <pod> --previous`, `kubectl describe pod <pod>` (check `Last State: Terminated, Reason:`) |
| `ImagePullBackOff` / `ErrImagePull` | Wrong image tag/registry, missing `imagePullSecrets`, private registry auth failure, image genuinely doesn't exist | `kubectl describe pod <pod>` for the exact pull error; verify the tag exists in the registry directly |
| `Pending` pod | Scheduler can't place it — insufficient node resources, an unsatisfiable `nodeSelector`/affinity, a taint with no matching toleration, no PV available for a bound PVC | `kubectl describe pod <pod>` (Events section names the exact scheduling failure); `kubectl get nodes -o wide` + `kubectl describe node` for allocatable resources |
| Service not routing traffic | Service `selector` labels don't match the Pod's actual labels (most common cause by far), or the container port doesn't match `targetPort` | `kubectl get endpoints <svc>` — empty endpoints means the selector matches zero Pods; diff `Service.spec.selector` against `kubectl get pod --show-labels` |
| Kerberos ticket fails to issue (`kinit` error) | DNS not resolving the realm's SRV/A records (client resolver not pointed at the DC, as this repo hit while seeding GPOs), or clock skew beyond Kerberos' default 5-minute tolerance | `dig _kerberos._tcp.<realm> SRV`, `dig dc1.<realm> A`; `w32tm /query /status` (Windows) or `chronyc tracking`/`timedatectl` (Linux) to check clock offset against the DC |
| Manifest passes `kubeconform` but is rejected on `apply` | Schema-valid YAML that still violates cluster admission policy — most often a `restricted` Pod Security Standard rejecting a container missing `runAsNonRoot`/`allowPrivilegeEscalation: false`/dropped capabilities | `kubectl apply --dry-run=server -f <file>` surfaces the admission error text directly; cross-check the Pod spec's `securityContext` against the namespace's enforced PSS level (`kubectl get ns <ns> -o yaml \| grep pod-security`) |

---

Zone 7's runnable recipes — the `kubeconform`/`kube-linter`/dry-run pre-deploy
chain, the Kustomize base/overlay layout, and the `kube-bench` reproduction
steps — live in the book's toolkit appendix alongside this repo's own
`k8s/` and `k8s/cis-benchmark/` files, which are the canonical source for
every command and manifest excerpt in this chapter.


---


# Chapter 8 — Zone 8: Operate and Observe

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone matters

Every other zone in this book produces something: a build, a scan result, a
signed image, a deployed pod. Zone 8 is the zone that tells you whether any
of it is still true five minutes, five hours, or five months later. You
cannot fix what you cannot see, and you cannot see what you didn't
instrument. That sentence sounds like a platitude until you've lived the
alternative: a cron job that silently stopped running 61 days ago, a
dashboard that still shows the old service topology, an alert that fires
into a Slack channel nobody reads. All three of those are *worse* than
having no monitoring at all, because they give you the confidence of
coverage without the substance of it.

This is also, deliberately, the chapter that does double duty as the book's
main troubleshooting reference. That's not an accident of scope — it's how
the zone actually works in practice. "Operate and observe" isn't a
dashboard you glance at once a day; it's the zone you're standing in at
2 a.m. when a page fires and you have sixty seconds to figure out whether
this is a one-pod blip or the whole platform is down. Everything in this
chapter — the metrics stack, the logging stack, the triage framework — is
in service of that one moment: something broke, now what.

Two things this repo has built for real ground the chapter: a working
Prometheus + Grafana stack in `observability/`, instrumented against a real
Flask service, with a real bug caught in the metrics pipeline itself (§4);
and a genuinely well-designed triage framework in `qrg.html` that this
chapter reproduces faithfully rather than reinventing (§6–§8). ELK gets a
full section on the merits — it's standard, expected knowledge for this
role — but it is explicitly **not deployed** anywhere in this repo. Where
this repo is real and where it's course-only is called out plainly,
because conflating the two is exactly the kind of unverified confidence
this zone exists to prevent.

---

## 2. Prometheus deep dive

### 2.1 The pull-based metrics model

Prometheus inverts the model most engineers expect from older monitoring
tools (Nagios, StatsD-push setups). Instead of applications pushing metrics
to a central collector, Prometheus **scrapes** — it polls each configured
target's `/metrics` HTTP endpoint on an interval and pulls whatever is
there. This has consequences worth understanding, not just accepting:

- **The target doesn't need to know Prometheus exists.** It just exposes a
  plaintext HTTP endpoint in the Prometheus exposition format. Any process
  that can serve HTTP can be scraped.
- **Prometheus itself becomes the thing that knows "is this target alive."**
  A failed scrape (`up == 0`) is itself a first-class signal — the absence
  of data is data. A push model has to build that detection separately
  (dead-man's-switch patterns); pull gets it for free.
- **Service discovery replaces static config at scale.** In Kubernetes,
  Prometheus (or the Prometheus Operator's `ServiceMonitor`/`PodMonitor`
  CRDs) discovers scrape targets from the API server rather than a static
  list of hosts, so targets that come and go with autoscaling or rolling
  deploys don't need manual re-registration.
- **Short-lived jobs are the actual weak point.** A batch job that runs for
  eight seconds and exits is gone before the next scrape interval — that's
  what the Prometheus Pushgateway exists for, as a deliberate, narrow
  exception to the pull model, not a general-purpose push path.

The exposition format itself is simple, line-oriented plaintext:

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/",status="200"} 42
```

Four metric types matter in practice:

- **Counter** — monotonically increasing (requests served, errors thrown).
  Never decreases except on process restart. You almost never query a
  counter's raw value; you query its `rate()`.
- **Gauge** — a value that goes up and down (memory in use, queue depth,
  number of ready pods).
- **Histogram** — buckets observations into configurable ranges (`le=`
  "less than or equal") and exposes `_bucket`, `_sum`, and `_count` series,
  used for latency distributions and `histogram_quantile()` queries.
- **Summary** — like a histogram but computes quantiles client-side; rarer
  in practice because it can't be aggregated across instances the way a
  histogram can.

### 2.2 PromQL basics

PromQL is Prometheus's query language, and the handful of patterns below
cover most of what shows up on a real dashboard or alert rule:

```promql
# Instantaneous value of a gauge
node_memory_MemAvailable_bytes

# Rate of a counter over a window — the correct way to read a counter,
# never the raw value, because it resets on restart and only rate() is
# restart-safe
rate(http_requests_total[5m])

# Aggregation across a label dimension
sum by (path) (rate(http_requests_total[1m]))

# p95 latency from a histogram
histogram_quantile(0.95,
  sum by (le, path) (rate(http_request_duration_seconds_bucket[5m])))

# Absolute increase over a window (not a rate — a count)
increase(http_requests_total[5m])

# Is the target even up?
up{job="status-service"} == 0
```

The `[5m]` range vector is the most commonly misunderstood part: it's not
"the last 5 minutes of data," it's "compute the rate using the samples
inside this trailing window," and the window needs to be at least a few
multiples of the scrape interval or the rate calculation gets noisy from
too few data points.

### 2.3 Node Exporter and Black Box Exporter

Prometheus itself only scrapes what exposes `/metrics` in its own format.
For everything that doesn't natively speak Prometheus, an **exporter**
translates.

- **Node Exporter** runs on every host (as a systemd service, or a
  DaemonSet in Kubernetes) and exposes OS-level metrics: CPU, memory, disk,
  filesystem, network, load average. This is the exporter behind almost
  every "is the box itself healthy" panel and behind the "boring six" disk
  and resource checks in §8.
- **Black Box Exporter** does something different: it doesn't report on
  the host it runs on, it *probes* other things — an HTTP endpoint, a TCP
  port, a DNS record, an ICMP ping — and exposes the result (up/down,
  response time, TLS cert expiry) as a metric. This is how you get
  external-facing synthetic checks ("is the load balancer reachable from
  outside") into the same Prometheus/Grafana/Alertmanager pipeline as
  everything else, and it's the natural home for TLS-expiry monitoring so
  the "quiet killer" cert sweep in §7 doesn't have to be a manual cron job
  forever.

### 2.4 Alertmanager and alert routing

Prometheus itself only evaluates alert rules and fires alerts into
**Alertmanager**, a separate component with a separate job: deduplication,
grouping, silencing, inhibition, and routing to a notification channel
(email, Slack, PagerDuty, a webhook). Splitting these two concerns matters:
Prometheus stays a pure metrics/query engine, and Alertmanager owns the
"who gets told, how often, and when to shut up" logic, which is genuinely
different logic from "is this condition true."

A minimal alert rule:

```yaml
groups:
  - name: status-service
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m])) > 0.05
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Error rate above 5% for 10 minutes"
```

The `for: 10m` clause is doing real work: it's the difference between an
alert that fires on every transient blip and one that fires on a sustained
condition. Alertmanager routing then decides where `severity: warning`
lands versus `severity: critical` — this is where the SEV1/SEV2/SEV3
cadence from §8 becomes config, not just a document nobody follows: a
`critical` route with a short `group_wait`/`repeat_interval` to a pager, a
`warning` route to a Slack channel with a longer repeat interval. An alert
that's correctly defined but routed to a channel nobody watches is not
meaningfully different from no alert at all — which is exactly the trap
the day-one checklist in §9 tells you to check for directly, not assume
away.

---

## 3. Grafana deep dive

### 3.1 Dashboards as code

Grafana dashboards *can* be built by hand in the UI, but "click around
until it looks right" doesn't survive a Grafana restart, a new environment,
or a second engineer needing to reproduce it. The durable pattern is
**provisioning**: dashboards and data sources defined as JSON/YAML files
checked into version control, loaded automatically on container start.
This repo does exactly that — `observability/grafana/provisioning/` wires
up the data source and dashboard directories, and
`observability/grafana/dashboards/status-service.json` is the dashboard
definition itself, so `docker compose up -d --build` produces a fully
populated dashboard with zero manual clicking. That's the difference
between a demo and infrastructure: the demo requires someone to remember
what they clicked; the infrastructure just comes back the same way every
time.

A minimal provisioning config for a data source:

```yaml
# provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

And for the dashboard loader itself:

```yaml
# provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: default
    folder: ""
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

### 3.2 Data sources and panel types

Grafana is fundamentally a query-and-render layer over one or more data
sources — Prometheus is the common one in this stack, but Grafana also
speaks Elasticsearch, Loki, InfluxDB, and plain SQL, among others, which is
part of why it's the standard visualization layer regardless of which
metrics or logging backend sits underneath it.

Panel types that cover most real dashboards:

- **Time series** — the default line/area graph, for rates and gauges over
  time (request rate, latency, CPU).
- **Stat** — a single big number, often with a sparkline and threshold
  coloring (current error count, total requests in the last 5 minutes).
- **Gauge** — a dial against a threshold (disk usage against 80%/95%
  warning/critical bands).
- **Pie chart / bar gauge** — distribution across a label (requests by
  status code, exactly what `status-service.json`'s panel 3 does with
  `sum by (status) (http_requests_total)`).
- **Table** — raw rows, useful for "top N" queries (slowest endpoints,
  noisiest pods).
- **Logs panel** — when the data source is Loki or Elasticsearch instead
  of Prometheus, for correlating a metric spike with the log lines from
  the same time window.

### 3.3 Alerting from Grafana

Grafana has its own unified alerting engine (since Grafana 8+), which can
alert directly off any configured data source's query, independent of
Prometheus's own rule evaluation. In practice, most shops pick one
alerting owner rather than run duplicate alert logic in both places —
Prometheus + Alertmanager for metrics-native alerting, or Grafana alerting
when the alert condition spans multiple data source types (a metric
crossed with a log pattern) that Prometheus alone can't express. Whichever
is chosen, the same principle from §2.4 applies: an alert that's correctly
defined but not routed to a human who's on call is a false sense of
coverage, not coverage.

---

## 4. Applied to poetic-musings: a real bug in the metrics pipeline itself

Everything above is standard-issue Prometheus/Grafana knowledge. This
section is why the chapter earns the word "real": this repo built a working
metrics pipeline and then found a bug **in the monitoring itself** —
the exact failure mode of "the dashboard is lying to you and looks
completely fine while it does it."

### The setup

`app/status-service/app.py` instruments two metrics via `prometheus_client`:
`http_requests_total{method, path, status}` (a Counter) and
`http_request_duration_seconds{method, path}` (a Histogram, feeding the
p95-latency panel). `/metrics` itself is excluded from both counters so
scraping the endpoint doesn't skew the numbers it's reporting.

The Dockerfile runs this service under **gunicorn with 2 worker
processes**, which is a completely ordinary production pattern — one
process per CPU core, or close to it, for a WSGI app under real load.

### The symptom

`prometheus_client`'s default registry lives **in-process**. Each gunicorn
worker is a separate OS process with its own Python interpreter and,
therefore, its own separate in-memory registry. A scrape of `/metrics`
hits *one* worker — whichever one the load balancer or gunicorn's own
connection handling routes it to — and that worker can only report *its
own* counters. It has no visibility into what the other worker counted.

Confirmed during development, not theorized: sending 30 requests to `/`
showed only **~13–17** on `/metrics** — roughly half the real traffic,
split unevenly across whichever worker happened to answer each request.
The dashboard wasn't down. It wasn't throwing errors. It was rendering a
perfectly smooth, perfectly wrong graph, quietly undercounting real
traffic by about 50%.

### Why it happened

This is the general lesson, not just the specific bug: **multi-process
serving and single-process metrics libraries are structurally
incompatible unless you explicitly bridge them.** Anything that forks or
spawns workers — gunicorn, uWSGI, any prefork server — breaks the
assumption that "the process" and "the application" are the same thing.
`prometheus_client`'s default in-memory registry assumes the latter. It's
correct in a single-process Flask dev server; it's silently wrong the
moment you add a second worker for real concurrency.

### The fix

Prometheus's own documented multiprocess pattern, implemented here in three
pieces that all have to be present together:

1. **`PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc`** set in the
   Dockerfile — critically, *before Python starts*, because
   `prometheus_client` checks this environment variable at import time to
   switch which internal value classes it uses (in-memory vs.
   file-backed). Setting it after import does nothing. It lives under
   `/tmp` to match the read-only-root-filesystem pattern the rest of the
   image already follows.
2. **`gunicorn.conf.py`'s `child_exit` hook** calls
   `multiprocess.mark_process_dead()` so a worker that dies or is recycled
   doesn't leave its last-known metric values permanently baked into the
   aggregate — a dead worker's numbers get cleaned up instead of
   contributing stale values forever.
3. **`/metrics` uses `MultiProcessCollector`** to merge every worker's
   file-backed metrics into one response when the env var is set, falling
   back to the ordinary single-process registry when it isn't (e.g.
   running `app.py` directly for local dev, not under gunicorn).

### Re-verification, three layers deep

The fix wasn't accepted on "it should work now." It was re-verified: 30
requests to `/` and 30 to `/status.json` showed as exactly 30 and 30 on
`/metrics`, confirmed a second time through **Prometheus's own query API**
(not just the raw scrape endpoint), and a third time through **Grafana's
datasource-proxy API** — the same number, independently observed at three
different layers of the stack.

### The lesson: who watches the watcher

The instinct when a dashboard looks fine is to trust it — that's the whole
point of a dashboard, to not have to check by hand. But "looks fine" and
"is correct" are different claims, and a monitoring system can fail in a
way that produces a smooth, confident, wrong graph rather than an obvious
gap or error. The only way this bug was caught was by generating a known
quantity of traffic (30 requests) and checking the observed count against
the expected one — treating the metrics pipeline itself as a system under
test, not a ground truth. Any time you stand up new instrumentation,
especially under a multi-process or multi-replica server, verify the count
against a known input before trusting the dashboard. The monitoring system
needs monitoring too — or at minimum, a sanity check on day one.

---

## 5. ELK stack — centralized logging, taught at full depth

**Explicit flag up front: ELK is not deployed anywhere in this repo.**
`observability/` is Prometheus + Grafana — metrics, not centralized logs.
This section is course-required knowledge taught at real depth because
it's standard, expected tooling for this role even where this specific
repo doesn't run it. Do not read this section as "this repo has ELK."

### 5.1 Why metrics aren't enough

Prometheus answers "how many, how fast, how much" — aggregate numeric
questions. It does not answer "what exactly did this one request do" or
"what was in the stack trace." That's a fundamentally different problem —
unstructured or semi-structured text, at high volume, from many sources,
that needs to be searchable after the fact. That's the problem ELK
(Elasticsearch, Logstash, Kibana) solves, and it's the natural complement
to a metrics stack, not a competitor to it: metrics tell you *that*
something is wrong and roughly *when*; logs tell you *what actually
happened*, line by line.

### 5.2 The three components

- **Elasticsearch** — the storage and search engine. A distributed,
  document-oriented datastore built on Apache Lucene, storing logs as JSON
  documents in indices, sharded and replicated across nodes for both
  scale and resilience. Its query DSL supports full-text search, filtering
  on structured fields, and aggregations (count-by-field, time-bucketed
  histograms) — the same aggregation instinct as PromQL, but over
  documents instead of time series.
- **Logstash** — the ingest and transform pipeline. Reads from an input
  (a file, a message queue like Kafka, a Beats shipper), applies filters
  (the most common: `grok` for pattern-matching unstructured text into
  structured fields, `date` for parsing timestamps into the right field,
  `mutate` for renaming/dropping/type-converting fields), and writes to an
  output (almost always Elasticsearch). This is the "parse a raw nginx
  access log line into `{client_ip, method, path, status, bytes,
  response_time}`" stage — the difference between a wall of text and a
  queryable field set.
- **Kibana** — the query and visualization layer on top of Elasticsearch,
  playing the same role for logs that Grafana plays for metrics:
  dashboards, saved searches, and its own query language (KQL) for
  ad-hoc exploration.

### 5.3 Beats — lightweight shippers

Running full Logstash on every host that produces logs is heavyweight —
it's a JVM process with real memory overhead. **Filebeat** (and the other
Beats: Metricbeat, Auditbeat, Packetbeat, each shipping a different signal
type) is the lightweight alternative: a small, low-overhead agent that
tails log files and ships them onward, either directly to Elasticsearch or
through Logstash for heavier transformation. The typical production
topology is:

```
app hosts (Filebeat) → Logstash (parse/enrich) → Elasticsearch → Kibana
```

Filebeat handles the "run efficiently on every node, survive restarts,
resume from where it left off" concerns; Logstash handles the CPU-heavy
parsing centrally, on fewer, bigger nodes, instead of duplicating that cost
on every host.

### 5.4 Index lifecycle management

Log volume grows without bound if left alone, and Elasticsearch performance
and cost both degrade with unbounded index growth. **Index Lifecycle
Management (ILM)** automates the standard pattern: a daily or size-based
rolling index (`app-logs-2026.09.21`), which moves through phases —
**hot** (actively written and queried, on fast storage), **warm** (no
longer written, occasionally queried, can be merged/shrunk), **cold**
(rarely queried, cheaper storage, possibly frozen/searchable snapshots),
and **delete** (past the retention window, removed entirely). This is the
direct logging analogue of `freshness.py`'s scan-summary retention concern
in this repo (§9, Zone 9) — data has a useful lifetime, and a system that
never prunes it either silently degrades or silently keeps something past
when it was authorized to.

### 5.5 A worked query example

Given logs indexed with `client_ip`, `path`, `status`, and `@timestamp`
fields, a Kibana Discover query using KQL to find every 5xx response on a
specific path in the last hour:

```
path: "/checkout" and status >= 500
```

And the same intent as a raw Elasticsearch query DSL request (what Kibana
generates underneath, and what you'd send directly via the `_search` API
or from Logstash's own conditional filters):

```json
GET /app-logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "path": "/checkout" } },
        { "range": { "status": { "gte": 500 } } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  }
}
```

A Kibana aggregation to answer "which paths are erroring most" — the log
equivalent of the Prometheus `sum by (path) (rate(...))` pattern from §2.2
— buckets by `path.keyword` with a `status >= 500` filter and a count
metric, rendered as a bar chart on a dashboard.

### 5.6 The real operational cost

ELK is not free to run at scale, and this needs to be said plainly rather
than glossed over: Elasticsearch is memory- and disk-hungry (JVM heap
sizing is a recurring operational headache), shard count and replica
strategy directly affect both cost and cluster stability, and log volume
from a busy production fleet can dwarf metrics volume by orders of
magnitude — a single verbose service can produce gigabytes of logs per
day where its Prometheus metrics footprint is kilobytes. This is exactly
why the standard shop runs both: Prometheus/Grafana for cheap, always-on
numeric monitoring and alerting, and ELK (or a lighter-weight equivalent
like Grafana's own Loki, which trades full-text indexing for cheaper
label-based log storage) reserved for the deeper, more expensive
after-the-fact investigation. Reaching for full-text log search as the
*first* line of defense, instead of metrics, is a common and expensive
mistake — it's the tool you go to once metrics have told you *where* to
look, not the tool you watch continuously by default.

---

## 6. The four-question triage framework

This is the real, working triage sequence from this repo's `qrg.html`,
reproduced faithfully — not reinvented, because it doesn't need to be. It
exists for exactly the moment described in §1: something's broken, and you
have limited time before the cost of not knowing exceeds the cost of
guessing wrong.

### Q1 — Blast radius? (first 120 seconds; scope decides urgency)

```
kubectl get pods -A | grep -v 'Running\|Completed'
systemctl --failed
kubectl get nodes
df -h
```

Is this one pod, one user, one host — or everything? The answer to Q1
alone often determines whether you're dealing with a SEV1 or a SEV3 (§8).
Ask a second human. Write the answer down — not for ceremony, but because
you will need it later for the postmortem, and because a second person
independently confirming scope catches the case where you're staring at
one symptom that isn't actually the whole picture.

### Q2 — What changed? (the highest-yield question; run the whole battery)

```
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl rollout history deployment/<name> -n <ns>
helm history <release> -n <ns>
git log --oneline --since="24 hours ago"
terraform plan -detailed-exitcode
journalctl --since "-24h" -p warning | tail -40
```

Something almost always changed — a deploy, a config edit, a certificate
rotation, an upstream dependency update, a scheduled job. **Nothing found
usually means you're looking at the wrong layer, not that there's no
cause.** This is the single highest-yield question in the whole framework
because most incidents are not novel failures of otherwise-stable systems
— they're a consequence of something that changed, and the fastest path to
resolution is usually finding that change and reversing it (Q4), not
diagnosing the failure mode from first principles.

### Q3 — Which layer? (walk the request path, half-split)

```
dig <name>
curl -v https://<host>/health
kubectl get endpoints <svc> -n <ns>
kubectl get pods -n <ns>
kubectl logs <pod> -n <ns> --previous
```

The request path, in order: **DNS → LB → ingress → service → endpoints →
pod → app.** Rather than checking every hop in sequence, half-split it:
start at `endpoints` (roughly the midpoint of that chain), and let whether
it's correct tell you which half of the path to check next. This is
ordinary binary search applied to infrastructure, and it turns an
eight-hop linear walk into roughly three checks.

### Q4 — Fastest safe rollback? (answer before any fix attempt)

```
helm rollback <release> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
git revert <sha> && git push
```

**Stabilize first, root-cause second.** If Q2 found the change and a
rollback path exists, take it — before you've fully explained *why* the
change broke things. Restoring service is not the same activity as
understanding the failure, and conflating them under time pressure is how
a five-minute outage becomes a forty-minute one. The postmortem (§8) is
where the "why" gets its full attention, on a timeline that isn't burning
down user impact while you write it.

### Rules of engagement on an unknown system

These apply across all four questions, especially when you're triaging
something you didn't build or don't fully own:

- **Read-only first** — `get`/`describe`/`logs`/`history`/`status` before
  any mutating verb. You cannot un-ring a bell you didn't need to ring.
- **Snapshot before touching** —
  `kubectl get ... -o yaml > was.yaml`,
  `terraform state pull > state.backup.json`. Capture the "before" state
  before you change anything, so a bad guess is reversible and a
  postmortem has ground truth to compare against.
- **Log the terminal** — `script -a /tmp/incident-$(date +%F-%H%M).log`.
  The transcript of what you actually ran, in order, is worth more after
  the fact than your memory of it.
- **One change at a time** — change, verify, record, then the next
  change. Stacking multiple simultaneous changes destroys your ability to
  attribute which one fixed (or worsened) things.
- **Stop and escalate** when the fix touches a security/ATO-boundary
  config, risks data loss, or you've spent 30 minutes with no working
  hypothesis. None of those are failures on your part — they're exactly
  the conditions this rule exists to catch before they become worse ones.

---

## 7. Rapid-fire diagnostic patterns

Faster pattern-matches for common failure shapes, reproduced from the same
source, for when you already know roughly what kind of thing broke.

### Pipeline is red — decode by stage

- **BUILD fails**: read the first error only. Build tool output cascades —
  the fifth error is usually a consequence of the first, not a second
  independent problem.
- **TEST fails**: rerun once at most — twice-failed is real. One retry
  absorbs ordinary flakiness (§9 of Chapter 3 covers this in the build/test
  context directly); a second consecutive failure means stop treating it
  as flake.
- **SCAN fails, no code change**: the CVE database moved. A dependency
  that passed yesterday can fail today with zero commits in between —
  that's the scanner doing its job against a new disclosure, not a broken
  pipeline.
- **DEPLOY fails**: ask what changed on the *target*, not the repo. A
  deploy failure is frequently an environment-state problem (quota,
  permissions, drift) rather than anything wrong with what's being
  deployed.

### Terraform died mid-apply

```
terraform plan                          # shows exactly what landed
terraform apply -replace=<failed-address>
```

**Plan first — never re-apply blind onto a half-applied state.** A partial
apply leaves real infrastructure in an inconsistent state relative to the
config; `plan` tells you precisely what Terraform believes is true right
now before you ask it to change anything further.

### Node NotReady — five suspects

```
systemctl status kubelet
journalctl -u kubelet | tail
df -h
free -m
systemctl status containerd
```

Kubelet down, disk full, memory exhausted, or the container runtime
(containerd) itself unhealthy — check all five before assuming the more
exotic cause.

### Everything down vs. one thing down

If `kubectl` itself is timing out, that's the control plane — go to the
node directly: `crictl ps -a`. If `kubectl` responds fine but services are
failing, that's the workload layer — back to Q3's request-path walk.

### The quiet killer sweep — certificates

```
echo | openssl s_client -connect <host>:443 2>/dev/null \
  | openssl x509 -enddate -noout
kubeadm certs check-expiration
```

Certificate expiry is the "quiet killer" because nothing changed in any
log you'd normally check — the cert was valid yesterday and isn't today,
purely from the calendar. **Date-clustered onset across unrelated
services is the tell**: if TLS failures start appearing across several
independent services at roughly the same moment, check expiry before
anything else.

---

## 8. Severity and communication cadence

### SEV1 / SEV2 / SEV3

- **SEV1** — mission service down, or a security event. Status every
  **30 minutes**, whether or not there's new information — silence during
  a SEV1 reads as "nobody's working it," which is its own problem
  independent of the technical one.
- **SEV2** — degraded, or redundancy lost (still up, but one bad event
  away from SEV1). **Hourly** status.
- **SEV3** — single user affected, or cosmetic. Ticket queue — no forced
  cadence.

**Solo-operator loop**: stabilize → communicate → capture → fix → verify →
write. Communication is not an afterthought bolted onto the technical work
— it's a step in the loop, in order, because stakeholders making decisions
during an incident need current information as much as the system needs a
fix.

### The boring six — check these first

1. Recent change
2. Certificate expiry
3. Disk full / inodes
4. DNS
5. Permissions (RBAC / IAM / SELinux)
6. Resource exhaustion

These are "boring" on purpose — none of them are interesting failure
modes, and that's exactly why they're first: the overwhelming majority of
real incidents trace back to one of these six, and checking all six takes
minutes. Reaching for an exotic hypothesis before ruling out the boring
six is a common way to burn thirty minutes chasing a theory when the
answer was `df -h` away.

### Blameless postmortem structure

Six fields, every time:

1. **Impact** — what broke, for whom, for how long, in concrete terms.
2. **Timeline** — what happened, in order, with timestamps.
3. **Root cause** — stated as **a condition, never a name**. "The
   deployment lacked a readiness probe, so traffic routed to pods before
   they could serve it" is a root cause. "Alex forgot to add a probe" is
   not — it's a person, and it doesn't generalize to preventing the next
   occurrence.
4. **What worked** — which part of the response held up, worth keeping.
5. **What didn't** — which part of the response was slow, wrong, or
   missing, stated as plainly as the failure itself.
6. **Actions, with owner and date** — not "we should improve monitoring
   here" as a vague aspiration, but a specific action assigned to a
   specific person with a specific date, or it doesn't happen.

---

## 9. Day-one checklist for this zone

If you inherit an environment's observability stack — which is the normal
case, not the exception — start here rather than trusting what the
dashboards claim to show:

1. **Find what's actually monitored versus what's silently unmonitored.**
   List every service, host, and scheduled job, and cross-check it against
   actual scrape targets (`Prometheus → Status → Targets`) and alert
   rules. A service with no scrape target isn't "monitored with nothing
   wrong" — it's unmonitored, full stop.
2. **Check alert routing actually reaches a human.** Trigger a test alert
   (or find the last time a real one fired) and trace it all the way
   through Alertmanager's routing tree to wherever it lands. An alert
   rule that's correctly defined but routed to a channel nobody watches,
   or an email address that bounces, is functionally identical to having
   no alert at all — and it's a common, easy-to-miss failure mode
   precisely because the *rule* looks fine on inspection.
3. **Verify dashboards reflect current architecture, not a stale one.**
   A dashboard built against last year's service topology (old service
   names, decommissioned components still queried, new components with no
   panel) actively misleads during an incident. Check that every panel's
   query still resolves against real, current label values.
4. **Identify log retention and access for when you need to dig.** Know
   where logs actually live (centralized ELK/Loki, or `kubectl logs`
   against ephemeral pod storage that's gone the moment the pod is), how
   far back retention goes, and who/what has query access — before an
   incident is the wrong time to be discovering that logs from three days
   ago were already rotated out.
5. **Confirm the scan-freshness pattern (Zone 9's `freshness.py`,
   documented in this repo's `playbook/`) has an observability-layer
   equivalent** — is there anything that would notice if the metrics
   scrape itself silently stopped, the way `freshness.py` notices when a
   scheduled scan silently stops? "Everything's green" and "nothing is
   reporting" render identically on a dashboard that isn't checking for
   the difference.
6. **Sanity-check one real metric against a known input**, the way §4's
   multiprocess bug was caught — generate a known quantity of traffic or
   events and confirm the dashboard shows that quantity, before trusting
   any of the numbers on it.

---

## 10. Incident response cheat sheet

A single scannable block — the Q1–Q4 flow plus the boring six, for the
moment you actually need it and don't have time to reread the chapter.

```
FIRST 120 SECONDS
  Q1 Blast radius?
    kubectl get pods -A | grep -v 'Running\|Completed'
    systemctl --failed ; kubectl get nodes ; df -h
    → one thing or everything? tell a second human, write it down.

  THE BORING SIX — check now, before anything clever
    1 recent change   2 cert expiry   3 disk/inodes
    4 DNS             5 permissions   6 resource exhaustion

NEXT
  Q2 What changed?  (highest-yield question — run all of these)
    kubectl get events -A --sort-by=.lastTimestamp | tail -30
    kubectl rollout history deployment/<n> -n <ns>
    helm history <rel> -n <ns>
    git log --oneline --since="24 hours ago"
    terraform plan -detailed-exitcode
    journalctl --since "-24h" -p warning | tail -40
    → nothing found = wrong layer, not no cause.

  Q3 Which layer?  (half-split the request path)
    DNS -> LB -> ingress -> service -> endpoints -> pod -> app
    dig <name> ; curl -v https://<host>/health
    kubectl get endpoints <svc> -n <ns>
    kubectl logs <pod> -n <ns> --previous
    → start at endpoints, split from there.

THEN — before any fix attempt
  Q4 Fastest safe rollback?
    helm rollback <release> -n <ns>
    kubectl rollout undo deployment/<n> -n <ns>
    git revert <sha> && git push
    → stabilize first, root-cause second.

RULES: read-only first · snapshot before touching · log the terminal
       (script -a) · one change at a time · escalate past 30 min with
       no hypothesis, or if the fix touches a security/ATO boundary.

COMMS: SEV1 = 30 min · SEV2 = hourly · SEV3 = queue.
POSTMORTEM: impact / timeline / root cause (a condition, never a name) /
            what worked / what didn't / actions with owner + date.
```

---

Zone 8 recipes — the exact PromQL queries, alert rules, provisioning
configs, and triage commands referenced throughout this chapter — are
collected for direct reuse in the book's toolkit appendix.


---


# Chapter 9 — Evidence & Govern

*Zone 9 of 9 in the DevSecOps playbook. Where the previous eight zones do the
engineering — scan, gate, harden, deploy — this zone converts that
engineering activity into accreditation evidence.*

## 1. Why this zone matters, especially for this job

Every zone before this one produces an *action*: a secret gets caught before
it's pushed, a container gets scanned, a Kubernetes cluster gets hardened to
a benchmark. `MASTER-PLAYBOOK.md` frames Zone 9 in one line worth quoting
directly, because it's the whole chapter in miniature: this zone turns
**"engineering activity turned into accreditation evidence."** An action
that happened but wasn't recorded, dated, and retrievable might as well not
have happened, from an auditor's point of view — and if you are reading this
book because you're studying for a GMD DevSecOps Engineer role at a company
like Valkyrie Enterprises, "an auditor's point of view" is not a hypothetical
future problem. It's the job.

Here is the reality of DoD-adjacent contracting that this zone exists to
serve: **a control isn't real until it's documented and auditable.** You can
run the most sophisticated STIG remediation pipeline in the world, but if
nobody can produce, on demand, the specific artifact proving rule
`SV-230222r743935_rule` passed on `2026-03-14` against `host-42`, that
control does not exist for accreditation purposes. This isn't bureaucratic
theater — it's how the government's Risk Management Framework (RMF) and the
Authority to Operate (ATO) process work. A system does not get to go live on
a DoD network until an Authorizing Official (AO) reviews a package of
evidence — STIG scan results, POA&Ms (Plans of Action and Milestones) for
open findings, SBOMs, vulnerability scan history, configuration baselines —
and signs off that the residual risk is acceptable. The ATO package *is* the
concrete artifact this whole zone produces. Everything else in this chapter
— SBOMs, waiver ledgers, evidence retention, maturity models — exists to
make that package buildable on demand instead of assembled in a two-week
fire drill the week before an assessment.

This is also the zone that most cleanly separates "we did security work"
from "we can prove we did security work," and a DevSecOps engineer who
cannot make that distinction plainly to a program manager or an assessor is
going to have a bad time in this specific industry. So the house rule for
this chapter, inherited from the rest of this book: no invented statistics,
no claimed verification that didn't happen, name every gap plainly. That
rule is not incidental to a chapter about evidence — it *is* the chapter's
subject matter, applied to itself.

## 2. SBOM fundamentals

A **Software Bill of Materials (SBOM)** is a manifest: a structured,
machine-readable list of every component that went into a shipped software
artifact — every direct dependency, every transitive dependency, often down
to the OS packages inside a container image. Think of it as the ingredient
label on a piece of software, except the label has to be complete or it's
useless.

The reason it matters is almost entirely reactive, and the trigger question
is always the same shape: **"Are we affected by CVE-2024-XXXXX?"** When a
critical vulnerability drops in, say, a logging library or a compression
utility, the organizations that answer that question in minutes are the ones
with SBOMs on file for every shipped artifact — they grep the manifest for
the package name and version, and they have their answer. The organizations
without SBOMs answer that question by paging every team, asking them to
manually check their `requirements.txt` or `package-lock.json` or container
base image, and hoping nobody misses a service. In a DoD-adjacent
environment, "we don't know if we're affected" is not an acceptable answer
to an AO or an incident response tasking, and it's genuinely not an
acceptable answer to a program manager either.

Two formats dominate: **CycloneDX** (originated in the OWASP ecosystem, JSON
or XML, strong on vulnerability and license metadata) and **SPDX** (Linux
Foundation project, also JSON or XML/tag-value, historically stronger on
license compliance, now an ISO standard). Neither is "more correct" — pick
one and be consistent, or generate both if your tooling and downstream
consumers require it. This repo's actual pipeline standardizes on
CycloneDX.

Generating one is a single command with **Syft**, the tool this repo
actually uses:

```
syft dir:. -o cyclonedx-json > sbom.json
```

That's the `FIELD-MANUAL.md` §3 scanner-cookbook form, run against a local
directory. The repo's live GitHub Actions pipeline
(`.github/workflows/security.yml`) runs the equivalent as a real, automated
step — not hand-run, not aspirational:

```yaml
- name: Generate SBOM (Syft)
  if: steps.reqs.outputs.found == 'true'
  uses: anchore/sbom-action@v0
  with:
    path: app/status-service
    format: cyclonedx-json
    output-file: sbom-status-service.cdx.json
    upload-artifact: true
```

This is worth being precise about, because it's exactly the kind of
precision an assessor will demand of you: **SBOM generation in this repo is
real, automated, and running on every CI trigger that touches
`app/status-service`.** It is a job step (`sbom-and-dependency-scan`) inside
`security.yml`, uploaded as a build artifact via `upload-artifact: true`.
That is a fully verified, currently-executing control. Section 3 below is
about a *different* piece of Zone 9 tooling — SBOM drift detection — which
is not yet verified against this repo's real containers, and the chapter is
going to be equally precise about that gap. Conflating "we generate SBOMs"
with "we diff SBOMs between releases and have proven the diff logic against
our own artifacts" is exactly the kind of overclaim an assessor will catch,
and exactly the kind this book refuses to make.

## 3. SBOM drift detection

Generating one SBOM per release is necessary but not sufficient. The
question that actually matters for supply-chain risk over time is: **what
changed?** A new dependency silently pulled in, a transitive dependency
quietly bumped three major versions, a package that disappeared between
releases because a maintainer yanked it — all of that is a supply-chain
changelog, and if you're not diffing SBOMs release-over-release, you're
finding out about that changelog only when something breaks or a CVE forces
the question.

This repo's tool for that is `playbook/sbom_diff.py`, and its logic is
genuinely simple and readable — it's a good teaching example of doing SBOM
diffing without reaching for a heavyweight framework:

```python
comps = lambda s: dict(mapMaybe(
    lambda c: (c["name"], c.get("version", "?")) if "name" in c else NOTHING,
    s.get("components", [])))

def main(old, new):
    a, b = (comps(json.loads(Path(p).read_text())) for p in (old, new))
    added   = sortOn(str, b.keys() - a.keys())
    removed = sortOn(str, a.keys() - b.keys())
    changed = sortOn(str, [(k, a[k], b[k]) for k in a.keys() & b.keys() if a[k] != b[k]])
```

It loads two CycloneDX documents, builds `{name: version}` maps out of each
`components[]` array, and set-diffs the keys: names only in the new SBOM are
`added`, names only in the old are `removed`, names in both with a different
version are `changed`. Run it:

```
sbom_diff.py sbom-old.json sbom-new.json
```

Output is a line per change (`+ name==version`, `- name==version`, `~ name
old -> new`) plus a one-line summary count, and it always exits 0 —
informational, not a gate (drift itself isn't a failure; an *unreviewed*
drift is a process problem, not a tool problem).

Now the honest part, and this is the single best worked example in this
whole book of the difference between "the logic is proven" and "the logic
is proven against my real artifacts." `playbook/README.md` documents exactly
this distinction for `sbom_diff.py`:

> `syft` is not installed in this environment (not on `PATH`), so this one
> is **not** re-verified against a real SBOM of this repo's containers — it
> ran only against the zip's demo fixtures (`sbom-old.json`/`sbom-new.json`),
> correctly reporting 1 added, 1 removed, 1 changed. Honest gap, not
> silently skipped.

Read that carefully, because it's the pattern to internalize for your own
evidence work, not just this one script. The demo-fixture run *did*
succeed, and it *did* correctly report the expected diff — that proves the
diff algorithm is correct. What it does not prove is that the tool produces
a correct, complete diff against this repo's own actual container SBOMs,
because the environment this verification happened in never had `syft`
installed to generate one. Those are two different claims, and conflating
them is exactly the kind of quiet overclaim that gets someone in trouble in
front of an assessor. The correct behavior — and the behavior this repo's
own documentation models — is: run what you can, state precisely what you
verified, and name the gap instead of hiding it or letting the reader
infer more confidence than the evidence supports. "I ran the tool against
demo fixtures and it's correct there; I have not yet run it against our real
release artifacts because the generator wasn't installed" is a complete,
honest, and *auditable* statement. An assessor can work with that. An
assessor cannot work with silence, and will trust you much less once they
discover silence was covering a gap.

## 4. The waiver ledger

No scan pipeline runs clean forever, and pretending every finding gets fixed
immediately produces one of two bad outcomes: either the gate blocks
legitimate work indefinitely, or someone quietly disables the gate. The
correct mechanism is a **waiver ledger** — an explicit, reviewed record of
accepted risk, not a bypass.

This repo's `playbook/waivers.json` is the concrete shape:

```json
[
  {"rule": "B602", "path": "app/run.py", "reason": "vetted subprocess use", "expires": "2026-12-31"},
  {"rule": "B105", "path": "", "reason": "expired example", "expires": "2025-01-01"}
]
```

Every entry needs four fields, and each one earns its place:

- **rule** — which specific finding is waived (a Bandit rule ID here; could
  be a CVE ID, a STIG rule ID, anything a scanner emits as a stable
  identifier). Never waive by description text — descriptions change
  between scanner versions, IDs don't.
- **path** — scope the waiver to the specific file or location. An empty
  path (as in the second example above) waives the rule everywhere, which
  is a much bigger blast radius and should be rare and deliberately chosen,
  not a default.
- **reason** — human-readable justification, reviewed like code. "vetted
  subprocess use" tells the next reviewer *why* someone decided this
  specific finding is acceptable risk, not just that someone clicked
  approve.
- **expires** — an ISO date, not a boolean. This is the field that makes
  the whole mechanism honest.

`FIELD-MANUAL.md` states the underlying principle bluntly: **"Timestamps in
waivers, not booleans: `expires` forces re-review; `permanent: true` is how
waivers become policy without anyone deciding."** This is worth sitting
with. An "accepted risk" that never expires isn't a risk decision at all —
it's an unaddressed finding wearing a green checkmark. Risk changes over
time: the threat landscape shifts, the code around the vetted subprocess
call gets refactored by someone who didn't know why it was vetted, a
dependency that was fine last year gets a CVE this year. An expiry date
forces someone to look at the waiver again and make a fresh decision, rather
than letting one person's judgment from eighteen months ago silently govern
forever.

Two more design principles worth carrying into any real program you run:

- **Two-approval rules for policy loosening.** Widening a waiver's scope,
  extending an expiry, or raising a gate's tolerance threshold should never
  be a single person's unilateral action — it's a policy decision, and
  `FIELD-MANUAL.md`'s lifecycle map explicitly separates "Plan" phase policy
  definition from day-to-day gate operation for exactly this reason. Treat
  waiver-ledger changes like the code review they are: PR-reviewed, not
  edited in place on a shared branch.
- **Expired waivers reactivate automatically.** This is the design
  principle that makes the whole ledger trustworthy rather than aspirational
  paperwork: the moment the `expires` date passes, the waived finding goes
  back to counting against the gate as if the waiver never existed — no
  human has to remember to revoke it. `MASTER-PLAYBOOK.md`'s Zone 9 entry
  states this as a load-bearing behavior of the system, and it's what
  prevents "we'll revisit this waiver" from quietly becoming "we forgot
  about this waiver forever." The second entry in the example ledger above
  — `expires: "2025-01-01"`, well in the past relative to this book's
  writing date — is exactly the state a live system should surface loudly:
  an expired-but-present waiver, waiting to be either re-justified or
  dropped, not silently honored.

Every scan summary should surface a `waived:` count so the number is visible
in the same place as pass/fail counts — a waiver ledger nobody looks at is
functionally the same as no waiver ledger.

## 5. Evidence retention

A scan that ran and produced results that nobody kept is, for audit
purposes, indistinguishable from a scan that never ran. Retention policy is
therefore not a storage-hygiene afterthought — it's the mechanism that makes
every other control in this book *provable* later.

The pattern this repo's playbook documents: **SARIF + SBOM + summaries
archived per run**, with two different retention windows for two different
purposes:

- **30 days in CI** — the short-lived, high-volume evidence: every PR's
  SARIF output, every branch build's dependency scan. This window exists to
  answer "what did the last few weeks of development look like" and to give
  triage and debugging a recent history, without paying to store every
  transient CI run forever.
- **Per-release, forever** — the evidence tied to something that actually
  shipped. A release's SBOM, its gate summary, its STIG/CIS scan snapshot —
  these need to survive as long as the artifact they describe might still
  be running somewhere, which for a DoD-adjacent system can be years. An
  ATO is typically reauthorized on a cycle (commonly three years, though
  continuous monitoring is increasingly the expectation under newer RMF
  guidance) — evidence has to outlive not just the release, but the
  authorization period built on top of it.

The payoff for getting this right is concrete and operational, not just
audit-theater: the question **"do we ship X?"** — some vulnerable package,
some deprecated library, some component under a newly-discovered CVE —
should be answerable by grepping stored SBOMs across releases, not by
polling engineers' memories or re-cloning old branches to regenerate
manifests after the fact. `MASTER-PLAYBOOK.md` states this explicitly as the
retention policy's reason for existing: the blast-radius question gets
answered from stored evidence, not institutional memory. Institutional
memory leaves the company; stored evidence doesn't.

## 6. STIG as flagship evidence

This is where Zone 5 (the technical hardening/scanning zone) and Zone 9 meet
directly, and it's worth walking the connection explicitly because it's the
clearest real example this repo has of a technical control becoming
accreditation evidence.

`stig/README.md` documents a real, scored OpenSCAP XCCDF evaluation: `oscap`
1.3.9 running DISA's own published SCAP Security Guide content for RHEL 8
(`ssg-rhel8-ds.xml`, profile
`xccdf_org.ssgproject.content_profile_stig`) against a genuine RHEL 8
filesystem (Red Hat's UBI8 base image, exported and probed offline via
`OSCAP_PROBE_ROOT`). The scored result:

```
   67 PASS
   51 FAIL
  286 notapplicable
    5 notchecked
 1163 notselected
----
  409 rules actually in scope for the STIG profile (67+51+286+5)
```

That is Zone 5's output — a technical scan against a real filesystem,
producing a real pass/fail count. Zone 9's job is what happens to that
output next: it becomes evidence, in three forms this repo actually
produces and retains —

- **`scap-results.xml`** (gzipped, 1.3MB compressed) — the machine-readable
  XCCDF results, the canonical artifact an automated evidence pipeline or a
  downstream tool would ingest.
- **`scap-report.html`** — the self-contained human-readable report,
  including every rule's DISA rationale text, exactly the form an AO or a
  security control assessor (SCA) would actually read during a package
  review.
- **`fail-rules.txt`** — the specific list of the 51 failing rule IDs, which
  is the seed of a POA&M: each failing rule ID becomes a line item with an
  owner, a remediation plan, and a target date, which is precisely what an
  ATO package's Plan of Action and Milestones document is built from.

This is exactly the kind of artifact a real ATO package needs, and it's
worth naming precisely why the *unremediated* baseline is the honest and
correct first deliverable rather than something to be embarrassed about.
`stig/README.md`'s own framing: all 51 failures are genuine, expected gaps
in an unconfigured base image — PAM password-complexity policy
(`pam_faillock`, `pam_pwquality`), crypto policy not set to
`DISA_STIG` (`update-crypto-policies --set DISA_STIG` is the real fix), RPM
integrity checks not enforced. None of that is a flaw in the pipeline; it's
the accurate, honest state of a stock base image before site-specific
hardening is applied. A real STIG compliance program runs exactly this
sequence: **baseline first** (scan, unremediated, score it honestly), **then
remediate** (apply `--remediate` or an Ansible role built from SSG's
published remediation playbooks), **then re-scan** to show the FAIL count
drop as a documented delta. That before/after pair — not the baseline alone
— is what eventually goes in front of an AO. A baseline with no remediation
plan is an admission; a baseline with a dated remediation plan and a
re-scan showing progress is exactly the evidence trail RMF continuous
monitoring wants to see. `stig/README.md` names the missing remediation pass
as an honest, undone next step rather than glossing over it — that's the
correct posture for evidence documentation generally, and it's the posture
this chapter has been modeling throughout.

## 7. Compliance maturity models

Zone 9 closes its own loop with a maturity self-assessment, and
`FIELD-MANUAL.md` §8 gives a concrete, four-level ladder rather than an
abstract maturity-model diagram. In plain English:

- **L1 — Scan.** The absolute floor: secrets scanning, SAST, and dependency
  audit run on every pull request, plus a weekly scheduled scan so CVEs
  disclosed against unchanged code don't rot silently. If you're at L1,
  you're finding things; you're not yet controlling what happens after you
  find them.
- **L2 — Gate.** A single policy chokepoint (one place that decides
  pass/fail, not five inconsistent ad-hoc checks), waivers with expiry (not
  permanent bypass flags), and a regression test proving the gate actually
  fails on known-bad input (a "dirty fixture" test — if your gate has never
  been proven to fail, you don't know it works). L2 is where "we scan
  things" becomes "we enforce a decision."
- **L3 — Supply chain.** SHA-pinned GitHub Actions (not tag-pinned — tags
  are mutable), pinned and bot-bumped dependencies, an SBOM generated per
  release, and signed artifacts (cosign or equivalent). L3 is where you stop
  trusting that your build inputs are what you think they are and start
  proving it cryptographically.
- **L4 — Operate.** Hardening baselines (STIG/CIS) automated rather than
  run by hand once, scan freshness actively monitored (something alerts if
  the weekly cron silently stopped firing), incident response roles named
  in advance rather than improvised during an incident, and SBOM-driven
  blast-radius lookup (the "do we ship X" question from Section 5,
  answerable in minutes). L4 is where evidence generation stops being a
  project and becomes an operating characteristic of the system.

How to honestly self-assess where a given control sits: don't grade the
zone as a whole — grade each control against the checklist line it
actually satisfies, and be willing to sit at different levels for different
controls simultaneously. This repo's own honest state is a useful worked
example: dependency/secret/SAST scanning on every PR is solidly L1-L2 (gated,
waivers with expiry, a proven dirty-fixture regression test);
SHA-pinning is a named, open L3 gap (21 `uses:` lines are tag-pinned, not
SHA-pinned — `playbook/README.md` reports this as a genuine finding, not
fixed, not hidden); SBOM generation is L3 (real, automated, per-build);
SBOM *diffing* is proven-on-fixtures but not yet L3-complete against real
artifacts (Section 3); the STIG baseline is a real L4-shaped artifact but
without the remediate-and-rescan delta that L4 operational maturity
implies. That's not one maturity score — it's a checklist with some boxes
checked, some half-checked, and some honestly unchecked, which is the only
honest way a maturity self-assessment should ever look. `MASTER-PLAYBOOK.md`
itself models this same discipline at the whole-playbook level: it reports
"29 plays, 14 executed, zero zones at zero" rather than claiming full
coverage, and names the two zones (1 and 6) with no executed play instead of
omitting them.

## 8. Day-one checklist for this zone

If you inherit or start a real DevSecOps Evidence & Govern function, here is
where to begin, in order:

1. **Find where SBOMs and scan evidence are actually archived, and for how
   long.** Check CI artifact retention settings (GitHub Actions defaults to
   90 days unless configured otherwise — don't assume it matches your
   intended policy), and separately confirm whether per-release evidence
   has a *different*, longer-lived home (a release-tagged artifact store,
   an evidence bucket, a document management system tied to the ATO
   package) rather than living only inside CI's own retention window.
2. **Audit every existing waiver for expired-but-still-active status.**
   Pull the waiver ledger and check every `expires` date against today.
   Anything already past its date and still suppressing a finding is either
   silently broken tooling (should be reactivating automatically — verify
   it actually does) or an unreviewed risk acceptance that's overdue for a
   real decision.
3. **Identify what compliance framework the organization is actually
   accountable to.** Don't assume — ask directly, and get it in writing if
   possible: NIST SP 800-53 controls under RMF, a specific DoD Instruction
   (8510.01 governs the RMF process itself), CMMC level if this is a
   contractor context, FedRAMP if there's a cloud-hosted component. The
   controls you need evidence for, and the format an assessor expects, both
   depend entirely on which framework governs.
4. **Confirm SBOM generation is actually wired into the pipeline for every
   shipped artifact**, not just the one service someone set it up for first
   — check every container/service that ships, not just the one with an
   existing `security.yml` job.
5. **Locate the most recent STIG/CIS (or equivalent hardening) scan for
   every system in scope, and check its age.** A scan from eight months ago
   is a stale baseline, not current evidence — RMF continuous monitoring
   expects recency, not a one-time snapshot.
6. **Ask directly whether a POA&M exists, and whether it's current.** Every
   known open finding (every STIG FAIL, every unwaived scan finding past
   its intended fix date) should have a line in it with an owner and a
   target date. If it doesn't exist yet, the STIG `fail-rules.txt`-style
   list from Section 6 is exactly the seed to build one from.

## 9. Troubleshooting quick-reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Auditor asks "prove you scanned X on date Y" and you can't find the artifact | Retention window too short, or evidence was never separated from short-lived CI storage | Fix retention policy going forward (per-release evidence to permanent storage, not just CI's 30-90 day default); for the immediate gap, be honest that the artifact doesn't exist rather than reconstructing a fake one — a documented gap with a fix date is recoverable, a fabricated artifact is not |
| A waiver expired silently and nobody noticed | No automated surfacing of the `waived:` count in scan summaries, or the reactivation logic was never actually verified to work | Confirm gate logic truly treats an expired waiver as absent (test it against a deliberately-expired fixture, the same "dirty fixture" discipline as L2); add the expired-waiver count to every summary output, not just total findings |
| SBOM generation succeeds but produces an empty or incomplete manifest | Syft ran against the wrong path (e.g., a monorepo root with no manifest file at that exact location), or a private/vendored dependency isn't resolvable so its entry gets silently dropped | Check the tool's own exit output/logs for skipped-package warnings, not just exit code 0; run `syft dir:. -o cyclonedx-json` and manually spot-check a known dependency's presence before trusting automation over a new path |
| Evidence retention policy conflicts with storage cost | Treating all evidence as one tier (everything kept forever, or everything on a short CI window) instead of the two-tier model | Apply the two-window pattern from Section 5 deliberately: short CI window for high-volume per-PR evidence, permanent (or authorization-cycle-length) retention only for per-release evidence — this is a policy decision to make explicitly with stakeholders, not a default to inherit silently |

---

Runnable recipes for this zone — `sbom_diff.py` usage, the waiver ledger
JSON shape, and the `syft`/`oscap` command forms referenced throughout this
chapter — are collected in the book's toolkit appendix.


---


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
