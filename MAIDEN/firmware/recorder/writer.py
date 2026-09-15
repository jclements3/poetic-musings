"""Min-RTC merge writer: rings in, one TMATS-first .ch10 out.

Wire/record contracts: firmware/recorder/PROTOCOL.md and D4 IF-1.

Rate budget (lesson 19, recomputed here — the arithmetic that sized the
rings; aggregate decides nothing, the SD stall depth does):

    Ch 3 RADAR_IF  48 000 S/s x 2 ch x 2 B          = 192.0 kB/s
    Ch 2 VIDEO     1080p30 H.264 @ 8 Mb/s           = 1000.0 kB/s
    Ch 4 RADAR_V   50 Hz x 12 B payload             =   0.6 kB/s
    Ch 5 TRACKER   30 Hz x 20 B payload             =   0.6 kB/s
    Ch 1 + Ch 6    2 Hz small packets               =   0.1 kB/s
    packet overhead: 26 B/packet; Ch 3 grouped 100 minor frames
    (19.2 kB) per packet -> ~10 pkt/s, Ch 2 one packet per frame
    (30/s), Ch 4/5 per record -> ~90 pkt/s x 26 B   =   2.3 kB/s
    ---------------------------------------------------------------
    aggregate ~= 1.20 MB/s ~= 4.3 GB/h

Ring sizing: >= 2 s at channel rate (an SD garbage-collection stall is
hundreds of ms; 2 s is the margin, Ch 2 dominates at ~2.5 MB):

    Ch 2: 60 frames   Ch 3: 20 grouped blocks   Ch 4: 100 records
    Ch 5: 60          Ch 1: 4                   Ch 6: 4
"""
import os
import threading
import time

from maiden.ch10.writer import Ch10Writer

from .rings import Ring

RING_SIZES = {1: 4, 2: 60, 3: 20, 4: 100, 5: 60, 6: 4}


def default_rings() -> dict[int, Ring]:
    return {ch: Ring(f"ch{ch}", n) for ch, n in RING_SIZES.items()}


class RecorderWriter:
    """Single writer thread: pop min-RTC head, append, fsync every N MB."""

    def __init__(self, path, tmats_text: str, rings: dict[int, Ring],
                 fsync_mb: float = 8.0):
        self.path = path
        self.tmats_text = tmats_text
        self.rings = rings
        self.fsync_bytes = int(fsync_mb * 1e6)
        self.late_clamped = 0
        self.written = 0
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._last_rtc = 0

    def start(self):
        self._thread.start()

    def stop(self):
        """Signal shutdown; the merge loop drains every ring, then closes."""
        self._stop.set()
        self._thread.join()

    def total_drops(self) -> int:
        return sum(r.drops for r in self.rings.values())

    def stats(self) -> dict:
        return {
            "drops": {r.name: r.drops for r in self.rings.values()},
            "high_water": {r.name: r.high_water for r in self.rings.values()},
            "late_clamped": self.late_clamped,
            "written": self.written,
        }

    def _run(self):
        w = Ch10Writer(self.path)
        w.write_tmats(0, self.tmats_text)
        unsynced = 0
        try:
            while True:
                live = [r for r in self.rings.values() if len(r)]
                if not live:
                    if self._stop.is_set():
                        break
                    time.sleep(0.005)
                    continue
                ring = min(live, key=lambda r: r.head_rtc())
                rtc, (channel, dtype, body) = ring.pop()
                if rtc < self._last_rtc:
                    # A late item would violate the ICD's nondecreasing-RTC
                    # rule (Ch10Writer raises). Clamp forward and count:
                    # timing truth lives in the payloads, not the clamp.
                    rtc = self._last_rtc
                    self.late_clamped += 1
                w.write_packet(channel=channel, dtype=dtype, rtc=rtc,
                               body=body)
                self._last_rtc = rtc
                self.written += 1
                unsynced += len(body) + 26
                if unsynced >= self.fsync_bytes:
                    w._f.flush()
                    os.fsync(w._f.fileno())
                    unsynced = 0
        finally:
            w.close()
