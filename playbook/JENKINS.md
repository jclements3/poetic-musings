# Jenkins — third dialect of the poetic-musings pipeline

`Jenkinsfile` mirrors `.github/workflows/{ci,security}.yml` and `gitlab-ci.yml`
stage-for-stage. Mastery here = reading all three side by side until the
translation is mechanical. **Not executed in this environment** (no Jenkins
controller); validate against your local instance before trusting it — see
Validation below.

## Rosetta stone

| Concept | GitHub Actions | GitLab CI | Jenkins (declarative) |
|---|---|---|---|
| Pipeline definition | workflow yml | `.gitlab-ci.yml` | `Jenkinsfile` |
| Unit of work | job | job | stage |
| Execution host | `runs-on` runner | runner + `image:` | `agent { docker { image } }` |
| Reuse | `uses:` actions | `include:` templates | plugins + shared libraries |
| Secrets | `secrets.X` | CI/CD variables | `credentials()` / `withCredentials` |
| Conditional job | `if:` / paths filter | `rules: exists/if` | `when { expression { fileExists } }` |
| Schedule | `on.schedule.cron` | pipeline schedules (UI) | `triggers { cron('H 6 * * 1') }` |
| Cancel stale runs | `concurrency: cancel-in-progress` | `interruptible: true` | `disableConcurrentBuilds(abortPrevious: true)` |
| Artifacts | `upload-artifact` | `artifacts:` | `archiveArtifacts` |
| Cache | `actions/cache` | `cache:` | nothing native — Job Cacher plugin, or a mounted volume |
| Job dependency | `needs:` | `needs:` / stages | sequential stages; `parallel {}` for fan-out |
| Full-history clone | `fetch-depth: 0` | `GIT_DEPTH: 0` | `git fetch --unshallow` (or job-level clone config) |

## Local bring-up (practice loop)

    docker network create jenkins
    docker run -d --name jenkins --network jenkins \
      -p 8080:8080 -p 50000:50000 \
      -v jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      jenkins/jenkins:lts-jdk17
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

- Install docker CLI inside the controller image (or build a derived image)
  so `agent { docker }` works: plugins **Docker Pipeline**, **Git**,
  **Credentials Binding**, **Timestamper**.
- Socket-mount (above) vs true DinD: socket is simpler and standard for labs;
  it also means pipeline containers are siblings, not children — `$PWD` volume
  mounts refer to *host* paths, the classic trivy-in-docker confusion.
- New Item → Multibranch Pipeline → point at the repo; Jenkins finds
  `Jenkinsfile` per branch, the analog of Actions discovering workflow files.

## Validation

    # declarative linter over HTTP (crumb needed if CSRF on):
    curl -s -X POST -u user:token -F "jenkinsfile=<Jenkinsfile" \
      http://localhost:8080/pipeline-model-converter/validate
    # or via CLI:
    java -jar jenkins-cli.jar -s http://localhost:8080 -auth user:token \
      declarative-linter < Jenkinsfile

Linter checks syntax/structure only — path guards and tool flags still need a
real run against the repo. Replay button on a build = edit-and-rerun without
committing; the fast iteration loop.

## Jenkins-specific gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Docker-agent stage hangs at start, no output | image has an ENTRYPOINT; Jenkins runs `docker run ... IMAGE cat` and the entrypoint eats it | `args '--entrypoint='` (see gitleaks/tfsec/kube-linter stages) |
| `Permission denied` writing workspace in docker agent | Jenkins passes `-u uid:gid` of the jenkins user; image expects root | `args '-u root'` for lab use; fix image user for real use |
| gitleaks finds nothing | git plugin shallow/refspec-limited clone | `git fetch --unshallow`; or configure clone depth 0 on the job |
| `NotSerializableException` mid-pipeline | CPS: scripted-block local vars must survive restarts | keep non-serializable objects inside `script {}` scope or `@NonCPS` helpers; declarative steps mostly avoid this |
| `RejectedAccessException` on Groovy call | script security sandbox | approve in *In-process Script Approval* — sparingly; each approval is attack surface |
| cron fires for every branch at once | literal minutes in cron | use `H` hashing (`H 6 * * 1`) — Jenkins spreads jobs deterministically |
| Stage reuses stale files from last run | workspaces persist per-agent, unlike fresh CI VMs | `cleanWs()` in a `post { always }` or start of stage — the single biggest GH-Actions-habit trap |
| Builds run on the controller | default `agent any` with no agents defined | in anything real: 0 executors on controller, all work on agents |
| `$PWD` mount empty in tool container | socket-mounted docker = sibling container; `$PWD` is a controller-container path the host can't see | mount a shared host path, or run tools directly in the agent image |

## Mastery drills (maps to QRG functions 3.1–3.5)

1. **3.1 Pipeline** — run the Jenkinsfile green on the repo; diff its console
   log against an Actions run of the same commit.
2. **3.2 Path-filtered jobs** — break `app/status-service`, confirm only the
   guarded stages react in all three dialects.
3. **3.3 Inject a secret** — `withCredentials([string(credentialsId:...)])`;
   confirm masking in the log, then confirm gitleaks catches the same value
   if committed.
4. **3.4 Schedules** — set the cron 5 minutes out, watch the triggered build,
   note `H` expansion in the job config.
5. **3.5 Artifacts & cache** — pull `bandit.sarif` from the build page; add
   Job Cacher for pip and measure the second-run delta.
6. Wire the playbook gate: add a stage running
   `python3 tools/triage.py .scan-out/bandit.sarif > .scan-out/bandit.summary.json`
   then `python3 tools/gate.py tools/policy.json .scan-out/*.summary.json` —
   the chokepoint is dialect-independent, which is the point.
