# Chapter 7 — Zone 7: Deploy & Orchestrate

## 1. Why this zone matters

Zone 6 (Infrastructure as Code) gets you a cluster: nodes exist, the control
plane answers `kubectl get nodes`, the VPC is wired, the load balancer has an
IP. None of that means an application is running, reachable, self-healing, or
safe to leave unattended. That's the entire subject of this zone: the gap
between "the platform exists" and "the workload survives contact with
reality" — a node dying at 3 a.m., a bad image rollout, a pod that leaks
memory until the kernel OOM-kills it, an attacker who compromises one
container and immediately tries to talk to every other pod in the namespace.

Deploy & Orchestrate is where you answer three questions honestly, per
workload:

1. **Does it come back if it dies?** (ReplicaSets, Deployments, restart
   policies, PodDisruptionBudgets)
2. **Can it reach, and be reached by, only what it should?** (Services,
   Ingress, NetworkPolicy, RBAC)
3. **Is the blast radius of a single compromised or misbehaving pod
   contained?** (Pod Security Standards, non-root, read-only filesystems,
   resource limits)

This repo's `k8s/` directory and `ad-lab/` are both worked answers to that
question, for two different kinds of workload — a stateless HTTP service on
Kubernetes, and identity infrastructure on Active Directory. They're treated
together in this chapter because the job posting this book maps to
(`JOB.html`) requires both, and because "deploy & orchestrate" is not a
Kubernetes-only idea — an enterprise that runs Kubernetes for its
applications is very likely also running Active Directory for its people and
endpoints, and a DevSecOps engineer who can reason about only one of those
two orchestration models is only half-useful in that environment.

---

## 2. Kubernetes architecture, precisely

A Kubernetes cluster has two kinds of machine: **control plane** nodes (the
brain) and **worker** nodes (where your containers actually run). Know this
split cold — it's the first whiteboard question in almost every Kubernetes
interview.

### Control plane components

- **`kube-apiserver`** — the only component that talks to `etcd`. Every
  `kubectl` command, every controller, every kubelet — all of them go
  through the API server. It validates and admits requests (this is where
  admission controllers like Pod Security Admission live), then persists
  the result to etcd. Stateless by design; you can run several replicas
  behind a load balancer for HA.
- **`etcd`** — a distributed, strongly-consistent key-value store. This is
  the *entire* state of the cluster: every object, every status field. If
  you lose etcd with no backup, you have lost the cluster's brain, not just
  its workloads. Back it up. `etcdctl snapshot save` is not optional in a
  real environment.
- **`kube-controller-manager`** — runs the control loops: the Deployment
  controller reconciling replica count, the Node controller marking nodes
  `NotReady` after a missed heartbeat, the ReplicaSet controller, the
  Job controller, and more. Each loop follows the same pattern: observe
  current state, compare to desired state (spec), act to close the gap.
  This reconciliation pattern is the single most important idea in
  Kubernetes and reappears verbatim in ArgoCD (§8).
- **`kube-scheduler`** — watches for Pods with no `nodeName` assigned yet,
  filters nodes by constraints (resource requests, taints/tolerations,
  affinity/anti-affinity, topology), scores the survivors, and binds the
  Pod to the winning node. It does not run anything itself — it only
  writes the binding decision back through the API server.
- **`cloud-controller-manager`** (when running on a cloud) — the piece that
  talks to the cloud provider's API: provisioning LoadBalancer-type
  Services as real cloud load balancers, attaching cloud disks for
  PersistentVolumes, tagging nodes. `kind` and bare-metal clusters don't
  have one, which is exactly why `type: LoadBalancer` Services never get
  an external IP on `kind` — there's no cloud controller to ask for one.

### Node (worker) components

- **`kubelet`** — the agent on every node. Watches the API server for Pods
  scheduled to its node, and drives the container runtime to actually start
  them. Runs liveness/readiness/startup probes and reports Pod status back
  up. If the kubelet on a node stops heartbeating, the Node controller
  eventually marks the node `NotReady` and, after a grace period, evicts
  its Pods so they get rescheduled elsewhere.
- **`kube-proxy`** — implements the Service abstraction on each node,
  programming iptables or IPVS rules so traffic to a Service's ClusterIP
  gets load-balanced across the matching Pod IPs. This is why Services
  work even though Pod IPs are ephemeral — kube-proxy keeps the mapping
  current as Pods come and go.
- **Container runtime** — `containerd` (or CRI-O), speaking the Container
  Runtime Interface (CRI) to the kubelet. Docker itself is not the runtime
  anymore in a modern cluster; `dockershim` was removed in 1.24. `kubeadm`
  installs with `containerd` are the standard local/on-prem setup path
  (TOC Module 10 item 4).

