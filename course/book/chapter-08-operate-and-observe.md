# Chapter 8 — Zone 8: Operate and Observe

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone matters

Every other zone in this book produces something: a build, a scan result, a
signed image, a deployed pod. Zone 8 is the zone that tells you whether any
of it is still true five minutes, five hours, or five months later. You
cannot fix what you cannot see, and you cannot see what you didn't
instrument. That sentence sounds like a platitude until you've lived the
alternative: a cron job that silently stopped running 61 days ago, a
dashboard that still shows the old service topology, an alert that fires
into a Slack channel nobody reads. All three of those are *worse* than
having no monitoring at all, because they give you the confidence of
coverage without the substance of it.

This is also, deliberately, the chapter that does double duty as the book's
main troubleshooting reference. That's not an accident of scope — it's how
the zone actually works in practice. "Operate and observe" isn't a
dashboard you glance at once a day; it's the zone you're standing in at
2 a.m. when a page fires and you have sixty seconds to figure out whether
this is a one-pod blip or the whole platform is down. Everything in this
chapter — the metrics stack, the logging stack, the triage framework — is
in service of that one moment: something broke, now what.

Two things this repo has built for real ground the chapter: a working
Prometheus + Grafana stack in `observability/`, instrumented against a real
Flask service, with a real bug caught in the metrics pipeline itself (§4);
and a genuinely well-designed triage framework in `qrg.html` that this
chapter reproduces faithfully rather than reinventing (§6–§8). ELK gets a
full section on the merits — it's standard, expected knowledge for this
role — but it is explicitly **not deployed** anywhere in this repo. Where
this repo is real and where it's course-only is called out plainly,
because conflating the two is exactly the kind of unverified confidence
this zone exists to prevent.

---

## 2. Prometheus deep dive

### 2.1 The pull-based metrics model

Prometheus inverts the model most engineers expect from older monitoring
tools (Nagios, StatsD-push setups). Instead of applications pushing metrics
to a central collector, Prometheus **scrapes** — it polls each configured
target's `/metrics` HTTP endpoint on an interval and pulls whatever is
there. This has consequences worth understanding, not just accepting:

- **The target doesn't need to know Prometheus exists.** It just exposes a
  plaintext HTTP endpoint in the Prometheus exposition format. Any process
  that can serve HTTP can be scraped.
