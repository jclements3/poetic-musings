#!/usr/bin/env python3
"""cve.py -- pip-audit JSON -> gate-compatible summary on stdout.
Usage: pip-audit -r reqs.txt -f json -o out.json; cve.py out.json > cve.summary.json
Exit: 0 (gate.py decides)"""
import sys, json
from pathlib import Path
from haskell import (concatMap, map_, fromListWith, add, sortOn, take, null)

rows_of = lambda audit: concatMap(
    lambda d: [dict(rule=v["id"], level="error", file=f"{d['name']}=={d['version']}",
                    fix=",".join(v.get("fix_versions", [])) or "none")
               for v in d.get("vulns", [])],
    audit.get("dependencies", []))

def main(path):
    rows = rows_of(json.loads(path.read_text()))
    print(json.dumps(dict(
        tool     = "pip-audit",
        total    = len(rows),
        by_level = fromListWith(add, [(r["level"], 1) for r in rows]),
        top_rules= take(5, sortOn(lambda kv: -kv[1],
                    list(fromListWith(add, [(r["file"], 1) for r in rows]).items()))),
        worst    = 0 if null(rows) else 3), indent=2))
    for r in rows:
        print(f"{r['file']}: {r['rule']} fix={r['fix']}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
