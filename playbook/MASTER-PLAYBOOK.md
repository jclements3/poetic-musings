# DevSecOps Playbook — poetic-musings

**Scope statement.** Complete against the repo's own spec — the QRG's 9 zones —
as of 2026-09-21. Not comprehensive in the absolute: no fixed document survives
tool churn (tfsec was absorbed by trivy inside this playbook's own references).
Re-audit this document against the QRG quarterly; the zone table below is the
audit checklist. Plays marked **[run]** were executed before this was written;
**[cfg]** is pipeline config not executable in the authoring environment —
validate before trusting; **[proc]** is a procedure, not a script.

Exit contract for every script: **0** clean, **1** findings, **2** bad input.

---

## Zone 1 — PLAN & SOURCE

- **[proc] Policy as reviewed code.** `policy.json` and `waivers.json` change
  only by PR; a waiver PR must contain rule, path, reason, expiry. Reviewer
  checklist: is the expiry ≤ 90 days? does the reason name a compensating
  control? Policy loosening is an org decision — two approvals, not one.
- **[proc] Branch protection.** `main` requires: the security pipeline green,
  no force-push, no direct commits. The gate is only a gate if the branch
  rules make it unavoidable.

## Zone 2 — DEVELOP

- **[run] Pre-commit gate** — `playbook/pre-commit`: runs `secrets.py` +
  `deps.py` before anything leaves the workstation. Verified twice: first in
  an isolated scratch repo (blocks a staged AWS key, exit 1; passes a clean
  tree, exit 0), then installed for real at poetic-musings'
  `.git/hooks/pre-commit` (scoped to `app/ infra/ k8s/ ansible/ playbook/`,
  same reason `secrets.py` skips `ad-lab/` — see playbook/README.md). Install:
  `cp playbook/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`
- **[proc] Workspace hygiene** — WSL table in FIELD-MANUAL §7.1: LF-only
  `.gitattributes`, repo in ext4 home not `/mnt/c`, clock resync after sleep.
  A standardized workspace (Coder) supersedes this table; until then the
  table is the workspace standard.

## Zone 3 — BUILD

- **[run] `pipeline.sh`** — local runner, stages 1–4, same order as CI.
- **[run] GitHub Actions / GitLab CI** — `workflow-{ci,security}.yml`,
  `gitlab-ci.yml`: live in the repo, badge-verified.
- **[cfg] `Jenkinsfile`** — third dialect, stage-for-stage mirror; lint it via
  `/pipeline-model-converter/validate` before first use (JENKINS.md).
- **[proc] Air-gap build** — FIELD-MANUAL §7.4: mirrored indexes, ferried
  vuln DBs, vendored wheels.

## Zone 4 — TEST

- **[run] Dirty-fixture regression** — `./pipeline.sh demo` MUST exit 1
  (2 seeded secrets, 3 unpinned deps, gate FAIL). A gate that cannot fail is
  decoration; this play proves the gate can.
- **[proc] Test-suite gating** — pytest wired in all three dialects;
  Hypothesis property tests complement, never replace, example-based tests.

## Zone 5 — SECURE

| Play | Does | Status |
|---|---|---|
| `secrets.py` | credential patterns over the tree | [run] 2/2 seeded demo findings; re-run against poetic-musings' `app/ infra/ k8s/ ansible/` — 0 findings (clean) |
| `deps.py` | parser-combinator pin audit | [run] 3 unpinned flagged on demo fixture; re-run against `app/status-service/requirements.txt` — 3 pinned, 0 unpinned (clean) |
| `cve.py` | pip-audit JSON → gate summary | [run] 10 seeded CVEs gated on demo fixture; re-run against a live `pip-audit -r app/status-service/requirements.txt` — 0 CVEs (clean) |
| `actions_pin.py` | SHA-pin audit of workflows | [run] 21 tag-pinned `uses:` findings across the real `.github/workflows/ci.yml` + `security.yml` (none of this repo's Actions are SHA-pinned yet — a real, open gap) |
| `triage.py` | any SARIF → summary, waiver-aware | [run] waiver + expiry verified on demo fixture; re-run against a real `bandit -r app -f sarif` output — 0 findings (clean) |
| `gate.py` | single policy chokepoint | [run] all 3 exit paths confirmed for real: 0 (pass, real bandit summary), 1 (fail, demo summary vs policy.json), 2 (bad input, missing file) |
| scanner cookbook | gitleaks/bandit/pip-audit/syft/grype/trivy/kube-linter | FIELD-MANUAL §3 |

## Zone 6 — PROVISION

- **[cfg] IaC validate/plan job** — add beside the tfsec scan in each dialect:

      # GitHub Actions / GitLab script body / Jenkins sh — identical body:
      terraform -chdir=infra/terraform init -backend=false -input=false
      terraform -chdir=infra/terraform validate
      terraform -chdir=infra/terraform fmt -check -recursive

  `-backend=false` needs no credentials — every commit gets syntax + schema
  validation even with no live account. `plan` requires state/creds: run it
  only in the environment that owns them, never on fork PRs.
- **[proc] IaC verbs drill** — QRG 6.1–6.4: init → validate → plan → apply →
  drift check (`plan` on unchanged code) → module extraction. Already proven
  once against live AWS (build log §1); the play is re-running it, not
  re-reading it.
- **[proc] Config management** — Ansible idempotency standard: cold run
  changed>0, warm rerun changed=0, asserted in CI not in a README.

## Zone 7 — DEPLOY & ORCHESTRATE

- **[run] Manifest schema gate** — kubeconform against the k8s schemas;
  verified: valid deployment passes, `replicas: "two"` + missing selector
  rejected (exit 1). One binary, no cluster needed:

      kubeconform -summary k8s/

- **[proc] Pre-deploy order** — kubeconform (schema) → kube-linter (policy,
  zone 5) → `kubectl apply --dry-run=server` (admission, needs a cluster) →
  apply. Cheapest check first, each layer catches what the previous can't.

## Zone 8 — OPERATE & OBSERVE

- **[run] `freshness.py`** — scan-freshness monitor: alerts when scheduled
  scans silently stop (the cron-disabled-after-60d failure mode). Verified:
  3-day-old summary flagged at a 48h threshold.
- **[proc] Gate-failure runbook** — FIELD-MANUAL §7.5: summary → detail →
  fix / waive / policy-change, local re-run before push.
- **[proc] Incident cadence** — QRG: SEV1 30-min comms, SEV2 hourly, SEV3
  queue; boring-six first (change, certs, disk, DNS, permissions, resources);
  blameless postmortem, root cause is a condition never a name.

## Zone 9 — EVIDENCE & GOVERN

- **[run] `sbom_diff.py`** — component drift between releases; the
  supply-chain changelog.
- **[run] Waiver ledger** — accepted risk with expiry, surfaced in every
  summary (`waived:` count); expired waivers reactivate automatically.
- **[proc] Evidence retention** — SARIF + SBOM + summaries archived per run
  (30d in CI, per-release forever); blast-radius question "do we ship X?"
  answered from stored SBOMs, not memory.
- **[proc] Maturity audit** — FIELD-MANUAL §8 checklist L1–L4, quarterly,
  same cadence as this document's re-audit.

---

## Zone coverage after this revision

| Zone | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Plays | 2 | 2 | 4 | 2 | 7 | 3 | 2 | 3 | 4 |
| Executed | 0 | 1 | 2 | 1 | 6 | 0 | 1 | 1 | 2 |

29 plays, 14 executed, zero zones at zero. The two zones with no executed play
(1, 6) are process-bound and credential-bound respectively — named, not hidden.