- **Prometheus itself becomes the thing that knows "is this target alive."**
  A failed scrape (`up == 0`) is itself a first-class signal — the absence
  of data is data. A push model has to build that detection separately
  (dead-man's-switch patterns); pull gets it for free.
- **Service discovery replaces static config at scale.** In Kubernetes,
  Prometheus (or the Prometheus Operator's `ServiceMonitor`/`PodMonitor`
  CRDs) discovers scrape targets from the API server rather than a static
  list of hosts, so targets that come and go with autoscaling or rolling
  deploys don't need manual re-registration.
- **Short-lived jobs are the actual weak point.** A batch job that runs for
  eight seconds and exits is gone before the next scrape interval — that's
  what the Prometheus Pushgateway exists for, as a deliberate, narrow
  exception to the pull model, not a general-purpose push path.

The exposition format itself is simple, line-oriented plaintext:

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/",status="200"} 42
```

Four metric types matter in practice:

- **Counter** — monotonically increasing (requests served, errors thrown).
  Never decreases except on process restart. You almost never query a
  counter's raw value; you query its `rate()`.
- **Gauge** — a value that goes up and down (memory in use, queue depth,
  number of ready pods).
- **Histogram** — buckets observations into configurable ranges (`le=`
  "less than or equal") and exposes `_bucket`, `_sum`, and `_count` series,
  used for latency distributions and `histogram_quantile()` queries.
- **Summary** — like a histogram but computes quantiles client-side; rarer
  in practice because it can't be aggregated across instances the way a
  histogram can.

### 2.2 PromQL basics

PromQL is Prometheus's query language, and the handful of patterns below
cover most of what shows up on a real dashboard or alert rule:

```promql
# Instantaneous value of a gauge
node_memory_MemAvailable_bytes

# Rate of a counter over a window — the correct way to read a counter,
# never the raw value, because it resets on restart and only rate() is
# restart-safe
rate(http_requests_total[5m])

# Aggregation across a label dimension
sum by (path) (rate(http_requests_total[1m]))

# p95 latency from a histogram
histogram_quantile(0.95,
  sum by (le, path) (rate(http_request_duration_seconds_bucket[5m])))

# Absolute increase over a window (not a rate — a count)
increase(http_requests_total[5m])

# Is the target even up?
up{job="status-service"} == 0
```

The `[5m]` range vector is the most commonly misunderstood part: it's not
"the last 5 minutes of data," it's "compute the rate using the samples
inside this trailing window," and the window needs to be at least a few
multiples of the scrape interval or the rate calculation gets noisy from
too few data points.

### 2.3 Node Exporter and Black Box Exporter

Prometheus itself only scrapes what exposes `/metrics` in its own format.
For everything that doesn't natively speak Prometheus, an **exporter**
translates.

- **Node Exporter** runs on every host (as a systemd service, or a
  DaemonSet in Kubernetes) and exposes OS-level metrics: CPU, memory, disk,
  filesystem, network, load average. This is the exporter behind almost
  every "is the box itself healthy" panel and behind the "boring six" disk
  and resource checks in §8.
- **Black Box Exporter** does something different: it doesn't report on
  the host it runs on, it *probes* other things — an HTTP endpoint, a TCP
  port, a DNS record, an ICMP ping — and exposes the result (up/down,
  response time, TLS cert expiry) as a metric. This is how you get
  external-facing synthetic checks ("is the load balancer reachable from
  outside") into the same Prometheus/Grafana/Alertmanager pipeline as
  everything else, and it's the natural home for TLS-expiry monitoring so
  the "quiet killer" cert sweep in §7 doesn't have to be a manual cron job
  forever.

### 2.4 Alertmanager and alert routing

Prometheus itself only evaluates alert rules and fires alerts into
**Alertmanager**, a separate component with a separate job: deduplication,
grouping, silencing, inhibition, and routing to a notification channel
(email, Slack, PagerDuty, a webhook). Splitting these two concerns matters:
Prometheus stays a pure metrics/query engine, and Alertmanager owns the
"who gets told, how often, and when to shut up" logic, which is genuinely
different logic from "is this condition true."

A minimal alert rule:

```yaml
groups:
  - name: status-service
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m])) > 0.05
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Error rate above 5% for 10 minutes"
```

The `for: 10m` clause is doing real work: it's the difference between an
alert that fires on every transient blip and one that fires on a sustained
condition. Alertmanager routing then decides where `severity: warning`
lands versus `severity: critical` — this is where the SEV1/SEV2/SEV3
cadence from §8 becomes config, not just a document nobody follows: a
`critical` route with a short `group_wait`/`repeat_interval` to a pager, a
`warning` route to a Slack channel with a longer repeat interval. An alert
that's correctly defined but routed to a channel nobody watches is not
meaningfully different from no alert at all — which is exactly the trap
the day-one checklist in §9 tells you to check for directly, not assume
away.

---

## 3. Grafana deep dive

### 3.1 Dashboards as code

Grafana dashboards *can* be built by hand in the UI, but "click around
until it looks right" doesn't survive a Grafana restart, a new environment,
or a second engineer needing to reproduce it. The durable pattern is
**provisioning**: dashboards and data sources defined as JSON/YAML files
checked into version control, loaded automatically on container start.
This repo does exactly that — `observability/grafana/provisioning/` wires
up the data source and dashboard directories, and
`observability/grafana/dashboards/status-service.json` is the dashboard
definition itself, so `docker compose up -d --build` produces a fully
populated dashboard with zero manual clicking. That's the difference
between a demo and infrastructure: the demo requires someone to remember
what they clicked; the infrastructure just comes back the same way every
time.

A minimal provisioning config for a data source:

```yaml
# provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

