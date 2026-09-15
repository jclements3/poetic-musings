"""maiden49: converter tests on the SYNTHETIC DataFlash fixture.

The fixture (maiden.convert.synth) is test infrastructure, clearly
labeled: no real H743 log exists until maiden47. VT-09's real pass runs
on the bench log; these tests pin the converter's behavior so that run
is a data swap, not a debug session.
"""

import numpy as np
import pytest

from maiden.convert import Airframe, get_adapter, read_back, write_aircraft_ch10
from maiden.convert.adapters import BetaflightBbl, EdgeTxCsv, Px4Ulog, UbloxUbx
from maiden.convert.ardupilot import LEAP_SECONDS, gps_to_utc
from maiden.convert.synth import write_synthetic_bin
from maiden.geo import enu_from_lla
from maiden.ingest import describe, load
from maiden.timebase import decoder_from_file

ORIGIN = (34.6851710, -86.5922440, 183.2)
AF = Airframe(name="KAOS_60", logger_serial="MAIDEN-LOG-001",
              mass_g=54.0, mount_xyz_mm=(12, 0, -8))


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    d = tmp_path_factory.mktemp("convert")
    bin_path = d / "synth.bin"
    truth = write_synthetic_bin(bin_path)
    rec = get_adapter(bin_path).read(bin_path)
    out = d / "AIRCRAFT_KAOS_60_synth.ch10"
    _, stats = write_aircraft_ch10(rec, AF, out, ORIGIN)
    return d, bin_path, truth, rec, out, stats


def test_adapter_counts_match_fixture(session):
    _, _, truth, rec, _, _ = session
    assert rec.counts() == {"GPS": len(truth["gps"]),
                            "IMU": len(truth["imu"]),
                            "BARO": len(truth["baro"]),
                            "ATT": len(truth["att"])}


def test_time_fit_recovers_utc_and_drift(session):
    _, _, truth, rec, _, _ = session
    a, _b, _t0, _u0, resid = rec.fit
    # slope: 1/(1+25ppm) in s per us -> drift recovered within 2 ppm
    drift_ppm = (1.0 / (a * 1e6) - 1.0) * 1e6
    assert abs(drift_ppm - truth["drift_ppm"]) < 2.0
    # GMS millisecond quantization bounds the residual
    assert resid < 1.5e-3
    # first GPS stamp equals the fixture's utc0 to the millisecond
    assert abs(rec.gps_t[0] - truth["utc0"]) < 1e-3


def test_leap_constant_documented_value():
    # utc(GWk=0, GMS=0) is the GPS epoch minus leap seconds
    assert gps_to_utc(0, 0) == 315_964_800.0 - LEAP_SECONDS
    assert LEAP_SECONDS == 18.0


def test_roundtrip_gps_lossless(session):
    _, _, truth, _rec, out, _ = session
    gps, imu, baro = read_back(out)
    g = np.array([r[1:4] for r in gps])          # lat, lon (f64), alt (f32)
    t = truth["gps"]
    assert len(gps) == len(t)
    # f64 fields: exact to adapter precision (1e-7 deg DataFlash quantum)
    assert np.abs(g[:, 0] - t[:, 3]).max() < 1e-7
    assert np.abs(g[:, 1] - t[:, 4]).max() < 1e-7
    # f32 fields: quantization only
    assert np.abs(g[:, 2] - t[:, 5]).max() < 1e-3
    vn = np.array([r[4] for r in gps])
    assert np.abs(vn - t[:, 6]).max() < 1e-5
    # sample-exact stream counts: dropped or duplicated is a fail
    assert len(imu) == len(truth["imu"])
    assert len(baro) == len(truth["baro"])


def test_ch10_time_channel_aligns_to_gps_time(session):
    _, _, _truth, rec, out, _ = session
    dec = decoder_from_file(out)
    # UTC of the RTC assigned to the first GPS fix must equal the fit's
    # stamp for it to the millisecond (SYS-006 airborne clause).
    rtc_first_gps = round((rec.gps_t[0] - rec.gps_t[0] + 1.0) * 1e7)
    day_sod = dec.to_utc(rtc_first_gps) % 86_400
    assert abs(day_sod - rec.gps_t[0] % 86_400) < 1e-3


def test_ingest_loads_truth_samples(session):
    _, _, _truth, rec, out, _ = session
    desc = describe(out)
    assert type(desc).__name__ == "Aircraft"
    assert desc.logger_serial == "MAIDEN-LOG-001"
    assert desc.mass_g == 54.0
    samples = [s for s in load(out) if s.source == "TRUTH"]
    assert len(samples) == len(rec.gps_t)
    # position matches geo transform of the raw LLA
    expect = enu_from_lla(ORIGIN, (rec.lat[0], rec.lon[0], rec.alt[0]))
    got = np.array(samples[0].pos_enu)
    assert np.abs(got - expect).max() < 1e-3
    # NED -> ENU velocity mapping
    assert abs(samples[0].vel_enu[0] - rec.ve[0]) < 1e-5
    assert abs(samples[0].vel_enu[1] - rec.vn[0]) < 1e-5
    # EKF attitude attached (ATT precedes GPS at same epoch rate)
    att_present = [s for s in samples if s.att_rpy is not None]
    assert len(att_present) >= len(samples) - 1


def test_rates_vt08_shaped(session):
    """VT-08-shaped rate check on the converted file — SYNTHETIC evidence
    only; the real VT-08 runs on maiden47's bench log."""
    _, _, _truth, rec, _out, _ = session
    for t, floor in ((rec.gps_t, 10.0), (rec.imu_t, 100.0),
                     (rec.baro_t, 10.0)):
        dt = np.diff(t)
        assert 1.0 / dt.mean() >= floor * 0.999
        assert dt.max() < 2.0 / floor              # no gaps > 2x nominal


def test_registry_dispatch_and_stubs(tmp_path):
    for cls, suffix in ((Px4Ulog, ".ulg"), (BetaflightBbl, ".bbl"),
                        (UbloxUbx, ".ubx"), (EdgeTxCsv, ".csv")):
        p = tmp_path / f"x{suffix}"
        p.touch()
        adapter = get_adapter(p)
        assert isinstance(adapter, cls)
        with pytest.raises(NotImplementedError) as e:
            adapter.read(p)
        assert "IF-3" in str(e.value)
    with pytest.raises(ValueError, match="no IF-3 adapter"):
        get_adapter(tmp_path / "x.foo")


def test_cli_end_to_end(tmp_path, capsys):
    from maiden.cli import main

    bin_path = tmp_path / "synth.bin"
    write_synthetic_bin(bin_path, duration_s=5.0)
    rc = main(["convert", str(bin_path),
               "--airframe", "config/airframes/kaos.yaml",
               "--out", str(tmp_path / "out")])
    assert rc == 0
    out = capsys.readouterr().out
    assert "GPS: 50 msgs" in out
    assert "time-fit residual RMS" in out
