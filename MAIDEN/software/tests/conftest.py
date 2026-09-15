"""Shared test helpers. Keep append-friendly: later sprints add fixtures."""
import numpy as np

from maiden.state import validate


def check_adapter_stream(samples):
    """Every adapter test in lessons 08 and 22 calls this. VT-14's core."""
    last = {}
    for s in samples:
        validate(s)
        assert s.t_utc >= last.get(s.source, -np.inf), "t_utc regressed"
        last[s.source] = s.t_utc
