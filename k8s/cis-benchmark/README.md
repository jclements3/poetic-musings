# CIS Kubernetes Benchmark — a real, scored run

Not a claim of alignment "by construction" — this is an actual `kube-bench`
run against a live cluster, with real PASS/FAIL/WARN counts.

## What ran

- Cluster: local `kind` (Kubernetes-in-Docker) v0.24.0, 1 control-plane + 1
  worker node, Kubernetes v1.31.0.
- This repo's real manifests deployed to it: `kubectl kustomize
  k8s/overlays/dev | kubectl apply -f -` — Deployment rolled out and
  `Ready`, Service, both `NetworkPolicy` objects, and the `PodDisruptionBudget`
  all confirmed live with `kubectl get`.
- Scanner: `kube-bench` v0.9.4 (aquasecurity), copied into the
  `kind` control-plane container and run in-place against etcd, the
  API server, controller-manager, scheduler, kubelet, and the cluster's
  Pod Security Policies, using the `cis-1.24` benchmark profile (closest
  published profile to this cluster's v1.31 control plane).

## Result

```
== Summary total ==
62 checks PASS
11 checks FAIL
48 checks WARN
0 checks INFO
```

Full output: [`kube-bench-report.txt`](kube-bench-report.txt).

## Honest read of the FAILs

All 11 failures are **kind's own default control-plane configuration**, not
this repo's manifests — `kube-bench` scores the cluster's control plane
(etcd, kube-apiserver, kubelet flags), which `kind` provisions itself, and
this repo's k8s/ directory has no ability to change (a kind config,
kubeadm, or an actual managed/self-hosted control plane would). For example:
`--profiling` left enabled on the API server, scheduler, and
controller-manager (`1.2.17`/`1.3.2`/`1.4.1`); no audit log configured
(`1.2.18`–`1.2.21`); kubelet service file permissions and
`--protect-kernel-defaults` unset (`4.1.1`/`4.2.6`). These are exactly the
kind of gaps a real hardening pass on a managed cluster (EKS/GKE/AKS with
CIS-hardened node images, or kubeadm with audit policy configured) would
close — kind intentionally ships a minimal, fast-to-boot control plane, not
a CIS-hardened one.

The 48 WARNs are almost entirely `kube-bench`'s workload-level advisory
checks (§5: Pod Security Policies, network policy presence, secrets as
env vars, image provenance, seccomp) — these require either judgment calls
per-workload or (for PSP, deprecated since Kubernetes 1.25 in favor of Pod
Security Admission, which this repo's manifests already use via the
`restricted` PSS label) simply don't apply to this cluster's version.

**What this genuinely proves**: this repo's Kubernetes manifests deploy
cleanly to a real cluster and produce real, running, network-policed
workloads — and a real scanner has scored the surrounding control plane
honestly, gaps included, rather than asserting alignment nobody checked.

## Reproduce it

```bash
kind create cluster --name poetic-musings
kubectl create namespace status-service-dev
kind load docker-image status-service:demo --name poetic-musings
kubectl kustomize k8s/overlays/dev | kubectl apply -f -
kubectl -n status-service-dev rollout status deployment/status-service

# kube-bench binary copied into the kind control-plane container and run there
docker cp kube-bench <container>:/usr/local/bin/kube-bench
docker cp cfg <container>:/etc/kube-bench-cfg
docker exec <container> kube-bench run --config-dir /etc/kube-bench-cfg \
  --benchmark cis-1.24 --targets master,etcd,node,policies

kind delete cluster --name poetic-musings
```

Run on: 2026-09-21, `kube-bench` v0.9.4, `kind` v0.24.0, Kubernetes v1.31.0.