And for the dashboard loader itself:

```yaml
# provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: default
    folder: ""
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

### 3.2 Data sources and panel types

Grafana is fundamentally a query-and-render layer over one or more data
sources — Prometheus is the common one in this stack, but Grafana also
speaks Elasticsearch, Loki, InfluxDB, and plain SQL, among others, which is
part of why it's the standard visualization layer regardless of which
metrics or logging backend sits underneath it.

Panel types that cover most real dashboards:

- **Time series** — the default line/area graph, for rates and gauges over
  time (request rate, latency, CPU).
- **Stat** — a single big number, often with a sparkline and threshold
  coloring (current error count, total requests in the last 5 minutes).
- **Gauge** — a dial against a threshold (disk usage against 80%/95%
  warning/critical bands).
- **Pie chart / bar gauge** — distribution across a label (requests by
  status code, exactly what `status-service.json`'s panel 3 does with
  `sum by (status) (http_requests_total)`).
- **Table** — raw rows, useful for "top N" queries (slowest endpoints,
  noisiest pods).
- **Logs panel** — when the data source is Loki or Elasticsearch instead
  of Prometheus, for correlating a metric spike with the log lines from
  the same time window.

### 3.3 Alerting from Grafana

Grafana has its own unified alerting engine (since Grafana 8+), which can
alert directly off any configured data source's query, independent of
Prometheus's own rule evaluation. In practice, most shops pick one
alerting owner rather than run duplicate alert logic in both places —
Prometheus + Alertmanager for metrics-native alerting, or Grafana alerting
when the alert condition spans multiple data source types (a metric
crossed with a log pattern) that Prometheus alone can't express. Whichever
is chosen, the same principle from §2.4 applies: an alert that's correctly
defined but not routed to a human who's on call is a false sense of
coverage, not coverage.

---

## 4. Applied to poetic-musings: a real bug in the metrics pipeline itself

Everything above is standard-issue Prometheus/Grafana knowledge. This
section is why the chapter earns the word "real": this repo built a working
metrics pipeline and then found a bug **in the monitoring itself** —
the exact failure mode of "the dashboard is lying to you and looks
completely fine while it does it."

### The setup

`app/status-service/app.py` instruments two metrics via `prometheus_client`:
`http_requests_total{method, path, status}` (a Counter) and
`http_request_duration_seconds{method, path}` (a Histogram, feeding the
p95-latency panel). `/metrics` itself is excluded from both counters so
scraping the endpoint doesn't skew the numbers it's reporting.

The Dockerfile runs this service under **gunicorn with 2 worker
processes**, which is a completely ordinary production pattern — one
process per CPU core, or close to it, for a WSGI app under real load.

### The symptom

`prometheus_client`'s default registry lives **in-process**. Each gunicorn
worker is a separate OS process with its own Python interpreter and,
therefore, its own separate in-memory registry. A scrape of `/metrics`
hits *one* worker — whichever one the load balancer or gunicorn's own
connection handling routes it to — and that worker can only report *its
own* counters. It has no visibility into what the other worker counted.

Confirmed during development, not theorized: sending 30 requests to `/`
showed only **~13–17** on `/metrics** — roughly half the real traffic,
split unevenly across whichever worker happened to answer each request.
The dashboard wasn't down. It wasn't throwing errors. It was rendering a
perfectly smooth, perfectly wrong graph, quietly undercounting real
traffic by about 50%.

### Why it happened

This is the general lesson, not just the specific bug: **multi-process
serving and single-process metrics libraries are structurally
incompatible unless you explicitly bridge them.** Anything that forks or
spawns workers — gunicorn, uWSGI, any prefork server — breaks the
assumption that "the process" and "the application" are the same thing.
`prometheus_client`'s default in-memory registry assumes the latter. It's
correct in a single-process Flask dev server; it's silently wrong the
moment you add a second worker for real concurrency.

