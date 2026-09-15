"""maiden.ingest — the adapter boundary. SW-001; interfaces D4 IF-1/2/4.

The one place in MAIDEN where file formats are allowed to exist: `load()`
yields StateSamples and nothing else; above this line nobody can tell
which container a sample came from.

Three-layer stack per lesson 08: a streaming PacketWalker, the lesson-04
TimeDecoder fed incrementally from Ch 1, and per-channel payload decoders
(structs imported from maiden.ch10.payloads — single definition).

Walker note (deviation from the card's "over PyChapter10"): PyChapter10's
typed packet classes assume per-type CSDWs that MAIDEN's IF-1 bodies do
not carry, and the strict maiden.ch10 reader both loads whole files and
refuses truncation. Ingest needs raw bodies, constant memory, and
truncated-tail tolerance (GS-007 battery deaths are a fact of life), so
the walker parses headers itself; PyChapter10 stays the independent
referee in the test suite.

Fail-hard decision (lesson 08 Explore 1, held to by maiden26): a data
packet arriving more than HOLDBACK_S before the first Ch 1 time packet is
an IF-1 violation by the *recorder* and raises IngestError — it is not
the degraded-sync case. D4's clap fallback covers a *lost or drifting*
timebase (TimeDecoder.fallback_reasons()), where time packets exist but
are untrustworthy; a recorder that emits data before any time packet is
broken hardware and must fail loudly at ingest, not softly at validate.

SNR decision (lesson 08 Explore 3, recorded per D5 change control): D4
IF-4 stays frozen — no snr_db field on StateSample for now. Rationale:
the tracker's SNR proxy already reaches fusion through `conf`, the radar
chain's real SNR statistics don't exist until VT-04/VT-05 run on the
bench, and guessing a weighting scheme from twin-modeled SNR would tune
the EKF against fiction. Revisit with bench data; until then the SNR is
preserved in the file (Ch 4 payload) and simply not forwarded.
"""

import struct
from collections import deque
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

from maiden import timebase as tb
from maiden import tmats as tmats_mod
from maiden.ch10 import payloads as pl
from maiden.state import Event, StateSample, validate

_HDR = struct.Struct("<HHIIBBBB6sH")
_SYNC = 0xEB25
_CHUNK = 24

# Hold-back bound: seconds of nominal RTC a data packet may precede the
# first time packet (lesson 08: "a small deque, cap ~2 s of packets").
HOLDBACK_S = 2.0
DEFAULT_CHANNELS = frozenset({1, 3, 4, 5, 6})


class IngestError(Exception):
    """A file-level IF-1 violation or unwalkable structure."""


class TmatsError(IngestError):
    """The first packet's TMATS payload could not yield a descriptor."""


@dataclass
class Station:
    id: str                              # "A" | "B" | "C"
    serial: str | None
    survey_lla: tuple | None             # (lat, lon, alt_m)
    heading_deg: float | None
    cam: dict | None
    radar: dict | None
    channel_names: dict                  # channel number -> TMATS DSI name


@dataclass
class Aircraft:
    tail: str
    logger_serial: str | None
    mass_g: float | None
    channel_names: dict


def walk_packets(path):
    """Stream (channel, dtype, rtc, body) with constant memory.

    Tolerant of a truncated tail: an incomplete final header or body ends
    the stream cleanly. Structural garbage (bad sync, bad header
    checksum) raises IngestError with the file offset — that is
    corruption, not truncation.
    """
    from maiden.ch10 import packet as pk

    with open(path, "rb") as f:
        off = 0
        while True:
            hdr = f.read(_CHUNK)
            if len(hdr) < _CHUNK:
                return                      # truncated tail: clean end
            (sync, channel, packet_len, data_len, _ver, _seq, flags,
             dtype, rtc6, hcs) = _HDR.unpack(hdr)
            if sync != _SYNC:
                raise IngestError(f"bad sync 0x{sync:04x} at offset {off}")
            if pk.header_checksum(hdr[:22]) != hcs:
                raise IngestError(f"header checksum mismatch at offset {off}")
            trailer = 2 if flags & 0x03 == 0x02 else 0
            if (packet_len < _CHUNK + trailer
                    or data_len > packet_len - _CHUNK - trailer):
                raise IngestError(f"nonsense lengths at offset {off}")
            rest = f.read(packet_len - _CHUNK)
            if len(rest) < packet_len - _CHUNK:
                return                      # truncated body: clean end
            yield channel, dtype, int.from_bytes(rtc6, "little"), \
                rest[:data_len]
            off += packet_len


