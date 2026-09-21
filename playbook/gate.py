#!/usr/bin/env python3
"""gate.py -- policy gate over triage summaries.
Usage: gate.py POLICY.json SUMMARY.json...    Exit: 0 pass, 1 fail, 2 bad input"""
import sys, json
from pathlib import Path
from haskell import (doE, Ok, Err, traverseE, mconcat, All, map_, null, snd)

def load(p):
    try:
        return Ok((p, json.loads(Path(p).read_text())))
    except (OSError, json.JSONDecodeError) as e:
        return Err(f"{p}: {e}")

def violations(pol, name, s):
    v = []
    if s["worst"] > pol.get("max_worst", 3):
        v.append(f"worst severity {s['worst']} > {pol['max_worst']}")
    if s["total"] > pol.get("max_total", 10**9):
        v.append(f"total {s['total']} > {pol['max_total']}")
    for lvl in pol.get("deny_levels", []):
        if (n := s["by_level"].get(lvl, 0)):
            v.append(f"{n} '{lvl}' finding(s) denied by policy")
    return v

@doE
def inputs(argv):
    pol  = yield load(argv[0])
    sums = yield traverseE(load, argv[1:])
    return (pol[1], sums)

def main(argv):
    r = inputs(argv)
    if r[0] == "err":
        print(f"gate: {r[1]}", file=sys.stderr)
        return 2
    pol, sums = r[1]
    per    = [(p, violations(pol, p, s)) for p, s in sums]
    passed = mconcat(All, map_(lambda pv: null(snd(pv)), per))
    for p, vs in per:
        print(f"{'PASS' if null(vs) else 'FAIL'} {p}")
        for v in vs:
            print(f"       - {v}")
    print("GATE", "PASS" if passed else "FAIL")
    return 0 if passed else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