### The fix

Prometheus's own documented multiprocess pattern, implemented here in three
pieces that all have to be present together:

1. **`PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc`** set in the
   Dockerfile — critically, *before Python starts*, because
   `prometheus_client` checks this environment variable at import time to
   switch which internal value classes it uses (in-memory vs.
   file-backed). Setting it after import does nothing. It lives under
   `/tmp` to match the read-only-root-filesystem pattern the rest of the
   image already follows.
2. **`gunicorn.conf.py`'s `child_exit` hook** calls
   `multiprocess.mark_process_dead()` so a worker that dies or is recycled
   doesn't leave its last-known metric values permanently baked into the
   aggregate — a dead worker's numbers get cleaned up instead of
   contributing stale values forever.
3. **`/metrics` uses `MultiProcessCollector`** to merge every worker's
   file-backed metrics into one response when the env var is set, falling
   back to the ordinary single-process registry when it isn't (e.g.
   running `app.py` directly for local dev, not under gunicorn).

### Re-verification, three layers deep

The fix wasn't accepted on "it should work now." It was re-verified: 30
requests to `/` and 30 to `/status.json` showed as exactly 30 and 30 on
`/metrics`, confirmed a second time through **Prometheus's own query API**
(not just the raw scrape endpoint), and a third time through **Grafana's
datasource-proxy API** — the same number, independently observed at three
different layers of the stack.

### The lesson: who watches the watcher

The instinct when a dashboard looks fine is to trust it — that's the whole
point of a dashboard, to not have to check by hand. But "looks fine" and
"is correct" are different claims, and a monitoring system can fail in a
way that produces a smooth, confident, wrong graph rather than an obvious
gap or error. The only way this bug was caught was by generating a known
quantity of traffic (30 requests) and checking the observed count against
the expected one — treating the metrics pipeline itself as a system under
test, not a ground truth. Any time you stand up new instrumentation,
especially under a multi-process or multi-replica server, verify the count
against a known input before trusting the dashboard. The monitoring system
needs monitoring too — or at minimum, a sanity check on day one.

---

## 5. ELK stack — centralized logging, taught at full depth

**Explicit flag up front: ELK is not deployed anywhere in this repo.**
`observability/` is Prometheus + Grafana — metrics, not centralized logs.
This section is course-required knowledge taught at real depth because
it's standard, expected tooling for this role even where this specific
repo doesn't run it. Do not read this section as "this repo has ELK."

### 5.1 Why metrics aren't enough

Prometheus answers "how many, how fast, how much" — aggregate numeric
questions. It does not answer "what exactly did this one request do" or
"what was in the stack trace." That's a fundamentally different problem —
unstructured or semi-structured text, at high volume, from many sources,
that needs to be searchable after the fact. That's the problem ELK
(Elasticsearch, Logstash, Kibana) solves, and it's the natural complement
to a metrics stack, not a competitor to it: metrics tell you *that*
something is wrong and roughly *when*; logs tell you *what actually
happened*, line by line.

### 5.2 The three components

- **Elasticsearch** — the storage and search engine. A distributed,
  document-oriented datastore built on Apache Lucene, storing logs as JSON
  documents in indices, sharded and replicated across nodes for both
  scale and resilience. Its query DSL supports full-text search, filtering
  on structured fields, and aggregations (count-by-field, time-bucketed
  histograms) — the same aggregation instinct as PromQL, but over
  documents instead of time series.
- **Logstash** — the ingest and transform pipeline. Reads from an input
  (a file, a message queue like Kafka, a Beats shipper), applies filters
  (the most common: `grok` for pattern-matching unstructured text into
  structured fields, `date` for parsing timestamps into the right field,
  `mutate` for renaming/dropping/type-converting fields), and writes to an
  output (almost always Elasticsearch). This is the "parse a raw nginx
  access log line into `{client_ip, method, path, status, bytes,
  response_time}`" stage — the difference between a wall of text and a
  queryable field set.
