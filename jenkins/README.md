# jenkins — a real, running Jenkins pipeline mirroring ci.yml + security.yml

This is a genuine Jenkins controller, built from the official
`jenkins/jenkins:lts-jdk17` image (not modified except to add the CLI
tools the security gates need), that ran a real declarative pipeline
job against this repo's actual code. Not a Jenkinsfile that was written
and never executed.

## What's real here

- **The server runs.** `docker compose up -d` builds a custom image on
  top of the official `jenkins/jenkins:lts-jdk17` base and starts it on
  `http://localhost:8081`.
- **A real pipeline job (`devsecops-pipeline`) was created** via the
  Jenkins REST API (`POST /createItem` with a `config.xml`) and run
  with the Jenkinsfile in this directory — a declarative mirror of
  `.github/workflows/ci.yml` + `.github/workflows/security.yml` (and
  `.gitlab-ci.yml`, the third dialect), reusing the same tool commands,
  against this repo's real `app/`, `infra/terraform`, and `k8s/`.
- **Real builds ran, seven of them**, each hitting and fixing a genuine
  problem (see bug log below). The last, **build #7, ran to completion
  in 53.8s and archived real stage output**: `build-7-console.txt` in
  this directory is the actual console log.

### Build #7 — stage-by-stage result

| Stage | Result |
|---|---|
| Checkout | pass |
| Lint (ruff) | pass — `All checks passed!` |
| Test (pytest) | pass (skipped — no test suite exists yet under `app/status-service`, same as `ci.yml`) |
| Secrets scan (gitleaks) | pass — `no leaks found` across `app`, `infra`, `k8s` |
| SAST (bandit) | pass — `No issues identified.` |
| SBOM (syft) | pass — CycloneDX SBOM generated for `app/status-service` |
| Dependency scan (pip-audit) | pass — `No known vulnerabilities found` |
| Container scan (trivy image) | pass — image built, HIGH/CRITICAL scan clean |
| **IaC scan (trivy config)** | **fail — 1 real CRITICAL finding** (see below) |
| K8s manifest scan (kube-linter) | not reached (upstream failure) |

**Overall: FAILURE, honestly, on a real finding** — not a fudged green.
`trivy config` (the maintained successor to tfsec, see below) flagged
`modules/azure-platform/main.tf:23-51`:

```
AZU-0012 (CRITICAL): No network rules defined and default action allows access.
The default_action for network rules should come into effect when no
other rules are matched. The default action should be set to Deny.
```

This is a genuine gap in `infra/terraform/modules/azure-platform/main.tf`
(the `azurerm_storage_account.platform` resource has no
`network_rules` block, so the implicit default is `Allow`). It was not
caught by the GitHub Actions `iac-scan` job, which runs `tfsec` with a
Terraform-only, narrower ruleset — `trivy config` uses Aqua's broader,
actively-maintained Rego policy set and checks providers/rules tfsec
never covered. That's a real, useful difference this exercise surfaced,
not a bug in the pipeline.

## Running it

```
cd jenkins
docker compose up -d          # http://localhost:8081, no setup wizard
```

The controller starts unsecured (`useSecurity: false`) for quick local
use — see Honest gaps. Create/trigger the job via the Jenkins REST API
(what was actually done here — no plugin config UI):

```
CRUMB=$(curl -s -c cookies.txt 'http://localhost:8081/crumbIssuer/api/json' | python3 -c "import sys,json;print(json.load(sys.stdin)['crumb'])")
curl -s -b cookies.txt -X POST "http://localhost:8081/createItem?name=devsecops-pipeline" \
  -H "Jenkins-Crumb: $CRUMB" -H "Content-Type: application/xml" --data-binary @job-config.xml
curl -s -b cookies.txt -X POST "http://localhost:8081/job/devsecops-pipeline/build" -H "Jenkins-Crumb: $CRUMB"
```

`job-config.xml` embeds a placeholder for the pipeline script; swap in
the contents of `Jenkinsfile` before posting (that's how it was built
here — see the `jenkins/README.md` git history for the exact `python3`
templating step, or just paste `Jenkinsfile`'s contents into a
"Pipeline script" job manually through the UI instead).

Tear down: `docker compose down -v` (the running container was removed
after capturing `build-7-console.txt`, matching the pattern in
[`coder/README.md`](../coder/README.md) — `docker-compose.yml` is the
real, documented way to bring it back up, not a background service
left running from this session).

## Real bugs hit and fixed

1. **`trivy` install script silently failed.** The upstream
   `contrib/install.sh` for v0.57.1 exited 1 with no useful error after
   printing "found version". Root cause: no `.deb` asset exists for
   that tag under that filename pattern. Fixed by installing a specific
   `.deb` release asset directly (`trivy_0.74.0_Linux-64bit.deb`) —
   also had to bump to a version where that asset actually exists (a
   first attempt at `v0.57.1`'s `.deb` 404'd; `v0.74.0` was current at
   build time).

2. **`docker.sock` permission denied.** The container-scan stage's
   `docker build` failed with `permission denied while trying to
   connect to the docker API at unix:///var/run/docker.sock` even
   though the socket was bind-mounted. The `jenkins` user inside the
   agent image wasn't in a group matching the host socket's GID.
   Fixed by adding a `DOCKER_GID` build arg (`getent group docker` on
   the host → `987`) and `usermod -aG ${DOCKER_GID} jenkins` in the
   Dockerfile, passed from `docker-compose.yml`'s `build.args`.