The mental model to keep: **desired state lives in etcd via the API
server; every other component is a loop that watches the API server and
tries to make reality match it.** A Deployment doesn't "deploy" anything —
it's a record the controller manager reconciles against, repeatedly,
forever.

---

## 3. Core workload objects

### Pods

The smallest deployable unit — one or more containers that share a network
namespace (same IP, `localhost` between them) and can share volumes. You
almost never create bare Pods in production; you create a controller that
creates Pods for you, because a bare Pod that dies stays dead.

### ReplicaSets and Deployments

A **ReplicaSet** guarantees N replicas of a Pod template are running,
recreating any that die. A **Deployment** manages ReplicaSets, and is what
you actually write — it adds versioned, controlled rollout semantics on top
(§7). `kubectl apply` on a Deployment with a new image creates a new
ReplicaSet and scales it up while scaling the old one down, according to the
`strategy` (default `RollingUpdate`).

This repo's `k8s/base/deployment.yaml` is a real Deployment: `replicas: 2`
at base, patched to `3` in the prod overlay
(`k8s/overlays/prod/kustomization.yaml`, a strategic merge patch on
`/spec/replicas`), demonstrating the Kustomize base/overlay pattern —
one canonical manifest, environment-specific patches, no copy-pasted YAML
drifting between dev and prod.

### StatefulSets — and when you actually need one

A Deployment's Pods are interchangeable: same template, arbitrary names,
any one can be killed and replaced by an identical twin. That's wrong for
anything that owns state tied to its identity — a database node that must
keep the *same* volume and the *same* network name across restarts because
its peers address it by that name (e.g. a MySQL replica, a Kafka broker, an
etcd member).

A **StatefulSet** gives each replica a stable, predictable identity:
`mysql-0`, `mysql-1`, `mysql-2`, each with its own PersistentVolumeClaim
that follows it across rescheduling, and a stable DNS name via a headless
Service (`mysql-0.mysql.default.svc.cluster.local`). Pods are created and
terminated in order (0, 1, 2 up; 2, 1, 0 down), which matters for
replication topologies where node 0 is often the primary.

The rule of thumb: **if losing Pod identity or swapping which volume is
attached to which replica would break the application, use a StatefulSet;
otherwise use a Deployment.** Most stateless HTTP services (this repo's
`status-service` included) never need one — state belongs in a managed
database or object store outside the cluster far more often than it belongs
in a StatefulSet, precisely because StatefulSets don't solve backup,
replication lag, or failover for you; they only solve stable identity.

### Services — ClusterIP / NodePort / LoadBalancer / ExternalName

Pod IPs are ephemeral; a Service gives a stable virtual IP and DNS name in
front of a set of Pods selected by label, with kube-proxy doing the
load-balancing.

| Type | What it does | When to use |
|---|---|---|
| `ClusterIP` (default) | Stable IP reachable only inside the cluster | Internal service-to-service traffic — this repo's `status-service` uses this |
| `NodePort` | Opens the same port on every node's IP, forwards to the Service | Quick manual/dev access, or as the substrate an Ingress/LoadBalancer sits on top of |
| `LoadBalancer` | Asks the cloud-controller-manager to provision a real external load balancer | Public-facing entry point on a real cloud cluster (does nothing useful on `kind` — no cloud controller to fulfil it) |
| `ExternalName` | Pure DNS CNAME to an external name, no proxying | Referencing an external system (a managed DB endpoint, a SaaS API) by an in-cluster name, so app code never hardcodes the external hostname |

In practice, most real ingress traffic doesn't go through
`LoadBalancer`-type Services at all — it goes through one shared Ingress
controller (§6), fronted by a single LoadBalancer Service, routing by
hostname/path to many ClusterIP Services behind it. That's cheaper than one
cloud load balancer per app.

### Secrets and ConfigMaps

