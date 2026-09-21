# DevSecOps Field Manual

Comprehensive companion to `PLAYBOOK.md` (the 2-page ops card). That file is
the contract; this one is doctrine, scanner cookbook, tips, and environment
troubleshooting. Everything gate-related here is executable — the 8 scripts
ship alongside and were run before this was written.

---

## 1. Doctrine

1. **Shift left, but gate center.** Scanners run everywhere (editor, pre-commit,
   CI); *enforcement* happens at exactly one chokepoint (`gate.py`) so policy
   lives in one JSON file, not scattered across job definitions.
2. **Exit codes are the API.** 0 clean, 1 findings, 2 bad input. Any tool that
   can't express itself that way gets wrapped until it can.
3. **Normalize, then judge.** Every scanner funnels to one summary shape
   (`{tool, total, by_level, top_rules, worst}`). New scanner = new adapter,
   never new gate logic.
4. **Waivers over exceptions.** Accepted risk gets a rule, path, reason, and
   expiry — visible in the summary, auto-reactivating. A gate without waivers
   gets bypassed; a bypass is invisible risk.
5. **Partial data is Maybe, bad input is Either, verdicts are monoids.**
   Malformed SARIF entries drop out (`doM`), unreadable files short-circuit
   loudly (`doE`), pass/fail folds (`mconcat All`).
6. **Verified before presented.** No claimed output that wasn't executed.
   Applies to scan results, doc examples, and this manual.

## 2. Lifecycle map

| Phase   | Control                                  | Tooling here                         |
|---------|------------------------------------------|--------------------------------------|
| Plan    | Threat model, policy definition          | `policy.json`, waiver review         |
| Code    | Pre-commit secrets/pins                  | `pipeline.sh` (stages 1-2), gitleaks |
| Build   | SAST, dependency CVEs, SBOM              | bandit→`triage.py`, `cve.py`, syft   |
| Test    | Unit + property tests, coverage          | pytest, Hypothesis                   |
| Release | Supply chain: pinning, signing, SBOM diff| `actions_pin.py`, cosign, `sbom_diff.py` |
| Deploy  | IaC + container + k8s scan, hardening    | trivy/tfsec/kube-linter→`triage.py`, STIG/CIS |
| Operate | Observability, weekly rescans, IR        | metrics/logs/traces stack, cron scans|

Weekly scheduled scans matter: CVEs are disclosed against *unchanged* code, so
a repo that only scans on push silently rots.

## 3. Scanner cookbook

### gitleaks (secrets)
    gitleaks detect --source . --report-format sarif --report-path out.sarif
- Needs **full history**: `fetch-depth: 0` (Actions) / `GIT_DEPTH: 0` (GitLab).
  Shallow clone = silent partial scan, the worst failure mode.
- False positive → `.gitleaksignore` with the finding's fingerprint, or an
  allowlist regex in `.gitleaks.toml`. Never delete the rule.
- A found secret is **compromised the moment it lands in history**. Revoke
  first; history rewrite (`git filter-repo`) is cleanup, not remediation.
- Pre-commit hook: `gitleaks protect --staged` — scans the index only, fast.

### bandit (Python SAST)
    bandit -r app -f sarif -o out.sarif --exit-zero     # artifact pass
    bandit -r app -ll -x '**/tests/**'                  # gating pass
- Two-pass pattern: `--exit-zero` so the SARIF always uploads, then a severity-
  filtered pass for the verdict (or drop the second pass and let `gate.py` decide).
- B101 (assert) fires all over test suites → exclude tests, don't waive.
- Suppress inline with `# nosec B603` + a comment saying why; bare `# nosec`
  should itself be a lint failure.

### pip-audit (dependency CVEs)
    pip-audit -r requirements.txt -f json --no-deps -o audit.json
- `--no-deps` audits exactly what's pinned; omit it and unpinned specs trigger
  full resolution (slow, network-heavy, can pick a different version than prod).
- Requires pins to be meaningful — run `deps.py` first; unpinned + audit = you
  audited a version you may not ship.
- Offline/air-gap: `--index-url` at your mirror; cache with `--cache-dir`.

### syft / grype (SBOM + CVEs)
    syft dir:. -o cyclonedx-json > sbom.json
    grype sbom:sbom.json -o sarif > grype.sarif
