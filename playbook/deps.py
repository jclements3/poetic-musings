#!/usr/bin/env python3
"""deps.py -- requirements.txt pin audit via haskell.py parser combinators.
Usage: deps.py REQUIREMENTS     Exit: 0 all pinned, 1 unpinned/unparsed"""
import sys
from pathlib import Path
from haskell import (doP, rx, lit, alt, sepBy, runParser, pipe,
                     map_, mapMaybe, partition, partitionEithers, NOTHING, null)

name    = rx(r"[A-Za-z0-9][A-Za-z0-9._-]*")
extras  = rx(r"\[[^\]]*\]")
op      = rx(r"==|~=|>=|<=|!=|<|>")
version = rx(r"[A-Za-z0-9.*+!_-]+")
opt     = lambda p: alt(p, lambda s: ("", s))

@doP
def spec():
    f = yield op
    v = yield version
    return f + v

@doP
def req():
    n  = yield name
    _  = yield opt(extras)
    ss = yield sepBy(spec(), lit(","))
    return (n, ss)

REQ   = req()
clean = lambda ln: pipe(ln.split("#", 1)[0].strip(),
                        lambda s: NOTHING if not s or s.startswith("-") else s)
pinned = lambda r: any(s.startswith("==") for s in r[1])

def main(path):
    oks, errs   = partitionEithers(map_(lambda ln: runParser(REQ, ln),
                                        mapMaybe(clean, path.read_text().splitlines())))
    good, loose = partition(pinned, oks)
    for n, ss in loose:
        print(f"UNPINNED {n} {','.join(ss) or '(any)'}")
    for e in errs:
        print(f"PARSE    {e}", file=sys.stderr)
    print(f"{len(good)} pinned, {len(loose)} unpinned, {len(errs)} unparsed")
    return 0 if null(loose) and null(errs) else 1

if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
