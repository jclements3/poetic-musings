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
| STIG evaluation, analysis, implementation | Covered — real, scored run | `stig/` (`oscap` vs DISA's RHEL8 STIG profile: 67 PASS / 51 FAIL, unremediated baseline) |
| Security/code scanning embedded in CI/CD | Covered — 7 real gates | Dashboard "Security Scanning Gates" table: gitleaks, bandit, Syft, pip-audit, Trivy, tfsec, kube-linter, CodeQL |
| IDE experience, e.g. Coder | Covered — real deploy | `coder/` (verified running: login page, `/healthz`, `/api/v2/buildinfo`) |
| Config management on top of IaC (implied — Ansible not explicit in posting but standard for this stack) | Covered — real, idempotent | `ansible/` (twice-run proof: `changed=1` cold, `changed=0` warm) |

## Named gaps not claimed as covered

- **STIG remediation not applied** — the `stig/` scan shows the
  *unremediated* baseline only (67 PASS / 51 FAIL against DISA's RHEL8
  STIG profile via `oscap`, scanning a real UBI8/RHEL8 filesystem, since
  no official DISA STIG content exists for Ubuntu/Debian). A real
  before/after remediation pass (`oscap xccdf eval --remediate` or an
  SSG-published Ansible remediation role, re-scanned) is the natural next
  step, not done here. See `stig/README.md` for the full honest breakdown.
- **Azure actually applied** — written, never run against a live
  subscription.
- **Real Windows Server + domain-joined client + SCCM** — Samba4 proves the
  AD mechanism (Kerberos, LDAP, DNS, GPO object/linkage), not the
  Windows-specific administration surface or SCCM itself.
- **Jenkins, Azure DevOps** — not represented; only GitHub Actions and
  GitLab CI.
- **CompTIA Security+, active clearance** — personal credentials, not
  something a repo can demonstrate.
