# k8s — status-service manifests

Kustomize layout for `app/status-service`:

```
k8s/
  base/                  Deployment, Service, NetworkPolicy, PodDisruptionBudget
  overlays/dev/          1 replica, image tag "demo"
  overlays/prod/         3 replicas, pinned registry image tag
```

Render either overlay with:

```sh
kustomize build k8s/overlays/dev
kustomize build k8s/overlays/prod
```

(Validated locally in this session with `registry.k8s.io/kustomize/kustomize:v5.4.3`
via `docker run`, since no `kubectl`/`kustomize` binary was installed on the
host. Both overlays build cleanly with no warnings.) Apply with:
`kubectl apply -k k8s/overlays/dev` (or `--dry-run=client` first) once a
cluster is available.

## Hardening choices and why

**Non-root user (`runAsNonRoot: true`, `runAsUser/runAsGroup: 10001`)**
The image itself creates and runs as a dedicated unprivileged system user
(no login shell, no home directory). If the app is ever compromised, the
attacker doesn't get root inside the container, and the pod-level
`securityContext` refuses to even start the container as root as a second
line of defense.

**`readOnlyRootFilesystem: true`**
The container filesystem can't be modified at runtime, which blocks a large
class of "drop a payload and execute it" attacks and any accidental writes
to the image. The one thing gunicorn needs to write (worker heartbeat files)
is redirected to a small `emptyDir` mounted at `/tmp`, not to root itself —
so the filesystem stays locked down everywhere else.

**`capabilities: drop: [ALL]` and `allowPrivilegeEscalation: false`**
The service needs zero Linux capabilities (no raw sockets, no chown, no
binding privileged ports — it listens on 8080, not 80). Dropping all of them
and disallowing setuid-style privilege escalation removes an entire category
of container-breakout techniques even if a vulnerability is found in a
dependency.

**`seccompProfile: RuntimeDefault`**
Applies the container runtime's default syscall filter, cutting off rarely
needed syscalls that are common building blocks in kernel exploits.

**Resource requests/limits**
Requests (50m CPU / 64Mi memory) let the scheduler place the pod sensibly;
limits (250m / 128Mi) stop a runaway or DoS'd instance from starving other
workloads on the node — important for a shared-cluster "good neighbor"
posture, and standard practice for demonstrating stability discipline.

**Liveness + readiness probes**
`/healthz` (liveness) is a pure process check with no I/O, so it won't
falsely report a dead process during a transient disk hiccup. `/readyz`
(readiness) checks the actual dependency (status file readable), so the
Service only routes traffic to pods that can genuinely serve it — this is
what makes rolling updates and node drains safe.

**NetworkPolicy: default-deny + explicit allow**
Three policies: one sets `policyTypes: [Ingress, Egress]` with no rules,
denying everything by default for pods matching this app; two more
explicitly re-open only what's needed — ingress on port 8080 from within the
namespace, and egress limited to DNS (UDP/TCP 53). The app makes no other
outbound calls, so there is no reason to allow any. This follows
least-privilege networking rather than relying on the app's own logic to
avoid making requests it doesn't need.

**PodDisruptionBudget (`minAvailable: 1`)**
Ensures voluntary disruptions (node drains, cluster upgrades) can't take
every replica down at once, protecting availability during routine cluster
maintenance — meaningful once `overlays/prod` runs 3 replicas.

**Pod Security Standards "restricted" alignment**
Between `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities:
drop: [ALL]`, `readOnlyRootFilesystem: true`, and `seccompProfile:
RuntimeDefault`, this Deployment satisfies the core checks of the
"restricted" Pod Security Standard, which is the strictest built-in profile
Kubernetes ships.

## What wasn't run locally

No `kubectl`, `kind`, or `kubeval` binary was present on this host, so the
manifests were validated with `kustomize build` (via the official Docker
image) for structural correctness and rendered output, plus a Python
`yaml.safe_load_all` pass over every file for syntax. The Docker image for
`app/status-service` was built and run locally end to end (`docker build`,
then `docker run --read-only --tmpfs /tmp --user 10001:10001`), confirming
`/`, `/status.json`, `/healthz`, and `/readyz` all work under the same
constraints the Kubernetes `securityContext` enforces. `kubectl apply
--dry-run=client|server` against a live/kind cluster was not run.
