"""RTC -> UTC resolution from Ch. 10 time packets. See D4 §Time; SYS-006.

Every Ch. 10 packet header carries a 48-bit RTC in 100 ns ticks. Once per
second the recorder emits a Time F1 packet on Ch 1 whose payload carries
absolute time (BCD day/h/m/s from IRIG-B) and whose header RTC was latched
at that second boundary. Each time packet is one (rtc, utc) correspondence
point; resolving any packet's RTC to UTC is a least-squares line through
those points.

The decoder also *detects* the degraded-sync conditions (gaps in the 1 Hz
stream, non-physical drift) that trigger D4's hand-clap fallback; applying
the fallback is ingest's job (lesson 08).
"""

from dataclasses import dataclass, field

import numpy as np

RTC_HZ = 10_000_000.0  # 100 ns ticks, per RCC 106 Ch. 10
NOMINAL = 1.0 / RTC_HZ


@dataclass
class TimePoint:
    rtc: int  # 48-bit counter value from packet header
    utc: float  # seconds since epoch, decoded from payload


@dataclass
class TimeDecoder:
    points: list = field(default_factory=list)
    max_gap_s: float = 2.5  # >2 missing 1 Hz packets = gap
    max_drift_ppm: float = 50.0

    def add(self, p: TimePoint) -> None:
        self.points.append(p)

    def fit(self) -> None:
        """Least-squares line utc = a*rtc + b over all points."""
        r = np.array([p.rtc for p in self.points], dtype=np.float64)
        u = np.array([p.utc for p in self.points], dtype=np.float64)
        if len(r) < 2:
            raise ValueError("need >= 2 time packets to fit")
        # Fit about (r[0], u[0]): with epoch-scale u (~1e9 s) an un-demeaned
        # polyfit loses the microsecond budget to float64 conditioning.
        self._a, b = np.polyfit(r - r[0], u - u[0], 1)
        self._b = b + u[0]
        self._r0 = r[0]

    def robust_fit(self, nsigma: float = 3.0) -> int:
        """Fit, drop residuals > nsigma*sigma, refit (lesson 04 Explore 3).

        Returns the number of points rejected. One hour-off corrupted time
        packet in a 300-point stream bends a plain least-squares line by
        seconds; this pass removes it.
        """
        self.fit()
        r = np.array([p.rtc for p in self.points], dtype=np.float64)
        u = np.array([p.utc for p in self.points], dtype=np.float64)
        resid = u - (self._a * (r - self._r0) + self._b)
        sigma = float(np.std(resid))
        if sigma == 0.0:
            return 0
        keep = np.abs(resid) <= nsigma * sigma
        rejected = int(np.count_nonzero(~keep))
        if rejected:
            self.points = [p for p, k in zip(self.points, keep) if k]
            self.fit()
        return rejected

    def to_utc(self, rtc: int) -> float:
        return self._a * (rtc - self._r0) + self._b

    @property
    def drift_ppm(self) -> float:
        """How far the RTC runs from nominal 10 MHz, in parts per million."""
        return (self._a / NOMINAL - 1.0) * 1e6

    def gaps(self) -> list[tuple[float, float]]:
        """UTC intervals where 1 Hz time packets went missing."""
        u = sorted(p.utc for p in self.points)
        du = np.diff(u)
        return [(u[i], u[i + 1]) for i in np.flatnonzero(du > self.max_gap_s)]

    def healthy(self) -> bool:
        return abs(self.drift_ppm) <= self.max_drift_ppm and not self.gaps()

    def fallback_reasons(self) -> list[str]:
        """Why this session needs the D4 clap fallback ([] if it doesn't)."""
        reasons = []
        if abs(self.drift_ppm) > self.max_drift_ppm:
            reasons.append(f"drift {self.drift_ppm:+.1f} ppm exceeds "
                           f"{self.max_drift_ppm} ppm")
        for lo, hi in self.gaps():
            reasons.append(f"time-packet gap {lo:.1f}..{hi:.1f} s")
        return reasons


# --- Time F1 payload: BCD day/h/m/s ---------------------------------------
#
# Layout used by MAIDEN's Ch 1 payload after the 4-byte CSDW, RCC 106
# Time F1 "day" format, three little-endian 16-bit words, nibble-aligned
# per the standard (every BCD digit gets a full 4 bits — the previous
# packed layout gave Hmn only 3 bits, so hundreds-of-ms digits 8-9
# overflowed into the seconds field; found by adversarial review):
#
#   word 0:  [15]=0     [14:12]=TSn (tens of s)  [11:8]=Sn (units s)
#            [7:4]=Hmn (hundreds of ms)          [3:0]=Tmn (tens of ms)
#   word 1:  [15:14]=0  [13:12]=THn (tens of hr) [11:8]=Hn (units hr)
#            [7]=0      [6:4]=TMn (tens of min)  [3:0]=Mn (units min)
#   word 2:  [15:12]=0  [11:8]=HDn (hundreds of day)
#            [7:4]=TDn (tens of day)             [3:0]=Dn (units day)
#
# The station writer (maiden.ch10, lesson 02) must emit exactly this; the
# encoder below is the executable statement of the contract.


