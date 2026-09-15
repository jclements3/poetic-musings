"""Capture sources: read, stamp, push — nothing else.

Record layouts and RTC-assignment rules: firmware/recorder/PROTOCOL.md.

Every source takes its I/O object as a constructor argument so tests
drive it with fakes; the real devices (serial port, V4L2 camera, INA219)
arrive at the bench in maiden41-42. Nothing here fabricates hardware.
"""
import struct
import threading
import time

from maiden import timebase as tb
from maiden.ch10 import payloads as pl

from . import protocol as proto
from .rings import Ring

RTC_HZ = 10_000_000


class FpgaSource:
    """Demultiplex the FPGA UART stream into Ch 1 / Ch 4 rings.

    RTC assignment (PROTOCOL.md "recorder-side notes"): TIME_MARK records
    carry their own RTC (the PPS latch). DOPPLER_V records carry none, so
    the recorder extrapolates from the latest TIME_MARK using the local
    monotonic clock — worst case ~1-2 ms of serial+scheduling latency,
    inside the radar's own 20 ms frame cadence and flagged in the ICD
    note. Records arriving before the first TIME_MARK are counted and
    dropped: un-timestampable data is a degraded state that says so.
    """

    def __init__(self, port, ch1: Ring, ch4: Ring,
                 clock=time.monotonic):
        self.port = port
        self.ch1 = ch1
        self.ch4 = ch4
        self.clock = clock
        self.parser = proto.FrameParser()
        self.pre_time_drops = 0
        self.pps_locked = False
        self.strobe_stamps: list[tuple[int, int, bool]] = []
        self._mark: tuple[int, float] | None = None   # (pps_rtc, mono)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    # -- record handling (callable directly by tests, no thread needed) --

    def handle(self, data: bytes):
        for rtype, _seq, payload in self.parser.feed(data):
            if rtype == proto.TIME_MARK:
                pps_rtc, day, secs = proto.decode_time_mark(payload)
                self._mark = (pps_rtc, self.clock())
                h, rem = divmod(secs, 3600)
                m, s = divmod(rem, 60)
                self.ch1.push(pps_rtc,
                              (1, 0x11, tb.encode_time_payload(day, h, m, s)))
            elif rtype == proto.DOPPLER_V:
                rtc = self._estimate_rtc()
                if rtc is None:
                    self.pre_time_drops += 1
                    continue
                _det, v_r, fbin, _pk, _nz, snr = \
                    proto.decode_doppler(payload)
                self.ch4.push(rtc, (4, 0x09,
                                    pl.pack_radar_v(v_r, snr, fbin)))
            elif rtype == proto.STROBE_STAMP:
                self.strobe_stamps.append(proto.decode_strobe(payload))
            elif rtype == proto.PPS_STATUS:
                _off, locked, _hold, _seen = proto.decode_pps_status(payload)
                self.pps_locked = locked

    def _estimate_rtc(self):
        if self._mark is None:
            return None
        pps_rtc, t0 = self._mark
        return pps_rtc + int((self.clock() - t0) * RTC_HZ)

    # -- thread plumbing --

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._thread.join()

    def _run(self):
        while not self._stop.is_set():
            data = self.port.read(256)
            if data:
                self.handle(data)
            else:
                time.sleep(0.002)


class CameraSource:
    """Associate encoded frames with strobe stamps BY INDEX, push Ch 2.

    Real capture/encode is maiden41 (V4L2/Picamera2 + hardware H.264).
    The association queue and the off-by-N discipline live here: frame n
    pairs with strobe record n; monotonicity is asserted, never assumed.
    """

    def __init__(self, fpga: FpgaSource, ch2: Ring):
        self.fpga = fpga
        self.ch2 = ch2
        self.frames_in = 0
        self.unstamped = 0
        self._last_seq = -1

    def push_frame(self, encoded: bytes):
        idx = self.frames_in
        self.frames_in += 1
        stamps = self.fpga.strobe_stamps
        if idx >= len(stamps):
            self.unstamped += 1        # stamp not yet arrived: degraded
            return False
        rtc, seq, _ovf = stamps[idx]
        if seq <= self._last_seq:
            raise RuntimeError(
                f"strobe association broke monotonicity: seq {seq} after "
                f"{self._last_seq} (see PROTOCOL.md, associate by index)")
        self._last_seq = seq
        return self.ch2.push(rtc, (2, 0x40, encoded))


class StatusSource:
    """Compose the 1 Hz Ch 6 STATION_STATUS payload.

    Battery/temp/disk come from the bench hardware in maiden41 (INA219,
    SoC thermal zone, statvfs); tests inject values. The total-drops
    counter rides in the payload's reserved pad halfword — layout note
    in PROTOCOL.md; base struct stays payloads._STATUS, unchanged.
    """

    def __init__(self, fpga: FpgaSource, ch6: Ring, drops_fn):
        self.fpga = fpga
        self.ch6 = ch6
        self.drops_fn = drops_fn

    @staticmethod
    def body(battery_v, temp_c, pps_lock, disk_free_pct,
             total_drops: int) -> bytes:
        base = pl.pack_status(battery_v, temp_c, pps_lock, disk_free_pct)
        drops = min(int(total_drops), 0xFFFF)
        return base[:10] + struct.pack("<H", drops)

    def emit(self, rtc: int, battery_v: float, temp_c: float,
             disk_free_pct: int) -> bool:
        return self.ch6.push(
            rtc, (6, 0x30, self.body(battery_v, temp_c, self.fpga.pps_locked,
                                     disk_free_pct, self.drops_fn())))
