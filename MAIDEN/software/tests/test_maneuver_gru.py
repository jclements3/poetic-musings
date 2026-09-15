"""maiden52: learned classifier — shipped weights + training smoke.

The full training run (`python -m maiden.maneuver train`) and its
evidence live in results/VT-16/rehearsal/; these tests keep CI fast:
inference with the shipped weights, a tiny deterministic training smoke,
and the two honesty probes (zero-wobble roll, long-leg false positive)
pinned as regressions.
"""

from pathlib import Path

import numpy as np

from maiden import maneuver as mv
from maiden.twin.model import level_leg

WEIGHTS = Path(mv.__file__).parent / "data" / "maneuver_mlp_v1.npz"


def test_shipped_weights_load_and_classify():
    ff, _, tr = mv._gen_track(100, wobble_m=1.0)
    events = mv.segment_gru(ff, WEIGHTS)
    matches = mv.match_segments(events, tr.events)
    assert all(p == n for n, p, _, _ in matches), matches


def test_long_leg_probe_no_false_roll():
    """Regression for the duration-shortcut bug (MODEL_CARD caveat 2)."""
    model = mv.TemporalMLP.load(WEIGHTS)
    for seed in (1, 2, 3):
        tr = level_leg(np.array([-100.0, 150.0, 40.0]), 90.0, 200.0,
                       25.0, 25.0, 40.0)
        ff = mv.features(
            mv.truth_to_samples(tr, 50.0, noise_pos=0.25, noise_vel=0.35,
                                drop_att=True, seed=seed), 50.0)
        assert mv.segment_gru_pred(ff, model) == []


def test_zero_wobble_roll_is_honestly_missed():
    """No signal -> no detection (MODEL_CARD caveat 1)."""
    model = mv.TemporalMLP.load(WEIGHTS)
    misses = 0
    for s in (200, 201, 202):
        ff, _, tr = mv._gen_track(s, wobble_m=0.0)
        matches = {n: p for n, p, _, _ in mv.match_segments(
            mv.segment_gru_pred(ff, model), tr.events)}
        if matches.get("roll") != "roll":
            misses += 1
    assert misses >= 2   # 0% in the shipped sweep; allow 1 fluke


def test_training_smoke_deterministic(tmp_path):
    """Tiny end-to-end training run: deterministic and functional."""
    xs, ys = [], []
    for s in (0, 1):
        ff, y, _ = mv._gen_track(s, wobble_m=1.0)
        xs.append(mv._stack_context(mv._matrix(ff)))
        ys.append(y)
    x, y = np.concatenate(xs), np.concatenate(ys)
    w = np.ones(len(mv.CLASSES))
    m1 = mv.TemporalMLP(np.random.default_rng(7))
    m1.train(x, y, w, epochs=3, seed=7)
    m2 = mv.TemporalMLP(np.random.default_rng(7))
    m2.train(x, y, w, epochs=3, seed=7)
    assert all(np.array_equal(a, b) for a, b in zip(m1.w, m2.w))
    p = tmp_path / "m.npz"
    m1.save(p)
    m3 = mv.TemporalMLP.load(p)
    probe = x[:64]
    assert np.array_equal(m1.predict(probe), m3.predict(probe))
