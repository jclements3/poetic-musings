"""CLI: `python -m maiden.twin --out DIR [--seed N] [--imperfect]`.

The pinned course interface is `maiden twin ...`; until a console-script
entry point is added to pyproject (orchestrator decision — this module
must not edit it), `python -m maiden.twin` is the same command minus the
alias, and a leading literal `twin` token is accepted so both spellings
work.
"""
import argparse
import sys

from maiden.twin.writer import write_session


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "twin":
        argv = argv[1:]
    ap = argparse.ArgumentParser(prog="maiden twin")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--imperfect", action="store_true")
    ap.add_argument("--render", metavar="STATION", choices=["A", "B", "C"],
                    help="also render Ch 2 video + labels for one station")
    ap.add_argument("--sun", nargs=2, type=float, metavar=("AZ", "EL"),
                    help="with --render: place a sun disc at az/el deg")
    a = ap.parse_args(argv)
    paths = write_session(a.out, seed=a.seed, imperfect=a.imperfect)
    for k, p in paths.items():
        print(f"{k}: {p}")
    if a.render:
        from maiden.camera import CameraModel
        from maiden.tmats import parse_station
        from maiden.twin.model import Imperfections, sportsman
        from maiden.twin.render import RenderConfig, write_video_file
        from maiden.twin.writer import default_poses

        imp = Imperfections() if a.imperfect else None
        truth = sportsman(imp, seed=a.seed)
        poses, _ = default_poses()
        with open("config/tmats/station.tmt") as f:
            model = CameraModel.from_tmats(parse_station(f.read()).cam)
        cfg = RenderConfig(sun_azel=tuple(a.sun) if a.sun else None)
        vp, lp = write_video_file(a.out, a.render, truth, model,
                                  poses[a.render], cfg)
        print(f"VIDEO: {vp}")
        print(f"labels: {lp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
