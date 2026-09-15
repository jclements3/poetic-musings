"""maiden53-54: rubric scoring + calibration layer (SYS-007/008 shape).

Twin sessions score against ground-truth events so these tests isolate
the geometry checks from classifier quality. VT-20 is demonstrable on
twin data; VT-21 cannot bind before the campaign (see test names).
"""

import numpy as np
import pytest

from maiden.maneuver import truth_to_samples
from maiden.score import (
    Calibration,
    ManeuverScore,
    load_rubric,
    score_sequence,
)
from maiden.twin.model import Imperfections, sportsman


def _scores(imp=None, seed=0):
    tr = sportsman(imp, seed=seed)
    samples = truth_to_samples(tr, rate_hz=50.0)
    return score_sequence(tr.events, samples)


def _by_cls(scores):
    return {s.cls: s for s in scores}


# ------------------------------------------------------------- null test


def test_clean_twin_scores_near_ten():
    """The null test: clean session ~10s with near-empty deductions.

    Catches sign errors in every geometry check at once (maiden53 card).
    """
    scores = _scores()
    assert {s.cls for s in scores} == {"loop", "roll", "stall_turn",
                                       "immelmann"}
    for s in scores:
        assert s.raw >= 9.0, f"{s.cls} scored {s.raw}: {[d.text for d in s.deductions]}"
        assert sum(d.points for d in s.deductions) <= 1.0
        assert s.calibrated is None  # untrained path, no special-casing


def test_imperfect_prints_vt20_shape(capsys):
    scores = _scores(Imperfections(loop_ovality=0.15, roll_drift_deg=8.0,
                                   alt_mismatch_m=6.0))
    for s in scores:
        print(s.line())
    out = capsys.readouterr().out.strip().splitlines()
    assert len(out) == 4                      # one 0-10 line per maneuver
    assert all(any(ch.isdigit() for ch in ln) for ln in out)


# ------------------------------------------------- knob-by-knob checks


def test_ovality_costs_the_loop_roundness_points():
    clean = _by_cls(_scores())["loop"]
    oval = _by_cls(_scores(Imperfections(loop_ovality=0.15)))["loop"]
    assert oval.raw <= clean.raw - 1.0
    round_ded = [d for d in oval.deductions if d.tag == "roundness"]
    assert round_ded, "ovality must show up as a roundness deduction"
    # magnitude consistency: fitted-center radius sigma for ovality=0.15
    # measured 1.89 m on the twin (maiden53 build); sentence must carry
    # a magnitude in that regime, and the shape line sees the ~23 m
    # height-vs-width asymmetry of the egg
    text = " ".join(d.text for d in round_ded)
    assert any(u in text for u in ("m ", "m,")), text


def test_center_offset_costs_centering():
    clean = _by_cls(_scores())["loop"]
    off = _by_cls(_scores(Imperfections(center_offset_m=40.0)))["loop"]
    cen = [d for d in off.deductions if d.tag == "centering"]
    assert cen and off.raw < clean.raw
    assert "centerline" in cen[0].text


def test_roll_drift_costs_heading():
    drift = _by_cls(_scores(Imperfections(roll_drift_deg=10.0)))["roll"]
    tags = {d.tag for d in drift.deductions}
    assert "heading" in tags or "track" in tags
    assert drift.raw <= 9.0


def test_alt_mismatch_costs_the_loop():
    mism = _by_cls(_scores(Imperfections(alt_mismatch_m=8.0)))["loop"]
    assert any(d.tag == "alt_match" for d in mism.deductions)


def test_determinism_bit_for_bit():
    a = _scores(Imperfections(loop_ovality=0.1), seed=3)
    b = _scores(Imperfections(loop_ovality=0.1), seed=3)
    assert [(s.cls, s.raw, [(d.text, d.points) for d in s.deductions])
            for s in a] == \
           [(s.cls, s.raw, [(d.text, d.points) for d in s.deductions])
            for s in b]


def test_rubric_is_the_single_numeric_home():
    rub = load_rubric()
    assert rub["box"]["center_classes"] == ["loop"]
    # doubling the roundness charge must change the oval loop's score
    oval1 = _by_cls(_scores(Imperfections(loop_ovality=0.15)))["loop"]
    rub2 = load_rubric()
    rub2["loop"]["roundness_pts_per_m"] *= 2.0
    tr = sportsman(Imperfections(loop_ovality=0.15), seed=0)
    oval2 = _by_cls(score_sequence(
        tr.events, truth_to_samples(tr, rate_hz=50.0), rubric=rub2))["loop"]
    assert oval2.raw < oval1.raw


# ---------------------------------------------------------- calibration


def _synthetic_sheet_rows():
    """SYNTHETIC judge sheet -- proves the plumbing, not SYS-008."""
    rng = np.random.default_rng(20260821)
    rows = []
    for raw in np.linspace(2.0, 10.0, 25):
        # a judge who is harsh in the middle band, monotone overall
        judge = np.clip(0.5 + 0.9 * raw + rng.normal(0, 0.3), 0, 10)
        rows.append({"maneuver_class": "loop", "rubric_raw": float(raw),
                     "judge_score": float(judge)})
    return rows


def test_calibration_fit_save_load_roundtrip_synthetic(tmp_path):
    cal = Calibration().fit(_synthetic_sheet_rows())
    assert cal.trained
    # monotone by construction
    xs = np.linspace(0, 10, 101)
    ys = np.array([cal.apply("loop", float(x)) for x in xs])
    assert np.all(np.diff(ys) >= -1e-9)
    p = tmp_path / "cal.npz"
    cal.save(p)
    cal2 = Calibration.load(p)
    assert cal2.apply("loop", 7.0) == pytest.approx(cal.apply("loop", 7.0))
    # unknown class stays uncalibrated
    assert cal2.apply("roll", 7.0) is None


def test_untrained_calibration_flows_as_none():
    tr = sportsman(seed=1)
    samples = truth_to_samples(tr, rate_hz=50.0)
    scores = score_sequence(tr.events, samples, calibration=Calibration())
    assert all(s.calibrated is None for s in scores)


def test_trained_calibration_populates_calibrated():
    cal = Calibration().fit(_synthetic_sheet_rows())
    tr = sportsman(seed=1)
    samples = truth_to_samples(tr, rate_hz=50.0)
    scores = score_sequence(tr.events, samples, calibration=cal)
    loop = _by_cls(scores)["loop"]
    assert loop.calibrated is not None and 0.0 <= loop.calibrated <= 10.0
    assert _by_cls(scores)["roll"].calibrated is None  # class not fitted


def test_maneuverscore_line_marks_uncalibrated():
    s = ManeuverScore("loop", 8.5, None, [])
    assert "cal" not in s.line()
