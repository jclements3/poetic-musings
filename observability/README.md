# Observability — Prometheus + Grafana for status-service

A real, working local metrics pipeline: `status-service` exposes
Prometheus-format metrics at `/metrics`, a real Prometheus scrapes them
every 5s, and a real Grafana dashboard queries Prometheus and renders
them. Not a mockup — every number on the dashboard is live traffic.

## What's instrumented

`app/status-service/app.py` tracks two metrics via `prometheus_client`,
covering what actually matters for a small HTTP service:

- `http_requests_total{method, path, status}` — a `Counter`, one
  increment per request.
- `http_request_duration_seconds{method, path}` — a `Histogram` of
  request latency, used for the p95-latency panel.

`/metrics` itself is excluded from both so scraping the service doesn't
skew its own numbers.

## The multiprocess gotcha (a real bug this caught)

The Dockerfile runs gunicorn with 2 worker processes. `prometheus_client`'s
default registry lives in-process — a `/metrics` scrape hitting one
worker would only ever see *that worker's* counters, silently
undercounting real traffic by roughly half. Confirmed this happening
during development: sending 30 requests to `/` showed only ~13–17 on
`/metrics`, split unevenly across whichever worker handled each request.

Fixed with Prometheus's documented multiprocess mode:
- `PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc` set in the
  Dockerfile (before Python starts, which is required — `prometheus_client`
  checks this env var at import time to switch its internal value classes).
  Lives under `/tmp` so it works under the same read-only-root-filesystem
  pattern the rest of this image already uses.
- `gunicorn.conf.py`'s `child_exit` hook calls
  `multiprocess.mark_process_dead()` so a dead worker's metric files don't
  keep contributing stale values forever.
- `/metrics` uses `MultiProcessCollector` to merge all workers' files into
  one response when the env var is set, falling back to the normal
  single-process registry otherwise (e.g. running `app.py` directly, not
  under gunicorn).

Re-verified after the fix: 30 requests to `/` and 30 to `/status.json`
showed as exactly 30 and 30 on `/metrics`, confirmed again through
Prometheus's own query API, and a third time through Grafana's
datasource-proxy API — the same number, three different layers deep.

## Running it

```
cd observability
docker compose up -d --build
```

- **status-service**: http://localhost:8080
- **Prometheus**: http://localhost:9090 (check Status → Targets to see
  the scrape as `UP`)
- **Grafana**: http://localhost:3000 — login `admin` / `admin` (change
  it on first login; this is a local demo stack only). The
  **status-service** dashboard is provisioned automatically — no manual
  setup, no clicking through an empty Grafana.

Generate some traffic so the dashboard has something to show:

```
for i in $(seq 1 30); do curl -s http://localhost:8080/ >/dev/null; done
```

Tear down:

```
docker compose down       # stop
docker compose down -v    # stop and wipe Prometheus/Grafana data volumes
```

## Dashboard panels

`grafana/dashboards/status-service.json` (provisioned automatically via
`grafana/provisioning/`):

1. **Request rate by path** — `sum by (path) (rate(http_requests_total[1m]))`
2. **p95 latency by path** — `histogram_quantile(0.95, sum by (le, path) (rate(http_request_duration_seconds_bucket[5m])))`
3. **Requests by status code** — pie chart, `sum by (status) (http_requests_total)`
4. **Total requests (5m)** — `sum(increase(http_requests_total[5m]))`

## What this doesn't cover yet

This is local-only — `docker-compose.yml` here is not part of the
`k8s/` manifests, and nothing in the Kubernetes deployment currently
scrapes `/metrics` or ships a `ServiceMonitor`/`PodMonitor` (Prometheus
Operator) or equivalent. The natural next step, if this moved toward a
real cluster: add a `ServiceMonitor` alongside `k8s/base/`, and this same
dashboard JSON would work unmodified against a cluster Prometheus.
