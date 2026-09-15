"""VT-14 hostile half: fuzzed TMATS, truncation, hold-back violation."""

import struct

import numpy as np
import pytest

from maiden import ingest
from maiden.ch10 import packet as pk
from maiden.ch10.writer import Ch10Writer
from maiden.state import validate
from maiden.twin.writer import write_session

SEED = 101
N_FUZZ = 500


@pytest.fixture(scope="module")
def session(tmp_path_factory):
    out = tmp_path_factory.mktemp("twin-fuzz")
    return write_session(out, seed=SEED)


def _raw_packet(channel, dtype, rtc, body, seqno=0):
    """Hand-assembled packet, bypassing the writer's IF-1 guards."""
    filler = (2 - len(body)) % 4
    padded = body + b"\x00" * filler
    packet_len = 24 + len(padded) + 2
    hdr22 = struct.pack("<HHIIBBBB6s", pk.SYNC, channel, packet_len,
                        len(body), 0, seqno, 0x02, dtype,
                        rtc.to_bytes(6, "little"))
    hdr = hdr22 + struct.pack("<H", pk.header_checksum(hdr22))
    return hdr + padded + struct.pack("<H", pk.data_checksum(padded))


def _mangle(rng, data: bytes) -> bytes:
    """One seeded mutation: flip, delete, insert, truncate, or junk."""
    b = bytearray(data)
    op = rng.integers(0, 5)
    if op == 0 and b:
        i = rng.integers(0, len(b))
        b[i] ^= 1 << rng.integers(0, 8)
    elif op == 1 and len(b) > 2:
        i = rng.integers(0, len(b) - 1)
        del b[i:i + int(rng.integers(1, min(40, len(b) - i)))]
    elif op == 2:
        i = rng.integers(0, len(b) + 1)
        b[i:i] = bytes(rng.integers(0, 256, size=rng.integers(1, 20),
                                    dtype=np.uint8))
    elif op == 3:
        b = b[:rng.integers(0, len(b) + 1)]
    else:
        b = bytearray(rng.integers(0, 256, size=rng.integers(0, 400),
                                   dtype=np.uint8))
    return bytes(b)


def test_tmats_fuzz_500_cases(tmp_path, session):
    """describe() returns a descriptor or raises TmatsError — nothing else."""
    first = next(ingest.walk_packets(session["A"]))
    tmats_body = first[3]
    rng = np.random.default_rng(20260821)
    outcomes = {"ok": 0, "tmats_error": 0}
    for i in range(N_FUZZ):
        body = _mangle(rng, tmats_body)
        p = tmp_path / "fz.ch10"
        p.write_bytes(_raw_packet(0, 0x01, 0, body)
                      + _raw_packet(1, 0x11, 100, b"\x00" * 10, seqno=0))
        try:
            d = ingest.describe(p)
            assert isinstance(d, (ingest.Station, ingest.Aircraft))
            outcomes["ok"] += 1
        except ingest.TmatsError:
            outcomes["tmats_error"] += 1
        # any other exception type propagates and fails the test
    assert sum(outcomes.values()) == N_FUZZ
    # sanity: the mangler produces both survivable and fatal inputs
    assert outcomes["ok"] > 0 and outcomes["tmats_error"] > 0


def test_truncation_ten_offsets(tmp_path, session):
    """A chopped file yields only complete, valid samples, then stops."""
    with open(session["A"], "rb") as f:
        data = f.read()
    full = sum(1 for _ in ingest.load(session["A"]))
    rng = np.random.default_rng(7)
    for off in rng.integers(200, len(data), size=10):
        p = tmp_path / "chop.ch10"
        p.write_bytes(data[:off])
        n = 0
        for s in ingest.load(p):
            validate(s)
            n += 1
        assert n <= full


def test_holdback_overflow_is_if1_violation(tmp_path):
    """Explore 1: >2 s of data before the first time packet fails hard."""
    p = tmp_path / "bad.ch10"
    from maiden.ch10 import payloads as pl
    from maiden.tmats import Station, render_station
    st = Station(station_id="STATION_A", serial="X", lat=1.0, lon=1.0,
                 alt_m=0.0, hdg_deg=0.0, cam=None, radar=None,
                 channels=[(0, "TMATS", "COM"), (1, "TIME", "TIM"),
                           (5, "TRACKER", "MSG")])
    w = Ch10Writer(p)
    w.write_tmats(0, render_station(st))
    for i in range(100):                       # 3 s of tracker, no time yet
        w.write_packet(channel=5, dtype=0x30, rtc=1000 + i * 300_000,
                       body=pl.pack_tracker(1.0, 2.0, 0.9))
    w.close()
    with pytest.raises(ingest.IngestError, match="IF-1"):
        list(ingest.load(p))


def test_too_few_time_packets(tmp_path):
    from maiden.ch10 import payloads as pl
    from maiden.tmats import Station, render_station
    st = Station(station_id="STATION_A", serial="X", lat=1.0, lon=1.0,
                 alt_m=0.0, hdg_deg=0.0, cam=None, radar=None,
                 channels=[(0, "TMATS", "COM"), (5, "TRACKER", "MSG")])
    p = tmp_path / "onetime.ch10"
    w = Ch10Writer(p)
    w.write_tmats(0, render_station(st))
    w.write_packet(channel=5, dtype=0x30, rtc=100,
                   body=pl.pack_tracker(1.0, 2.0, 0.9))
    w.close()
    with pytest.raises(ingest.IngestError, match="held back"):
        list(ingest.load(p))


def test_walker_memory_stays_bounded(session):
    """Streaming means streaming: walker peak allocation is packet-sized,
    not file-sized (bench-scale RSS check deferred to a real session)."""
    import tracemalloc

    tracemalloc.start()
    n = sum(1 for _ in ingest.walk_packets(session["A"]))
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert n > 4000
    import os
    size = os.path.getsize(session["A"])
    assert peak < 64 * 1024 and peak < size / 3
