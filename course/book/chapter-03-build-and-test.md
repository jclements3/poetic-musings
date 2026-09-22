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
