"""VT-14 desk half: twin round-trip, contracts, counts. SW-001."""

import numpy as np
import pytest
from conftest import check_adapter_stream

from maiden import ingest
from maiden.ch10 import read_packets
from maiden.twin import sensors
from maiden.twin.writer import EPOCH_UTC, default_poses, write_session

SEED = 101
SIG_DEG = np.degrees(sensors.SIGMA_THETA_RAD)


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    out = tmp_path_factory.mktemp("twin-vt14")
    paths = write_session(out, seed=SEED)
    return paths, np.load(paths["npz"])


def _station_path(paths, name):
    return paths[name]


def test_walker_matches_strict_reader(session):
    paths, _ = session
    p = _station_path(paths, "A")
    ours = list(ingest.walk_packets(p))
    strict = list(read_packets(p))
    assert len(ours) == len(strict)
    assert all(a[:3] == (b.channel, b.dtype, b.rtc)
               for a, b in zip(ours, strict))
    assert {c for c, *_ in ours} == {0, 1, 4, 5, 6}


def test_describe_all_files(session):
    paths, _ = session
    for name, serial in (("A", "MAIDEN-STA-001"), ("B", "MAIDEN-STA-002"),
                         ("C", "MAIDEN-STA-003")):
        d = ingest.describe(_station_path(paths, name))
        assert isinstance(d, ingest.Station)
        assert d.id == name and d.serial == serial
        assert d.survey_lla is not None and d.heading_deg is not None
        assert d.channel_names[5] == "TRACKER"
        assert d.channel_names[4] == "RADAR_V"
    t = ingest.describe(paths["TRUTH"])
    assert isinstance(t, ingest.Aircraft)
    assert t.channel_names == {0: "TMATS", 1: "TIME", 3: "GNSS", 4: "ATT"}


def test_roundtrip_station_a(session):
    """Residuals vs pre-noise truth: zero-mean, std within [0.7, 1.3]x
    the injected sigma — the degrees/radians slip detector."""
    paths, npz = session
    poses, _ = default_poses()
    samples = list(ingest.load(_station_path(paths, "A")))
    t_seq = np.array([s.t_utc - EPOCH_UTC for s in samples])
    tr = np.array([[s.az_deg, s.el_deg, s.conf] for s in samples
                   if s.az_deg is not None], dtype=float)
    tt = t_seq[[i for i, s in enumerate(samples) if s.az_deg is not None]]
    vr = np.array([s.v_r for s in samples if s.v_r is not None])
    tv = t_seq[[i for i, s in enumerate(samples) if s.v_r is not None]]

    pos = np.column_stack([np.interp(tt, npz["t"], npz["pos_enu"][:, i])
                           for i in range(3)])
    az_true, el_true = sensors.station_azel(pos, poses["A"])
    r_az, r_el = tr[:, 0] - az_true, tr[:, 1] - el_true
    for r in (r_az, r_el):
        assert 0.7 * SIG_DEG < np.std(r) < 1.3 * SIG_DEG
        assert abs(np.mean(r)) < 0.1 * SIG_DEG
    assert np.all((tr[:, 2] >= 0.5) & (tr[:, 2] <= 1.0))

    pos_v = np.column_stack([np.interp(tv, npz["t"], npz["pos_enu"][:, i])
                             for i in range(3)])
    vel_v = np.column_stack([np.interp(tv, npz["t"], npz["vel_enu"][:, i])
                             for i in range(3)])
    vr_true = sensors.vr_from_state(pos_v, vel_v, poses["A"])
    r_vr = vr - vr_true
    assert 0.7 * sensors.SIGMA_VR < np.std(r_vr) < 1.3 * sensors.SIGMA_VR
    assert abs(np.mean(r_vr)) < 0.1 * sensors.SIGMA_VR


def test_adapter_contract_all_files(session):
    paths, _ = session
    for key in ("A", "B", "C", "TRUTH"):
        check_adapter_stream(ingest.load(paths[key]))


def test_counts_vs_dropout(session):
    paths, npz = session
    dur = float(npz["t"][-1] - npz["t"][0])
    for name in ("A", "C"):
        n_tr = sum(1 for s in ingest.load(_station_path(paths, name))
                   if s.az_deg is not None)
        expect = sensors.TRACKER_HZ * dur * (1 - sensors.DROPOUT_P)
        assert abs(n_tr - expect) < 0.03 * expect
    # B lost its 4 s sun window on top of the dropout rate
    n_b = sum(1 for s in ingest.load(_station_path(paths, "B"))
              if s.az_deg is not None)
    outage_frames = 4.0 * sensors.TRACKER_HZ
    expect_b = sensors.TRACKER_HZ * dur * (1 - sensors.DROPOUT_P)
    assert n_b < expect_b - 0.8 * outage_frames


def test_truth_samples_match_npz(session):
    paths, npz = session
    samples = [s for s in ingest.load(paths["TRUTH"])]
    assert all(s.source == "TRUTH" for s in samples)
    t_seq = np.array([s.t_utc - EPOCH_UTC for s in samples])
    pos = np.array([s.pos_enu for s in samples])
    want = np.column_stack([np.interp(t_seq, npz["t"], npz["pos_enu"][:, i])
                            for i in range(3)])
    # float32 packing at |pos| <= ~300 m -> worst-case ~0.01 m
    assert np.max(np.abs(pos - want)) < 0.05
    assert sum(s.att_rpy is not None for s in samples) >= len(samples) - 1


def test_status_events(session):
    paths, npz = session
    evs = list(ingest.events(_station_path(paths, "A")))
    dur = float(npz["t"][-1] - npz["t"][0])
    assert abs(len(evs) - dur) <= 2          # 1 Hz status
    assert all(e.kind == "STATUS" and e.data["pps_lock"] for e in evs)
    import itertools

    t = [e.t_utc for e in evs]
    assert all(b >= a for a, b in itertools.pairwise(t))
