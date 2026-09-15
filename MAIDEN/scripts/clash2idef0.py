#!/usr/bin/env python3
"""clash2idef0 -- generate an IDEF0 model (idef0-kit DSL) from Clash sources.

The F (firmware) plates are DERIVED from the code, not maintained beside
it: rerun this after changing the Clash and the drawing set cannot drift.

What is extracted, and from where (conventions of this codebase):

  activity boxes   one per "block function" -- an exported function whose
                   signature mentions Signal/HiddenClockResetEnable.
  i / o ports      fields of the block's <Prefix>In / <Prefix>Out records
                   (prefix stripped, camelCase -> Title Case); for
                   functions without record ports, `-- ^` haddock comments
                   on Signal arguments; for the root topEntity, the
                   PortName list of the Synthesize annotation.
  hierarchy        module A is the parent of block b when A imports b's
                   module and applies b in its body; the instantiation
                   tree becomes the plate decomposition.
  multiplicity     a block applied more than once in its parent gets an
                   `## instantiated xN` doc attribute (the QuadX idiom)
                   rather than N boxes.
  ## docs          the first paragraph of each module's haddock header.
  m mechanisms     none are invented; add measured primitive usage by
                   hand in a wrapper model if wanted.

Wiring is deliberately left to the kit's name rule (same flow name =>
connected).  Where the code connects ports whose names disagree (e.g. a
producer's ChangeEdge feeding a consumer's EdgeType), the flows come out
unconnected and appear as boundary arrows on the plate: that is a true
statement about the code's naming, made visible for review instead of
being silently bridged.

Usage:
  clash2idef0.py LETTER TITLE FILE.hs...   > model.txt
"""

import re
import sys


def strip_comments(src: str) -> str:
    src = re.sub(r"\{-.*?-\}", "", src, flags=re.DOTALL)
    return "\n".join(ln for ln in src.splitlines()
                     if not ln.lstrip().startswith("--"))


def title_case(field: str) -> str:
    # esoEdgePosition -> Edge Position   (strip the lowercase prefix)
    m = re.match(r"[a-z]+(?=[A-Z])", field)
    body = field[m.end():] if m else field
    words = re.findall(r"[A-Z][a-z0-9]*|[0-9]+", body)
    return " ".join(words) if words else field


def block_docs_stripped(src: str) -> str:
    return re.sub(r"\{-.*?-\}", "", src, flags=re.DOTALL)


def module_name(src: str) -> str:
    # parse the real declaration, not prose in a haddock header
    m = re.search(r"^module\s+([\w.]+)", block_docs_stripped(src), re.MULTILINE)
    return m.group(1) if m else "?"


