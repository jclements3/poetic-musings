#!/usr/bin/env python3
"""secrets.py -- secret scan over a working tree.
Usage: secrets.py [ROOT]        Exit: 0 clean, 1 findings"""
import sys, re
from pathlib import Path
from haskell import (map_, mapMaybe, concat, concatMap, enum,
                     partitionEithers, Ok, Err, NOTHING, sortOn, null)

PATTERNS = [
    ("aws-access-key", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("private-key",    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("github-token",   re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("slack-token",    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
    ("generic-secret", re.compile(r"(?i)\b(api[_-]?key|secret|token|passwd|password)\s*[:=]\s*['\"][^'\"\s]{12,}['\"]")),
]
SKIP = {".git", ".venv", "node_modules", "__pycache__", ".cache", ".scan-out"}
EXT  = {".py",".txt",".md",".yml",".yaml",".json",".toml",".cfg",".ini",
        ".sh",".env",".tf",".hs",".c",".h",".el"}

hits = lambda path: lambda pair: mapMaybe(
    lambda pn: dict(rule=pn[0], file=str(path), line=pair[0],
                    text=pair[1].strip()[:80]) if pn[1].search(pair[1]) else NOTHING,
    PATTERNS)

def scan(path):
    try:
        txt = path.read_text(errors="replace")
    except OSError as e:
        return Err(f"{path}: {e}")
    return Ok(concatMap(hits(path), enum(txt.splitlines(), 1)))

walk = lambda root: [p for p in root.rglob("*")
                     if p.is_file() and p.suffix in EXT and not SKIP & set(p.parts)]

def main(root):
    oks, errs = partitionEithers(map_(scan, walk(root)))
    findings  = sortOn(lambda f: (f["file"], f["line"]), concat(oks))
    for f in findings:
        print(f"{f['file']}:{f['line']}: {f['rule']}: {f['text']}")
    for e in errs:
        print(f"warn: {e}", file=sys.stderr)
    return 0 if null(findings) else 1

if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
