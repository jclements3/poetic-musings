"""LESSON 1 — the client and twelve-factor configuration.

Goal: construct a Lattice client from environment variables with sane
defaults, the way a coding test expects config to be handled.

Key facts about this SDK (v4.29.x):
  * import name is `anduril`; the client class is anduril.client.Lattice
  * EVERYTHING is keyword-only: Lattice(token=..., base_url=...)
  * auth is a bearer token: token= a string OR a zero-arg callable (rotation!)
  * you can inject an httpx.Client — that is the door to offline testing
"""
import os
import inspect

from anduril.client import Lattice
import harness

# --- WORKED EXAMPLE ---------------------------------------------------------
# 1. Discover a signature instead of guessing (do this in the test!):
sig = inspect.signature(Lattice.__init__)
print("Lattice takes:", ", ".join(list(sig.parameters)[1:8]), "...")

# 2. Config precedence: explicit arg > env var > default.
def make_lattice_from_env(**overrides):
    cfg = {
        "base_url": os.environ.get("LATTICE_URL", "https://mock.lattice.local"),
        "token": os.environ.get("LATTICE_TOKEN", "offline-lesson-token"),
        "timeout": float(os.environ.get("LATTICE_TIMEOUT", "10")),
    }
    cfg.update(overrides)
    return Lattice(**cfg)

client = make_lattice_from_env()
print("client resources:", [a for a in dir(client) if not a.startswith("_")])

# 3. A token CALLABLE lets you rotate credentials without rebuilding the client:
tokens = iter(["tok-1", "tok-2", "tok-3"])
rotating = make_lattice_from_env(token=lambda: next(tokens))
print("token-callable client built OK:", rotating is not None)

# --- EXERCISES --------------------------------------------------------------
# E1. Write env_flag(name, default) -> bool that treats "1/true/yes/on"
#     (any case) as True and everything else as False; use it to add a
#     LATTICE_VERBOSE flag to make_lattice_from_env (print cfg when set).
# E2. make_lattice_from_env silently produces a broken client if
#     LATTICE_TIMEOUT is "ten". Fix it: fall back to the default AND collect a
#     warning string; return (client, warnings).
# E3. Using inspect.signature only (no docs), list every Lattice.__init__
#     parameter whose default is None.

# --- SOLUTIONS (run with SOLUTIONS=1) ---------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def env_flag(name, default=False):
        raw = os.environ.get(name)
        if raw is None:
            return default
        return raw.strip().lower() in ("1", "true", "yes", "on")

    def make_lattice_from_env2(**overrides):
        warnings = []
        raw_t = os.environ.get("LATTICE_TIMEOUT", "10")
        try:
            timeout = float(raw_t)
        except ValueError:
            warnings.append(f"LATTICE_TIMEOUT={raw_t!r} is not a number; using 10")
            timeout = 10.0
        cfg = {
            "base_url": os.environ.get("LATTICE_URL", "https://mock.lattice.local"),
            "token": os.environ.get("LATTICE_TOKEN", "offline-lesson-token"),
            "timeout": timeout,
        }
        cfg.update(overrides)
        if env_flag("LATTICE_VERBOSE"):
            print("cfg:", {k: v for k, v in cfg.items() if k != "token"})
        return Lattice(**cfg), warnings

    os.environ["LATTICE_TIMEOUT"] = "ten"
    _, warns = make_lattice_from_env2()
    print("E2 warnings:", warns)
    del os.environ["LATTICE_TIMEOUT"]

    none_defaults = [n for n, p in sig.parameters.items()
                     if p.default is None]
    print("E3 None-default params:", none_defaults)
    print("lesson01 solutions OK")
