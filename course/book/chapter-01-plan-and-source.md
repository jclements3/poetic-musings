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
