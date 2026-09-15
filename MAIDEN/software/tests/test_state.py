"""maiden08: IF-4 dataclasses, validate() rules, adapter registry.

Property layer uses a seeded numpy Generator (seed recorded below), not
hypothesis — one fewer dependency, same coverage of the legal/illegal
field-combination space.
"""
import numpy as np
import pytest
from conftest import check_adapter_stream

from maiden import adapters
from maiden.state import SOURCES, STATIONS, Event, StateSample, validate

SEED = 20260821  # course date; property layer is reproducible


# --- example-based: one accept per source kind ------------------------------

def station(**kw):
    return StateSample(t_utc=0.0, source="A", **kw)


def test_accept_station_angles_only():
    validate(station(az_deg=10.0, el_deg=5.0, conf=0.9))


def test_accept_station_vr_only():
    validate(station(v_r=-12.5))


def test_accept_fused():
    validate(StateSample(t_utc=0.0, source="FUSED", pos_enu=(0, 0, 0),
                         vel_enu=(1, 0, 0), cov=np.eye(6)))


def test_accept_fused_without_cov():
    # validate encodes the ICD, not hopes: cov optional on FUSED
    validate(StateSample(t_utc=0.0, source="FUSED", pos_enu=(0, 0, 0),
                         vel_enu=(1, 0, 0)))


def test_accept_truth():
    validate(StateSample(t_utc=0.0, source="TRUTH", pos_enu=(0, 0, 0),
                         vel_enu=(1, 0, 0), att_rpy=(0, 0, 90)))


# --- example-based: one reject per validate rule ----------------------------

def test_reject_unknown_source():
    with pytest.raises(ValueError, match="unknown source"):
        validate(StateSample(t_utc=0.0, source="D"))


def test_reject_station_with_pos():
    with pytest.raises(ValueError, match="angles, not state"):
        validate(station(az_deg=1.0, pos_enu=(0, 0, 0)))


def test_reject_station_with_cov():
    with pytest.raises(ValueError, match="angles, not state"):
        validate(station(az_deg=1.0, cov=np.eye(6)))


def test_reject_station_no_measurement():
    with pytest.raises(ValueError, match="no measurement"):
        validate(station(conf=0.5))


@pytest.mark.parametrize("conf", [-0.01, 1.01])
def test_reject_conf_out_of_range(conf):
    with pytest.raises(ValueError, match="conf"):
        validate(station(az_deg=1.0, conf=conf))


@pytest.mark.parametrize("source", ["FUSED", "TRUTH"])
def test_reject_state_sources_missing_pos_vel(source):
    with pytest.raises(ValueError, match="pos"):
        validate(StateSample(t_utc=0.0, source=source, pos_enu=(0, 0, 0)))


def test_reject_fused_bad_cov_shape():
    with pytest.raises(ValueError, match="6x6"):
        validate(StateSample(t_utc=0.0, source="FUSED", pos_enu=(0, 0, 0),
                             vel_enu=(0, 0, 0), cov=np.eye(3)))


def test_reject_truth_with_cov():
    with pytest.raises(ValueError, match="no covariance"):
        validate(StateSample(t_utc=0.0, source="TRUTH", pos_enu=(0, 0, 0),
                             vel_enu=(0, 0, 0), cov=np.eye(6)))


# --- property-based: seeded random samples per source kind ------------------

def _random_sample(rng):
    """Draw a sample with fields chosen per source kind; return it plus
    whether the draw is legal by construction."""
    source = rng.choice(SOURCES)
    s = StateSample(t_utc=float(rng.uniform(0, 1e5)), source=str(source))
    legal = True
    if source in STATIONS:
        if rng.random() < 0.8:
            s.az_deg, s.el_deg = float(rng.uniform(-180, 180)), float(
                rng.uniform(-5, 85))
        if rng.random() < 0.8:
            s.v_r = float(rng.uniform(-60, 60))
        if s.az_deg is None and s.v_r is None:
            legal = False
        if rng.random() < 0.5:
            s.conf = float(rng.uniform(-0.2, 1.2))
            if not 0.0 <= s.conf <= 1.0:
                legal = False
        if rng.random() < 0.1:
            s.pos_enu = (0.0, 0.0, 0.0)
            legal = False
    else:
        if rng.random() < 0.9:
            s.pos_enu = tuple(rng.uniform(-200, 200, 3))
        if rng.random() < 0.9:
            s.vel_enu = tuple(rng.uniform(-40, 40, 3))
        if s.pos_enu is None or s.vel_enu is None:
            legal = False
        if rng.random() < 0.3:
            s.cov = np.eye(int(rng.choice([3, 6])))
            if source == "TRUTH" or s.cov.shape != (6, 6):
                legal = False
    return s, legal


def test_property_validate_accepts_exactly_legal():
    rng = np.random.default_rng(SEED)
    n_legal = n_illegal = 0
    for _ in range(2000):
        s, legal = _random_sample(rng)
        if legal:
            validate(s)
            n_legal += 1
        else:
            with pytest.raises(ValueError):
                validate(s)
            n_illegal += 1
    # both branches must actually be exercised
    assert n_legal > 200 and n_illegal > 200


# --- adapter registry -------------------------------------------------------

def test_registry_roundtrip_and_keyerror():
    @adapters.adapter("test.dummy")
    def dummy(path, descriptor):  # pragma: no cover - never called
        yield from ()

    assert adapters.get("test.dummy") is dummy
    assert "test.dummy" in adapters.kinds()
    with pytest.raises(KeyError, match="test.dummy"):
        adapters.get("no.such.kind")
    with pytest.raises(ValueError, match="already registered"):
        adapters.adapter("test.dummy")(dummy)


# --- adapter contract engine (VT-14 core) -----------------------------------

def test_check_adapter_stream_accepts_legal_stream():
    stream = [station(az_deg=float(i), el_deg=1.0) for i in range(10)]
    for i, s in enumerate(stream):
        s.t_utc = float(i)
    check_adapter_stream(stream)


def test_check_adapter_stream_catches_invalid_sample():
    bad = [station(az_deg=1.0), station(conf=0.5)]  # second has no measurement
    with pytest.raises(ValueError, match="no measurement"):
        check_adapter_stream(bad)


def test_check_adapter_stream_catches_regression():
    a, b = station(az_deg=1.0), station(az_deg=2.0)
    a.t_utc, b.t_utc = 5.0, 4.0
    with pytest.raises(AssertionError, match="t_utc regressed"):
        check_adapter_stream([a, b])


def test_hostile_adapter_one_bad_sample_in_1000():
    """Lesson 05 Explore 3: the lesson-08 fuzz test in embryo."""
    rng = np.random.default_rng(SEED)
    bad_at = int(rng.integers(1, 1000))

    def hostile():
        t = 0.0
        for i in range(1000):
            t += float(rng.uniform(0.01, 0.05))
            s = station(az_deg=float(rng.uniform(-90, 90)))
            s.t_utc = t - 1.0 if i == bad_at else t  # one out-of-order sample
            yield s

    with pytest.raises(AssertionError, match="t_utc regressed"):
        check_adapter_stream(hostile())


# --- interleaved sources: monotonicity is per source, not global ------------

def test_stream_monotone_per_source_not_global():
    a = station(az_deg=1.0)
    b = StateSample(t_utc=0.5, source="B", az_deg=2.0)
    a.t_utc = 1.0
    check_adapter_stream([a, b])  # B earlier than A's sample is fine


def test_event_defaults():
    e = Event(t_utc=1.0, kind="TAKEOFF")
    assert e.data == {}
