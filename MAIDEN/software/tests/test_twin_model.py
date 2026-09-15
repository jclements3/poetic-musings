"""Physics police for the twin flight model (lesson 06, maiden09/10)."""
import numpy as np
import pytest

from maiden.twin import model as tm

G = tm.G


@pytest.fixture(scope="module")
def seq():
    return tm.sportsman(seed=0)


def _window(seq, name):
    """(t0, t1) of the first maneuver `name`, from the Events."""
    t0 = t1 = None
    for e in seq.events:
        if e.data.get("maneuver") == name:
            if e.kind == "MANEUVER_START" and t0 is None:
                t0 = e.t_utc
            elif e.kind == "MANEUVER_END" and t1 is None:
                t1 = e.t_utc
    assert t0 is not None and t1 is not None, f"no Events bracket {name}"
    return t0, t1


# ------------------------------------------------------------- primitives

def test_loop_closes_and_is_coplanar():
    tr = tm.loop((0.0, 150.0, 40.0), 90.0, 40.0, 25.0)
    assert np.linalg.norm(tr.pos_enu[-1] - tr.pos_enu[0]) < 2.0
    pts = tr.pos_enu - tr.pos_enu.mean(axis=0)
    resid = np.linalg.svd(pts, full_matrices=False)[1][-1]
    assert resid < 0.5  # smallest singular value ~ out-of-plane spread


def test_roll_holds_altitude_and_heading():
    tr = tm.roll((0.0, 150.0, 40.0), 90.0, 100.0, 25.0)
    assert np.ptp(tr.pos_enu[:, 2]) < 0.01
    assert np.ptp(tr.pos_enu[:, 1]) < 0.01          # due-east line
    assert abs(tr.att_rpy[0, 0]) < 1e-9
    assert abs(tr.att_rpy[-1, 0] - 360.0) < 1e-9


def test_roll_drift_bends_the_path():
    tr = tm.roll((0.0, 150.0, 40.0), 90.0, 100.0, 25.0, drift_deg=6.0)
    vE, vN = tr.vel_enu[-1, 0], tr.vel_enu[-1, 1]
    exit_heading = np.degrees(np.arctan2(vE, vN))
    assert abs(exit_heading - 96.0) < 0.1


def test_stall_turn_reverses_and_returns_to_altitude():
    tr = tm.stall_turn((0.0, 150.0, 40.0), 90.0, 40.0, 25.0)
    assert abs(tr.pos_enu[-1, 2] - 40.0) < 0.5
    assert tr.vel_enu[-1, 0] < -20.0                 # exits westbound
    speeds = np.linalg.norm(tr.vel_enu, axis=1)
    assert speeds.min() < 3.0                        # bleeds near the top


def test_immelmann_composition():
    tr = tm.immelmann((0.0, 150.0, 40.0), 90.0, 30.0, 25.0)
    assert abs(tr.pos_enu[-1, 2] - 100.0) < 1.0      # +2r altitude
    assert tr.vel_enu[-1, 0] < -20.0                 # reversed heading
    assert abs(tr.att_rpy[-1, 0] - 360.0) < 1e-9     # rolled upright


def test_concat_trips_on_mismatch():
    a = tm.level_leg((0.0, 150.0, 40.0), 90.0, 50.0, 20.0, 25.0, 40.0)
    b = tm.level_leg((999.0, 150.0, 40.0), 90.0, 50.0, 25.0, 25.0, 40.0)
    with pytest.raises(AssertionError, match="position gap"):
        tm.concat([a, b])
    c = tm.level_leg(a.pos_enu[-1], 90.0, 50.0, 10.0, 10.0, 40.0)
    with pytest.raises(AssertionError, match="speed gap"):
        tm.concat([a, c])


# ---------------------------------------------------------- physics police

def test_speed_range(seq):
    speeds = np.linalg.norm(seq.vel_enu, axis=1)
    assert speeds.min() >= 2.0 - 1e-6
    assert speeds.max() <= 40.0
    t0, t1 = _window(seq, "stall_turn")
    outside = (seq.t < t0) | (seq.t > t1)
    assert speeds[outside].min() >= 12.0   # floor only inside the stall turn
    inside = ~outside
    assert speeds[inside].min() < 3.0


def test_g_limit(seq):
    acc = np.gradient(seq.vel_enu, tm.DT, axis=0)
    acc[:, 2] += G                                   # felt acceleration
    assert np.linalg.norm(acc, axis=1).max() <= 4.0 * G


def test_step_continuity(seq):
    steps = np.linalg.norm(np.diff(seq.pos_enu, axis=0), axis=1)
    assert steps.max() <= 1.5 * 40.0 * tm.DT


def test_loop_closure_in_sequence(seq):
    t0, t1 = _window(seq, "loop")
    m = (seq.t >= t0) & (seq.t <= t1)
    pts = seq.pos_enu[m]
    assert np.linalg.norm(pts[-1] - pts[0]) < 2.0
    centered = pts - pts.mean(axis=0)
    assert np.linalg.svd(centered, full_matrices=False)[1][-1] < 0.5


def test_box_containment(seq):
    t0 = next(e.t_utc for e in seq.events if e.kind == "SCORED_START")
    t1 = next(e.t_utc for e in seq.events if e.kind == "SCORED_END")
    m = (seq.t >= t0) & (seq.t <= t1)
    e, n, u = seq.pos_enu[m].T
    assert n.min() >= 100.0 and n.max() <= 220.0
    assert (np.abs(e) <= n * np.tan(np.radians(60.0))).all()
    assert u.min() >= 25.0 and u.max() <= 120.0


def test_events_bracket_and_nest(seq):
    names = ["loop", "roll", "stall_turn", "immelmann"]
    stack = []
    seen = []
    for ev in seq.events:
        if ev.kind == "MANEUVER_START":
            stack.append(ev.data["maneuver"])
        elif ev.kind == "MANEUVER_END":
            assert stack and stack[-1] == ev.data["maneuver"]
            seen.append(stack.pop())
    assert not stack
    assert seen == names                            # course order, no nesting
    times = [e.t_utc for e in seq.events]
    assert times == sorted(times)


def test_seed_determinism():
    a, b = tm.sportsman(seed=7), tm.sportsman(seed=7)
    assert np.array_equal(a.pos_enu, b.pos_enu)
    assert np.array_equal(a.vel_enu, b.vel_enu)
    assert np.array_equal(a.att_rpy, b.att_rpy)


def test_imperfections_deform():
    ideal = tm.sportsman(seed=0)
    bent = tm.sportsman(tm.Imperfections(loop_ovality=0.15,
                                         roll_drift_deg=6.0,
                                         alt_mismatch_m=3.0,
                                         center_offset_m=10.0), seed=0)
    n = min(len(ideal.t), len(bent.t))
    rms = np.sqrt(((ideal.pos_enu[:n] - bent.pos_enu[:n]) ** 2).mean())
    assert rms > 1.0