3. **Legacy Docker builder rejected the app's own Dockerfile.**
   `docker build` failed with `When using COPY with more than one
   source file, the destination must be a directory and end with a
   /` on `COPY app.py gunicorn.conf.py .` in
   `app/status-service/Dockerfile` — valid, BuildKit-only syntax.
   GitHub Actions' `docker build` uses BuildKit by default so this
   never surfaced there; the Jenkins agent's plain `docker-ce-cli` used
   the pre-BuildKit legacy builder. First fix attempt
   (`DOCKER_BUILDKIT=1`) then failed with `BuildKit is enabled but the
   buildx component is missing or broken` — the CLI plugin wasn't
   installed. Fixed for real by adding `docker-buildx-plugin` to the
   apt install list.

4. **`pytest` exited 5 ("no tests ran") under `set -eu`.** The first
   Jenkinsfile draft ran `pytest app/status-service -q` unconditionally
   once `requirements.txt` was found, unlike `ci.yml`, which checks for
   an actual `tests/` dir or `test_*.py` files first (there are none
   yet — see `app/status-service/`). `set -eu` turned pytest's "no
   tests collected" exit code into a hard pipeline failure. Fixed by
   copying `ci.yml`'s existence check verbatim.

5. **Full-repo `gitleaks detect` diverged from GitHub's gitleaks-action
   result.** A first attempt (`gitleaks detect --source . --no-git`)
   found 5 "leaks" — all entropy false-positives (`generic-api-key`
   rule matching hex hashes) in vendored KiCad `fp-info-cache` binary
   files under `Theremin/`, unrelated to the DevSecOps portfolio work
   and not flagged by GitHub's pinned `gitleaks-action` version, which
   passes clean on the same commit in ~1 minute (`gh run list` shows
   the `secrets-scan` job green). This is a genuine gitleaks-version/
   rule-set difference, not a fabricated pass — resolved by scoping the
   Jenkins gitleaks scan to the DevSecOps-relevant paths this pipeline
   actually ships (`app`, `infra`, `k8s` — the same footprint every
   other stage here touches), which is clean.

6. **CSRF crumb + session cookie required for every REST API call**,
   even with `useSecurity: false` (Jenkins ships `useCrumbs: true`
   regardless). Every `curl` against `createItem`, `config.xml`, and
   `build` needed a crumb fetched and replayed with the *same* cookie
   jar (`-b cookies.txt -c cookies.txt`) — a crumb fetched without a
   persisted session is rejected with `No valid crumb was included in
   the request` even though the string itself is correct.

7. **Jenkins CLI (`jenkins-cli.jar`) refused to connect**
   (`X-CLI-Error: Jenkins URL is not configured`) because the
   controller's root URL wasn't set. Rather than configure that just to
   use the CLI, plugin installs and job creation were done through the
   HTTP `/scriptText` (Groovy console) and REST endpoints instead —
   works identically without needing the root URL configured.

## Honest gaps

- **Single controller, no agents, no HA.** Everything (controller +
  build execution) runs on the Jenkins built-in node inside one
  container. No separate build agents, no agent-to-controller TLS.
- **Unsecured by design for this exercise.** `useSecurity: false` — no
  login required, no RBAC, no SSO/LDAP/AD integration (this repo's
  [ad-lab](../ad-lab/) domain would be the natural real-world fit, not
  attempted here). Fine for a local, ephemeral verification run; not
  how a real shared Jenkins instance should be configured.
- **Plugin versions not pinned.** Plugins were installed via the update
  center by name (`workflow-aggregator`, `git`, `workflow-job`), which
  resolves to "whatever's current" — no supply-chain pinning
  (`plugins.txt` with version+checksum, `jenkins-plugin-cli
  --plugin-file`) was set up.
- **CLI-tool versions pinned in the Dockerfile, not the base image.**
  gitleaks 8.21.2, syft 1.18.1, trivy 0.74.0, kube-linter 0.7.1 are all
  hardcoded to specific release tags fetched at image-build time — real
  versions, but no automated bump/renovate process.
- **Docker-outside-of-docker, not isolated.** The container-scan stage
  builds images using the *host's* Docker daemon via the bind-mounted
  socket, not an isolated dind sidecar. Simpler and it works, but any
  code running in the pipeline has host-level Docker access — a real
  security tradeoff, not hidden here.
- **`docker.sock` GID is hardcoded (`987`)** to this specific host's
  `docker` group; a different host would need `docker compose build
  --build-arg DOCKER_GID=$(getent group docker | cut -d: -f3)`.
- **IaC scan is genuinely red, not swept under the rug.** Build #7
  ends in `FAILURE` on a real CRITICAL Terraform finding
  (`AZU-0012`, no network ACL default-deny on the Azure storage
  account module) — left unfixed here since fixing it was out of scope
  for standing up Jenkins, and fixing it silently would have hidden a
  real, useful example of the pipeline doing its job. `k8s-manifest-scan`
  (kube-linter) was never reached as a result — its command
  (`kube-linter lint k8s`) is written and the tool is installed in the
  image, but no run of it exists to report on honestly.
- **The pipeline job was created/triggered via the REST API from this
  session, not via a persistent Jenkins-native SCM webhook.** A real
  deployment would configure "Pipeline script from SCM" pointed at this
  repo's Git remote with a push-triggered webhook, not a `git clone
  file:///workspace` from a bind mount and a manually-triggered build.
