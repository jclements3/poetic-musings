"""maiden57 — field-rule checker (SYS-010; VT-23 rehearsal shapes)."""

import numpy as np
import pytest

from maiden.rules import FieldRules, Polygon, check, load_rules
from maiden.runner import FIELD_CFG
from maiden.state import StateSample

HYST = 5


def _track(path_en, dt=0.02):
    """FUSED samples walking the given E/N points at 50 Hz."""
    out = []
    for i, (e, n) in enumerate(path_en):
        out.append(StateSample(t_utc=i * dt, source="FUSED",
                               pos_enu=(e, n, 30.0), vel_enu=(25.0, 0, 0)))
    return out


def _rules(polys=(), line=None):
    return FieldRules(status="TEST", hysteresis=HYST,
                      polygons=list(polys),
                      flight_line=np.asarray(line, float)
                      if line is not None else None)


BOX = Polygon("test box", "no_overflight",
              np.array([[50.0, 130.0], [80.0, 130.0],
                        [80.0, 170.0], [50.0, 170.0]]))


def test_scripted_violation_one_enter_one_exit():
    # fly straight through the box at N=150: -20 .. 150 in E
    path = [(e, 150.0) for e in np.linspace(-20, 150, 200)]
    ev = check(_track(path), _rules([BOX]))
    assert len(ev) == 2
    enter, exit_ = ev
    assert enter.data["enter"] is True and exit_.data["enter"] is False
    assert enter.t_utc < exit_.t_utc
    # sensible locations: near the box edges (hysteresis delays by a few
    # samples; edge spacing here is ~0.85 m/sample)
    assert 50.0 <= enter.data["pos_enu"][0] <= 60.0
    assert 80.0 <= exit_.data["pos_enu"][0] <= 90.0


def test_clean_flight_no_events():
    path = [(e, 50.0) for e in np.linspace(-200, 200, 300)]   # south of box
    assert check(_track(path), _rules([BOX])) == []


def test_boundary_jitter_hysteresis():
    """Covariance-wide jitter ON a boundary must emit zero Events.

    This test forced the design: pure sample-count hysteresis fails it
    (a run of N same-side samples happens every ~2^N samples), which is
    why check() carries a spatial deadband too."""
    rng = np.random.default_rng(7)
    # hover at the box's west edge, jittering +/-1.5 m across it
    path = [(50.0 + rng.uniform(-1.5, 1.5), 150.0) for _ in range(400)]
    ev = check(_track(path), _rules([BOX]))
    assert ev == []              # inside the 2 m deadband: silence


def test_flight_line_crossing():
    line = [[-200.0, 0.0], [200.0, 0.0]]
    path = [(0.0, n) for n in np.linspace(40, -20, 120)]      # fly south
    ev = check(_track(path), _rules(line=line))
    assert len(ev) == 1 and ev[0].data["enter"] is True
    assert ev[0].data["rule"] == "flight_line"


def test_shipped_placeholder_loads_and_says_so():
    rules = load_rules(FIELD_CFG)
    assert rules.status == "PLACEHOLDER_PENDING_SURVEY"
    assert rules.polygons and rules.flight_line is not None
    # the twin's box flight (N >= ~110 m) never enters the placeholder
    # pits polygon (N <= -10) — a clean twin session stays clean
    path = [(e, 120.0) for e in np.linspace(-200, 200, 200)]
    assert check(_track(path), rules) == []


def test_degenerate_polygon_rejected_at_load(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text(
        "field_rules:\n"
        "  no_fly_polygons:\n"
        "    - name: degenerate\n"
        "      kind: no_overflight\n"
        "      vertices_enu: [[0.0, 0.0]]\n")
    with pytest.raises(ValueError, match="degenerate"):
        load_rules(bad)
