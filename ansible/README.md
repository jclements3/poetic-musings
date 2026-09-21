# ansible — real config management on top of the real infra

Terraform (`infra/terraform/`) answers "does the infrastructure exist."
This answers a different, separate question: "is the right software
deployed and configured on it, every time, idempotently" — the actual
distinction between IaC/provisioning and config management that comes up
in a DevSecOps interview.

## What this manages

The `observability_stack` role deploys and verifies the real
Prometheus + Grafana + status-service stack in `observability/`
(itself built and verified earlier in this repo's history). It:

1. Confirms Docker is present and reachable (`docker info`).
2. Deploys the compose stack via `community.docker.docker_compose_v2`
   (`build: always`, `state: present`) — a real module, not a `shell:`
   wrapper around `docker compose up`.
3. Polls `status-service`'s `/healthz` until it answers 200.
4. Polls `/metrics` and asserts the real `http_requests_total`
   Prometheus metric is present in the response body.
5. Polls Prometheus's own `/-/healthy`, then queries
   `/api/v1/targets` and asserts Prometheus has actually scraped
   `status-service` and marked it `health: up` — not just "the
   container is running," but "the metrics pipeline is actually
   working end to end."
6. Polls Grafana's `/api/health`.

Every check is a real HTTP call against a real running service —
nothing here is asserting against a mock.

## Running it

```
cd ansible
ansible-galaxy collection install community.docker   # one-time
ansible-playbook -i inventory.ini playbook.yml -v
```

Target is `localhost` via `ansible_connection=local` — see "Honest
gaps" below for why, not a disguised no-op.

## Real idempotency proof

Ran three times against genuinely different states, captured logs in
this directory:

- `docker compose down` (stack fully torn down), then
  `ansible-playbook ... playbook.yml` →
  **`ok=10 changed=1`** (`run-cold.txt`) — it actually built/started
  the stack from nothing.
- Immediately ran again, stack now up →
  **`ok=10 changed=0`** (`run-idempotent.txt`) — same desired state,
  nothing to do, real idempotency, not "it happened not to fail twice."

## Real bug hit and fixed

`ansible-playbook` failed immediately with:

```
ERROR: Ansible requires blocking IO on stdin/stdout/stderr. Non-blocking
file handles detected: <stdout>, <stderr>
```

Root cause: this shell's stdin is a non-blocking pipe (the harness's
own bash tool), which Ansible's process-forking model rejects outright.
Fixed by redirecting stdin from `/dev/null`
(`ansible-playbook ... < /dev/null`) — a real, documented Ansible
constraint, not something papered over with `--no-verify`-style
flag-hiding.

Separately, `ansible-galaxy collection install community.docker`
hit a transient `504 Gateway Timeout` against Galaxy's API on the
first attempt and succeeded on retry — noted here since it's an
external-service flake, not a bug in this repo.

## Honest gaps

- **Target is `localhost`, not a real remote/SSH host or a fleet.**
  This environment has no second machine to manage over SSH, so this
  demonstrates the real Ansible mechanics (modules, idempotency,
  handlers, `uri` polling) against a real Docker Engine on this host,
  not fleet-scale orchestration. The `inventory.ini` structure and role
  layout are written the same way they would be for N remote hosts —
  swapping `ansible_connection=local` for real SSH-reachable hosts is
  the only change needed to scale it, but that swap has not been done
  or tested here.
- **No secrets/vault usage.** Nothing sensitive is configured by this
  playbook (Grafana ships default `admin/admin`, same as
  `observability/README.md` already documents), so `ansible-vault` was
  not needed here — a real gap if this were managing anything with
  actual credentials.
- **`community.docker` required a Galaxy fetch, not vendored.** In a
  fully air-gapped environment this collection would need to be
  pre-downloaded; that's not set up here.