Both inject configuration into Pods (as env vars or mounted files);
the difference is intent, not real encryption strength by default.
**ConfigMap** — non-sensitive config. **Secret** — intended for sensitive
values, but base64-encoded, not encrypted, at rest in etcd unless you've
explicitly turned on
[encryption at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
for the API server. Treat "it's a Secret object" as access-control
labeling, not encryption — pair it with RBAC restricting who can `get`
Secrets, and for anything truly sensitive (this book's stance, consistent
with Zone 6's guidance on secrets management) prefer an external secrets
manager (Vault, cloud KMS-backed secret store) synced in, over storing the
plaintext secret as a Kubernetes object at all.

### PersistentVolumes, PersistentVolumeClaims, StorageClasses

- **PersistentVolume (PV)** — a piece of real storage (a cloud disk, an NFS
  export, a local disk) represented as a cluster resource, provisioned
  either statically by an admin or dynamically on demand.
- **PersistentVolumeClaim (PVC)** — a Pod's request for storage ("give me
  10Gi, ReadWriteOnce"), bound to a matching PV.
- **StorageClass** — a template for *dynamic* provisioning: when a PVC
  names a StorageClass, the cluster's storage provisioner creates a
  matching PV on demand instead of requiring one to already exist. On a
  managed cloud cluster this is what turns a PVC into an actual EBS
  volume/Persistent Disk with zero manual PV authoring.

This repo's `status-service` is deliberately stateless and needs none of
this — its only volume is an in-memory `emptyDir` for `/tmp`, sized and
capped at 16Mi so a runaway write can't fill node disk. That's a real,
minimal example of "don't reach for a PVC you don't need."

---

## 4. Kubernetes security and resilience, applied for real

This is where the chapter stops being generic Kubernetes theory and walks
through what this repo actually deployed and actually scanned. Every choice
below is in `k8s/base/deployment.yaml`, `networkpolicy.yaml`, and
`pdb.yaml`, deployed live to a `kind` cluster (1 control-plane + 1 worker,
Kubernetes v1.31.0) and scanned with `kube-bench` v0.9.4.

**Restricted Pod Security Standard, non-root, no privilege escalation:**

```yaml
securityContext:            # Pod-level
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:        # Container-level, more specific wins
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: [ALL]
```

Why each line matters, plainly:

- `runAsNonRoot` / `runAsUser: 10001` — a container process running as
  root inside the container is one kernel exploit or misconfigured
  volume mount away from root *on the node*. Non-root by default means a
  compromised app process can't `chmod`, install packages, or touch
  anything outside its own UID's permissions.
- `readOnlyRootFilesystem: true` — the container's own filesystem can't
  be written to at runtime. An attacker who gets code execution inside
  the container can't drop a second-stage payload to disk, can't modify
  the app binary in place, can't persist across a Pod restart. The app
  gets exactly one writable path it actually needs (`/tmp`, mounted as
  its own size-capped `emptyDir` — see the deployment's `volumeMounts`),
  nothing more.
- `allowPrivilegeEscalation: false` — blocks `setuid`/`setgid` tricks
  that would let a process gain more privilege than it started with,
  independent of the `runAsNonRoot` setting.
- `capabilities: drop: [ALL]` — Linux capabilities are the fine-grained
  pieces root's power is split into (`NET_ADMIN`, `SYS_PTRACE`, etc.).
  Dropping all of them means even *if* something ran as root by mistake,
  it still couldn't bind privileged ports, trace other processes, or
  manipulate network interfaces. Add back only the specific capability a
  workload provably needs — this app needs none.
- `seccompProfile: RuntimeDefault` — restricts the set of syscalls the
  container can make to the runtime's default allow-list, closing off
  most kernel-level escape and exploit primitives that need an
  uncommon syscall.
- `automountServiceAccountToken: false` — this Pod never calls the
  Kubernetes API, so it doesn't get a token that could be stolen and
  used to. Least privilege applied to the identity a Pod is handed by
  default, not just the identity a human requests.

**Default-deny NetworkPolicy, then explicit allow:**

```yaml
# deny-all baseline for this Pod's ingress AND egress
podSelector:
  matchLabels: {app.kubernetes.io/name: status-service}
policyTypes: [Ingress, Egress]
---
# then: allow ingress on 8080 from anywhere in the namespace
# then: allow egress only to DNS (UDP/TCP 53)
```

Kubernetes networking is flat and any-to-any by default — every Pod can
reach every other Pod's IP directly unless a NetworkPolicy says otherwise
(and only if the CNI plugin actually enforces NetworkPolicy — not all do;
`kind`'s default CNI does). The comment in this repo's own manifest states
the reasoning plainly: *"The app makes no outbound calls of its own (it
only reads a local file), so egress is locked down hard."* That's the
right way to write a NetworkPolicy — start from what the app's actual
traffic pattern is, not from a template. A default-deny policy with no
allow rules turns a compromised pod into a dead end: it can't be reached
except on the one port it serves, and it can't reach anything except DNS
to resolve names it will never actually query.

**PodDisruptionBudget:**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 1
  unhealthyPodEvictionPolicy: AlwaysAllow
```

This governs *voluntary* disruptions — node drains for maintenance,
cluster autoscaler scale-downs, `kubectl drain` — guaranteeing at least one
healthy replica stays up while the rest churn. It does nothing for
involuntary disruption (a node crashing outright); that's what replica
count and anti-affinity are for.

**Pod anti-affinity:**

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: {matchLabels: {app.kubernetes.io/name: status-service}}
          topologyKey: kubernetes.io/hostname
```

`preferred` (soft), not `required` (hard) — the scheduler tries to spread
replicas across distinct nodes (so one node failing doesn't take out every
replica at once) but will still schedule co-located replicas rather than
leave a Pod `Pending` if the cluster is too small to spread them. On a
2-node `kind` cluster with `replicas: 2`, this is exactly the right choice
— a hard `required` rule would make the third prod replica (`replicas: 3`
in the prod overlay) permanently unschedulable on a 2-node cluster.

### The real kube-bench scan — and the distinction that matters most

`kube-bench` v0.9.4, `cis-1.24` benchmark profile, run against the live
`kind` v0.24.0 cluster (Kubernetes v1.31.0) with this repo's manifests
actually deployed and confirmed `Ready`:

```
== Summary total ==
62 checks PASS
11 checks FAIL
48 checks WARN
0 checks INFO
```

The FAILs matter less than *why* they're FAILs. All 11 are the cluster's
control plane — `--profiling` left enabled on the API server, scheduler,
and controller-manager; no audit log configured; kubelet service file
permissions and `--protect-kernel-defaults` unset. None of these are
things `k8s/base/*.yaml` has any power over — they're `kind`'s own
default, minimal, fast-to-boot control-plane configuration, the kind of
gaps a CIS-hardened managed cluster (EKS/GKE/AKS with hardened node images)
or a `kubeadm` install with an actual audit policy would close instead.

This is the single most important skill this chapter can teach beyond the
manifest syntax itself: **when a scanner reports a failure, the first
question is "is this my code, or the platform's defaults?"** Claiming
"CIS-compliant" because you wrote hardened manifests, without checking
whether the *cluster underneath* those manifests is also hardened, is
exactly the kind of unverified claim this book's house style refuses to
make. The honest version is what this repo's `cis-benchmark/README.md`
says: the manifests deploy cleanly to a real cluster and produce real,
running, network-policed workloads, and a real scanner scored the
*surrounding* control plane honestly, gaps named and attributed, not
asserted away.

The 48 WARNs are mostly `kube-bench`'s advisory §5 workload checks — Pod
Security Policies (deprecated since 1.25, superseded by Pod Security
Admission, which this repo's manifests already satisfy via the `restricted`
PSS), secrets-as-env-vars, image provenance, seccomp — the kind of checks
that need a per-workload judgment call rather than a binary pass/fail.

---

## 5. RBAC and networking

### RBAC

Kubernetes RBAC has four objects, in two pairs:

- **`Role`** (namespace-scoped) / **`ClusterRole`** (cluster-scoped) — a
  set of permitted verbs (`get`, `list`, `watch`, `create`, `update`,
  `delete`) on resource types.
- **`RoleBinding`** / **`ClusterRoleBinding`** — grants a Role/ClusterRole
  to a subject (a User, Group, or ServiceAccount).

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: status-service-prod
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: status-service-prod
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: status-service-prod
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

The least-privilege discipline: bind a `ClusterRoleBinding` with
`cluster-admin` to exactly the identities that must administer the whole
cluster (almost never a CI pipeline, almost never an application's
ServiceAccount), and default every application ServiceAccount to nothing
— this repo's Deployment goes further and turns off the token mount
entirely with `automountServiceAccountToken: false`, because the
`status-service` Pod never calls the API server at all. The audit
checklist item every real environment needs and few actually run:
`kubectl get clusterrolebindings -o json | jq` filtered for bindings to
`cluster-admin` or wildcard (`*`) verbs/resources, checked against who or
what actually needs that reach.

### Networking model

Three rules define Kubernetes networking, and they're worth memorizing
verbatim because they explain *why* NetworkPolicy is necessary at all:

1. Every Pod gets its own IP; containers within a Pod share that IP.
2. All Pods can reach all other Pods' IPs directly, cluster-wide, without
   NAT, by default.
3. Nodes can reach all Pods, and vice versa, without NAT.

Rule 2 is the one that surprises people coming from traditional network
segmentation — Kubernetes networking starts fully open, and Namespaces by
themselves provide zero network isolation. NetworkPolicy is the only object
that restricts rule 2, and it's opt-in and additive: with no NetworkPolicy
selecting a Pod, that Pod is fully open; the moment *any* NetworkPolicy
selects it for a given direction (Ingress or Egress), that direction
becomes default-deny except for what's explicitly allowed — which is
exactly the pattern this repo's `networkpolicy.yaml` uses (a deny-all
policy with no rules, immediately followed by narrow allow policies).

---

## 6. Ingress, custom domains, and TLS

A **NodePort/LoadBalancer Service per app** doesn't scale past a handful of
apps — one cloud load balancer per app is expensive and each gets its own
IP. An **Ingress controller** (nginx-ingress, Traefik, cloud-native
alternatives) is a single reverse proxy running as Pods in the cluster,
fronted by one `LoadBalancer` Service, that routes by hostname and/or path
to many backend ClusterIP Services based on `Ingress` objects:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: status-service
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [status.example.com]
      secretName: status-service-tls
  rules:
    - host: status.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: status-service
                port: {number: 80}
```

**Custom domain mapping** is just DNS: point `status.example.com`'s A/CNAME
record at the Ingress controller's external LoadBalancer IP/hostname. No
Kubernetes object does that for you — it's a DNS provider change, made once
the Ingress controller's external address is known.

**TLS the pattern used almost everywhere now**: `cert-manager` running in
the cluster, watching `Ingress`/`Certificate` objects, talking to Let's
Encrypt's ACME API to prove domain ownership (HTTP-01 challenge via a
temporary path the Ingress serves, or DNS-01 via a TXT record) and issuing
a real certificate, stored as a Secret (`status-service-tls` above) that
the Ingress controller terminates TLS with — and cert-manager renews it
automatically before the (typically 90-day) Let's Encrypt certificate
expires. This is the free, automated, industry-standard path; manually
managed certificates are the exception now, not the rule.

---

## 7. Scaling and safe rollouts

### Horizontal and Vertical autoscaling

- **HPA (HorizontalPodAutoscaler)** — adds/removes replicas based on a
  metric (CPU/memory by default, custom metrics via an adapter). Requires
  `resources.requests` to be set on the container (this repo's Deployment
  sets `cpu: 50m` / `memory: 64Mi` requests) — HPA computes utilization as
  a percentage of the *request*, so a Pod with no request has nothing to
  scale against.
- **VPA (VerticalPodAutoscaler)** — adjusts a Pod's resource
  requests/limits over time based on observed usage, instead of replica
  count. Combining HPA and VPA on the same metric is a known anti-pattern
  (they fight each other); use HPA for request-driven horizontal scale and
  VPA for right-sizing requests you set once and don't want to hand-tune.

### Rollout and rollback

```bash
kubectl set image deployment/status-service status-service=ghcr.io/jclements3/status-service:1.1.0
kubectl rollout status deployment/status-service
kubectl rollout undo deployment/status-service          # back to previous revision
kubectl rollout undo deployment/status-service --to-revision=3
```

`kubectl rollout status` blocking on the readiness probe passing is the
whole safety mechanism of a `RollingUpdate` — if the new image's Pods never
become `Ready` (bad image, crashing app, failing `/readyz`), the rollout
stalls rather than replacing every old Pod with a broken one, and
`rollout undo` reverts cleanly because the old ReplicaSet is kept around.

### Deployment strategies, honestly compared

| Strategy | How it works | Tradeoff |
|---|---|---|
| **Recreate** | Kill all old Pods, then start new ones | Downtime window, simplest, fine for dev/single-replica or when the app can't run two versions concurrently (e.g. an exclusive-lock migration) |
| **Rolling update** (Kubernetes Deployment default) | Old and new Pods coexist during the transition, old scaled down as new becomes Ready | No downtime, but both versions serve traffic simultaneously for a window — requires backward/forward-compatible API and schema during that window |
| **Blue-green** | Two full environments; switch traffic (Service selector or Ingress/DNS) atomically from old to new | Instant cutover and instant rollback (flip back), but doubles resource cost while both stacks run, and needs an explicit traffic-switch step Kubernetes doesn't do natively — usually scripted or handled by a mesh/Ingress |
| **Canary** | Route a small percentage of real traffic to the new version, watch metrics, ramp up | Catches bad releases against real traffic before full exposure, but needs weighted routing (Ingress annotations, a service mesh, or a tool like Argo Rollouts/Flagger) — plain Kubernetes Deployments don't natively support percentage-based traffic splits |

Kubernetes' native rollout mechanism is rolling update; blue-green and
canary both require something on top (an Ingress controller with weighted
routing, a service mesh, or a purpose-built controller like Argo Rollouts)
— know this distinction, because "Kubernetes does canary deployments" is a
common but imprecise claim.

---

## 8. Helm and GitOps with ArgoCD

### Helm

Helm packages a set of manifests as a versioned, templated, parameterized
**chart** — `values.yaml` supplies the parameters, `templates/*.yaml` are
manifests with Go template placeholders, and `helm install`/`upgrade`
renders and applies them, tracking each install as a numbered **release**
you can `helm rollback` by number.

```bash
helm install status-service ./chart --namespace status-service-prod \
  --set image.tag=1.1.0 --set replicaCount=3
helm upgrade status-service ./chart --set image.tag=1.2.0
helm rollback status-service 4
```

**Honest comparison to this repo's actual approach**: `k8s/` uses
Kustomize, not Helm — a `base/` of plain manifests plus `overlays/dev` and
`overlays/prod` patches (strategic-merge and JSON patches) that layer
environment-specific changes on top without templating syntax inside the
YAML. Kustomize's manifests stay valid, plain Kubernetes YAML at every
layer, which is exactly why `kubeconform` (the schema gate in Zone 5/7's
pre-deploy order) can validate them directly. Helm's templates are *not*
valid YAML until rendered (`helm template` first), so schema validation
has to run after rendering, and Helm charts pull in a templating language,
a values schema, and a release/rollback state model Kustomize doesn't have.
Helm wins when you're packaging something for many independent consumers
to parameterize (a public chart, an internal platform team distributing a
standard app pattern); Kustomize wins when it's your own app's own
manifests and you want the smallest possible layer between the YAML you
read and the YAML that gets applied. This repo picked Kustomize
deliberately for that reason — there's no packaging-for-others use case
here, just base + two overlays.

### GitOps and ArgoCD

GitOps' core claim: **git is the single source of truth for desired
cluster state**, and a controller running *inside* the cluster
continuously reconciles live state toward whatever's committed — not a CI
pipeline pushing `kubectl apply` outward.

ArgoCD implements this as an `Application` custom resource pointing at a
git repo path (raw manifests, a Kustomize overlay, or a Helm chart) and a
destination cluster/namespace. Its controller runs the same reconciliation
loop pattern as `kube-controller-manager` (§2) one level up: watch the git
repo, watch live cluster state, diff them, and either auto-sync the
difference away or flag `OutOfSync` for a human to approve. This closes a
security-relevant gap plain CI/CD leaves open — CI pipelines typically hold
a credential with `apply` rights into the cluster from *outside* it; ArgoCD
instead runs *inside* the cluster with its own scoped RBAC and pulls, so no
external CI system needs standing write access to production. It also
means someone running `kubectl edit` directly against a live Deployment
gets silently reverted back to whatever git says on the next sync — drift
is not just detected, it's corrected, which enforces "if it's not in git,
it doesn't happen" far more effectively than a policy document does.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: status-service-prod
spec:
  source:
    repoURL: https://github.com/jclements3/poetic-musings
    path: k8s/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: status-service-prod
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

`k8s/overlays/prod` as the `path` here is not hypothetical — that's this
repo's real Kustomize overlay, and it's exactly the kind of source ArgoCD
is built to point at natively, no adapter needed.

---

## 9. Service mesh, briefly (course knowledge — flagged, not run here)

**Nothing in this repo runs a service mesh.** This section is TOC-sourced
(Module 10, item 17) course breadth, not a verified deployment — flagged
explicitly per this book's house style.

A service mesh (Istio being the reference implementation) injects a
sidecar proxy (Envoy) into every Pod, intercepting all pod-to-pod traffic,
and adds three things on top of plain Kubernetes networking:

- **Traffic control** — fine-grained routing (percentage-based canary
  splits, retries, timeouts, circuit breaking) without touching
  application code, via `VirtualService`/`DestinationRule` objects —
  this is what gives you the canary traffic-splitting that plain
  Kubernetes Deployments (§7) don't do natively.
- **mTLS everywhere** — every pod-to-pod connection automatically
  encrypted and mutually authenticated, without the application knowing
  TLS exists. This is real defense in depth on top of NetworkPolicy:
  NetworkPolicy controls *which* pods can talk; mTLS ensures *what's said*
  can't be read or spoofed even if network segmentation is bypassed.
- **Observability** — uniform request-level metrics, distributed tracing,
  and access logs for every service, for free, because every request
  already passes through the sidecar.

The honest cost side: a sidecar per Pod roughly doubles the container
count and adds real memory/CPU overhead and a new class of failure mode
(the mesh's own control plane, certificate rotation, sidecar injection
webhook misfires). The rule of thumb worth stating plainly: adopt a mesh
when you have enough services that manual mTLS and manual canary tooling
per-service has become the actual bottleneck — not by default on a
handful of services, which is this repo's actual scale (one app, two
NetworkPolicies handle its real traffic pattern completely).

---

## 10. Windows/Active Directory as parallel identity infrastructure

### Why this is in a Kubernetes deploy chapter at all

The job posting behind this book (`JOB.html`) requires Active
Directory/Windows Server skills alongside Kubernetes, and that's not an
odd pairing — it's the normal shape of a real enterprise environment.
Kubernetes orchestrates *workloads*; Active Directory orchestrates
*identity* — which humans and machines exist, what groups they belong to,
what policy gets pushed to their endpoints, how Kerberos issues them
proof of who they are. An enterprise almost never runs one without the
other: the same organization running Kubernetes for its applications is
running AD (or Entra ID/Azure AD, its cloud descendant) for its employee
laptops, its internal service accounts, its VPN, and often its
Kubernetes cluster's own SSO/OIDC integration back into that same AD
tenant. Treating this as "Kubernetes vs. Windows" is the wrong frame;
the right frame is that both are orchestration and reconciliation
systems — AD's domain controller reconciles directory state the same
conceptual way `kube-controller-manager` reconciles cluster state — and
a DevSecOps engineer in this environment needs to operate both.

### This repo's real Samba4 AD work, as a worked example

`ad-lab/` proves the same "verify the mechanism for real, name what's
not covered" discipline this whole book insists on, applied to identity
infrastructure instead of container orchestration:

- **Real domain, real DC**: `poeticmusings.lab` (NetBIOS `POETICM`),
  provisioned for real with `samba-tool domain provision`, running as a
  genuine Samba4 Active Directory Domain Controller — open source, no
  Windows license, and wire-compatible with real Windows clients (a real
  Windows machine could join this domain and authenticate against it
  exactly as it would against a licensed Windows Server DC).
- **Real Kerberos**: `kinit jclements@POETICMUSINGS.LAB` against a real
  password produced a real TGT
  (`krbtgt/POETICMUSINGS.LAB@POETICMUSINGS.LAB`) with real expiry,
  confirmed with `klist` — not a diagram of how Kerberos works, an actual
  ticket.
- **Real LDAP/DNS**: OUs (`OU=IT`, `OU=Engineering`), groups
  (`DevSecOps-Admins`, `Platform-Team`), and a real user (`jclements`,
  member of `DevSecOps-Admins`) created via `samba-tool`; DNS confirmed
  externally with `dig @127.0.0.1 -p 8053 dc1.poeticmusings.lab A` and
  the `_ldap._tcp` SRV record a real client's domain-discovery process
  depends on.
- **Real GPO object**: `Password-Policy-Baseline` created with
  `samba-tool gpo create`, stored in real SYSVOL, linked to `OU=IT` with
  `samba-tool gpo setlink`, confirmed with `samba-tool gpo getlink`.

**Two real bugs, fixed for real** — worth knowing because both are classic
container/virtualization-environment AD failures, not toy problems:

1. SYSVOL provisioning failed with `NT_STATUS_ACCESS_DENIED` because
   Docker's overlay filesystem (and WSL2's backing store under it)
   doesn't reliably support the extended attributes Samba normally uses
   to store NT ACLs. Fixed with `--option="posix:eadb=..."` on `domain
   provision`, making Samba emulate those ACLs via a TDB database instead
   of real xattrs — the same category of fix as "this platform's storage
   layer doesn't support the primitive the software assumes," which is
   worth recognizing anywhere containers meet a filesystem-attribute-
   dependent service.
2. `samba-tool gpo create` failed with a DNS SRV lookup failure because
   the container's `/etc/resolv.conf` still pointed at Docker's default
   resolver, not Samba's own internal DNS server — fixed by repointing
   resolution at `127.0.0.1` once the DC's own DNS was up. This is the
   same "identity infrastructure depends on itself for DNS, and if the
   resolver isn't pointed at the DC yet, DC operations that need DNS
   fail" trap that shows up constantly in real AD deployments, not just
   lab ones.

### Honest gaps — what a real Windows Server environment adds

Stated exactly as `ad-lab/README.md` states them, because naming the gap
is the point:

- **No domain-joined Windows client.** The DC side is proven completely
  — real domain, real Kerberos, a real linked GPO object — but nothing
  has actually joined a Windows machine to this domain, so GPO
  *application* (a client pulling and enforcing the policy) is unproven;
  only GPO *object creation and linkage* is. Closing this needs a real or
  lab Windows client VM, which needs a GUI/hypervisor this lab
  environment doesn't have.
- **No policy settings authored inside the GPO.** The GPO object exists
  and is linked, but its `registry.pol` content is empty — authoring real
  settings (password complexity, lockout thresholds, screen-lock timeout)
  is normally done in the Group Policy Management Console (GPMC) from a
  Windows admin workstation with RSAT installed. That's genuinely a
  different toolchain than anything `samba-tool` gives you.
- **No MECM/SCCM or Intune.** Those manage endpoints at fleet scale —
  software deployment, patch compliance, configuration baselines — *on
  top of* an AD/Entra identity foundation. This lab proves the
  foundation; it doesn't reach into fleet management at all.
- **Single DC, no replication topology.** Production AD runs 2+ DCs for
  redundancy and site-local authentication; this is one DC, sufficient to
  prove the mechanism, not a production topology.

The transferable lesson for the interview and the job itself: know the
difference between *proving a mechanism is real* (a working KDC issuing
real tickets, a working GPO object linked to a real OU) and *proving an
enterprise-scale operational capability* (GPO settings actually enforced
fleet-wide via SCCM, multi-DC failover). Both matter; conflating them is
how claims get overstated. This book's stance throughout is: say exactly
which one you've verified.

---

## 11. Day-one checklist for this zone

1. **Map what's actually running vs. what's just defined.** `kubectl get
   deploy,po,svc,networkpolicy,pdb -A` against the real cluster, diffed
   against everything committed in the manifest repo — a manifest that
   exists in git but was never applied, or was applied and later drifted,
   is not a control, it's a document.
2. **Check NetworkPolicy coverage per namespace.** `kubectl get
   networkpolicy -A` — any namespace with workloads and zero
   NetworkPolicies is fully open by Kubernetes' default (§5); that's the
   single highest-leverage gap to close first.
3. **Audit RBAC for overly broad bindings.** `kubectl get
   clusterrolebindings -o json`, filtered for `cluster-admin` or wildcard
   verbs/resources, checked against who/what genuinely needs cluster-wide
   admin — CI ServiceAccounts and application ServiceAccounts almost
   never should have it.
4. **Confirm Pod Security Standard enforcement per namespace**, not just
   per manifest: `kubectl get ns --show-labels | grep pod-security` —
   labels on the manifest mean nothing if the namespace itself doesn't
   enforce the `restricted` (or at least `baseline`) admission level.
5. **Check every Deployment for resource requests/limits.** No
   `requests` means HPA has nothing to scale against and the scheduler
   can't bin-pack sanely; no `limits` means one runaway Pod can starve
   its node.
6. **Verify PodDisruptionBudgets exist for anything that can't tolerate
   going fully to zero replicas during a node drain or cluster
   autoscaler event.**
7. **Confirm the pre-deploy validation order is actually wired into
   CI**, not just documented: `kubeconform -summary k8s/` (schema) →
   `kube-linter` (policy) → `kubectl apply --dry-run=server` (admission)
   → apply. Each layer catches what the previous structurally can't —
   kubeconform can't catch a Pod Security Admission rejection, and a
   dry-run needs a live cluster kubeconform doesn't.
8. **For identity infrastructure**: confirm which OUs/groups actually
   have GPOs linked vs. which exist unlinked; confirm DNS for the domain
   resolves from a client's actual configured resolver, not just from
   the DC itself; confirm there's more than one DC in anything
   production-facing.

---

## 12. Troubleshooting quick-reference

| Symptom | Likely cause | First commands |
|---|---|---|
| `CrashLoopBackOff` | App exits non-zero shortly after start — bad config, missing env var/secret, failing startup dependency, OOM-killed | `kubectl logs <pod> --previous`, `kubectl describe pod <pod>` (check `Last State: Terminated, Reason:`) |
| `ImagePullBackOff` / `ErrImagePull` | Wrong image tag/registry, missing `imagePullSecrets`, private registry auth failure, image genuinely doesn't exist | `kubectl describe pod <pod>` for the exact pull error; verify the tag exists in the registry directly |
| `Pending` pod | Scheduler can't place it — insufficient node resources, an unsatisfiable `nodeSelector`/affinity, a taint with no matching toleration, no PV available for a bound PVC | `kubectl describe pod <pod>` (Events section names the exact scheduling failure); `kubectl get nodes -o wide` + `kubectl describe node` for allocatable resources |
| Service not routing traffic | Service `selector` labels don't match the Pod's actual labels (most common cause by far), or the container port doesn't match `targetPort` | `kubectl get endpoints <svc>` — empty endpoints means the selector matches zero Pods; diff `Service.spec.selector` against `kubectl get pod --show-labels` |
| Kerberos ticket fails to issue (`kinit` error) | DNS not resolving the realm's SRV/A records (client resolver not pointed at the DC, as this repo hit while seeding GPOs), or clock skew beyond Kerberos' default 5-minute tolerance | `dig _kerberos._tcp.<realm> SRV`, `dig dc1.<realm> A`; `w32tm /query /status` (Windows) or `chronyc tracking`/`timedatectl` (Linux) to check clock offset against the DC |
| Manifest passes `kubeconform` but is rejected on `apply` | Schema-valid YAML that still violates cluster admission policy — most often a `restricted` Pod Security Standard rejecting a container missing `runAsNonRoot`/`allowPrivilegeEscalation: false`/dropped capabilities | `kubectl apply --dry-run=server -f <file>` surfaces the admission error text directly; cross-check the Pod spec's `securityContext` against the namespace's enforced PSS level (`kubectl get ns <ns> -o yaml \| grep pod-security`) |

---

Zone 7's runnable recipes — the `kubeconform`/`kube-linter`/dry-run pre-deploy
chain, the Kustomize base/overlay layout, and the `kube-bench` reproduction
steps — live in the book's toolkit appendix alongside this repo's own
`k8s/` and `k8s/cis-benchmark/` files, which are the canonical source for
every command and manifest excerpt in this chapter.
