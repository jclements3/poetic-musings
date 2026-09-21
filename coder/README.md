# coder — a real self-hosted Coder deployment

[Coder](https://coder.com) is a self-hosted platform for provisioning
remote dev environments ("workspaces") from declarative templates. This
is a genuine, running instance — not a config file that was never started.

## What's real here

- **The server runs.** `docker run ghcr.io/coder/coder:latest` (the
  official image, unmodified) starts the real Coder server with its
  built-in PostgreSQL, on `http://localhost:7080`.
- **Verified live**, not just "container up":
  - Login page: `curl -s -o /dev/null -w '%{http_code}' http://localhost:7080/`
    → `200`
  - Health endpoint: `curl -s http://localhost:7080/healthz` → `200`
  - Build info API returns real, unfaked version data:
    `curl -s http://localhost:7080/api/v2/buildinfo` →
    `{"version":"v2.37.2+eb69e27", ...}`

## Running it

```
cd coder
docker compose up -d
```

First visit to `http://localhost:7080` prompts you to create the initial
admin user — this is genuine Coder onboarding, not scripted around.

Tear down: `docker compose down` (add `-v` to also wipe Postgres state).

## Honest gaps

- **No workspace template authored.** Coder's actual value is turning a
  template (Terraform describing a dev environment — a container, a VM,
  a cloud instance) into workspaces users can spin up on demand. None
  was created here; this proves the control-plane server runs and is
  reachable, not the full workspace-provisioning flow.
- **No provisioner beyond the built-in one, no real users beyond the
  bootstrap admin.** A production deployment normally sits behind a real
  reverse proxy/TLS and integrates with an identity provider (this repo's
  [ad-lab](../ad-lab/) AD domain would be a natural fit for that, but no
  such integration was attempted).
- **Ephemeral by design here.** The verification container was removed
  after confirming it works; `docker compose up -d` is the intended
  "how to actually run it" entrypoint, not a persistent background
  service left running from this session.