def _descriptor_from_tmats(body: bytes):
    """TMATS payload bytes -> Station | Aircraft. Raises TmatsError only."""
    try:
        text = body.decode("ascii", errors="replace")
        st = tmats_mod.parse_station(text)
        dsi = st.raw.get("G\\DSI-1", st.station_id or "")
        if not dsi and not st.channels:
            raise ValueError("no G\\DSI-1 and no channel rows")
        names = {num: name for num, name, _cdt in st.channels
                 if num is not None and name}
        if dsi.startswith("STATION_") and len(dsi) > 8:
            lla = None
            if st.lat is not None and st.lon is not None:
                lla = (st.lat, st.lon, st.alt_m)
            return Station(id=dsi[8:], serial=st.serial, survey_lla=lla,
                           heading_deg=st.hdg_deg, cam=st.cam,
                           radar=st.radar, channel_names=names)
        mass = st.raw.get("C\\MAIDEN\\LOGGER\\MASS_G")
        return Aircraft(tail=dsi or "UNKNOWN", logger_serial=st.serial,
                        mass_g=float(mass) if mass is not None else None,
                        channel_names=names)
    except TmatsError:
        raise
    except Exception as e:                  # contract: TmatsError or success
        raise TmatsError(f"unusable TMATS payload: {e}") from e


def describe(path) -> Station | Aircraft:
    """Parse only the first packet (TMATS, per IF-1) into a descriptor."""
    for channel, dtype, _rtc, body in walk_packets(path):
        if channel != 0 or dtype != 0x01:
            raise TmatsError(
                f"first packet is ch {channel}/0x{dtype:02x}, not TMATS")
        return _descriptor_from_tmats(body)
    raise TmatsError(f"no packets in {path}")


def _station_sample(desc, name, t, body):
    if name == "TRACKER":
        m = pl.unpack_tracker(body)
        return StateSample(t_utc=t, source=desc.id, az_deg=m.az_deg,
                           el_deg=m.el_deg, conf=m.conf)
    if name == "RADAR_V":
        m = pl.unpack_radar_v(body)
        # snr_db intentionally not forwarded — see module docstring.
        return StateSample(t_utc=t, source=desc.id, v_r=m.v_r)
    return None


