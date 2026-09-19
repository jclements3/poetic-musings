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

WORKDIR /app
COPY app.py .

# STATUS.md is mounted read-only at /data in Kubernetes (see k8s/ manifests);
# bake a copy in the image too so `docker run` works standalone.
COPY STATUS.md /data/STATUS.md

ENV STATUS_MD_PATH=/data/STATUS.md \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)" || exit 1

# Read-only root filesystem friendly: gunicorn needs no writable dirs for this app.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "2", "app:app"]
