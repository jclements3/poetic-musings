"""maiden.runner — `maiden run --session DIR` (D9 §Session workflow §6).

Chains ingest -> track -> fuse -> maneuvers -> score -> approach ->
rules -> report, one PDF + sidecar per detected flight, and prints the
stage-by-stage wall-clock table the 10-minute budget lives or dies by
(SYS-011; VT-24 is the field stopwatch — this rehearses the compute
half).

Flight detection: one flight per session directory for the Prototype
milestone. Multi-flight sessions split by recording gaps are Phase 2
hardening (D5) — the table already reports per-stage cost so the
extrapolation is arithmetic.
"""

import time
from pathlib import Path

from maiden.approach import approach_metrics
from maiden.fuse import fuse, poses_from_session
from maiden.maneuver import features, segment_rules
from maiden.report import Bands, FlightData, render
from maiden.rules import check, load_rules
from maiden.score import score_sequence

REPO_ROOT = Path(__file__).resolve().parents[2]
FIELD_CFG = REPO_ROOT / "config" / "field" / "rcrc.yaml"
BANDS_CAMPAIGN = REPO_ROOT / "results" / "campaign" / "bands.json"
BANDS_REHEARSAL = REPO_ROOT / "results" / "validate" / "bands.json"
EPOCH_HZ = 50.0


def _stage(timings, name):
    class _T:
        def __enter__(self):
            self.t0 = time.perf_counter()
            return self

        def __exit__(self, *exc):
            timings.append((name, time.perf_counter() - self.t0))
    return _T()


def stage_table(timings) -> str:
    lines = ["stage        wall [s]", "-" * 22]
    total = 0.0
    for name, dt in timings:
        lines.append(f"{name:12s} {dt:8.2f}")
        total += dt
    lines.append("-" * 22)
    lines.append(f"{'total':12s} {total:8.2f}")
    return "\n".join(lines)


def run_session(session_dir, out_dir=None, field_cfg=FIELD_CFG) -> dict:
    session_dir = Path(session_dir)
    out_dir = Path(out_dir) if out_dir else session_dir / "report"
    timings: list[tuple[str, float]] = []

    with _stage(timings, "ingest"):
        from maiden.ingest import load
        samples = []
        for p in sorted(session_dir.glob("STATION_*.ch10")):
            samples.extend(load(p))
        stations = poses_from_session(session_dir)

    with _stage(timings, "track"):
        # Twin sessions (and any station that ran its on-station tracker)
        # already carry Ch 5 az/el; the host-side video tracker only runs
        # when a session has video without tracker messages (field path).
        has_azel = any(s.az_deg is not None for s in samples)
        track_note = ("skipped — tracker channels present" if has_azel
                      else "no tracker channels and no video path wired "
                           "for real sessions yet (maiden41)")

    with _stage(timings, "fuse"):
        fused, stats = fuse(samples, stations, epoch_hz=EPOCH_HZ)

    with _stage(timings, "maneuvers"):
        ff = features(fused, EPOCH_HZ)
        events = segment_rules(ff)

    with _stage(timings, "approach"):
        import yaml
        with open(field_cfg) as f:
            fld = yaml.safe_load(f)
        c_samples = [s for s in samples if s.source == "C"]
        ap = approach_metrics(fused, events, fld,
                              c_samples=c_samples,
                              c_pose=stations.get("C"))
        if ap is not None:
            # The landing approach is not an aerobatic figure: drop any
            # maneuver segment overlapping the detected final leg (the
            # steep twin descent otherwise classifies as a 0-point
            # "loop" — segmentation fold-back flagged for maiden51).
            t0, t1 = ap.final_leg
            events = [e for e in events
                      if not (e.kind.startswith("MANEUVER")
                              and t0 <= e.t_utc <= t1)]

    with _stage(timings, "score"):
        scores = score_sequence(events, fused)

    with _stage(timings, "rules"):
        rules = load_rules(field_cfg)
        rule_events = check(fused, rules)
        events = events + rule_events

    with _stage(timings, "report"):
        # Clips need a playable container. Field path: Ch 2 payloads are
        # H.264 TS packets, so extraction to .ts precedes ffmpeg (wired
        # with the real recorder, maiden41). A raw .ch10 is not fed to
        # ffmpeg; twin JPEG video has no TS to extract.
        vids = sorted(session_dir.glob("VIDEO_A_*.ts")) or \
            sorted(session_dir.glob("VIDEO_A_*.mp4"))
        if not vids and sorted(session_dir.glob("VIDEO_A_*.ch10")):
            track_note += "; Ch2 video present but TS extraction " \
                          "not wired (maiden41) — clips skipped"
        fd = FlightData(
            session=session_dir.name,
            name=f"flight-{session_dir.name}",
            samples=fused, events=events, scores=scores, approach=ap,
            pose_a=stations["A"],
            bands=Bands(BANDS_CAMPAIGN if BANDS_CAMPAIGN.exists()
                        else BANDS_REHEARSAL),
            rules_status=rules.status,
            provenance="twin" if (session_dir / "truth.npz").exists()
            else "field",
            video_a=vids[0] if vids else None,
            meta={"gate_rate": round(stats.gate_rate, 5),
                  "n_epochs": stats.n_epochs, "track": track_note},
        )
        paths = render(fd, out_dir)

    table = stage_table(timings)
    return {"paths": paths, "timings": timings, "table": table,
            "track_note": track_note, "n_scores": len(scores)}


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(
        prog="maiden run",
        description="ingest, fuse, recognize, score, and write the "
                    "pilot report for a session (D9 step 6)")
    ap.add_argument("--session", required=True)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    r = run_session(args.session, args.out)
    print(f"track: {r['track_note']}")
    print(f"report: {r['paths']['pdf']}")
    print(f"sidecar: {r['paths']['sidecar']}")
    for line in r["paths"]["clips"]:
        print(f"clips: {line}")
    print()
    print(r["table"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
