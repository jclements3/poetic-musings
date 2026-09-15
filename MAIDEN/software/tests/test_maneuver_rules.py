"""maiden51: stage (a) rule segmenter vs twin ground truth (SW-003).

Tolerances are explicit; everything is seeded. The clean-session test
uses TRUTH samples (attitude present, so the roll-rate feature is
direct); the attitude-free test pins the documented roll limitation
rather than discovering it in the field.
"""

import numpy as np
import pytest

from maiden import maneuver as mv
from maiden.twin.model import Imperfections, sportsman

MANEUVERS = ("loop", "roll", "stall_turn", "immelmann")


def _run(seed=0, imp=None, drop_att=False):
    tr = sportsman(imp, seed=seed)
    samples = mv.truth_to_samples(tr, 50.0, drop_att=drop_att, seed=seed)
    ff = mv.features(samples, 50.0)
    return tr, ff, mv.segment_rules(ff)


@pytest.mark.parametrize("seed", [0, 1, 5, 9])
def test_clean_session_all_maneuvers(seed):
    tr, _ff, events = _run(seed=seed)
    matches = mv.match_segments(events, tr.events)
    assert [n for n, _, _, _ in matches] == list(MANEUVERS)
    for name, pred, _, _ in matches:
        assert pred == name, f"{name} classified as {pred}"
    # no spurious maneuver segments
    n_pred = sum(1 for e in events if e.kind == "MANEUVER_START")
    assert n_pred == len(MANEUVERS)


def test_boundaries_within_one_second():
    tr, _ff, events = _run(seed=0)
    for name, pred, t0, _ in mv.match_segments(events, tr.events):
        starts = [e.t_utc for e in events
                  if e.kind == "MANEUVER_START" and e.data["class"] == pred]
        assert min(abs(s - t0) for s in starts) < 1.0, name


def test_imperfections_do_not_break_classes():
    imp = Imperfections(loop_ovality=0.15, roll_drift_deg=5.0,
                        alt_mismatch_m=4.0)
    tr, _ff, events = _run(seed=1, imp=imp)
    matches = mv.match_segments(events, tr.events)
    assert all(p == n for n, p, _, _ in matches)


def test_feature_signatures_on_loop():
    tr, ff, _ = _run(seed=0)
    loop = next(e for e in tr.events if e.kind == "MANEUVER_START"
                and e.data["maneuver"] == "loop")
    end = next(e for e in tr.events if e.kind == "MANEUVER_END"
               and e.data["maneuver"] == "loop")
    m = (ff.t >= loop.t_utc + 1.0) & (ff.t <= end.t_utc - 1.0)
    # a 38 m loop: kappa ~ 1/38, flown in a vertical plane
    assert np.median(ff.kappa[m]) == pytest.approx(1 / 38.0, rel=0.3)
    assert np.median(ff.vplane_deg[m]) > 80.0


def test_attitude_free_roll_limitation_is_pinned():
    """Documented, not discovered later: from pos/vel alone a twin roll
    is a level leg (zero wobble), so stage (a) must NOT find it."""
    tr, _ff, events = _run(seed=0, drop_att=True)
    matches = {n: p for n, p, _, _ in mv.match_segments(events,
                                                              tr.events)}
    assert matches["loop"] == "loop"
    assert matches["stall_turn"] == "stall_turn"
    assert matches["roll"] != "roll"   # the honest failure, pinned


def test_hysteresis_kills_flicker():
    _, ff, _ = _run(seed=0)
    lab = mv._window_tree(ff)
    lab_f = lab.copy()
    lab_f[10] = mv._VERT if lab[10] != mv._VERT else mv._LEVEL  # 1-window blip
    runs = mv._runs_with_hysteresis(lab_f, h=5)
    assert len(runs) == len(mv._runs_with_hysteresis(lab, h=5))
