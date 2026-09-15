"""maiden.convert — airborne native logs -> Ch. 10 (D4 IF-3, AB-002).

`maiden convert LOG --airframe config/airframes/kaos.yaml --out DIR`
"""

import argparse
from pathlib import Path

from .adapters import AirborneRecords, get_adapter  # noqa: F401
from .writer import Airframe, read_back, write_aircraft_ch10  # noqa: F401


def _default_origin():
    """Field-frame origin from rcrc.yaml Station A (the ground set owns
    the frame; --origin-lla overrides for other sessions)."""
    import yaml

    root = Path(__file__).resolve().parents[3]
    with open(root / "config" / "field" / "rcrc.yaml") as f:
        d = yaml.safe_load(f)
    return tuple(d["field_origin"]["lla"])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="maiden convert")
    ap.add_argument("log")
    ap.add_argument("--airframe", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--origin-lla", nargs=3, type=float, default=None,
                    metavar=("LAT", "LON", "ALT"))
    args = ap.parse_args(argv)

    adapter = get_adapter(args.log)
    rec = adapter.read(Path(args.log))
    af = Airframe.from_yaml(args.airframe)
    origin = tuple(args.origin_lla) if args.origin_lla else _default_origin()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"AIRCRAFT_{af.name}_{Path(args.log).stem}.ch10"
    _, stats = write_aircraft_ch10(rec, af, out, origin)

    for k in ("GPS", "IMU", "BARO", "ATT"):
        print(f"{k}: {stats[k]} msgs")
    print(f"time-fit residual RMS: {stats['fit_resid_rms_s'] * 1e3:.3f} ms")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
