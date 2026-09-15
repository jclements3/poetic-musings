"""maiden05: TMATS template, parser/generator, fuzz (VT-14 groundwork)."""
import dataclasses
import random
from pathlib import Path

from maiden.tmats import parse_attributes, parse_station, render_station

TEMPLATE = (Path(__file__).parents[2]
            / "config" / "tmats" / "station.tmt").read_text()


def _key_fields(st):
    d = dataclasses.asdict(st)
    d.pop("raw")
    d.pop("warnings")
    return d


def test_template_parses():
    st = parse_station(TEMPLATE)
    assert st.station_id == "STATION_A"
    assert st.serial == "MAIDEN-STA-001"
    assert st.lat == 34.6851710
    assert st.hdg_deg == 12.4
    assert st.cam["fx"] == 1820.4
    assert st.radar["module"] == "CDM324"
    assert len(st.channels) == 7
    assert st.channels[1] == (1, "TIME", "TIM")
    assert st.warnings == []


def test_roundtrip_stable():
    st = parse_station(TEMPLATE)
    rendered = render_station(st)
    st2 = parse_station(rendered)
    assert _key_fields(st2) == _key_fields(st)
    assert render_station(st2) == rendered  # byte-identical re-render


def test_degradation_missing_attribute():
    text = "\n".join(line for line in TEMPLATE.splitlines()
                     if "HDG_DEG" not in line)
    st = parse_station(text)
    assert st.hdg_deg is None
    assert st.lat == 34.6851710  # neighbors intact
    assert any("HDG_DEG" in w for w in st.warnings)


def test_fuzz_never_raises():
    rng = random.Random(2026)
    raw = TEMPLATE.encode("latin-1")
    for _ in range(200):
        b = bytearray(raw)
        for _ in range(rng.randint(1, 8)):
            op = rng.choice(("del", "ins", "trunc"))
            if op == "del" and b:
                del b[rng.randrange(len(b))]
            elif op == "ins":
                b.insert(rng.randrange(len(b) + 1), rng.randrange(256))
            else:
                del b[rng.randrange(len(b) + 1):]
        st = parse_station(bytes(b).decode("latin-1"))  # must not raise
        assert st is not None


def test_parse_attributes_errors_collected():
    attrs = parse_attributes("G\\PN:MAIDEN; broken piece; G\\106:23;")
    assert attrs["G\\PN"] == "MAIDEN"
    assert attrs["G\\106"] == "23"
    assert attrs["__errors__"] == ["broken piece"]


def test_real_tmats_through_writer(tmp_path):
    """maiden05 wiring: the rendered template as the real first packet."""
    from chapter10 import C10

    from maiden.ch10 import Ch10Writer, read_packets
    from maiden.ch10 import packet as pk

    st = parse_station(TEMPLATE)
    p = tmp_path / "real.ch10"
    w = Ch10Writer(p)
    w.write_tmats(100, render_station(st))
    w.write_packet(1, pk.T_TIME, 200, b"\x00" * 12)
    w.close()

    _, dtype, _, body = next(read_packets(p))
    assert dtype == pk.T_TMATS
    text = body[4:].decode("ascii")  # CSDW then ASCII
    st2 = parse_station(text)
    assert st2.lat == st.lat and st2.cam["fx"] == st.cam["fx"]
    assert len(list(C10(str(p)))) == 2  # foreign parser still happy