- **Kibana** — the query and visualization layer on top of Elasticsearch,
  playing the same role for logs that Grafana plays for metrics:
  dashboards, saved searches, and its own query language (KQL) for
  ad-hoc exploration.

### 5.3 Beats — lightweight shippers

Running full Logstash on every host that produces logs is heavyweight —
it's a JVM process with real memory overhead. **Filebeat** (and the other
Beats: Metricbeat, Auditbeat, Packetbeat, each shipping a different signal
type) is the lightweight alternative: a small, low-overhead agent that
tails log files and ships them onward, either directly to Elasticsearch or
through Logstash for heavier transformation. The typical production
topology is:

```
app hosts (Filebeat) → Logstash (parse/enrich) → Elasticsearch → Kibana
```

Filebeat handles the "run efficiently on every node, survive restarts,
resume from where it left off" concerns; Logstash handles the CPU-heavy
parsing centrally, on fewer, bigger nodes, instead of duplicating that cost
on every host.

### 5.4 Index lifecycle management

Log volume grows without bound if left alone, and Elasticsearch performance
and cost both degrade with unbounded index growth. **Index Lifecycle
Management (ILM)** automates the standard pattern: a daily or size-based
rolling index (`app-logs-2026.09.21`), which moves through phases —
**hot** (actively written and queried, on fast storage), **warm** (no
longer written, occasionally queried, can be merged/shrunk), **cold**
(rarely queried, cheaper storage, possibly frozen/searchable snapshots),
and **delete** (past the retention window, removed entirely). This is the
direct logging analogue of `freshness.py`'s scan-summary retention concern
in this repo (§9, Zone 9) — data has a useful lifetime, and a system that
never prunes it either silently degrades or silently keeps something past
when it was authorized to.

### 5.5 A worked query example

Given logs indexed with `client_ip`, `path`, `status`, and `@timestamp`
fields, a Kibana Discover query using KQL to find every 5xx response on a
specific path in the last hour:

```
path: "/checkout" and status >= 500
```

