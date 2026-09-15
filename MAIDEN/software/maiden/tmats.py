r"""TMATS (IRIG-106 Ch. 9 subset) parse + generate per D4 IF-2.

Comment-preservation posture (decided per lesson 03 §Verify): `--`
comments are template-side only. `config/tmats/station.tmt` is the
commented reference artifact; `render_station` emits attributes without
comments, in the template's fixed order, with deterministic float
formatting (repr of the stored value). Diffing a render against the
template is therefore expected to differ in comments and float spelling
only; diffing render-against-render is byte-stable.

Parser posture: the generator is strict, the parser defensive. `parse_*`
raises only on programmer error, never on data — broken pieces land in
``__errors__``, missing MAIDEN attributes become ``None`` plus a warning.
"""
from dataclasses import dataclass, field

_SURVEY = ("LAT", "LON", "ALT_M", "HDG_DEG")
_CAM = ("FX", "FY", "CX", "CY", "K1", "K2")
_RADAR = ("MODULE", "F_GHZ", "BORESIGHT_AZ", "BORESIGHT_EL")


@dataclass
class Station:
    station_id: str                 # R-1\ID
    serial: str | None              # R-1\RID
    lat: float | None               # C\MAIDEN\SURVEY\LAT
    lon: float | None
    alt_m: float | None
    hdg_deg: float | None
    cam: dict | None                # fx, fy, cx, cy, k1, k2
    radar: dict | None              # module, f_ghz, boresight_az, boresight_el
    channels: list = field(default_factory=list)   # (num, name, cdt) rows
    raw: dict = field(default_factory=dict)        # every attribute, verbatim
    warnings: list = field(default_factory=list)


def parse_attributes(text: str) -> dict:
    """CODE:VALUE; attributes -> ordered dict; broken pieces to __errors__."""
    stripped = []
    for line in text.splitlines():
        cut = line.find("--")
        stripped.append(line if cut < 0 else line[:cut])
    attrs: dict = {}
    errors = []
    for piece in " ".join(stripped).split(";"):
        piece = piece.strip()
        if not piece:
            continue
        code, sep, value = piece.partition(":")
        if not sep or not code.strip():
            errors.append(piece)
            continue
        attrs[code.strip()] = value.strip()
    if errors:
        attrs["__errors__"] = errors
    return attrs


def _maiden_float(attrs, code, warnings):
    v = attrs.get(code)
    if v is None:
        warnings.append(f"missing {code}")
        return None
    try:
        return float(v)
    except ValueError:
        warnings.append(f"unparseable {code}: {v!r}")
        return None


def parse_station(text: str) -> Station:
    attrs = parse_attributes(text)
    warnings = list(attrs.get("__errors__", []))

    survey = {k.lower(): _maiden_float(attrs, f"C\\MAIDEN\\SURVEY\\{k}",
                                       warnings) for k in _SURVEY}
    cam = {k.lower(): _maiden_float(attrs, f"C\\MAIDEN\\CAM\\{k}", warnings)
           for k in _CAM}

    radar: dict | None = {}
    module = attrs.get("C\\MAIDEN\\RADAR\\MODULE")
    if module is None:
        warnings.append("missing C\\MAIDEN\\RADAR\\MODULE")
    radar["module"] = module
    for k in _RADAR[1:]:
        radar[k.lower()] = _maiden_float(attrs, f"C\\MAIDEN\\RADAR\\{k}",
                                         warnings)
    if all(v is None for v in radar.values()):
        radar = None
    if cam is not None and all(v is None for v in cam.values()):
        cam = None

    channels = []
    try:
        n = int(attrs.get("R-1\\N", "0"))
    except ValueError:
        n = 0
        warnings.append("unparseable R-1\\N")
    for row in range(1, max(n, 0) + 1):
        tk = attrs.get(f"R-1\\TK1-{row}")
        dsi = attrs.get(f"R-1\\DSI-{row}")
        cdt = attrs.get(f"R-1\\CDT-{row}")
        if tk is None and dsi is None and cdt is None:
            warnings.append(f"missing channel row {row}")
            continue
        try:
            num = int(tk) if tk is not None else None
        except ValueError:
            num = None
            warnings.append(f"unparseable R-1\\TK1-{row}: {tk!r}")
        channels.append((num, dsi, cdt))

    station_id = attrs.get("R-1\\ID", "")
    if not station_id:
        warnings.append("missing R-1\\ID")

    return Station(
        station_id=station_id,
        serial=attrs.get("R-1\\RID"),
        lat=survey["lat"], lon=survey["lon"], alt_m=survey["alt_m"],
        hdg_deg=survey["hdg_deg"],
        cam=cam, radar=radar, channels=channels,
        raw=attrs, warnings=warnings,
    )


def _fmt(v) -> str:
    return repr(v) if isinstance(v, float) else str(v)


def render_station(st: Station) -> str:
    """Deterministic render in the template's order, no comments."""
    lines = [
        "G\\PN:MAIDEN;",
        f"G\\DSI\\N:1;  G\\DSI-1:{st.station_id};",
        "G\\106:23;",
        f"R-1\\ID:{st.station_id};",
    ]
    if st.serial is not None:
        lines.append(f"R-1\\RID:{st.serial};")
    lines.append(f"R-1\\N:{len(st.channels)};")
    for row, (num, dsi, cdt) in enumerate(st.channels, start=1):
        parts = []
        if num is not None:
            parts.append(f"R-1\\TK1-{row}:{num};")
        if dsi is not None:
            parts.append(f"R-1\\DSI-{row}:{dsi};")
        if cdt is not None:
            parts.append(f"R-1\\CDT-{row}:{cdt};")
        # carry the template's per-row extras through verbatim from raw
        for extra in ("TFMT", "TSRC", "VTF"):
            v = st.raw.get(f"R-1\\{extra}-{row}")
            if v is not None:
                parts.append(f"R-1\\{extra}-{row}:{v};")
        lines.append(" ".join(parts))
    for grp, keys, data in (
        ("SURVEY", _SURVEY,
         {"LAT": st.lat, "LON": st.lon, "ALT_M": st.alt_m,
          "HDG_DEG": st.hdg_deg}),
        ("CAM", _CAM,
         {k: (st.cam or {}).get(k.lower()) for k in _CAM}),
        ("RADAR", _RADAR,
         {k: (st.radar or {}).get(k.lower()) for k in _RADAR}),
    ):
        for k in keys:
            v = data.get(k)
            if v is not None:
                lines.append(f"C\\MAIDEN\\{grp}\\{k}:{_fmt(v)};")
    return "\n".join(lines) + "\n"
