"""maiden55/57 — report render + `maiden run` end to end on a twin
session: page produced, sidecar deterministic, bands honest, stages
timed. (VT-24's stopwatch is the field; this rehearses the compute.)"""

import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from maiden.report import SCORE_BAND_FLOOR_PTS, Bands, FlightData, clip_commands
from maiden.runner import run_session

SEED = 505


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    d = tmp_path_factory.mktemp("twin") / "s505"
    subprocess.run([sys.executable, "-m", "maiden.twin", "--out", str(d),
                    "--seed", str(SEED), "--imperfect"], check=True)
    return d


@pytest.fixture(scope="module")
def run1(session, tmp_path_factory):
    out = tmp_path_factory.mktemp("rep1")
    return run_session(session, out), out


def test_page_and_sidecar_exist(run1):
    r, _out = run1
    paths = r["paths"]
    assert Path(paths["pdf"]).exists() and Path(paths["sidecar"]).exists()
    # exactly one page (single savefig into PdfPages)
    with open(paths["pdf"], "rb") as f:
        raw = f.read()
    n_pages = len(re.findall(rb"/Type\s*/Page[^s]", raw))
    assert n_pages == 1


def test_all_stages_timed(run1):
    r, _ = run1
    names = [n for n, _ in r["timings"]]
    assert names == ["ingest", "track", "fuse", "maneuvers", "approach",
                     "score", "rules", "report"]
    assert "total" in r["table"]
    total = sum(dt for _, dt in r["timings"])
    assert total < 120.0        # compute half far inside the 10-min clock


def test_track_skipped_on_twin(run1):
    r, _ = run1
    assert "skipped" in r["track_note"]


def test_scores_present_no_approach_pollution(run1, session):
    r, _out = run1
    with open(r["paths"]["sidecar"]) as f:
        d = json.load(f)
    classes = [s["class"] for s in d["scores"]]
    assert "loop" in classes
    # the runner's final-leg filter: at most one segment per class —
    # the landing descent must not appear as a second scored loop
    assert len(classes) == len(set(classes))


def test_sidecar_deterministic(session, tmp_path_factory):
    out2 = tmp_path_factory.mktemp("rep2")
    out3 = tmp_path_factory.mktemp("rep3")
    r2 = run_session(session, out2)
    r3 = run_session(session, out3)
    with open(r2["paths"]["sidecar"], "rb") as f:
        b2 = f.read()
    with open(r3["paths"]["sidecar"], "rb") as f:
        b3 = f.read()
    assert b2 == b3             # byte-identical (PDF may differ; JSON not)


def test_sidecar_carries_the_honesty_trail(run1):
    r, _ = run1
    with open(r["paths"]["sidecar"]) as f:
        d = json.load(f)
    assert d["provenance"] == "twin"
    assert d["bands"]["provenance"] == "twin rehearsal"
    assert d["rules_status"] == "PLACEHOLDER_PENDING_SURVEY"
    # sidecar archaeology (lesson 24 Explore): loop roundness must be
    # recoverable from sidecars alone — deduction tags carry it
    loop = next(s for s in d["scores"] if s["class"] == "loop")
    assert any(dd["tag"] == "roundness" for dd in loop["deductions"])


def test_widening_rule_hand_computed():
    b = Bands()
    # median trace 0.16 m^2 vs campaign placeholder 0.04 -> factor 2.0
    assert b.widen_factor(np.array([0.16, 0.16, 0.16])) == pytest.approx(2.0)
    # quieter than campaign never narrows below 1
    assert b.widen_factor(np.array([0.01])) == 1.0
    assert "twin rehearsal" in b.footer()


def test_band_abuse_visibly_widens(run1):
    """Explore: inflate covariance -> gray band and score +/- must grow."""
    r, _ = run1
    with open(r["paths"]["sidecar"]) as f:
        d = json.load(f)
    base = d["bands"]["score_band_pts"]
    b = Bands()
    fat = b.widen_factor(np.array([0.36]))    # 3x sigma -> factor 3
    assert fat * SCORE_BAND_FLOOR_PTS > base


def test_clip_commands_dry_run(run1, session):
    """No video in this twin session: clip step reports and moves on;
    command construction is exercised against a pretend video path."""
    r, _ = run1
    assert any("no video" in line for line in r["paths"]["clips"])
    # dry-run construction: same flight, pretend Station A video exists
    with open(r["paths"]["sidecar"]) as f:
        d = json.load(f)
    from maiden.geo import Pose
    from maiden.state import Event, StateSample
    fd = FlightData(
        session="x", name="x",
        samples=[StateSample(e["t"], "FUSED", pos_enu=(0, 0, 0),
                             vel_enu=(0, 0, 0))
                 for e in d["events"][:1]],
        events=[Event(e["t"], e["kind"], e["data"]) for e in d["events"]],
        scores=[], approach=None, pose_a=Pose((0.0, 0.0, 0.0), 0.0),
        bands=Bands(), video_a=Path("VIDEO_A_fake.ch10"))
    from maiden.score import ManeuverScore
    fd.scores = [ManeuverScore("loop", 10.0, None, [])]
    cmds = clip_commands(fd, Path("/tmp"))
    assert cmds and cmds[0][0] == "ffmpeg" and "-c" in cmds[0]
    ss = float(cmds[0][cmds[0].index("-ss") + 1])
    assert ss >= 0.0


def test_cli_smoke(session, tmp_path):
    p = subprocess.run(  # noqa: PLW1510
        [sys.executable, "-m", "maiden.cli", "run",
         "--session", str(session), "--out", str(tmp_path / "rep")],
        capture_output=True, text=True)
    assert p.returncode == 0
    assert "stage" in p.stdout and "total" in p.stdout
