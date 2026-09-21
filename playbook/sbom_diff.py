#!/usr/bin/env python3
"""sbom_diff.py -- diff two CycloneDX SBOMs (added/removed/version-changed).
Usage: sbom_diff.py OLD.json NEW.json      Exit: 0 (informational)"""
import sys, json
from pathlib import Path
from haskell import mapMaybe, NOTHING, sortOn, null

comps = lambda s: dict(mapMaybe(
    lambda c: (c["name"], c.get("version", "?")) if "name" in c else NOTHING,
    s.get("components", [])))

def main(old, new):
    a, b = (comps(json.loads(Path(p).read_text())) for p in (old, new))
    added   = sortOn(str, b.keys() - a.keys())
    removed = sortOn(str, a.keys() - b.keys())
    changed = sortOn(str, [(k, a[k], b[k]) for k in a.keys() & b.keys() if a[k] != b[k]])
    for k in added:         print(f"+ {k}=={b[k]}")
    for k in removed:       print(f"- {k}=={a[k]}")
    for k, va, vb in changed: print(f"~ {k} {va} -> {vb}")
    print(f"{len(added)} added, {len(removed)} removed, {len(changed)} changed")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
