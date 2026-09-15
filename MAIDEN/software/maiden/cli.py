"""`maiden` command-line front end.

Subcommands arrive as their sprints land: twin (maiden12), ingest
(maiden14), validate (maiden27), run (maiden57). Each is a thin wrapper
over the module's own __main__-style entry so `python -m maiden.twin`
and `maiden twin` behave identically.
"""

import sys


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        print("usage: maiden <twin|ingest|validate|run> ...", file=sys.stderr)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "twin":
        from maiden.twin.__main__ import main as twin_main

        return twin_main(rest)
    if cmd == "ingest":
        from maiden.ingest import main as ingest_main

        return ingest_main(rest)
    if cmd == "fuse":
        from maiden.fuse import main as fuse_main

        return fuse_main(rest)
    if cmd == "validate":
        from maiden.validate import main as validate_main

        return validate_main(rest)
    if cmd == "convert":
        from maiden.convert import main as convert_main

        return convert_main(rest)
    if cmd == "run":
        from maiden.runner import main as run_main

        return run_main(rest)
    print(f"maiden: unknown or not-yet-built subcommand '{cmd}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
