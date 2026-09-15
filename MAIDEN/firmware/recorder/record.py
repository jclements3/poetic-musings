"""Recorder CLI: `python -m recorder --station A --out FILE.ch10`.

Contracts: firmware/recorder/PROTOCOL.md (UART records), D4 IF-1/IF-2.

Two modes:
  --selftest N   drive a deterministic fake FPGA stream for N virtual
                 seconds and write a real file — the desk-verifiable
                 path (maiden40).
  (default)      open the real serial port; bench work (maiden41-42).
                 Exits with a clear message until that sprint lands.

SIGINT lands a clean shutdown: sources stop first, then the writer
drains every ring before closing (RecorderWriter.stop's drain rule).
"""
import argparse
import signal
import sys
import time
from pathlib import Path

from maiden.tmats import parse_station, render_station

from . import protocol as proto
from .sources import FpgaSource, StatusSource
from .writer import RecorderWriter, default_rings

TEMPLATE = Path(__file__).resolve().parents[2] / "config/tmats/station.tmt"


def station_tmats(letter: str) -> str:
    st = parse_station(TEMPLATE.read_text())
    st.station_id = f"STATION_{letter}"
    st.serial = f"MAIDEN-STA-00{ord(letter) - 64}"
    return render_station(st)


class VirtualClock:
    """Monotonic stand-in the selftest advances by hand (seconds)."""

    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def second_frames(s: int):
    """One virtual second of FPGA traffic: TIME_MARK + PPS_STATUS +
    50 DOPPLER_V — the 1 Hz records the timebase FPGA actually emits."""
    rtc = s * 10_000_000
    yield proto.pack_frame(
        proto.TIME_MARK, s & 0xFF,
        proto.encode_time_mark(rtc, 233, 12 * 3600 + s))
    yield proto.pack_frame(
        proto.PPS_STATUS, s & 0xFF,
        proto.encode_pps_status(2, locked=True))
    for k in range(50):
        yield proto.pack_frame(
            proto.DOPPLER_V, (s * 50 + k) & 0xFF,
            proto.encode_doppler(True, 10.0 + s, 100 + k, 900, 40))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="recorder")
    ap.add_argument("--station", required=True, choices="ABC")
    ap.add_argument("--out", required=True)
    ap.add_argument("--selftest", type=int, metavar="SECONDS")
    ap.add_argument("--port", default="/dev/ttyUSB1",
                    help="FPGA UART device (bench; maiden41)")
    args = ap.parse_args(argv)

    if args.selftest is None:
        print("real serial capture is bench work (maiden41); run with "
              "--selftest N for the desk path", file=sys.stderr)
        return 2

    rings = default_rings()
    writer = RecorderWriter(args.out, station_tmats(args.station), rings)
    clock = VirtualClock()
    fpga = FpgaSource(port=None, ch1=rings[1], ch4=rings[4], clock=clock)
    status = StatusSource(fpga, rings[6], writer.total_drops)

    stopping = {"now": False}
    signal.signal(signal.SIGINT, lambda *_: stopping.update(now=True))

    writer.start()
    for s in range(args.selftest):
        if stopping["now"]:
            break
        frames = list(second_frames(s))
        clock.t = float(s)
        fpga.handle(frames[0])                 # TIME_MARK at top of second
        for k, frame in enumerate(frames[1:]):
            clock.t = s + (k + 1) * 0.02       # 50 Hz cadence
            fpga.handle(frame)
        status.emit(s * 10_000_000 + 5_000_000, 13.2, 41.0, 80)
        # pace the burst: the bench spreads these over a real second,
        # the selftest instead waits for the writer to drain halfway
        while len(rings[4]) > rings[4].capacity // 2:
            time.sleep(0.001)
    writer.stop()
    print(f"wrote {args.out}: {writer.stats()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