def _bcd_digit(x: int) -> int:
    if not 0 <= x <= 9:
        raise ValueError(f"not a BCD digit: {x}")
    return x


def encode_time_payload(day: int, h: int, m: int, s: int,
                        ms: int = 0) -> bytes:
    """Pack day-of-year + h/m/s(/ms) into the 3-word BCD payload (+CSDW)."""
    w0 = (_bcd_digit(s // 10) << 12 | _bcd_digit(s % 10) << 8
          | _bcd_digit(ms // 100) << 4 | _bcd_digit((ms // 10) % 10))
    w1 = (_bcd_digit(h // 10) << 12 | _bcd_digit(h % 10) << 8
          | _bcd_digit(m // 10) << 4 | _bcd_digit(m % 10))
    w2 = (_bcd_digit(day // 100) << 8 | _bcd_digit((day // 10) % 10) << 4
          | _bcd_digit(day % 10))
    csdw = (0).to_bytes(4, "little")  # date fmt/day, IRIG-B source
    return csdw + b"".join(w.to_bytes(2, "little") for w in (w0, w1, w2))


def decode_time_payload(payload: bytes) -> tuple[int, float]:
    """Decode (day_of_year, seconds_since_midnight) from a Ch 1 payload.

    BCD is not binary: 0x23 in the seconds field is 23 s, not 35.
    """
    if len(payload) < 10:
        raise ValueError(f"time payload too short: {len(payload)} bytes")
    w0, w1, w2 = (int.from_bytes(payload[4 + 2 * i:6 + 2 * i], "little")
                  for i in range(3))
    s = ((w0 >> 12) & 0x7) * 10 + ((w0 >> 8) & 0xF)
    ms = ((w0 >> 4) & 0xF) * 100 + (w0 & 0xF) * 10
    h = ((w1 >> 12) & 0x3) * 10 + ((w1 >> 8) & 0xF)
    m = ((w1 >> 4) & 0x7) * 10 + (w1 & 0xF)
    day = ((w2 >> 8) & 0xF) * 100 + ((w2 >> 4) & 0xF) * 10 + (w2 & 0xF)
    return day, h * 3600.0 + m * 60.0 + s + ms / 1000.0


def decoder_from_packets(packets, **kw) -> TimeDecoder:
    """Build a fitted TimeDecoder from (rtc, payload_bytes) pairs.

    Seconds-of-day are unwrapped across midnight: a session crossing
    23:59:59 -> 00:00:00 jumps backwards in raw seconds-of-day; add 86 400
    per wrap so UTC out is monotonic. Day-of-year is folded in so multi-day
    ambiguity is caught rather than silently unwrapped.
    """
    dec = TimeDecoder(**kw)
    offset = 0.0
    prev = None
    for rtc, payload in packets:
        day, sod = decode_time_payload(payload)
        utc = day * 86_400.0 + sod + offset
        # Half-day thresholds, both directions: a source whose day field
        # does not increment at midnight wraps backwards by ~a day (add
        # 86 400); when its day field then catches up one packet late,
        # the same stream jumps forwards by ~a day (remove the offset
        # again). A plain "utc < prev" check left the offset sticky and
        # injected a permanent +86 400 — found by adversarial review.
        if prev is not None:
            if utc < prev - 43_200.0:
                offset += 86_400.0
                utc += 86_400.0
            elif utc > prev + 43_200.0 and offset >= 86_400.0:
                offset -= 86_400.0
                utc -= 86_400.0
        prev = utc
        dec.add(TimePoint(rtc=rtc, utc=utc))
    dec.fit()
    return dec


def decoder_from_file(path, **kw) -> TimeDecoder:
    """Walk a .ch10 file's Ch 1 packets into a fitted TimeDecoder.

    Imports maiden.ch10 lazily so timebase stands alone until the reader
    (lesson 02 / maiden03) is on disk.
    """
    from maiden import ch10  # deferred: maiden03's reader

    def pairs():
        for pkt in ch10.read_packets(path):
            if pkt.channel == 1 and pkt.dtype == 0x11:
                yield pkt.rtc, pkt.body

    return decoder_from_packets(pairs(), **kw)
