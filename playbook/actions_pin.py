#!/usr/bin/env python3
"""actions_pin.py -- flag GitHub Actions not pinned to a full commit SHA.
Usage: actions_pin.py WORKFLOW.yml...     Exit: 0 all pinned, 1 findings"""
import sys, re
from pathlib import Path
from haskell import (concatMap, mapMaybe, enum, NOTHING, null, sortOn)

USES = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
OK   = re.compile(r"@[0-9a-f]{40}$")
LOCAL = ("./", "docker://")

def flag(path):
    def line(pair):
        m = USES.match(pair[1])
        if not m: return NOTHING
        ref = m.group(1)
        if ref.startswith(LOCAL) or OK.search(ref): return NOTHING
        return (str(path), pair[0], ref)
    return line

audit = lambda paths: concatMap(
    lambda p: mapMaybe(flag(p), enum(p.read_text().splitlines(), 1)), paths)

def main(argv):
    findings = sortOn(lambda f: f[:2], audit(map(Path, argv)))
    for f, n, ref in findings:
        print(f"{f}:{n}: tag-pinned action: {ref}")
    return 0 if null(findings) else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
