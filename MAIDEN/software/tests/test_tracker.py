"""maiden21: track management, conf semantics, Ch 5 round-trip, CI floor."""

from itertools import pairwise

import pytest

from maiden.camera import CameraModel
from maiden.geo import Pose
from maiden.ingest import load
from maiden.track.candidates import Candidate
from maiden.track.metrics import Report
from maiden.track.session import track_rendered_session, write_track_session
from maiden.track.tracker import StationTracker, TrackerCfg, TrackState
from maiden.twin.model import sportsman
from maiden.twin.render import RenderConfig

MODEL = CameraModel(fx=1663 / 2, fy=1663 / 2, cx=480.0, cy=270.0)
POSE = Pose((0.0, 0.0, 0.0), 12.4, 8.0)
CFG_960 = RenderConfig(width=960, height=540, noise_sigma=0.01)


def _cand(u, v, area=60, contrast=8.0, coherence=3.0):
    return Candidate(u=u, v=v, area=area, bbox=(int(u) - 4, int(v) - 2, 9, 5),
                     contrast=contrast, coherence=coherence)


def _feed(tracker, script, du=3.0):
    """script: string of H (hit) / M (miss) frames; target moves du px/frame
    and its position persists across calls on the same tracker.
    Returns (per-frame TrackOut lists, final internal track or None)."""
    outs = []
    u = getattr(tracker, "_test_u", 100.0)
    for ch in script:
        u += du
        cands = [_cand(u, 50.0)] if ch == "H" else []
        outs.append(tracker.consume(cands))
    tracker._test_u = u
    tr = tracker.tracks[0] if tracker.tracks else None
    return outs, tr


def test_confirmation_at_m_of_n():
    tk = StationTracker(TrackerCfg())
    outs, tr = _feed(tk, "HH")           # 2 hits: still tentative, no emission
    assert outs[-1] == [] and tr.state is TrackState.TENTATIVE
    outs, tr = _feed(tk, "H")            # 3rd hit of 5-window: confirms
    assert tr.state is TrackState.CONFIRMED
    assert len(outs[-1]) == 1 and outs[-1][0].state is TrackState.CONFIRMED


def test_confirmed_miss_coasts_then_hit_reconfirms():
    tk = StationTracker(TrackerCfg())
    _feed(tk, "HHH")
    _, tr = _feed(tk, "M")
    assert tr.state is TrackState.COASTING
    _, tr = _feed(tk, "H")
    assert tr.state is TrackState.CONFIRMED


def test_death_at_k_consecutive_misses():
    cfg = TrackerCfg()
    tk = StationTracker(cfg)
    _feed(tk, "HHH")
    _, tr = _feed(tk, "M" * (cfg.k_dead - 1))
    assert tr is not None and tr.state is TrackState.COASTING
    _, tr = _feed(tk, "M")
    assert tr is None                    # pruned at K


def test_conf_monotone_decreasing_while_coasting():
    tk = StationTracker(TrackerCfg())
    _feed(tk, "HHHHH")
    confs = []
    for _ in range(10):
        outs, _tr = _feed(tk, "M")
        if outs[-1]:
            confs.append(outs[-1][0].conf)
    assert len(confs) >= 5
    assert all(b < a for a, b in pairwise(confs))
    # and a hit restores it above the coasted value
    outs, _ = _feed(tk, "H")
    assert outs[-1][0].conf > confs[-1]


def test_tentative_track_never_emits():
    tk = StationTracker(TrackerCfg())
    outs, _ = _feed(tk, "HH")
    assert all(o == [] for o in outs)


@pytest.fixture(scope="module")
def clean_sky_run():
    """One tracked pass over the twin's first camera transit (~35 s)."""
    truth = sportsman()
    rows = list(track_rendered_session(
        truth, "A", MODEL, POSE, CFG_960, frame_range=(440, 740)))
    return rows


def test_clean_sky_track_recall_ci_floor(clean_sky_run):
    """CI floor (VT-15 twin rehearsal): recall >= 0.90 at >= 6 px.

    Twin evidence only — the field subset of VT-15 stays open until the
    campaign (lesson 11 §What twin numbers prove).
    """
    rep = Report()
    for t, outs, label in clean_sky_run:
        rep.add(t, label, outs)
    rec = rep.recall_by_bin()
    assert rec[">=6px"] is not None and rec[">=6px"] >= 0.90
    assert rep.false_per_frame() < 0.1


def test_ch5_round_trip_through_real_file(tmp_path):
    """Track a twin sequence -> Ch 5 packets -> maiden.ingest.load:
    ingested az/el/conf equal the emitted ones (float32 quantization)."""
    truth = sportsman()
    path, emitted = write_track_session(
        tmp_path, truth, "A", MODEL, POSE, CFG_960, frame_range=(440, 560))
    assert emitted, "no emissions in the round-trip window"
    ingested = [s for s in load(path) if s.az_deg is not None]
    assert len(ingested) == len(emitted)
    for a, b in zip(emitted, ingested):
        assert b.source == "A"
        assert abs(a.az_deg - b.az_deg) < 1e-4
        assert abs(a.el_deg - b.el_deg) < 1e-4
        assert abs(a.conf - b.conf) < 1e-6
