# DEFSECOPS.md — DevSecOps / Platform Engineering training log

This document records what was built in this repo to exercise the skills listed in a
**Senior DevSecOps / Platform Engineer** job description, what each piece demonstrates,
and what genuinely can't be simulated in a hobby repo (and how it maps to the real job
anyway). Use it as a study guide, not just a changelog.

poetic-musings is an FPGA/hardware/music project — it has no cloud footprint of its own.
Everything below is a bolt-on "Internal Developer Platform" (IDP) demo layer: a small
real service, containerized and deployed with real manifests, provisioned by real
Terraform, gated by a real CI/CD security pipeline. None of it has been applied to a
live cloud account — it's built to be correct and reviewable, not to run in production.

---

## 1. Terraform / Infrastructure-as-Code — `infra/terraform/`

**What's there:** a root module wiring an `aws-platform` module and an `azure-platform`
module together, with `dev`/`prod` environment tfvars reusing the same modules, remote
state strategy documented (S3+DynamoDB, with the Azure Storage backend alternative
noted), and provider versions pinned.

- `aws-platform`: VPC with public/private subnets across 2 AZs, ECR repo (KMS-encrypted,
  immutable tags, scan-on-push), S3 artifact bucket (versioned, SSE-KMS, public-access
  blocked, `BucketOwnerEnforced`) plus a *separate* access-log bucket, a rotating KMS CMK,
  and an IAM role for CI scoped to exact resource ARNs (not `*`).
- `azure-platform`: resource group, Premium ACR (admin disabled, public network access
  disabled), GRS storage account (TLS 1.2 minimum, shared-key auth disabled, versioning +
  soft delete), private container, and a comment block documenting how this would hook
  into on-prem Windows AD via Azure AD Connect (password hash sync, seamless SSO,
  group-based RBAC) — see §5, this is the part that can't be built here.

**Validation status:** `terraform`, `tfsec`, `checkov` are not installed on this machine.
Validated by hand (brace-balance across all 15 `.tf` files, provider-version-correct
attribute names — caught and fixed one `azurerm` 3.x vs 4.x attribute-name mismatch).
Machine validation (`terraform fmt/validate`, `tfsec`, `checkov`) now runs in CI — see §3.

**What this demonstrates / study points:**
- Encrypt-by-default, not opt-in (SSE-KMS everywhere, TLS 1.2 minimum).
- Deny public access explicitly at the resource level rather than trusting defaults.
- Least-privilege IAM scoped to specific resource ARNs with an externally-supplied trust
  principal, not wildcard trust.
- Immutable + scanned container images (`IMMUTABLE` tags, `scan_on_push`) as a
  supply-chain control, not just a registry setting.
- Consistent tagging (`Project`/`Environment`/`Owner`/`ManagedBy`) for cost allocation and
  policy enforcement — this is also how CIS-style governance gets enforced at scale.
- Separation of duties in state/logging: dedicated log bucket, remote state with locking
  instead of local `.tfstate` files (which would leak secrets into git).
- Same module tree, different tfvars per environment — the core "don't copy-paste your
  infrastructure" IaC pattern.

**Real-job gap:** in production this would run against real AWS/Azure accounts with SSO
federation, org-level SCPs/Azure Policy, and a state backend with actual locking under
concurrent CI runs. Here it's structurally correct but never `apply`'d.

---

## 2. Containerized service + Kubernetes — `app/status-service/`, `k8s/`

**What's there:** a real Flask app (`app.py`) serving this repo's `STATUS.md` as HTML and
JSON, with `/healthz` (liveness, no I/O) and `/readyz` (readiness, checks the file
exists). Pinned dependencies (`flask==3.0.3`, `gunicorn==22.0.0`). A hardened multi-stage
Dockerfile: `python:3.12-slim` builder → slim runtime, non-root uid/gid 10001, no apt
packages, `HEALTHCHECK`, runs under gunicorn.

Kubernetes manifests under `k8s/base/` (Kustomize) + `overlays/dev` (1 replica) and
`overlays/prod` (3 replicas, pinned tag):
- Deployment: resource requests/limits, non-root `securityContext`,
  `readOnlyRootFilesystem: true` with an `emptyDir`-backed `/tmp` (gunicorn needs
  *somewhere* writable — this is the real-world reconciliation between "hardened" and
  "the process still needs to run"), `drop: ALL` capabilities,
  `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`, liveness/readiness
  probes.
