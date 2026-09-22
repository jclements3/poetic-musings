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
