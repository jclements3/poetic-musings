"""Adapter registry: everything below IF-4 registers here.

The adapter contract (enforced by ``check_adapter_stream`` in the test
suite, which is VT-14's engine):

- An adapter is a callable registered under a kind string, e.g.
  ``@adapter("ch10.station")`` or ``@adapter("ardupilot.bin")``.
- It takes a source path plus its descriptor (a ``Station`` or
  ``Aircraft``, parsed from TMATS) and yields ``StateSample`` objects.
- Emitted samples are in nondecreasing ``t_utc`` per source, and every
  one of them passes :func:`maiden.state.validate`.

New sensors and log formats are adapters that emit IF-4; consumers above
ingest never change.
"""
from collections.abc import Callable

_REGISTRY: dict[str, Callable] = {}


def adapter(kind: str):
    """Decorator: @adapter("ch10.station"), @adapter("ardupilot.bin"), ..."""
    def register(fn: Callable) -> Callable:
        if kind in _REGISTRY:
            raise ValueError(f"adapter kind {kind!r} already registered")
        _REGISTRY[kind] = fn
        return fn
    return register


def get(kind: str) -> Callable:
    """Return the adapter callable or raise a KeyError naming known kinds."""
    try:
        return _REGISTRY[kind]
    except KeyError:
        known = ", ".join(sorted(_REGISTRY)) or "(none registered)"
        raise KeyError(f"no adapter for {kind!r}; known kinds: {known}") from None


def kinds() -> tuple[str, ...]:
    """Registered adapter kinds, sorted (introspection/tests)."""
    return tuple(sorted(_REGISTRY))