- Generate the SBOM once, scan the SBOM — decouples inventory from CVE lookup
  and gives `sbom_diff.py` its input for free.
- Store SBOMs as release artifacts; the diff between releases is your
  supply-chain changelog.

### trivy (containers, IaC)
    trivy image --format sarif -o trivy.sarif IMAGE
    trivy config --format sarif -o iac.sarif infra/
- DB downloads from ghcr.io on every cold run — cache it
  (`trivy image --download-db-only` in a warm-up step) or mirror via
  `TRIVY_DB_REPOSITORY` in restricted networks.
- `trivy config` absorbed tfsec; one binary for images + Terraform + k8s YAML.

### kube-linter / CIS
    kube-linter lint k8s/ --format sarif > kube.sarif
- Lints manifests pre-deploy; CIS benchmark (kube-bench) audits the *running*
  cluster — different phase, keep both.

All of the above emit SARIF or JSON → `triage.py`/`cve.py` → `gate.py`.
That's the whole integration story.

## 4. Supply chain

- **Pin actions to SHAs** (`actions_pin.py`). Tags are mutable; `@v4` today is
  not `@v4` after a maintainer compromise (see: multiple 2024-25 action
  hijacks). Pair with Renovate/Dependabot so SHAs don't fossilize.
- **Pin dependencies** (`deps.py`) + automate bumps. Pins without a bump bot
  trade supply-chain risk for CVE rot — you need both halves.
- **Sign artifacts**: `cosign sign-blob` (keyless via OIDC in CI) on release
  artifacts; verify at deploy. SBOM + signature + provenance = SLSA direction.
- **Least-privilege tokens**: top-level `permissions: contents: read`, widen
  per-job only (`security-events: write` for SARIF upload). Fork PRs don't get
  secrets — design secret-needing jobs to skip, not fail, on forks.

## 5. Hardening & operate (pointers, not scripts)

- OS baseline: STIG track (see repo `stig-README`); automate checks with
  OpenSCAP, remediate with Ansible — hand-hardening doesn't survive reimaging.
- Cluster baseline: k8s CIS benchmark track (repo `k8s-cis-benchmark-README`).
- Detection: the observability stack (metrics/logs/traces, repo
  `observability-README`) is the security telemetry substrate — auth failures,
  egress anomalies, and scan-job health are just more time series.
- IR minimum: know *before* the incident who revokes credentials, who can
  force-push history rewrites, and where the SBOMs are (blast-radius lookup).

## 6. Tips & tricks

- `--exit-zero` + separate gate beats letting scanners self-gate: you keep the
  artifact even on failure, and thresholds live in policy, not CLI flags.
- Give every SARIF upload a distinct `category:` — same category from two jobs
  clobbers results in code scanning.
- `concurrency: cancel-in-progress: true` on scan workflows: stale scans of
  dead commits waste minutes and confuse "latest" status.
- Seed a deliberately-dirty fixture tree (`demo/`) and assert the pipeline
  FAILS on it. A gate that can't fail is decoration. This is the playbook's
  own regression test.
- Sort findings deterministically (`sortOn`) — diffable scan output turns
  "what changed" into `diff old new`.
- Cap detail output (`text[:80]`) in secret findings: the report must not
  itself become a secret exfiltration channel.
- Timestamps in waivers, not booleans: `"expires"` forces re-review;
  `"permanent": true` is how waivers become policy without anyone deciding.
- DockerHub anonymous pulls are rate-limited per-IP; shared CI runners hit it
  randomly. Authenticate or mirror; "flaky" image pulls usually aren't flaky.
- Renovate the scanners themselves — a 2-year-old bandit misses 2 years of rules.

## 7. Troubleshooting environments

