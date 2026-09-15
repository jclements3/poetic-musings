#!/usr/bin/env python
"""SW-005 replay gate: canonical twin set -> ingest -> fuse -> validate.

The one script both `make ci` and .github/workflows/ci.yml run — the
human path and the CI path are literally the same commands (lesson 15).

Canonical set: seeds 1001-1003, --imperfect, generated into data/twin-ci/
and cached keyed on a hash of software/maiden/twin/** SOURCE plus the
seed — a cached dataset from an older twin silently tests the wrong
thing, which is worse than a slow build. Thresholds are absolute (the
SYS numbers from config/thresholds.yaml), never golden-file diffs.

HIL half (lesson 15, dataset lands in maiden45): data/hil/ (or data/HIL/)
is checked structurally when present; until then the job SKIPS WITH A
VISIBLE NOTICE — skips are explicit, never silent.

Exit nonzero on any threshold breach or structural failure.
"""

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "software"))

SEEDS = (1001, 1002, 1003)
CACHE = REPO / "data" / "twin-ci"


def twin_source_hash() -> str:
    # The cached .ch10 bytes depend on more than twin/**: the packet
    # writer, TMATS renderer, time-payload encoding, and geo all shape
    # the files. Hashing only twin/** let an encoding change (e.g. the
    # BCD layout fix) poison the cache silently — found by adversarial
    # review. Hash every module that touches the written bytes.
    h = hashlib.sha256()
    roots = [REPO / "software/maiden/twin", REPO / "software/maiden/ch10"]
    singles = [REPO / "software/maiden/timebase.py",
               REPO / "software/maiden/tmats.py",
               REPO / "software/maiden/geo.py"]
    files = sorted(p for r in roots for p in r.rglob("*.py")) + singles
    for p in files:
        h.update(p.name.encode())
        h.update(p.read_bytes())
    return h.hexdigest()[:16]


def ensure_session(seed: int, src_hash: str) -> Path:
    d = CACHE / f"seed-{seed}"
    manifest = d / "MANIFEST.json"
    if manifest.exists():
        m = json.loads(manifest.read_text())
        if m.get("twin_source_hash") == src_hash and m.get("seed") == seed:
            print(f"[replay] seed {seed}: cache hit ({src_hash})")
            return d
        print(f"[replay] seed {seed}: STALE cache "
              f"({m.get('twin_source_hash')} != {src_hash}) — regenerating")
        shutil.rmtree(d)
    else:
        print(f"[replay] seed {seed}: no cache — generating")
    d.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [sys.executable, "-m", "maiden.twin",
         "--out", str(d), "--seed", str(seed), "--imperfect"],
        check=True, cwd=REPO,
    )
    manifest.write_text(json.dumps(
        {"seed": seed, "twin_source_hash": src_hash, "imperfect": True}))
    return d


def margin(value: float, limit: float, higher_is_better: bool) -> float:
    """Signed percent margin to the threshold (positive = inside)."""
    if limit == 0.0:
        # Pathological (e.g., a corrupted thresholds file): no meaningful
        # percentage; report maximally-breached so the flag still prints.
        return float("-inf")
    if higher_is_better:
        return 100.0 * (value - limit) / limit
    return 100.0 * (limit - value) / limit


def replay_sessions() -> bool:
    from maiden.validate import (
        CONTINUITY_MIN,
        POS_RMS_MAX_M,
        VEL_RMS_MAX_MPS,
        run_session,
    )

    src_hash = twin_source_hash()
    ok = True
    for seed in SEEDS:
        d = ensure_session(seed, src_hash)
        report = run_session(d, flight_name=f"twin-{seed}")
        fm = report["flight"]
        rows = [
            ("SYS-002 pos RMS", fm["pos_rms"], POS_RMS_MAX_M, False, "m"),
            ("SYS-003 vel RMS", fm["vel_rms"], VEL_RMS_MAX_MPS, False, "m/s"),
            ("SYS-004 continuity", fm["continuity"], CONTINUITY_MIN, True, ""),
        ]
        print(f"[replay] seed {seed}: "
              f"{'PASS' if fm['passed'] else 'FAIL'} (sync={fm['sync']})")
        for name, v, lim, hib, unit in rows:
            m = margin(v, lim, hib)
            flag = "ok" if m >= 0 else "BREACH"
            print(f"  {name}: {v:.3f} {unit} vs {lim} "
                  f"({m:+.1f}% margin) [{flag}]")
            # A 2%-margin pass deserves different attention than a 60% one.
            if 0 <= m < 5:
                print(f"  {name}: NOTE thin margin ({m:+.1f}%)")
        if not fm["passed"]:
            ok = False
    return ok


def hil_block() -> bool:
    hil = next((p for p in (REPO / "data/hil", REPO / "data/HIL")
                if p.is_dir()), None)
    if hil is None:
        print("=" * 64)
        print("[replay] HIL SKIPPED: data/hil/ absent — the bench Station 1 "
              "dataset lands in maiden45 (lesson 20). This skip is loud on "
              "purpose; do not silence it, record the dataset.")
        print("=" * 64)
        return True
    # Structural + statistical checks only: HIL has no truth file.
    from maiden.ingest import load, summarize  # noqa: F401
    ok = True
    stations = sorted(hil.glob("STATION_*.ch10"))
    if not stations:
        print(f"[replay] HIL FAIL: {hil} has no STATION_*.ch10")
        return False
    for p in stations:
        n = sum(1 for _ in load(p))
        print(f"[replay] HIL {p.name}: {n} samples ingest cleanly")
        ok = ok and n > 0
    return ok


def main() -> int:
    ok = replay_sessions()
    ok = hil_block() and ok
    print(f"[replay] RESULT: {'GREEN' if ok else 'RED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