def load(path, *, channels=None) -> Iterator[StateSample]:
    """Stream StateSamples in file order; constant memory.

    channels=None decodes the defaults ({1,4,5,6} for stations, plus the
    TRUTH channels for aircraft files — dispatch is by TMATS DSI *name*,
    never channel number alone, per maiden.ch10.payloads).
    """
    want = DEFAULT_CHANNELS if channels is None else set(channels) | {1}
    walker = walk_packets(path)
    desc = None
    dec = tb.TimeDecoder()
    fitted_points = 0
    hold: deque = deque()
    last_att = None

    def emit(channel, rtc, body):
        nonlocal last_att
        t = dec.to_utc(rtc)
        name = desc.channel_names.get(channel, "")
        if isinstance(desc, Station):
            s = _station_sample(desc, name, t, body)
        elif name == "GNSS":
            pos, vel = pl.unpack_truth_gnss(body)
            s = StateSample(t_utc=t, source="TRUTH", pos_enu=pos,
                            vel_enu=vel, att_rpy=last_att)
        elif name == "ATT":
            last_att = pl.unpack_truth_att(body)   # attached to next GNSS
            s = None
        else:
            s = None
        if s is not None:
            validate(s)
        return s

    for channel, dtype, rtc, body in walker:
        if desc is None:
            if channel != 0 or dtype != 0x01:
                raise IngestError("first packet is not TMATS (IF-1)")
            desc = _descriptor_from_tmats(body)
            continue
        if channel == 1 and dtype == 0x11:
            day, sod = tb.decode_time_payload(body)
            dec.add(tb.TimePoint(rtc=rtc, utc=day * 86_400.0 + sod))
            continue
        if channel not in want or channel == 6:
            continue
        if len(dec.points) < 2:
            hold.append((channel, rtc, body))
            span = hold[-1][1] - hold[0][1]
            if span > HOLDBACK_S * tb.RTC_HZ:
                raise IngestError(
                    "data precedes the first time packets by more than "
                    f"{HOLDBACK_S} s of RTC — recorder violates IF-1 "
                    "(TMATS first, time early); failing hard, see module "
                    "docstring")
            continue
        if len(dec.points) != fitted_points:
            dec.fit()
            fitted_points = len(dec.points)
            while hold:
                s = emit(*hold.popleft())
                if s is not None:
                    yield s
        s = emit(channel, rtc, body)
        if s is not None:
            yield s

    if desc is None:
        raise IngestError(f"no packets in {path}")
    if hold:
        raise IngestError(
            "file ended with data packets still held back — fewer than two "
            "Ch 1 time packets present (IF-1 violation)")


def events(path) -> Iterator[Event]:
    """Ch 6 STATUS packets (and later recorder-marked events) as Events."""
    walker = walk_packets(path)
    desc = None
    dec = tb.TimeDecoder()
    fitted = 0
    hold: deque = deque()

    def to_event(rtc, body):
        st = pl.unpack_status(body)
        return Event(t_utc=dec.to_utc(rtc), kind="STATUS",
                     data={"source": getattr(desc, "id", "TRUTH"),
                           "battery_v": st.battery_v, "temp_c": st.temp_c,
                           "pps_lock": st.pps_lock,
                           "disk_free_pct": st.disk_free_pct})

    for channel, dtype, rtc, body in walker:
        if desc is None:
            if channel != 0 or dtype != 0x01:
                raise IngestError("first packet is not TMATS (IF-1)")
            desc = _descriptor_from_tmats(body)
            continue
        if channel == 1 and dtype == 0x11:
            day, sod = tb.decode_time_payload(body)
            dec.add(tb.TimePoint(rtc=rtc, utc=day * 86_400.0 + sod))
            continue
        if channel != 6:
            continue
        hold.append((rtc, body))
        if len(dec.points) >= 2:
            if len(dec.points) != fitted:
                dec.fit()
                fitted = len(dec.points)
            while hold:
                yield to_event(*hold.popleft())


def summarize(path) -> str:
    """Human-readable session summary for `maiden ingest --summary`."""
    desc = describe(path)
    counts: dict = {}
    t_lo = t_hi = None
    for s in load(path):
        key = "tracker" if s.az_deg is not None else \
            "radar" if s.v_r is not None else "truth"
        counts[key] = counts.get(key, 0) + 1
        t_lo = s.t_utc if t_lo is None else min(t_lo, s.t_utc)
        t_hi = s.t_utc if t_hi is None else max(t_hi, s.t_utc)
    n_status = sum(1 for _ in events(path))
    lines = [f"{Path(path).name}: {desc}"]
    span = 0.0 if t_lo is None else t_hi - t_lo
    lines.append(f"  samples: {counts}  status events: {n_status}")
    lines.append(f"  time span: {span:.1f} s "
                 f"(utc {t_lo:.3f} .. {t_hi:.3f})" if t_lo is not None
                 else "  time span: empty")
    return "\n".join(lines)


def main(argv=None) -> int:
    import argparse

    ap = argparse.ArgumentParser(prog="maiden ingest")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--summary", action="store_true")
    args = ap.parse_args(argv)
    for p in args.paths:
        if args.summary:
            print(summarize(p))
        else:
            n = sum(1 for _ in load(p))
            print(f"{p}: {n} samples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
