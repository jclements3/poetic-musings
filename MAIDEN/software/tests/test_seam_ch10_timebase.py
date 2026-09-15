"""Seam regression: Ch10Writer time packets decode through TimeDecoder.

Pins the cross-module contract reconciled after maiden03-07: read_packets
yields Packet(channel, dtype, rtc, body) namedtuples, and the writer's
Ch 1 / 0x11 payloads are exactly timebase's BCD time layout.
"""

from maiden import timebase as tb
from maiden.ch10 import read_packets
from maiden.ch10.writer import Ch10Writer

TMATS = "config/tmats/station.tmt"


def test_writer_time_packets_fit_decoder(tmp_path):
    p = tmp_path / "t.ch10"
    w = Ch10Writer(p)
    with open(TMATS) as f:
        w.write_tmats(0, f.read())
    for i in range(4):
        w.write_packet(
            channel=1,
            dtype=0x11,
            rtc=10_000_000 * i,
            body=tb.encode_time_payload(233, 14, 30, i),
        )
    w.close()

    pkts = list(read_packets(p))
    # attribute access and tuple unpacking both work
    assert pkts[0].channel == 0 and pkts[0].dtype == 0x01
    channel, dtype, rtc, _body = pkts[1]
    assert (channel, dtype, rtc) == (1, 0x11, 0)

    dec = tb.decoder_from_file(p)
    assert abs((dec.to_utc(5_000_000) - dec.to_utc(0)) - 0.5) < 1e-6
    assert dec.healthy()
