# Job requirement coverage — GMD DevSecOps Engineer (Valkyrie Enterprises, Job ID 4472)

Tracks which technical requirements from this specific posting are actually
demonstrated in this repo, and which are honest, named gaps. Updated as work
lands — see `git log` for when each item below was closed.

## Requirement → repo mapping

| Job requirement | Status | Where |
|---|---|---|
| Terraform for complex IaC deployments | Covered — real applied+verified | `infra/terraform/` (AWS applied & destroyed for real; KMS/CloudWatch bug caught and fixed) |
| Kubernetes: build, deploy, manage, HA/resilience | Covered — real cluster | `k8s/` manifests deployed to a real `kind` cluster; PDB, anti-affinity, NetworkPolicy |
| CI/CD pipelines (GitLab CI, Jenkins, Azure DevOps) | Partial — GitHub Actions + GitLab CI real; no Jenkins, no Azure DevOps | `.github/workflows/`, `.gitlab-ci.yml` |
| Hybrid cloud: AWS **and** Azure | Partial — AWS applied for real; Azure written only, never applied (no subscription) | `infra/terraform/modules/azure-platform/` |
| Windows Server admin, AD, GPOs, SCCM | Partial — real AD DC (Samba4), real GPO object+link, real Kerberos; no Windows Server itself, no domain-joined client, no real SCCM/MECM | `ad-lab/` |
| STIG evaluation, analysis, implementation | In progress | `stig/` |
| Security/code scanning embedded in CI/CD | Covered — 7 real gates | Dashboard "Security Scanning Gates" table: gitleaks, bandit, Syft, pip-audit, Trivy, tfsec, kube-linter, CodeQL |
| IDE experience, e.g. Coder | Covered — real deploy | `coder/` (verified running: login page, `/healthz`, `/api/v2/buildinfo`) |
| Config management on top of IaC (implied — Ansible not explicit in posting but standard for this stack) | Covered — real, idempotent | `ansible/` (twice-run proof: `changed=1` cold, `changed=0` warm) |

## Named gaps not claimed as covered

- **STIG** — DISA STIG is a distinct standard from CIS Benchmark (kube-bench
  covers CIS, not STIG). Being closed now via OpenSCAP/`scap-security-guide`
  in `stig/` — see that directory's README for real scored results and
  honest caveats once landed.
- **Azure actually applied** — written, never run against a live
  subscription.
- **Real Windows Server + domain-joined client + SCCM** — Samba4 proves the
  AD mechanism (Kerberos, LDAP, DNS, GPO object/linkage), not the
  Windows-specific administration surface or SCCM itself.
- **Jenkins, Azure DevOps** — not represented; only GitHub Actions and
  GitLab CI.
- **CompTIA Security+, active clearance** — personal credentials, not
  something a repo can demonstrate.
