"""maiden26-27: D7 steps 1-6 (align, residuals, rollups, gate, bands).

VT-17 territory: the twin knows the answers. The known-noise
consistency evidence run lives in test_validate_vt17.py.
"""

import numpy as np
import pytest

from maiden.twin.__main__ import main as twin_main
from maiden.validate import (
    ACC_HDR,
    FlightMetrics,
    SegmentTable,
    Track,
    align,
    flight_passes,
    gate,
    residuals,
    rollup,
    run_session,
)


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    out = tmp_path_factory.mktemp("twin_clean")
    assert twin_main(["--out", str(out), "--seed", "42"]) == 0
    return out


@pytest.fixture(scope="module")
def truth(session):
    return Track.from_truth_npz(session / "truth.npz")


def _resample(track: Track, hz=50.0) -> Track:
    te = np.arange(track.t[0], track.t[-1], 1.0 / hz)
    pos = np.column_stack([np.interp(te, track.t, track.pos[:, i])
                           for i in range(3)])
    vel = np.column_stack([np.interp(te, track.t, track.vel[:, i])
                           for i in range(3)])
    return Track(t=te, pos=pos, vel=vel)


def test_zero_noise_identity(truth):
    """Truth resampled to epochs vs truth: every RMS ~ 0, gate-clean.

    Catches sign and interpolation bugs before anything subtle.
    """
    tr, _meta = truth
    fused = _resample(tr)
    res = residuals(fused, tr)
    roll = rollup(res)
    assert roll["ALL"]["pos_rms"] < 1e-9
    assert roll["ALL"]["vel_rms"] < 1e-6  # interp of analytic vel
    assert roll["ALL"]["n"] > 1000
    assert res.att_absent  # emitted absent, not zero


def test_alignment_ok_on_clean_session(session, truth):
    from maiden.fuse import poses_from_session
    from maiden.ingest import load

    tr, meta = truth
    streams = {p.name.split("_")[1]: list(load(p))
               for p in sorted(session.glob("STATION_*.ch10"))}
    a = align(tr, streams, poses_from_session(session),
              sync_event_utc=meta["sync_event_utc"])
    assert not a.degraded, a.note
    assert a.sync == "ok"
    # every station's offset resolved well under a frame time
    assert all(abs(o) < 1 / 30 for o in a.offsets_s.values()), a.offsets_s


def test_alignment_tripwire(session, truth):
    """One station shifted +100 ms must be flagged, localized, and
    reported to within a frame time. (Shift applied to the ingested
    stream of a copied session — equivalent to shifting the file's
    timestamps, without re-encoding packets.)
    """
    from dataclasses import replace

    from maiden.fuse import poses_from_session
    from maiden.ingest import load

    tr, meta = truth
    streams = {p.name.split("_")[1]: list(load(p))
               for p in sorted(session.glob("STATION_*.ch10"))}
    streams["B"] = [replace(s, t_utc=s.t_utc + 0.100) for s in streams["B"]]
    a = align(tr, streams, poses_from_session(session),
              sync_event_utc=meta["sync_event_utc"])
    assert a.degraded
    assert a.worst_station == "B"
    assert a.offsets_s["B"] == pytest.approx(0.100, abs=1 / 30)
    assert a.sync.startswith("degraded(+")
    assert "recorded" in a.note  # never silent


def _fm(passed=True, **kw):
    base = {"flight": "f", "aircraft": "twin", "sequence": "sportsman",
            "pos_rms": 0.2, "pos_p95": 0.5, "vel_rms": 0.9,
            "continuity": 1.0, "sync": "ok", "passed": passed}
    base.update(kw)
    return FlightMetrics(**base)


def test_gate_arithmetic():
    assert gate([_fm() for _ in range(8)] + [_fm(passed=False)] * 2)
    assert not gate([_fm() for _ in range(7)] + [_fm(passed=False)] * 3)
    # boundary: one flight fails on continuity alone
    borderline = _fm(continuity=0.94,
                     passed=flight_passes(0.2, 0.9, 0.94))
    assert not borderline.passed
    assert not gate([_fm() for _ in range(7)] + [borderline] +
                    [_fm(passed=False)] * 2)


def test_segment_table_from_events(truth):
    _tr, meta = truth
    seg = SegmentTable.from_events(meta["event_t"], meta["event_kind"])
    assert len(seg.rows) == 4  # loop, roll, stall turn, immelmann
    for _label, t0, t1 in seg.rows:
        assert t1 > t0


def test_run_session_end_to_end(session):
    """`maiden validate --session` on a clean twin: D8-schema outputs."""
    rep = run_session(session)
    fm = rep["flight"]
    assert fm["passed"], fm
    assert fm["sync"] == "ok"
    assert fm["pos_rms"] <= 1.0 and fm["vel_rms"] <= 1.0  # sim rehearsal
    md = (session / "report.md").read_text()
    assert ACC_HDR in md  # column-for-column D8 Accuracy schema
    assert "| Maneuver | n |" in md
    assert (session / "report.json").exists()
    assert rep["bands"]["position_p95_m"] > 0


def test_run_campaign_and_bands(tmp_path):
    """--campaign: combined tables, gate verdict, bands.json persisted.

    Two twin flights cannot pass an 8-of-10 gate — the verdict must be
    FAIL even though both flights individually pass.
    """
    from maiden.validate import run_campaign

    for i, seed in enumerate((11, 12)):
        d = tmp_path / f"flight{i + 1:02d}"
        d.mkdir()
        assert twin_main(["--out", str(d), "--seed", str(seed)]) == 0
    out = run_campaign(tmp_path)
    assert len(out["flights"]) == 2
    assert all(f["passed"] for f in out["flights"])
    assert out["gate"] is False  # 2 < 8
    md = (tmp_path / "report.md").read_text()
    assert "Campaign gate: FAIL" in md
    import json as _json

    bands_file = _json.loads(
        open("results/validate/bands.json").read())  # noqa: SIM115
    assert bands_file["position_p95_m"] > 0


def test_cli_validate_session(session, capsys):
    from maiden.cli import main as cli_main

    assert cli_main(["validate", "--session", str(session)]) == 0
    assert "PASS" in capsys.readouterr().out


def test_schema_matches_d8_html():
    """Paste-into-D8 is the acceptance test for the format."""
    with open("docs/MAIDEN_D8_ValReport.html") as f:
        html = f.read()
    for col in ["Pos RMS (m)", "Pos p95 (m)", "Vel RMS (m/s)",
                "Continuity", "Sync", "Pass"]:
        assert col in html
        assert col in ACC_HDR
