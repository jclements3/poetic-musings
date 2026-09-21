# Jenkins agent/controller with the same security-gate CLIs used by
# .github/workflows/security.yml, installed so the Jenkinsfile can run the
# identical commands as literal shell steps instead of GitHub Actions
# marketplace actions (which have no Jenkins equivalent).
FROM jenkins/jenkins:lts-jdk17

USER root

# python3/pip for ruff, pytest, bandit, pip-audit (same tools ci.yml/security.yml use)
# docker CLI (not a daemon) so the container-scan stage can build the app
# image via the host's docker.sock, mounted in docker-compose.yml
# (docker-outside-of-docker pattern -- no dind, no privileged container).
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv curl ca-certificates gnupg unzip \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# gitleaks (secrets scan)
RUN curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz \
      -o /tmp/gitleaks.tgz \
    && tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks \
    && rm /tmp/gitleaks.tgz

# syft (SBOM)
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
      | sh -s -- -b /usr/local/bin v1.18.1

# trivy (container image + IaC config scan; tfsec is deprecated/merged into
# `trivy config` upstream per docs.html -- see Jenkinsfile note).
# The upstream install.sh script fails under `set -o pipefail`-free sh here
# with no useful error (see jenkins/README.md bug log); install the .deb
# directly from the GitHub release instead.
RUN curl -fsSL https://github.com/aquasecurity/trivy/releases/download/v0.74.0/trivy_0.74.0_Linux-64bit.deb \
      -o /tmp/trivy.deb \
    && dpkg -i /tmp/trivy.deb \
    && rm /tmp/trivy.deb

# kube-linter (k8s manifest scan)
RUN curl -fsSL https://github.com/stackrox/kube-linter/releases/download/v0.7.1/kube-linter-linux.tar.gz \
      -o /tmp/kube-linter.tgz \
    && tar -xzf /tmp/kube-linter.tgz -C /usr/local/bin kube-linter \
    && rm /tmp/kube-linter.tgz

# pip-audit, bandit, ruff, pytest run inside a venv created at build time in
# the pipeline (PEP 668 "externally-managed-environment" blocks a bare
# `pip install` on this base image -- see jenkins/README.md bug log).

# The jenkins user needs group access to the host's mounted docker.sock to
# `docker build` for the container-scan stage (docker-outside-of-docker).
# GID is passed at build time to match the host's docker group (`getent
# group docker`), since it varies per host -- see jenkins/README.md bug log.
ARG DOCKER_GID=987
RUN groupadd -g ${DOCKER_GID} dockerhost 2>/dev/null || true \
    && usermod -aG ${DOCKER_GID} jenkins

USER jenkins
