#!/usr/bin/env python3
"""freshness.py -- zone 8: alert when scheduled scans silently stop.
Usage: freshness.py MAX_AGE_HOURS SUMMARY.json...   Exit: 0 fresh, 1 stale"""
import sys, time
from pathlib import Path
from haskell import map_, partition, null

def main(max_h, paths):
    now = time.time()
    age = lambda p: (p, (now - p.stat().st_mtime) / 3600)
    stale, fresh = partition(lambda pa: pa[1] > max_h, map_(age, map(Path, paths)))
    for p, a in stale: print(f"STALE {p} ({a:.1f}h > {max_h}h)")
    for p, a in fresh: print(f"OK    {p} ({a:.1f}h)")
    return 0 if null(stale) else 1

if __name__ == "__main__":
    sys.exit(main(float(sys.argv[1]), sys.argv[2:]))