def first_doc_paragraph(src: str) -> str:
    m = re.search(r"\{-\|(.*?)(?:\n\s*\n|-\})", src, re.DOTALL)
    if not m:
        return ""
    text = " ".join(ln.strip() for ln in m.group(1).splitlines())
    text = re.sub(r"[@'\"]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def records(src: str) -> dict:
    """name -> [field, ...] for every record data decl."""
    out = {}
    for m in re.finditer(
            r"^data\s+(\w+)[^=]*=\s*\w+\s*\n?\s*\{(.*?)\}\s*\n",
            strip_comments(src) + "\n", re.DOTALL | re.MULTILINE):
        fields = re.findall(r"(\w+)\s*::", m.group(2))
        out[m.group(1)] = fields
    return out


def block_functions(src: str) -> list:
    """Exported functions whose type signature involves Signal."""
    m = re.search(r"^module\s+[\w.]+\s*\((.*?)\)\s*where",
                  block_docs_stripped(src), re.DOTALL | re.MULTILINE)
    exports = re.findall(r"(?:^|,)\s*([a-z]\w*)\s*(?=,|$)",
                         m.group(1), re.MULTILINE) if m else []
    blocks = []
    for name in exports:
        sig = re.search(rf"^{name}\s*::(.*?)(?=^\S)", src, re.DOTALL | re.MULTILINE)
        if sig and ("Signal" in sig.group(1)
                    or "HiddenClockResetEnable" in sig.group(1)):
            blocks.append((name, sig.group(1)))
    return blocks


def haddock_ports(sig: str) -> tuple:
    """`Signal dom X ->  -- ^ @NAME@` comments; a Signal line without an
    arrow is the function result, i.e. the o port."""
    ins, outs = [], []
    for line in sig.splitlines():
        m = re.search(
            r"Signal.*?--\s*\^\s*@?([\w][\w ]*?)@?\s*(?:[,.].*)?$", line)
        if not m:
            continue
        name = m.group(1).strip()
        name = name.title() if name.islower() else name
        (ins if "->" in line else outs).append(name)
    return ins, outs


def ann_ports(src: str) -> tuple:
    ins = re.findall(r'PortName\s+"(\w+)"',
                     src.split("t_inputs", 1)[-1].split("t_output", 1)[0]) \
        if "t_inputs" in src else []
    outs = re.findall(r'PortName\s+"(\w+)"',
                      src.split("t_output", 1)[-1]) \
        if "t_output" in src else []
    return ins, outs


def main() -> int:
    letter, model_title, *paths = sys.argv[1:]
    mods = {}
    for p in paths:
        with open(p, encoding="utf-8") as fh:
            src = fh.read()
        mods[module_name(src)] = src

    # every candidate block, keyed by function name
    info = {}
    for mod, src in mods.items():
        recs = records(src)
        for fn, sig in block_functions(src):
            if fn in ("topEntity",):
                continue
            pref = fn[0].upper() + fn[1:]
            rin = next((recs[r] for r in recs
                        if r.lower().startswith(fn[:4].lower())
                        and r.endswith("In")), None)
            rout = next((recs[r] for r in recs
                         if r.lower().startswith(fn[:4].lower())
                         and r.endswith("Out")), None)
            # fall back to the module's single In/Out record, but only
            # when this is the module's only block (else misattribution)
            sole = len(block_functions(src)) - (
                1 if "topEntity" in dict(block_functions(src)) else 0) == 1
            if rin is None and sole:
                only = [r for r in recs if r.endswith("In")]
                rin = recs[only[0]] if len(only) == 1 else None
            if rout is None and sole:
                only = [r for r in recs if r.endswith("Out")]
                rout = recs[only[0]] if len(only) == 1 else None
            h_ins, h_outs = haddock_ports(sig)
            ins = [title_case(f) for f in rin] if rin else h_ins
            outs = [title_case(f) for f in rout] if rout else h_outs
            info[fn] = {"mod": mod, "title": title_case(pref) or pref,
                        "ins": ins, "outs": outs,
                        "doc": first_doc_paragraph(src)}

    # parent -> [(child fn, count)] via imports + application counts,
    # scoped to the parent function's own definition region so a call in
    # a sibling function in the same file is not double-attributed.
    def fn_region(src_clean: str, fn: str) -> str:
        tops = [(m.start(), m.group(1)) for m in
                re.finditer(r"^([a-z]\w*)", src_clean, re.MULTILINE)]
        parts, take = [], False
        for i, (pos, name) in enumerate(tops):
            end = tops[i + 1][0] if i + 1 < len(tops) else len(src_clean)
            if name == fn:
                take = True
            elif name != fn and take and name not in ("where",):
                take = False
            if name == fn:
                parts.append(src_clean[pos:end])
        return "".join(parts)

    children = {fn: [] for fn in info}
    for fn, d in info.items():
        body = fn_region(strip_comments(mods[d["mod"]]), fn)
        for other, od in info.items():
            if other == fn:
                continue
            same = od["mod"] == d["mod"]
            imported = re.search(
                rf"^import\s+{re.escape(od['mod'])}\b",
                mods[d["mod"]], re.MULTILINE)
            if same or imported:
                n = len(re.findall(rf"[^\w]{other}[^\w]", body))
                if n:
                    children[fn].append((other, n))

    nested = {c for kids in children.values() for c, _ in kids}
    roots = [fn for fn in info if fn not in nested]

    def emit(fn, depth, count=1):
        d = info[fn]
        pad = "  " * depth
        print(f"{pad}a# {d['title']}")
        doc = d["doc"]
        if count > 1:
            doc = f"Instantiated x{count} by the parent. " + doc
        if doc:
            if len(doc) > 200:
                doc = doc[:200].rsplit(" ", 1)[0] + " ..."
            print(f"{pad}## {doc}")
        src = mods[d["mod"]]
        ins, outs = (d["ins"], d["outs"])
        if not ins and "t_inputs" in src:
            a_in, a_out = ann_ports(src)
            ins = [t.replace("_", " ").title() for t in a_in
                   if t not in ("CLK", "RESET")]
            outs = [t.replace("_", " ").title() for t in a_out]
        for name in ins:
            print(f"{pad}  i# {name}")
        for name in outs:
            print(f"{pad}  o# {name}")
        for child, n in sorted(children[fn],
                               key=lambda c: info[c[0]]["title"]):
            emit(child, depth + 1, n)

    print("; -*- mode: idef0 -*-")
    print("; GENERATED by scripts/clash2idef0.py -- do not edit; rerun:")
    print(f";   scripts/clash2idef0.py {letter} '{model_title}' "
          "<the same .hs files>")
    print(f"t{letter} {model_title}")
    print("## Derived from the Clash sources: boxes are block functions,")
    print("## ports are In/Out record fields, decomposition is the")
    print("## instantiation tree. Unconnected arrows are real port-name")
    print("## mismatches in the code, left visible on purpose.")
    for r in sorted(roots, key=lambda f: info[f]["title"]):
        emit(r, 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