### 7.1 WSL (your dev loop)
| Symptom | Cause | Fix |
|---|---|---|
| `bash\r: command not found`, scripts fail only on Linux | CRLF endings from Windows-side edits | `.gitattributes`: `* text=auto eol=lf`; `git config core.autocrlf input` |
| TLS/cert errors, apt/pip failures after laptop sleep | WSL2 clock skew | `sudo hwclock -s`; recent WSL: `wsl --shutdown` resyncs |
| Everything under `/mnt/c` is mode 777, git shows phantom mode changes | DrvFs metadata off | `/etc/wsl.conf` → `[automount] options="metadata,umask=022"`; or keep repos in the ext4 home |
| Builds 10-50x slower than expected | Repo on `/mnt/c` (9P filesystem) or Defender scanning | Move repo into WSL home; add Defender exclusion for `\\wsl$` paths |
| DNS dies on VPN | Auto-generated resolv.conf fights the VPN | `[network] generateResolvConf=false` + static resolv.conf |
| Docker unavailable in WSL | Desktop integration toggle per-distro | Docker Desktop → Resources → WSL integration |

### 7.2 CI runners
| Symptom | Cause | Fix |
|---|---|---|
| gitleaks finds nothing, ever | shallow clone | `fetch-depth: 0` / `GIT_DEPTH: 0` |
| `cmd \| tee log` "passes" despite failure | pipe masks exit code | `set -o pipefail`; note Actions' default `run:` shell is `bash -e` **without** pipefail — set `shell: bash` explicitly to get `-o pipefail` |
| `PIPESTATUS: bad substitution` | job image runs `sh`/dash, not bash | bash-capable image, or restructure without PIPESTATUS |
| SARIF upload 403 | missing permission | job-level `security-events: write` |
| Two tools' results overwrite each other | same SARIF category | unique `category:` per tool |
| Scheduled scans silently stop | GH disables cron on 60d-inactive repos | keep-alive commit or manual re-enable; monitor scan-job freshness as a metric |
| Secrets empty on PR builds | fork PRs get no secrets by design | skip secret-needing steps on forks; never `pull_request_target` + checkout of PR head |
| trivy cold-start timeout | DB pull from ghcr each run | cache DB dir between runs; `TRIVY_DB_REPOSITORY` mirror |

### 7.3 Python environments
| Symptom | Cause | Fix |
|---|---|---|
| `externally-managed-environment` on pip install | PEP 668 (Debian/Ubuntu 23+) | venv per job (preferred) or `--break-system-packages` in throwaway containers |
| pip-audit takes minutes / OOMs | resolving unpinned specs | pin first (`deps.py`), then `--no-deps` |
| Hash mismatch on install | mirror serving stale wheel, or requirements hash-pinned against different platform | regenerate hashes with `pip-compile --generate-hashes` on the target platform |
| Works locally, differs in CI | different Python patch / resolver picked another version | pin interpreter (`python-version: "3.12"`) and everything else |

### 7.4 Restricted / air-gapped networks (defense-relevant)
- Mirror indexes (devpi/Artifactory for PyPI, registry proxy for OCI), point
  tools at mirrors via `--index-url`, `TRIVY_DB_REPOSITORY`, grype's
  `GRYPE_DB_UPDATE_URL`.
- Vulnerability DBs are the hard part offline: schedule a connected host to
  export DBs (`trivy --download-db-only`, `grype db export`) and ferry them in.
- Vendor wheels: `pip download -r requirements.txt -d wheels/` connected-side,
  `--no-index --find-links wheels/` inside.
- Egress allowlists: proxies that strip or fail silently are indistinguishable
  from tool bugs — check the proxy's deny header/log *first* when a tool that
  worked yesterday can't download today.

### 7.5 Gate-failure runbook
1. `gate.py` prints the failing summary file and the violated rule — start there.
2. Detail lives beside the summary (`.scan-out/*.detail.txt`, scanner stderr).
3. Decide: **fix** (preferred), **waive** (rule+path+reason+expiry into
   `waivers.json`, PR-reviewed like code), or **tune policy** (rare; policy
   changes are org decisions, not unblock buttons).
4. Re-run `./pipeline.sh` locally before pushing — the gate is deterministic,
   so local green = CI green modulo environment (see 7.1-7.4).

## 8. Maturity checklist

- [ ] L1 Scan: secrets + SAST + dep audit on every PR, weekly cron
- [ ] L2 Gate: single policy chokepoint, waivers with expiry, dirty-fixture regression test
- [ ] L3 Supply chain: SHA-pinned actions, pinned+bot-bumped deps, SBOM per release, signed artifacts
- [ ] L4 Operate: hardening baselines (STIG/CIS) automated, scan freshness monitored, IR roles named, SBOM-driven blast-radius lookup

