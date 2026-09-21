"""gunicorn config: only exists for the Prometheus multiprocess hook.

Without child_exit, a dead worker's metric files under
PROMETHEUS_MULTIPROC_DIR are never cleaned up -- they'd keep contributing
stale counter values to every future /metrics scrape forever.
"""
from prometheus_client import multiprocess


def child_exit(server, worker):
    multiprocess.mark_process_dead(worker.pid)