- Service, three `NetworkPolicy` objects (default-deny, then explicit ingress on 8080,
  then explicit DNS egress) — least-privilege networking rather than one big rule.
- `PodDisruptionBudget` (`minAvailable: 1`) paired with the 3-replica prod overlay, so a
  voluntary node drain/upgrade can't take the whole service down at once.

**Validation status:** Docker was available and used — `docker build` succeeded, and
`docker run --read-only --tmpfs /tmp --user 10001:10001 ...` was run against the built
image to prove the container actually works under the same constraints the Kubernetes
`securityContext` imposes (this caught the `/tmp` issue above — the first run failed with
`FileNotFoundError: No usable temporary directory` before the `emptyDir` mount was added).
No `kubectl`/`kind`/`kubeval` on this machine, so manifests were validated via
`yaml.safe_load_all` (all parse) and `docker run registry.k8s.io/kustomize/kustomize
build` against both overlays (both render cleanly — this also caught a deprecated
`commonLabels` field that needed to become `labels`). Real `kubectl apply --dry-run`
against a live/kind cluster was not run (no cluster available).

**What this demonstrates / study points:**
- Non-root at both layers (image *and* pod `securityContext`) — defense in depth against
  container escape.
- Pod Security Standards "restricted" profile in practice: capability dropping, no
  privilege escalation, seccomp, read-only root FS — not just CPU/memory requests.
- NetworkPolicy as default-deny-then-allow, including locking egress down to just DNS.
- Kustomize base + overlays: one source of truth, environment-specific patches, no
  manifest duplication.
- PodDisruptionBudget as the HA control that's easy to forget — protects against
  *voluntary* disruption (node drains, cluster upgrades), which is different from crash
  recovery.

**Real-job gap:** a real IDP would deploy this via GitOps (Argo CD/Flux) into an actual
EKS/AKS cluster with an ingress controller, cert-manager for TLS, and cluster-level
policy enforcement (OPA/Gatekeeper or Kyverno) rather than `kubectl apply` by hand.

---

## 3. CI/CD security pipeline — `.github/workflows/`, `SECURITY.md`

**What's there:** `ci.yml` (lint with ruff, conditional pytest) and `security.yml`, a
scan pipeline that runs on push/PR to main plus a weekly Monday cron:

| Stage | Tool | Fails build on |
|---|---|---|
| Secrets detection | gitleaks (full git history, not just the diff) | any finding |
| SAST | bandit over `app/` + root `*.py`, SARIF → code scanning | medium/high |
| SBOM | Syft, CycloneDX format | — (artifact only) |
| Dependency scan (SCA) | pip-audit against `requirements.txt` | known CVEs |
| Container scan | Trivy against the built image | HIGH/CRITICAL |
| IaC scan | tfsec against `infra/terraform/` | SARIF → code scanning |
| K8s manifest scan | kube-linter against `k8s/` | lint failures |

Every job that touches a path owned by another part of the platform (Dockerfile,
Terraform, k8s manifests) checks the path exists first and no-ops with a summary note if
not — so the pipeline is safe to land incrementally rather than needing everything to
exist atomically.

Least-privilege `permissions:` blocks (`contents: read` repo-wide, `security-events:
write` only on jobs that upload SARIF), and third-party actions pinned to a specific
version/tag rather than `@main`. `SECURITY.md` documents the vulnerability-reporting
process and summarizes the scanning above for anyone auditing the repo.

**Validation status:** `actionlint` not installed; both workflow YAML files parsed
cleanly with `yaml.safe_load`, and job/step structure, `permissions:` blocks, and action
pinning were hand-reviewed.

**What this demonstrates / study points:**
- "Shift left": secrets/SAST run before anything expensive (build/scan), and full-history
  gitleaks catches a secret committed three commits ago, not just in today's diff.
- Defense-in-depth *pipeline staging*: cheap checks (lint, secrets) fail fast before
  expensive ones (container build + scan) even start.
- SBOM + SCA are two different questions answered together: SBOM = "what's in this
  artifact" (attestable, exportable), SCA/pip-audit = "does any of it have a known CVE."
- The container image is scanned as its own artifact *after* build, not assumed safe
  because the source passed SAST.
- "Security as code" extends past application code to the IaC and K8s manifests that
  provision and run it — tfsec and kube-linter are the same category of check as bandit,
  just aimed at a different layer.
