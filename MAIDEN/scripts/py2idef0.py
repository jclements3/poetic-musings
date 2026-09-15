#!/usr/bin/env python3
"""py2idef0 -- generate an IDEF0 model (idef0-kit DSL) from Python sources.

Sibling of clash2idef0.py for the laptop-side pipeline: the model is
DERIVED from the code via the ast module, so it cannot drift.

Extraction rules:

  activity boxes   public top-level functions that participate in the
                   cross-module call graph of the given files -- either
                   called from another input module, or calling into one.
                   Intra-module math helpers stay off the plates.
  i ports          function parameters (self/cls skipped), Title Case.
  o ports          the return annotation; project dataclass names are
                   used verbatim (StateSample, FuseStats), containers are
                   unwrapped, unannotated returns yield no o port --
                   visible pressure to annotate.
  hierarchy        caller -> callee across modules; call count > 1
                   becomes an `## Called xN` attribute.
  ## docs          the function docstring's first line, else the module
                   docstring's first line (these carry the SYS/D refs).

Usage:
  py2idef0.py LETTER TITLE FILE.py...   > model.txt
"""

import ast
import re
import sys


def title_case(name: str) -> str:
    words = re.split(r"[_\W]+", name)
    return " ".join(w.capitalize() if w.islower() else w
                    for w in words if w)


def ann_flows(node, classes) -> list:
    """Project dataclass names inside an annotation, else its text."""
    if node is None:
        return []
    names = [n.id for n in ast.walk(node)
             if isinstance(n, ast.Name) and n.id in classes]
    if names:
        return [title_case(n) for n in dict.fromkeys(names)]
    text = ast.unparse(node)
    if text in ("None", "?"):
        return []
    return [title_case(text.split("[")[0].split(".")[-1])]


def import_map(tree) -> dict:
    """local name -> source module (last dotted part), for this package."""
    out = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.ImportFrom) and n.module:
            src = n.module.rsplit(".", 1)[-1]
            for a in n.names:
                out[a.asname or a.name] = (src, a.name)
        elif isinstance(n, ast.Import):
            for a in n.names:
                out[a.asname or a.name.split(".")[0]] = \
                    (a.name.rsplit(".", 1)[-1], None)
    return out


def called(fn, own_mod, imap) -> list:
    """Resolved (module, function) call targets; unresolvable calls
    (stdlib, methods on objects) are dropped rather than guessed."""
    out = []
    for n in ast.walk(fn):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        if isinstance(f, ast.Name):
            if f.id in imap and imap[f.id][1] is not None:
                out.append(imap[f.id])           # from mod import f
            else:
                out.append((own_mod, f.id))      # local call
        elif (isinstance(f, ast.Attribute)
              and isinstance(f.value, ast.Name)
              and f.value.id in imap and imap[f.value.id][1] is None):
            out.append((imap[f.value.id][0], f.attr))  # mod.f(...)
    return out


def main() -> int:
    letter, model_title, *paths = sys.argv[1:]
    trees, classes = {}, set()
    for p in paths:
        with open(p, encoding="utf-8") as fh:
            tree = ast.parse(fh.read())
        mod = p.rsplit("/", 1)[-1][:-3]
        trees[mod] = tree
        classes |= {n.name for n in tree.body
                    if isinstance(n, ast.ClassDef)}

    funcs = {}        # (mod, name) -> dict
    for mod, tree in trees.items():
        imap = import_map(tree)
        for n in tree.body:
            if (isinstance(n, ast.FunctionDef)
                    and not n.name.startswith("_")):
                doc = (ast.get_docstring(n)
                       or ast.get_docstring(tree) or "")
                funcs[(mod, n.name)] = {
                    "mod": mod, "node": n, "name": n.name,
                    "doc": doc.split("\n")[0].strip(),
                    "calls": called(n, mod, imap)}

    # keep only functions on the cross-module call graph
    def cross(key, d):
        if any(c in funcs and funcs[c]["mod"] != d["mod"]
               for c in d["calls"]):
            return True
        return any(key in o["calls"] for o in funcs.values()
                   if o["mod"] != d["mod"])

    boxes = {k: d for k, d in funcs.items() if cross(k, d)}

    children = {k: [] for k in boxes}
    for k, d in boxes.items():
        for other in boxes:
            if other != k and boxes[other]["mod"] != d["mod"]:
                n = d["calls"].count(other)
                if n:
                    children[k].append((other, n))
    nested = {c for kids in children.values() for c, _ in kids}
    roots = sorted(k for k in boxes if k not in nested)

    def emit(key, depth, count=1):
        d = boxes[key]
        node = d["node"]
        pad = "  " * depth
        print(f"{pad}a# {title_case(d['name'])}")
        doc = d["doc"]
        if count > 1:
            doc = f"Called x{count} by the parent. " + doc
        if doc:
            print(f"{pad}## {doc[:200]}")
        for a in node.args.args:
            if a.arg in ("self", "cls"):
                continue
            print(f"{pad}  i# {title_case(a.arg)}")
        for flow in ann_flows(node.returns, classes):
            print(f"{pad}  o# {flow}")
        for child, n in sorted(children[key]):
            emit(child, depth + 1, n)

    print("; -*- mode: idef0 -*-")
    print("; GENERATED by scripts/py2idef0.py -- do not edit; rerun:")
    print(f";   scripts/py2idef0.py {letter} '{model_title}' "
          "<the same .py files>")
    print(f"t{letter} {model_title}")
    print("## Derived from the Python sources via ast: boxes are the")
    print("## cross-module call graph, i ports are parameters, o ports")
    print("## are return annotations (missing annotation = missing o,")
    print("## on purpose). Docstring first lines carry the SYS/D refs.")
    for r in roots:
        emit(r, 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