And the same intent as a raw Elasticsearch query DSL request (what Kibana
generates underneath, and what you'd send directly via the `_search` API
or from Logstash's own conditional filters):

```json
GET /app-logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "path": "/checkout" } },
        { "range": { "status": { "gte": 500 } } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  }
}
```

A Kibana aggregation to answer "which paths are erroring most" — the log
equivalent of the Prometheus `sum by (path) (rate(...))` pattern from §2.2
— buckets by `path.keyword` with a `status >= 500` filter and a count
metric, rendered as a bar chart on a dashboard.

### 5.6 The real operational cost

ELK is not free to run at scale, and this needs to be said plainly rather
than glossed over: Elasticsearch is memory- and disk-hungry (JVM heap
sizing is a recurring operational headache), shard count and replica
strategy directly affect both cost and cluster stability, and log volume
from a busy production fleet can dwarf metrics volume by orders of
magnitude — a single verbose service can produce gigabytes of logs per
day where its Prometheus metrics footprint is kilobytes. This is exactly
why the standard shop runs both: Prometheus/Grafana for cheap, always-on
numeric monitoring and alerting, and ELK (or a lighter-weight equivalent
like Grafana's own Loki, which trades full-text indexing for cheaper
label-based log storage) reserved for the deeper, more expensive
after-the-fact investigation. Reaching for full-text log search as the
*first* line of defense, instead of metrics, is a common and expensive
mistake — it's the tool you go to once metrics have told you *where* to
look, not the tool you watch continuously by default.

---

## 6. The four-question triage framework

This is the real, working triage sequence from this repo's `qrg.html`,
reproduced faithfully — not reinvented, because it doesn't need to be. It
exists for exactly the moment described in §1: something's broken, and you
have limited time before the cost of not knowing exceeds the cost of
guessing wrong.

### Q1 — Blast radius? (first 120 seconds; scope decides urgency)

```
kubectl get pods -A | grep -v 'Running\|Completed'
systemctl --failed
kubectl get nodes
df -h
```

Is this one pod, one user, one host — or everything? The answer to Q1
alone often determines whether you're dealing with a SEV1 or a SEV3 (§8).
Ask a second human. Write the answer down — not for ceremony, but because
you will need it later for the postmortem, and because a second person
independently confirming scope catches the case where you're staring at
one symptom that isn't actually the whole picture.

### Q2 — What changed? (the highest-yield question; run the whole battery)

```
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl rollout history deployment/<name> -n <ns>
helm history <release> -n <ns>
git log --oneline --since="24 hours ago"
terraform plan -detailed-exitcode
journalctl --since "-24h" -p warning | tail -40
```

Something almost always changed — a deploy, a config edit, a certificate
rotation, an upstream dependency update, a scheduled job. **Nothing found
usually means you're looking at the wrong layer, not that there's no
cause.** This is the single highest-yield question in the whole framework
because most incidents are not novel failures of otherwise-stable systems
— they're a consequence of something that changed, and the fastest path to
resolution is usually finding that change and reversing it (Q4), not
diagnosing the failure mode from first principles.

### Q3 — Which layer? (walk the request path, half-split)

```
dig <name>
curl -v https://<host>/health
kubectl get endpoints <svc> -n <ns>
kubectl get pods -n <ns>
kubectl logs <pod> -n <ns> --previous
```

The request path, in order: **DNS → LB → ingress → service → endpoints →
pod → app.** Rather than checking every hop in sequence, half-split it:
start at `endpoints` (roughly the midpoint of that chain), and let whether
it's correct tell you which half of the path to check next. This is
ordinary binary search applied to infrastructure, and it turns an
eight-hop linear walk into roughly three checks.

### Q4 — Fastest safe rollback? (answer before any fix attempt)

```
helm rollback <release> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
git revert <sha> && git push
```

**Stabilize first, root-cause second.** If Q2 found the change and a
rollback path exists, take it — before you've fully explained *why* the
change broke things. Restoring service is not the same activity as
understanding the failure, and conflating them under time pressure is how
a five-minute outage becomes a forty-minute one. The postmortem (§8) is
where the "why" gets its full attention, on a timeline that isn't burning
down user impact while you write it.

### Rules of engagement on an unknown system

These apply across all four questions, especially when you're triaging
something you didn't build or don't fully own:

- **Read-only first** — `get`/`describe`/`logs`/`history`/`status` before
  any mutating verb. You cannot un-ring a bell you didn't need to ring.
- **Snapshot before touching** —
  `kubectl get ... -o yaml > was.yaml`,
  `terraform state pull > state.backup.json`. Capture the "before" state
  before you change anything, so a bad guess is reversible and a
  postmortem has ground truth to compare against.
- **Log the terminal** — `script -a /tmp/incident-$(date +%F-%H%M).log`.
  The transcript of what you actually ran, in order, is worth more after
  the fact than your memory of it.
- **One change at a time** — change, verify, record, then the next
  change. Stacking multiple simultaneous changes destroys your ability to
  attribute which one fixed (or worsened) things.
- **Stop and escalate** when the fix touches a security/ATO-boundary
  config, risks data loss, or you've spent 30 minutes with no working
  hypothesis. None of those are failures on your part — they're exactly
  the conditions this rule exists to catch before they become worse ones.

---

## 7. Rapid-fire diagnostic patterns

Faster pattern-matches for common failure shapes, reproduced from the same
source, for when you already know roughly what kind of thing broke.

### Pipeline is red — decode by stage

- **BUILD fails**: read the first error only. Build tool output cascades —
  the fifth error is usually a consequence of the first, not a second
  independent problem.
- **TEST fails**: rerun once at most — twice-failed is real. One retry
  absorbs ordinary flakiness (§9 of Chapter 3 covers this in the build/test
  context directly); a second consecutive failure means stop treating it
  as flake.
- **SCAN fails, no code change**: the CVE database moved. A dependency
  that passed yesterday can fail today with zero commits in between —
  that's the scanner doing its job against a new disclosure, not a broken
  pipeline.
- **DEPLOY fails**: ask what changed on the *target*, not the repo. A
  deploy failure is frequently an environment-state problem (quota,
  permissions, drift) rather than anything wrong with what's being
  deployed.

### Terraform died mid-apply

```
terraform plan                          # shows exactly what landed
terraform apply -replace=<failed-address>
```

**Plan first — never re-apply blind onto a half-applied state.** A partial
apply leaves real infrastructure in an inconsistent state relative to the
config; `plan` tells you precisely what Terraform believes is true right
now before you ask it to change anything further.

### Node NotReady — five suspects

```
systemctl status kubelet
journalctl -u kubelet | tail
df -h
free -m
systemctl status containerd
```

Kubelet down, disk full, memory exhausted, or the container runtime
(containerd) itself unhealthy — check all five before assuming the more
exotic cause.

### Everything down vs. one thing down

If `kubectl` itself is timing out, that's the control plane — go to the
node directly: `crictl ps -a`. If `kubectl` responds fine but services are
failing, that's the workload layer — back to Q3's request-path walk.

### The quiet killer sweep — certificates

```
echo | openssl s_client -connect <host>:443 2>/dev/null \
  | openssl x509 -enddate -noout
kubeadm certs check-expiration
```

Certificate expiry is the "quiet killer" because nothing changed in any
log you'd normally check — the cert was valid yesterday and isn't today,
purely from the calendar. **Date-clustered onset across unrelated
services is the tell**: if TLS failures start appearing across several
independent services at roughly the same moment, check expiry before
anything else.

---

## 8. Severity and communication cadence

### SEV1 / SEV2 / SEV3

- **SEV1** — mission service down, or a security event. Status every
  **30 minutes**, whether or not there's new information — silence during
  a SEV1 reads as "nobody's working it," which is its own problem
  independent of the technical one.
- **SEV2** — degraded, or redundancy lost (still up, but one bad event
  away from SEV1). **Hourly** status.
- **SEV3** — single user affected, or cosmetic. Ticket queue — no forced
  cadence.

**Solo-operator loop**: stabilize → communicate → capture → fix → verify →
write. Communication is not an afterthought bolted onto the technical work
— it's a step in the loop, in order, because stakeholders making decisions
during an incident need current information as much as the system needs a
fix.

### The boring six — check these first

1. Recent change
2. Certificate expiry
3. Disk full / inodes
4. DNS
5. Permissions (RBAC / IAM / SELinux)
6. Resource exhaustion

These are "boring" on purpose — none of them are interesting failure
modes, and that's exactly why they're first: the overwhelming majority of
real incidents trace back to one of these six, and checking all six takes
minutes. Reaching for an exotic hypothesis before ruling out the boring
six is a common way to burn thirty minutes chasing a theory when the
answer was `df -h` away.

### Blameless postmortem structure

Six fields, every time:

1. **Impact** — what broke, for whom, for how long, in concrete terms.
2. **Timeline** — what happened, in order, with timestamps.
3. **Root cause** — stated as **a condition, never a name**. "The
   deployment lacked a readiness probe, so traffic routed to pods before
   they could serve it" is a root cause. "Alex forgot to add a probe" is
   not — it's a person, and it doesn't generalize to preventing the next
   occurrence.
4. **What worked** — which part of the response held up, worth keeping.
5. **What didn't** — which part of the response was slow, wrong, or
   missing, stated as plainly as the failure itself.
6. **Actions, with owner and date** — not "we should improve monitoring
   here" as a vague aspiration, but a specific action assigned to a
   specific person with a specific date, or it doesn't happen.

---

## 9. Day-one checklist for this zone

If you inherit an environment's observability stack — which is the normal
case, not the exception — start here rather than trusting what the
dashboards claim to show:

1. **Find what's actually monitored versus what's silently unmonitored.**
   List every service, host, and scheduled job, and cross-check it against
   actual scrape targets (`Prometheus → Status → Targets`) and alert
   rules. A service with no scrape target isn't "monitored with nothing
   wrong" — it's unmonitored, full stop.
2. **Check alert routing actually reaches a human.** Trigger a test alert
   (or find the last time a real one fired) and trace it all the way
   through Alertmanager's routing tree to wherever it lands. An alert
   rule that's correctly defined but routed to a channel nobody watches,
   or an email address that bounces, is functionally identical to having
   no alert at all — and it's a common, easy-to-miss failure mode
   precisely because the *rule* looks fine on inspection.
3. **Verify dashboards reflect current architecture, not a stale one.**
   A dashboard built against last year's service topology (old service
   names, decommissioned components still queried, new components with no
   panel) actively misleads during an incident. Check that every panel's
   query still resolves against real, current label values.
