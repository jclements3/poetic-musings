#!/usr/bin/env python3
"""triage.py -- SARIF triage: aggregate findings into a summary JSON on stdout.
Usage: triage.py FILE.sarif [WAIVERS.json] > summary.json     Exit: 0
Waiver: {"rule": "B602", "path": "app/run.py", "reason": "...", "expires": "2026-12-31"}"""
import sys, json
from datetime import date
from pathlib import Path
from haskell import (doM, maybe_get, getpath, listToMaybe, mapMaybe, fromMaybe,
                     bind, fromListWith, foldMap, MaxM, sortOn, take, lookup,
                     add, concatMap, null, partition, filter_)

SEV  = [("error", 3), ("warning", 2), ("note", 1), ("none", 0)]
rank = lambda lvl: fromMaybe(0, lookup(lvl, SEV))

@doM
def row(r):
    rule = yield maybe_get(r, "ruleId")
    loc  = yield listToMaybe(r.get("locations", []))
    uri  = yield getpath(loc, ["physicalLocation", "artifactLocation", "uri"])
    return dict(rule=rule, level=r.get("level", "warning"), file=uri)

active = lambda today: lambda w: w.get("expires", "9999") >= today
waived = lambda ws: lambda r: any(
    w["rule"] == r["rule"] and r["file"].startswith(w.get("path", "")) for w in ws)

def main(path, wpath):
    sarif = json.loads(path.read_text())
    runs  = sarif.get("runs", [])
    ws    = filter_(active(date.today().isoformat()),
                    json.loads(wpath.read_text()) if wpath else [])
    out, rows = partition(waived(ws), 
                mapMaybe(row, concatMap(lambda run: run.get("results", []), runs)))
    tool  = fromMaybe("unknown",
            bind(listToMaybe(runs), lambda r: getpath(r, ["tool", "driver", "name"])))
    summary = dict(
        tool     = tool,
        total    = len(rows),
        by_level = fromListWith(add, [(r["level"], 1) for r in rows]),
        top_rules= take(5, sortOn(lambda kv: -kv[1],
                    list(fromListWith(add, [(r["rule"], 1) for r in rows]).items()))),
        waived   = len(out),
        worst    = 0 if null(rows) else foldMap(lambda r: rank(r["level"]), MaxM, rows))
    print(json.dumps(summary, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) > 2 else None))