- Centralizing SARIF into GitHub code scanning gives one pane of glass instead of N
  separate job logs nobody reads.
- CI credentials follow least privilege exactly like the AWS IAM role in §1 does — scoped
  permissions per job, not a blanket token.

**Real-job gap:** this is GitHub Actions because that's what the repo has; the job
description calls out GitLab CI/Jenkins/Azure DevOps specifically. The *concepts*
transfer directly — same stages, same gating logic, different YAML dialect. Worth
rebuilding this same pipeline in Azure DevOps or GitLab CI once in an Azure/GitLab
environment, specifically to get the dialect differences under your fingers.

---

## 4. What's covered vs. what's a real gap

| JD requirement | Status here |
|---|---|
| Terraform IaC | Built (§1) — structurally correct, never applied to a live account |
| Kubernetes at scale | Built (§2) — manifests validated, no live cluster to prove HA/scaling under load |
| CI/CD pipelines with security scanning | Built (§3), on GitHub Actions |
| Hybrid cloud sysadmin (AWS + Azure) | Partially — both providers' Terraform written; no live account, no actual cross-cloud networking/IAM federation exercised |
| Windows AD / GPO / MECM / Intune | **Not built — see §5** |
| CIS hardening baselines | Applied *ad hoc* throughout (§1, §2) but not run against a formal CIS Benchmark profile/scanner |
| SAST / SBOM / dependency / container / secrets scanning in CI | Built (§3) |
| Coder (managed dev environments) | **Not built — see §5** |
| Cloud/Kubernetes/security certs (CKA, CKS, Security+, AWS/Azure) | N/A — certifications, not something a repo can demonstrate |

## 5. Deliberate gaps and how to close them

These require infrastructure this repo genuinely cannot host, and are noted here so
they're not silently missing from the study plan:

- **Windows Server / Active Directory / GPOs / endpoint management (MECM/SCCM, Intune):**
  no Windows domain exists in this environment. The Azure Terraform module documents
  *where* this would attach (Azure AD Connect, password hash sync, group-based RBAC
  feeding into ACR/storage access), but the actual AD forest, GPO design, and
  MECM/Intune policy work need a real (or lab) Windows Server environment — e.g. a home
  lab VM running Server + a domain controller, or a free-tier Azure AD/Entra tenant with
  a couple of test VMs joined to it. This is the single largest hands-on gap for the JD
  and the one most worth a dedicated lab session.
- **Coder (managed dev environments):** no Coder deployment here. Coder itself deploys
  onto Kubernetes (there's a Helm chart) — the `k8s/` cluster patterns in §2 (NetworkPolicy,
  PodSecurityStandards, resource limits) are directly reusable as the security baseline
  for a Coder workspace template; standing up Coder itself against a real or kind cluster
  is the next concrete exercise.
- **Formal CIS Benchmark scanning:** the hardening choices in §1/§2 (encryption at rest,
  non-root containers, network default-deny, least-privilege IAM) are CIS-*aligned* by
  construction, but nothing here runs an actual CIS Benchmark scanner (e.g. AWS Config
  conformance packs, Azure Policy's CIS initiative, or `kube-bench` for a live cluster)
  against a live account/cluster to produce a scored compliance report. That needs a real
  account and a real cluster, respectively.
- **GitLab specifically:** the JD calls out GitLab CI, repos, and backlog management by
  name; this repo is on GitHub. `.gitlab-ci.yml` at the repo root now mirrors
  `security.yml`/`ci.yml` stage-for-stage (lint → test → security: gitleaks, bandit,
  syft+pip-audit, trivy, tfsec, kube-linter), with `rules: exists:` standing in for the
  GitHub version's path-existence no-ops, and notes on GitLab's managed
  SAST/Secret-Detection/Dependency-Scanning/Container-Scanning templates as the
  production alternative to hand-rolling each tool. It's only been YAML-syntax
  validated locally (no GitLab runner here) — pushing it to a real GitLab.com project and
  watching it run is still the actual exercise; this file is scaffolding for that, not a
  substitute for it. Also still worth getting comfortable with GitLab's MR/backlog UI
  directly, which no config file will teach.

---

*This document reflects the state of the repo as of 2026-09-19. Files: `infra/terraform/`,
`app/status-service/`, `k8s/`, `.github/workflows/`, `SECURITY.md`.*
