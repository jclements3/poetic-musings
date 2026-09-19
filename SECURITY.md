# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it
privately rather than opening a public issue:

- Open a [GitHub Security Advisory](../../security/advisories/new) for this
  repository ("Report a vulnerability" under the Security tab), or
- Email the maintainer directly with a description of the issue, steps to
  reproduce, and any relevant logs or proof-of-concept.

Please include:

- Affected component/path (e.g. `app/status-service`, `infra/terraform`, an
  FPGA/Clash package, etc.)
- Impact and severity, as you assess it
- Reproduction steps or a minimal example

You should expect an initial acknowledgment within a few days. This is a
hobby/portfolio project maintained on a best-effort basis, so response and
fix timelines are not guaranteed, but reports are taken seriously and
triaged as soon as practical.

Please do not exploit any finding beyond what is necessary to demonstrate
it, and give a reasonable amount of time to remediate before any public
disclosure.

## Automated Scanning in This Repository

This repository runs continuous security scanning via GitHub Actions
(`.github/workflows/ci.yml` and `.github/workflows/security.yml`) on every
push and pull request to `main`, plus a weekly scheduled run:

- **Secrets detection** — [gitleaks](https://github.com/gitleaks/gitleaks)
  scans the full git history for committed secrets and fails the build on
  any finding.
- **Static application security testing (SAST)** — 
  [bandit](https://github.com/PyCQA/bandit) scans Python sources under
  `app/` and the repo root for common insecure coding patterns; results are
  uploaded to GitHub code scanning as SARIF.
- **Software bill of materials (SBOM) & dependency scanning** —
  [Syft](https://github.com/anchore/syft) generates a CycloneDX SBOM for
  `app/status-service`, and [pip-audit](https://github.com/pypa/pip-audit)
  checks its dependencies against known vulnerability databases.
- **Container image scanning** — the `app/status-service` Docker image is
  built in CI and scanned with [Trivy](https://github.com/aquasecurity/trivy),
  failing on HIGH/CRITICAL findings; results are uploaded to code scanning.
- **Infrastructure-as-code (IaC) scanning** — 
  [tfsec](https://github.com/aquasecurity/tfsec) scans `infra/terraform` for
  misconfigurations, with results uploaded to code scanning.
- **Kubernetes manifest scanning** — 
  [kube-linter](https://github.com/stackrox/kube-linter) checks manifests
  under `k8s/` for security and correctness issues.
- **Build/lint/test** — Python sources are linted with
  [ruff](https://github.com/astral-sh/ruff) before any security jobs run.

Workflows use least-privilege `permissions:` blocks scoped per job, pin
third-party GitHub Actions to a specific version, and upload tool findings
to the repository's **Security > Code scanning alerts** tab (SARIF) where
supported, so results are visible without digging through job logs.
