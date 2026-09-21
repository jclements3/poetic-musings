# syntax=docker/dockerfile:1

########################
# Stage 1: build deps  #
########################
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .

# Install into an isolated prefix so the runtime stage can copy just this,
# not pip/setuptools/build tooling.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

########################
# Stage 2: runtime     #
########################
FROM python:3.12-slim AS runtime

# No apt-get at all: python:3.12-slim already has everything gunicorn/flask need.
# Non-root user with no login shell, no home dir writes required.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /install /usr/local

# python:3.12-slim ships its own pip/setuptools/wheel in every stage,
# independent of the --prefix=/install copy above -- the runtime image
# never needs a package manager, so remove it entirely: smaller attack
# surface, and no CVEs to track in a tool this image will never run.
RUN python3 -m pip uninstall --yes pip setuptools wheel 2>/dev/null; \
    rm -rf /usr/local/lib/python3.12/site-packages/pip* \
           /usr/local/lib/python3.12/site-packages/setuptools* \
           /usr/local/lib/python3.12/site-packages/wheel* \
           /usr/local/bin/pip*

WORKDIR /app
COPY app.py gunicorn.conf.py .

# STATUS.md is mounted read-only at /data in Kubernetes (see k8s/ manifests);
# bake a copy in the image too so `docker run` works standalone.
COPY STATUS.md /data/STATUS.md

# PROMETHEUS_MULTIPROC_DIR must be writable by every gunicorn worker; it
# lives under /tmp so it works under the same read-only-root-filesystem +
# emptyDir-at-/tmp pattern the rest of this image already relies on (see
# app.py's __main__ comment and k8s/base/deployment.yaml's tmp volume).
ENV STATUS_MD_PATH=/data/STATUS.md \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)" || exit 1

# Read-only root filesystem friendly: the only writes are gunicorn's own
# temp needs and the Prometheus multiprocess dir, both under /tmp.
CMD ["sh", "-c", "mkdir -p \"$PROMETHEUS_MULTIPROC_DIR\" && exec gunicorn --config gunicorn.conf.py --bind 0.0.0.0:8080 --workers 2 --threads 2 app:app"]
