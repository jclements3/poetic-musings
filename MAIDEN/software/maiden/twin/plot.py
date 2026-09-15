"""Eyeball check for the twin flight model: 3D path + plan view.

Usage:  python -m maiden.twin.plot [out.png]
Saves results/lesson06/sportsman_plan.png by default; also writes the
Explore-1 ovality overlay next to it.
"""
import pathlib
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from maiden.twin.model import Imperfections, loop, sportsman


def main(out: str | None = None) -> None:
    out_path = pathlib.Path(out or "results/lesson06/sportsman_plan.png")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    seq = sportsman(seed=0)
    fig = plt.figure(figsize=(12, 5))
    ax3 = fig.add_subplot(1, 2, 1, projection="3d")
    ax3.plot(*seq.pos_enu.T, lw=0.8)
    ax3.set_xlabel("E [m]"), ax3.set_ylabel("N [m]"), ax3.set_zlabel("U [m]")
    ax3.set_title("Sportsman twin — 3D")

    ax2 = fig.add_subplot(1, 2, 2)
    ax2.plot(seq.pos_enu[:, 0], seq.pos_enu[:, 2], lw=0.8)
    for e in seq.events:
        if e.kind == "MANEUVER_START":
            i = round(e.t_utc / 0.01)
            ax2.annotate(e.data["maneuver"],
                         (seq.pos_enu[i, 0], seq.pos_enu[i, 2]),
                         fontsize=8)
    ax2.set_xlabel("E [m]"), ax2.set_ylabel("U [m]")
    ax2.set_title("Side view (flight line), boundaries from Events")
    ax2.set_aspect("equal")
    fig.tight_layout()
    fig.savefig(out_path, dpi=130)

    # Explore 1: ovality overlay
    ideal = loop((0.0, 150.0, 40.0), 90.0, 38.0, 25.0)
    egg = loop((0.0, 150.0, 40.0), 90.0, 38.0, 25.0, ovality=0.15)
    fig2, ax = plt.subplots(figsize=(5, 5))
    ax.plot(ideal.pos_enu[:, 0], ideal.pos_enu[:, 2], label="ideal")
    ax.plot(egg.pos_enu[:, 0], egg.pos_enu[:, 2], "--",
            label="ovality=0.15")
    ax.set_aspect("equal"), ax.legend()
    ax.set_xlabel("E [m]"), ax.set_ylabel("U [m]")
    ax.set_title("Loop ovality knob (Explore 1)")
    fig2.tight_layout()
    fig2.savefig(out_path.with_name("loop_ovality_overlay.png"), dpi=130)
    print(f"wrote {out_path} and loop_ovality_overlay.png")
    _ = Imperfections  # documented knobs live in model.py


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
