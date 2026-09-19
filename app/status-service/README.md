# status-service

A tiny read-only Flask service that renders this repo's `STATUS.md` as HTML
(`/`) and JSON (`/status.json`), plus Kubernetes probe endpoints (`/healthz`,
`/readyz`). It's a demo/training artifact: a real, buildable service used to
show containerization and Kubernetes hardening practices, not a rewrite of
the project itself.

## Files

- `app.py` — the whole app. Flask, stdlib-only Markdown rendering (no
  Markdown dependency — the subset STATUS.md actually uses: headings, pipe
  tables, `-` lists, `**bold**`, paragraphs), served via gunicorn.
- `requirements.txt` — pinned: `flask==3.0.3`, `gunicorn==22.0.0`.
- `Dockerfile` — hardened multi-stage build (see `k8s/README.md` for the
  full rationale shared with the manifests).
- `STATUS.md` — a build-time copy of the repo root's `STATUS.md`, baked into
  the image so `docker run` works standalone. In Kubernetes this is
  overridden by mounting the real file (or a ConfigMap) at `/data/STATUS.md`
  via `STATUS_MD_PATH`.

## Endpoints

| Path | Purpose |
|---|---|
| `/` | STATUS.md rendered as HTML |
| `/status.json` | STATUS.md content + metadata as JSON |
| `/healthz` | Liveness — process is up, no I/O performed |
| `/readyz` | Readiness — confirms the status file is actually readable |

## Run locally

```sh
docker build -t status-service:demo .
docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --user 10001:10001 status-service:demo
curl localhost:8080/
```

`--read-only --tmpfs /tmp` mirrors the Kubernetes `readOnlyRootFilesystem`
setup: gunicorn needs a writable `/tmp` for its worker heartbeat files, and
nothing else, so it gets an `emptyDir`/`tmpfs` there and nowhere else.

## Design notes

- No write endpoints, no outbound network calls, no secrets. The only
  configurable input (`STATUS_MD_PATH`) is a filesystem path that is only
  ever read.
- Two probe types are split on purpose: `/healthz` never touches disk (so a
  slow/broken mount doesn't get mistaken for a dead process and trigger
  needless restarts), while `/readyz` checks the real dependency (the status
  file existing) so traffic isn't routed to a pod that can't serve it yet.