4. **Identify log retention and access for when you need to dig.** Know
   where logs actually live (centralized ELK/Loki, or `kubectl logs`
   against ephemeral pod storage that's gone the moment the pod is), how
   far back retention goes, and who/what has query access — before an
   incident is the wrong time to be discovering that logs from three days
   ago were already rotated out.
5. **Confirm the scan-freshness pattern (Zone 9's `freshness.py`,
   documented in this repo's `playbook/`) has an observability-layer
   equivalent** — is there anything that would notice if the metrics
   scrape itself silently stopped, the way `freshness.py` notices when a
   scheduled scan silently stops? "Everything's green" and "nothing is
   reporting" render identically on a dashboard that isn't checking for
   the difference.
6. **Sanity-check one real metric against a known input**, the way §4's
   multiprocess bug was caught — generate a known quantity of traffic or
   events and confirm the dashboard shows that quantity, before trusting
   any of the numbers on it.

---

## 10. Incident response cheat sheet

A single scannable block — the Q1–Q4 flow plus the boring six, for the
moment you actually need it and don't have time to reread the chapter.

```
FIRST 120 SECONDS
  Q1 Blast radius?
    kubectl get pods -A | grep -v 'Running\|Completed'
    systemctl --failed ; kubectl get nodes ; df -h
    → one thing or everything? tell a second human, write it down.

  THE BORING SIX — check now, before anything clever
    1 recent change   2 cert expiry   3 disk/inodes
    4 DNS             5 permissions   6 resource exhaustion

NEXT
  Q2 What changed?  (highest-yield question — run all of these)
    kubectl get events -A --sort-by=.lastTimestamp | tail -30
    kubectl rollout history deployment/<n> -n <ns>
    helm history <rel> -n <ns>
    git log --oneline --since="24 hours ago"
    terraform plan -detailed-exitcode
    journalctl --since "-24h" -p warning | tail -40
    → nothing found = wrong layer, not no cause.

  Q3 Which layer?  (half-split the request path)
    DNS -> LB -> ingress -> service -> endpoints -> pod -> app
    dig <name> ; curl -v https://<host>/health
    kubectl get endpoints <svc> -n <ns>
    kubectl logs <pod> -n <ns> --previous
    → start at endpoints, split from there.

THEN — before any fix attempt
  Q4 Fastest safe rollback?
    helm rollback <release> -n <ns>
    kubectl rollout undo deployment/<n> -n <ns>
    git revert <sha> && git push
    → stabilize first, root-cause second.

RULES: read-only first · snapshot before touching · log the terminal
       (script -a) · one change at a time · escalate past 30 min with
       no hypothesis, or if the fix touches a security/ATO boundary.

COMMS: SEV1 = 30 min · SEV2 = hourly · SEV3 = queue.
POSTMORTEM: impact / timeline / root cause (a condition, never a name) /
            what worked / what didn't / actions with owner + date.
```

---

Zone 8 recipes — the exact PromQL queries, alert rules, provisioning
configs, and triage commands referenced throughout this chapter — are
collected for direct reuse in the book's toolkit appendix.
