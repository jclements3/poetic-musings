"""Lesson 04 / maiden06: TimeDecoder cases per SYS-006's ground half.

No captured output to match — the assertions are the evidence, same as a
requirement-tagged testbench.
"""

from itertools import pairwise

import numpy as np

from maiden.timebase import (
    TimeDecoder,
    TimePoint,
    decoder_from_packets,
    encode_time_payload,
)

R0 = 123_456_789
T0 = 1_800_000_000.0  # arbitrary UTC epoch seconds


def make_decoder(n=300, rtc_rate=10_000_000.0, drop=()):
    dec = TimeDecoder()
    for k in range(n):
        if k in drop:
            continue
        dec.add(TimePoint(rtc=R0 + round(k * rtc_rate), utc=T0 + k))
    dec.fit()
    return dec


def test_exact_recovery():
    dec = make_decoder()
    mid = R0 + round(150.5 * 10_000_000)
    assert abs(dec.to_utc(mid) - (T0 + 150.5)) < 1e-6  # <= 1 us mid-span
    assert abs(dec.drift_ppm) < 1e-3
    assert dec.healthy()


def test_drift_recovered():
    # RTC runs fast: 10 MHz * (1 + 20e-6). drift_ppm must report ~ -? No:
    # more ticks per true second means utc advances *slower* per tick, and
    # drift_ppm is defined on the tick rate — the fit slope a is utc-per-
    # tick, so a = NOMINAL/(1+20e-6) and drift_ppm ~= -20... The sign
    # convention the lesson uses is "RTC at 10 MHz * (1+eps)" -> here we
    # generate rtc = k * 10e6 * (1+20e-6) for utc steps of 1 s.
    dec = make_decoder(rtc_rate=10_000_000.0 * (1 + 20e-6))
    assert abs(abs(dec.drift_ppm) - 20.0) < 0.1
    # Far end of a 300 s span: the fit stays within 100 us.
    far = R0 + round(299.0 * 10_000_000.0 * (1 + 20e-6))
    assert abs(dec.to_utc(far) - (T0 + 299.0)) < 100e-6
    # Executable rationale for the fit: a naive single-point offset using
    # the first packet and NOMINAL tick length would be ~6 ms off by the
    # far end (299 s * 20e-6 = 5.98 ms).
    naive = T0 + (far - R0) * (1.0 / 10_000_000.0)
    assert abs(naive - (T0 + 299.0)) > 5e-3


def test_gap_detection():
    dec = make_decoder(drop=set(range(100, 110)))
    gs = dec.gaps()
    assert len(gs) == 1
    lo, hi = gs[0]
    assert abs(lo - (T0 + 99)) < 1e-6 and abs(hi - (T0 + 110)) < 1e-6
    assert not dec.healthy()
    assert any("gap" in r for r in dec.fallback_reasons())


def test_bcd_midnight_rollover_monotonic():
    # Hand-built packet stream crossing 23:59:59 -> 00:00:00 (day rolls).
    packets = []
    times = [(200, 23, 59, 58), (200, 23, 59, 59), (201, 0, 0, 0),
             (201, 0, 0, 1), (201, 0, 0, 2)]
    for k, (day, h, m, s) in enumerate(times):
        packets.append((R0 + k * 10_000_000,
                        encode_time_payload(day, h, m, s)))
    dec = decoder_from_packets(packets)
    utcs = [p.utc for p in dec.points]
    assert all(b > a for a, b in pairwise(utcs)), "UTC must be monotonic"
    assert all(abs(b - a - 1.0) < 1e-9 for a, b in pairwise(utcs))


def test_bcd_is_not_binary():
    # 0x23-style trap: 23 s encodes as BCD nibbles 2,3 — decoding as binary
    # would give 35. Round-trip proves digit-wise handling.
    from maiden.timebase import decode_time_payload
    day, sod = decode_time_payload(encode_time_payload(123, 12, 34, 23))
    assert day == 123
    assert sod == 12 * 3600 + 34 * 60 + 23


def test_outlier_rejection():
    # Explore 3: one time packet an hour off bends a plain fit badly;
    # robust_fit drops it and recovers the clean line.
    dec = TimeDecoder()
    for k in range(300):
        utc = T0 + k + (3600.0 if k == 150 else 0.0)
        dec.add(TimePoint(rtc=R0 + k * 10_000_000, utc=utc))
    dec.fit()
    bent = abs(dec.to_utc(R0) - T0)
    assert bent > 1.0  # plain least squares is seconds off at the ends
    rejected = dec.robust_fit()
    assert rejected == 1
    assert abs(dec.to_utc(R0) - T0) < 1e-3
    assert np.isclose(dec.drift_ppm, 0.0, atol=0.1)
