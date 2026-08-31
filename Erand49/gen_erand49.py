# Generates Erand49.html — string band drawn from the Erard DXF geometry.
# Band drawing units are mm: string positions/lengths come from the DXF
# (matched to the spec table by length), and each stroke width IS the
# string's actual overall diameter (ODIA). C red, F blue, others gray.
import os, math
import ezdxf

HERE = os.path.dirname(os.path.abspath(__file__))
IN = 25.4

# STR#, NOTE, FREQ Hz, LENGTH in, CMAT, WMAT, ODIA in, TENSION lbf  (Erard tutorial)
ROWS = [
 (1,"g7",3136.000,2.386,"Nylon","",0.025,10.976),(2,"f7",2793.800,2.783,"Nylon","",0.025,11.851),
 (3,"e7",2637.000,3.181,"Nylon","",0.025,13.794),(4,"d7",2349.300,3.579,"Nylon","",0.025,13.859),
 (5,"c7",2093.000,3.976,"Nylon","",0.025,13.576),(6,"b6",1975.500,4.374,"Nylon","",0.025,14.637),
 (7,"a6",1760.000,4.771,"Nylon","",0.025,13.822),(8,"g6",1568.000,5.169,"Nylon","",0.028,16.154),
 (9,"f6",1396.900,5.765,"Nylon","",0.028,15.948),(10,"e6",1318.500,6.362,"Nylon","",0.028,17.303),
 (11,"d6",1174.700,6.958,"Nylon","",0.030,18.859),(12,"c6",1046.500,7.555,"Nylon","",0.032,20.077),
 (13,"b5",987.770,8.151,"Nylon","",0.032,20.821),(14,"a5",880.000,8.748,"Nylon","",0.032,19.034),
 (15,"g5",783.990,9.344,"Nylon","",0.036,21.815),(16,"f5",698.460,10.338,"Nylon","",0.036,21.194),
 (17,"e5",659.260,10.934,"Nylon","",0.036,21.122),(18,"d5",587.330,11.929,"Nylon","",0.036,19.954),
 (19,"c5",523.250,12.923,"Nylon","",0.040,22.947),(20,"b4",493.880,13.917,"Nylon","",0.040,23.709),
 (21,"a4",440.000,15.109,"Nylon","",0.040,22.180),(22,"g4",392.000,16.302,"Nylon","",0.045,25.938),
 (23,"f4",349.230,17.694,"Nylon","",0.045,24.253),(24,"e4",329.630,19.086,"Nylon","",0.045,25.140),
 (25,"d4",293.660,20.676,"Nylon","",0.050,28.908),(26,"c4",261.630,22.465,"Nylon","",0.050,27.089),
 (27,"b3",246.940,24.454,"Nylon","",0.050,28.594),(28,"a3",220.000,26.243,"Nylon","Nylon",0.061,35.098),
 (29,"g3",196.000,28.827,"Nylon","Nylon",0.061,33.614),(30,"f3",174.610,31.213,"Nylon","Nylon",0.066,36.873),
 (31,"e3",164.810,33.996,"Nylon","Nylon",0.066,38.969),(32,"d3",146.830,36.382,"Nylon","Nylon",0.076,45.407),
 (33,"c3",130.810,38.967,"Nylon","Nylon",0.081,47.285),(34,"b2",123.470,41.551,"Nylon","Nylon",0.081,47.900),
 (35,"a2",110.000,43.738,"Nylon","Nylon",0.086,47.783),(36,"g2",97.990,46.720,"Nylon","Nylon",0.092,48.780),
 (37,"f2",87.310,48.112,"Nylon","Nylon",0.100,47.745),(38,"e2",82.410,48.907,"Nylon","Nylon",0.104,47.219),
 (39,"d2",73.420,50.497,"Steel","Bronze",0.046,48.835),(40,"c2",65.410,51.889,"Steel","Bronze",0.050,49.930),
 (41,"b1",61.740,53.082,"Steel","Bronze",0.054,50.873),(42,"a1",55.000,54.275,"Steel","Bronze",0.057,53.218),
 (43,"g1",49.000,55.468,"Steel","Bronze",0.064,50.823),(44,"f1",43.650,56.661,"Steel","Bronze",0.071,48.861),
 (45,"e1",41.200,57.655,"Steel","Bronze",0.076,49.053),(46,"d1",36.710,58.649,"Steel","Bronze",0.083,50.985),
 (47,"c1",32.700,59.643,"Steel","Bronze",0.091,52.693),
]
# b0/a0: not in the tutorial — extrapolated 2026-08-31 from c1 (f=(1/2L)sqrt(T/mu),
# same wound construction, effective density 5691 kg/m3; lengths continue the 0.994 in/step trend)
# (STR#, NOTE, FREQ, LENGTH in, ODIA in, TENSION lbf)
GHOSTS = [(48,"b0",30.868,60.637,0.0955,53.4),(49,"a0",27.500,61.631,0.1060,54.0)]

def color(note):
    if note.startswith("c"): return "#c0392b"
    if note.startswith("f"): return "#2e5fa3"
    return "#3b3e44"

# ---- read the DXF ----
doc = ezdxf.readfile(os.path.join(HERE, 'erard original stringband tutorial.dxf'))
msp = doc.modelspace()
dxf_lines = []
for e in msp.query('LINE'):
    a, b = e.dxf.start, e.dxf.end
    dxf_lines.append(((a.x, a.y), (b.x, b.y), math.hypot(b.x-a.x, b.y-a.y)))

# match each spec row to the DXF line of the same length (all verticals, 47/47 match)
used = set()
strings = []   # (row, (x, y_bottom, y_top)) in DXF inches, y-up
for row in ROWS:
    L = row[3]
    best, bd = None, 1e9
    for i, (a, b, ll) in enumerate(dxf_lines):
        if i in used: continue
        d = abs(ll - L)
        if d < bd: bd, best = d, i
    assert bd < 0.08, (row, bd)
    used.add(best)
    a, b, _ = dxf_lines[best]
    ylo, yhi = min(a[1], b[1]), max(a[1], b[1])
    strings.append((row, (a[0], ylo, yhi)))

frame = [dxf_lines[i] for i in range(len(dxf_lines)) if i not in used]

# ---- band SVG in mm, y flipped ----
allx = [g[0] for _, g in strings]; ally = [g[1] for _, g in strings] + [g[2] for _, g in strings]
for a, b, _ in frame:
    allx += [a[0], b[0]]; ally += [a[1], b[1]]

# ghost geometry: continue anchor line and spacing ratio past string 47
(x46, lo46, _), (x47, lo47, _) = strings[-2][1], strings[-1][1]
dx = (x47 - x46) * 1.025
slope = (lo47 - lo46) / (x47 - x46)
gpts = []
gx, glo = x47, lo47
for (n, note, fg, Lg, odg, tg) in GHOSTS:
    dx *= 1.025
    gx, glo = gx + dx, glo + slope * dx
    gpts.append((n, note, fg, Lg, odg, tg, gx, glo))
    allx.append(gx); ally += [glo, glo + Lg]

# frame side profile (pillar + midrib band) — inches, y-up.
# y_crown pins to the existing max so Y() mapping (and the hand-edited neck
# curves, which are absolute coords) do NOT shift.
mid = max(frame, key=lambda r: r[2])             # the long anchor line
m = (mid[1][1]-mid[0][1])/(mid[1][0]-mid[0][0])
cxi = mid[0][1] - m*mid[0][0]
MHW = 2.0                                        # 4" channel half-height
PW  = 1.0                                        # 2" pillar half-width
pilc = min(p[6] for p in gpts) - 2.0             # pillar center, 2 in past a0 (crown/bass end)
y_crown = max(ally)
y_base  = m*pilc + cxi - 2*MHW - 0.8
xr_m = max(g[0] for _, g in strings) + 2.2       # midrib reaches the shoulder (treble end)
allx += [pilc-PW, pilc+PW, xr_m]; ally.append(y_base)

x0, x1 = (min(allx)-1.2)*IN, (max(allx)+1.2)*IN
y0, y1 = (min(ally)-3.0)*IN, (max(ally)+0.8)*IN
def X(v): return v*IN
def Y(v): return y1 - v*IN   # y-up inches -> y-down mm, 0-based for the viewBox

# classify the non-string lines: 0.25" ticks, 3 per string per the DXF: optical point
# at 0.944L, flat pin at L, tuner at L+1.5; ~1.53" at 78 deg = tuner leads; rest = frame.
SENSE_RATIO = 1 - 1/1.0594631   # optical point per the DXF: 0.0561*L below the flat pin (a semitone's fret distance)
tops = [(g[0], g[2], color(r[1]), r[6]*IN) for r, g in strings]
geom = {g[0]: (g[1], g[2]) for _, g in strings}   # x -> (ylo, yhi)
marks, keys, outline, sense = [], [], [], []
for a, b, L in frame:
    if L < 0.5:
        mx, my = (a[0]+b[0])/2, (a[1]+b[1])/2
        sx = min(geom, key=lambda x: abs(x-mx))
        ylo, yhi = geom[sx]
        if my < yhi - 0.05:            # the DXF's bottom tick IS the optical point — use its own position
            sense.append((sx, my))
        else:
            marks.append((a, b))
    elif L < 2.0:
        lo = a if a[1] < b[1] else b
        best = min(tops, key=lambda t: (t[0]-lo[0])**2 + (t[1]-lo[1])**2)
        keys.append((a, b, best[2], best[3]))
    else: outline.append((a, b))
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    sense.append((gx, glo + Lg - Lg*SENSE_RATIO))

# figure 1 mirrors the hand-edited sensor-axes group in Erand49.svg when present
# (same master-file rule as the neck rails); falls back to the computed DXF points
sense_px = [(X(sx), Y(sy)) for sx, sy in sense]
try:
    import re as _re
    _svg = open(os.path.join(HERE, 'Erand49.svg')).read()
    _grp = _re.search(r'<g[^>]*id="sensor-axes"[^>]*>(.*?)</g>', _svg, _re.S)
    if _grp:
        _pts = []
        for _ln in _re.findall(r'<line[^>]*>', _grp.group(1)):
            _c = _re.search(r'x1="([\d.]+)"[^>]*y1="([\d.]+)"[^>]*x2="([\d.]+)"[^>]*y2="([\d.]+)"', _ln)
            if _c:
                _x1, _y1, _x2, _y2 = map(float, _c.groups())
                if abs(_y1 - _y2) < 0.01:          # the horizontal stroke of each crosshair
                    _pts.append(((_x1 + _x2) / 2, _y1))
        if len(_pts) >= 40:
            sense_px = _pts
except OSError:
    pass
# ---- frame in side view: midrib C-channel band + pillar + ISO 129 dims ----
band = []
band.append('<defs><marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#3b5a7a"/></marker></defs>')
_h = math.hypot(1, m)
px_, py_ = -m/_h, 1/_h                            # unit perpendicular to midrib axis
def mp(t, off):
    return X(t + px_*off), Y(m*t + cxi + py_*off)
# midrib continues to the FLOOR with a horizontal end cut (it is the rear foot);
# pillar drops through a top-face slot and bears on the bottom face inside (ER-004)
y_floor = y_base
def t_at_y(yq, off):
    return (yq - cxi - py_*off) / m
y_sh = m*(xr_m - 1.5) + cxi                 # start of the shoulder lap along the channel top
for off in (0, -2*MHW):
    (xa, ya), (xb, yb) = mp(t_at_y(y_floor, off), off), mp(xr_m, off)
    band.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#8d877a" stroke-width="2"/>')
(sx1, sy1), (sx2, sy2) = mp(xr_m - 1.5, -8/25.4), mp(xr_m, -8/25.4)
band.append(f'<line x1="{sx1:.1f}" y1="{sy1:.1f}" x2="{sx2:.1f}" y2="{sy2:.1f}" stroke="#8d877a" stroke-width="1.4" stroke-dasharray="6 4"><title>shoulder rebate — 8 mm into each side wall along the channel top; plates lap here, web stands proud between them (ER-005)</title></line>')
# horizontal shoulder weld: plate bottom tab to midrib side wall, both plates.
# mirrored from Erand49.svg (id="shoulder-weld") when present, else 12 mm below the lap start
y_w = y_sh - 12/IN
(wx1, wy1) = mp(t_at_y(y_w, 0), 0)
(wx2, wy2) = mp(t_at_y(y_w, -2*MHW), -2*MHW)
try:
    import re as _re2
    _svg2 = open(os.path.join(HERE, 'Erand49.svg')).read()
    _wl = _re2.search(r'<line[^>]*id="shoulder-weld"[^>]*>', _svg2, _re2.S)
    if _wl:
        _g = dict(_re2.findall(r'(x1|y1|x2|y2)="([-\d.]+)"', _wl.group(0)))
        wx1, wy1, wx2, wy2 = float(_g['x1']), float(_g['y1']), float(_g['x2']), float(_g['y2'])
except OSError:
    pass
band.append(f'<line x1="{wx1:.1f}" y1="{wy1:.1f}" x2="{wx2:.1f}" y2="{wy2:.1f}" stroke="#c9553a" stroke-width="2.5"><title>shoulder weld — horizontal fillet, plate bottom edge to midrib side wall, both plates (ER-005); position mirrors id=shoulder-weld in Erand49.svg</title></line>')
band.append(f'<text x="{wx2+10:.0f}" y="{wy2+14:.0f}" class="nl" fill="#c9553a">shoulder weld</text>')

(cx2, cy2) = mp(xr_m - 0.6, -2*MHW)
band.append(f'<text x="{cx2+10:.0f}" y="{cy2+2:.0f}" class="nl" fill="#8d877a">shoulder rebate: ER-005</text>')
(fx1, fy1), (fx2, fy2) = mp(t_at_y(y_floor, 0), 0), mp(t_at_y(y_floor, -2*MHW), -2*MHW)
band.append(f'<line x1="{fx1:.1f}" y1="{fy1:.1f}" x2="{fx2:.1f}" y2="{fy2:.1f}" stroke="#8d877a" stroke-width="2"><title>horizontal end cut — the midrib stands on the floor as the rear foot</title></line>')
(xa, ya), (xb, yb) = mp(t_at_y(y_floor, -MHW), -MHW), mp(xr_m, -MHW)
band.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#c9553a" stroke-width="0.8" stroke-dasharray="12 3 3 3"><title>midrib tube centerline (top face carries the string anchors)</title></line>')
lx, ly = mp(pilc+4.5, -2*MHW)
band.append(f'<text x="{lx:.0f}" y="{ly+30:.0f}" class="nl" fill="#8d877a">midrib — C 2.5"×4"×3/16" open-bottom, 6061-T6 (ER-003)</text>')
# round pillar: continuous crown -> floor, hidden (dashed) where it passes inside the midrib
for xe in (pilc-PW, pilc+PW):
    y_hi = m*(xe) + cxi                     # top-face line at this pillar edge
    y_lo = y_hi - 2*MHW                     # side-wall lower edge
    band.append(f'<line x1="{X(xe):.1f}" y1="{Y(y_crown):.1f}" x2="{X(xe):.1f}" y2="{Y(y_hi):.1f}" stroke="#8d877a" stroke-width="2"/>')
    band.append(f'<line x1="{X(xe):.1f}" y1="{Y(y_hi):.1f}" x2="{X(xe):.1f}" y2="{Y(y_lo):.1f}" stroke="#8d877a" stroke-width="2" stroke-dasharray="7 5"/>')
    band.append(f'<line x1="{X(xe):.1f}" y1="{Y(y_lo):.1f}" x2="{X(xe):.1f}" y2="{Y(y_floor):.1f}" stroke="#8d877a" stroke-width="2"/>')
band.append(f'<line x1="{X(pilc-PW):.1f}" y1="{Y(y_crown):.1f}" x2="{X(pilc+PW):.1f}" y2="{Y(y_crown):.1f}" stroke="#8d877a" stroke-width="2"><title>pillar — Ø2" × 3/16" round tube, crown to floor, through the midrib (ER-004)</title></line>')
band.append(f'<text x="{X(pilc)+40:.0f}" y="{(Y(y_crown)+Y(y_floor))/2:.0f}" class="nl" fill="#8d877a">pillar Ø2"×3/16"</text>')
band.append(f'<text x="{X(pilc)+40:.0f}" y="{Y(y_base)-8:.0f}" class="nl" fill="#8d877a">pillar into midrib + floor foot: ER-004</text>')
sbx, sby = mp(xr_m-0.6, MHW)
# ISO 129 dims: overall height, pillar width
dx0 = X(pilc-PW) - 34
band.append(f'<g stroke="#3b5a7a" stroke-width="1" fill="none"><line x1="{dx0:.0f}" y1="{Y(y_crown):.1f}" x2="{dx0:.0f}" y2="{Y(y_base):.1f}" marker-start="url(#arr)" marker-end="url(#arr)"/><line x1="{dx0-8:.0f}" y1="{Y(y_crown):.1f}" x2="{X(pilc-PW):.1f}" y2="{Y(y_crown):.1f}"/><line x1="{dx0-8:.0f}" y1="{Y(y_base):.1f}" x2="{X(pilc-PW):.1f}" y2="{Y(y_base):.1f}"/></g>')
midy = (Y(y_crown)+Y(y_base))/2
band.append(f'<text x="{dx0-12:.0f}" y="{midy:.0f}" class="nl" fill="#3b5a7a" text-anchor="middle" transform="rotate(-90 {dx0-12:.0f} {midy:.0f})">{(y_crown-y_base)*IN:.0f} mm</text>')
band.append(f'<g stroke="#3b5a7a" stroke-width="1" fill="none"><line x1="{X(pilc-PW):.1f}" y1="{Y(y_base)+26:.1f}" x2="{X(pilc+PW):.1f}" y2="{Y(y_base)+26:.1f}" marker-start="url(#arr)" marker-end="url(#arr)"/></g>')
band.append(f'<text x="{X(pilc):.0f}" y="{Y(y_base)+44:.0f}" class="nl" fill="#3b5a7a" text-anchor="middle">50.8</text>')
band.append('<g stroke="#555" stroke-width="1.0" fill="none">')
band += [f'<line x1="{X(a[0]):.1f}" y1="{Y(a[1]):.1f}" x2="{X(b[0]):.1f}" y2="{Y(b[1]):.1f}"/>' for a, b in marks]
band.append('</g>')
for a, b, c, w in keys:
    band.append(f'<line x1="{X(a[0]):.1f}" y1="{Y(a[1]):.1f}" x2="{X(b[0]):.1f}" y2="{Y(b[1]):.1f}" stroke="{c}" stroke-width="{w:.3f}"/>')
for cxp, cyp in sense_px:
    band.append(f'<g stroke="#a8700f" stroke-width="1.4"><line x1="{cxp-3.2:.1f}" y1="{cyp:.1f}" x2="{cxp+3.2:.1f}" y2="{cyp:.1f}"/><line x1="{cxp:.1f}" y1="{cyp-3.2:.1f}" x2="{cxp:.1f}" y2="{cyp+3.2:.1f}"/><title>optical X/Y sensor axis — mirrors the sensor-axes group in Erand49.svg (0.056·L below the flat pin; Gate 1 placeholder, final fraction set on the bench)</title></g>')
for (n, note, f, Lin, cm, wm, od, t), (x, ylo, yhi) in strings:
    c, odmm = color(note), od*IN
    tip = f"#{n} {note} · {f:g} Hz · {Lin:.3f} in / {Lin*IN:.1f} mm · Ø {od:.3f} in / {odmm:.2f} mm · {t:.1f} lbf"
    band.append(f'<line x1="{X(x):.1f}" y1="{Y(ylo):.1f}" x2="{X(x):.1f}" y2="{Y(yhi):.1f}" stroke="{c}" stroke-width="{odmm:.3f}"><title>{tip}</title></line>')
    if note.startswith(("c", "f")) or n in (1, 47):
        band.append(f'<text x="{X(x):.1f}" y="{Y(ylo)+24:.1f}" class="nl" fill="{c}" text-anchor="middle">{note}</text>')
KEY_DX, KEY_DY = 1.5*math.sin(math.radians(12)), 1.5*math.cos(math.radians(12))  # 12 deg off vertical
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    tip = f"#{n} {note} · {fg:g} Hz · {Lg:.3f} in / {Lg*IN:.1f} mm · Ø {odg:.4f} in / {odg*IN:.2f} mm · {tg:.1f} lbf — EXTRAPOLATED from c1 (see string-specs.md)"
    top = glo + Lg
    band.append(f'<line x1="{X(gx):.1f}" y1="{Y(glo):.1f}" x2="{X(gx):.1f}" y2="{Y(top):.1f}" stroke="{color(note)}" stroke-width="{odg*IN:.3f}"><title>{tip}</title></line>')
    band.append(f'<line x1="{X(gx):.1f}" y1="{Y(top):.1f}" x2="{X(gx+KEY_DX):.1f}" y2="{Y(top+KEY_DY):.1f}" stroke="{color(note)}" stroke-width="{odg*IN:.3f}"/>')
    band.append(f'<g stroke="#555" stroke-width="1.0"><line x1="{X(gx)-3.2:.1f}" y1="{Y(top):.1f}" x2="{X(gx)+3.2:.1f}" y2="{Y(top):.1f}"/><line x1="{X(gx+KEY_DX)-3.2:.1f}" y1="{Y(top+KEY_DY):.1f}" x2="{X(gx+KEY_DX)+3.2:.1f}" y2="{Y(top+KEY_DY):.1f}"/></g>')
    band.append(f'<text x="{X(gx):.1f}" y="{Y(glo)+24:.1f}" class="nl" fill="#8d877a" text-anchor="middle">{note}*</text>')

# Bezier rails: Catmull-Rom smooth curves through the 49 tuner pins (the neck's
# tuner rail) and the 49 optical sensor axes (the sensor rail), in svg mm coords
def crpath(pts):
    pts = sorted(pts)
    d = f'M {pts[0][0]:.1f} {pts[0][1]:.1f}'
    n = len(pts)
    for i in range(n-1):
        p0, p1, p2, p3 = pts[max(i-1,0)], pts[i], pts[i+1], pts[min(i+2,n-1)]
        c1 = (p1[0]+(p2[0]-p0[0])/6, p1[1]+(p2[1]-p0[1])/6)
        c2 = (p2[0]-(p3[0]-p1[0])/6, p2[1]-(p3[1]-p1[1])/6)
        d += f' C {c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}'
    return d

tuner_pts = []
for a, b, c, w in keys:
    tp = a if a[1] > b[1] else b
    tuner_pts.append((X(tp[0]), Y(tp[1])))
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    tuner_pts.append((X(gx+KEY_DX), Y(glo+Lg+KEY_DY)))
sense_pts = [(X(sx), Y(sy)) for sx, sy in sense]
# use the HAND-EDITED neck curves from Erand49.svg (same coordinate space);
# fall back to the auto-fit only if the edited paths are not found
import re
def edited_rail(colorhex):
    try:
        src = open(os.path.join(HERE, 'Erand49.svg')).read()
        for p in re.findall(r'<path[^>]*>', src):
            if colorhex in p:
                return re.search(r'\bd="([^"]+)"', p).group(1)
    except OSError:
        pass
    return None
t_d = edited_rail('7a5a2a') or crpath(tuner_pts)
s_d = edited_rail('a8700f') or crpath(sense_pts)
t_src = 'hand-edited (Erand49.svg)' if edited_rail('7a5a2a') else 'auto-fit'
band.append(f'<path d="{t_d}" fill="none" stroke="#7a5a2a" stroke-width="2.5" opacity="0.6"><title>tuner rail — {t_src} — the neck top curve</title></path>')
band.append(f'<path d="{s_d}" fill="none" stroke="#a8700f" stroke-width="2.0" opacity="0.6"><title>sensor rail — {t_src} — the neck bottom curve, optical axes</title></path>')

# widen the viewBox to cover the hand-edited curves (they may extend past the DXF extents)
def _path_xmax(dstr):
    toks = re.findall(r"[mMcClLzZ]|-?\d+\.?\d*(?:e-?\d+)?", dstr)
    i = 0; cur = (0.0, 0.0); mx = -1e9; cmd = None
    def f():
        nonlocal i; v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if toks[i] in 'mMcClLzZ': cmd = toks[i]; i += 1
        if cmd in 'mM':
            x, y = f(), f(); cur = (x, y) if cmd == 'M' else (cur[0]+x, cur[1]+y)
            mx = max(mx, cur[0]); cmd = 'l' if cmd == 'm' else 'L'
        elif cmd in 'cC':
            while i < len(toks) and toks[i] not in 'mMcClLzZ':
                v = [f() for _ in range(6)]
                pts = [(v[0],v[1]),(v[2],v[3]),(v[4],v[5])]
                if cmd == 'c': pts = [(cur[0]+a, cur[1]+b) for a, b in pts]
                mx = max(mx, *[p[0] for p in pts]); cur = pts[2]
        elif cmd in 'lL':
            while i < len(toks) and toks[i] not in 'mMcClLzZ':
                x, y = f(), f(); cur = (x, y) if cmd == 'L' else (cur[0]+x, cur[1]+y)
                mx = max(mx, cur[0])
        else: i += 1
    return mx
x1v = max(x1, _path_xmax(t_d) + 15, _path_xmax(s_d) + 15)
x0v = min(x0, X(pilc-PW) - 75)   # cover the overall-height dimension left of the pillar

# ---- cross sections at 5x, aligned to real string x positions ----
xsec = []
for (n, note, f, Lin, cm, wm, od, t), (x, ylo, yhi) in strings:
    tip = f"#{n} {note} · Ø {od:.3f} in / {od*IN:.2f} mm"
    xsec.append(f'<circle cx="{X(x):.1f}" cy="40" r="{od*IN*5/2:.2f}" fill="{color(note)}"><title>{tip}</title></circle>')
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    tip = f"#{n} {note}* · Ø {odg:.4f} in / {odg*IN:.2f} mm — extrapolated"
    xsec.append(f'<circle cx="{X(gx):.1f}" cy="40" r="{odg*IN*5/2:.2f}" fill="{color(note)}"><title>{tip}</title></circle>')

# ---- full DXF render (lines + text) ----
fx, fy = [], []
for a, b, _ in dxf_lines:
    fx += [a[0], b[0]]; fy += [a[1], b[1]]
fx0, fx1, fy0, fy1 = min(fx)-1, max(fx)+1, min(fy)-1, max(fy)+1
def FF(v): return (fy1+fy0) - v
el = [f'<line x1="{a[0]:.3f}" y1="{FF(a[1]):.3f}" x2="{b[0]:.3f}" y2="{FF(b[1]):.3f}"/>' for a, b, _ in dxf_lines]
tx = [f'<text x="{e.dxf.insert.x:.2f}" y="{FF(e.dxf.insert.y):.2f}" font-size="{e.dxf.height:.2f}">{e.dxf.text}</text>'
      for e in msp.query('TEXT')]

# ---- standalone SVG for Inkscape (true scale: 1 user unit = 1 mm) ----
svg_doc = (f'<?xml version="1.0" encoding="UTF-8"?>\n'
 f'<svg xmlns="http://www.w3.org/2000/svg" width="{x1-x0:.0f}mm" height="{y1-y0:.0f}mm" '
 f'viewBox="{x0v:.0f} 0 {x1v-x0v:.0f} {y1-y0:.0f}">\n'
 '<style>.nl{font-size:13px;font-weight:700;font-family:ui-monospace,Menlo,Consolas,monospace}</style>\n'
 + "\n".join(band) + '\n</svg>\n')
# Erand49.svg is now the USER-EDITED neck design (Inkscape) — never overwrite it.
open(os.path.join(HERE, 'Erand49-generated.svg'), 'w').write(svg_doc)

# ---- standalone harp page: Erand49/LAYOUT.html ----
BAND_STYLE = '<style>.nl{font-size:13px;font-weight:700;font-family:ui-monospace,Menlo,Consolas,monospace}</style>'
html = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=6, user-scalable=yes">
<title>Erand49 harp layout</title>
<style>
html,body{{margin:0;background:#fff !important;color:#111 !important;font:16px/1.5 ui-monospace,Menlo,Consolas,monospace}}
main{{max-width:1100px;margin:0 auto;padding:16px}}
h1{{font-size:22px;margin:0 0 4px}} h2{{font-size:17px;margin:28px 0 8px;border-bottom:2px solid #111;padding-bottom:4px}}
h3{{font-size:15px;margin:20px 0 6px}}
p{{margin:0 0 10px}} .sub{{color:#444}} .k{{font-weight:700}} .leg{{font-weight:700}}
table{{border-collapse:collapse;width:100%;font-size:14px}} th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid #999;vertical-align:top}} th{{background:#eee}}
.wrap{{overflow:auto;border:1px solid #ccc;margin:8px 0}} .wrap svg{{min-width:900px}}
</style></head><body><main>
<h1>ERAND49 — HARP LAYOUT</h1>
<p class="sub">The silent 49-string optical harp (A0–G7). The PM console is its voice and control
surface — connection, docking, and travel live in the PM's <code>../LAYOUT.html</code>; this page is
the instrument itself: string band, sensors, and frame.</p>

<h2>Figure 1 — harp side-view profile (ISO 128/129): strings on the frame</h2>
<p class="sub">From <code>erard original stringband tutorial.dxf</code>: variable spacing
(13.325→17.94 mm, ratio 1.025), sloped anchors, in mm — <b>each stroke width is the string's actual
overall diameter</b>. Colors per harp convention: <span class="leg" style="color:#c0392b">C red</span> ·
<span class="leg" style="color:#2e5fa3">F blue</span> · others dark gray; hover any string for its
spec. Dark ticks: nut and tuner pin; colored 12° top segments: tuner leads. Amber crosshairs:
optical X/Y sensor axes, 1.0 in below each nut on the neck rail. Brown/amber Beziers: tuner and
sensor rails (hand-tuned neck: <code>Erand49.svg</code>). b0*/a0*: spec extrapolated from c1 physics
(<code>string-specs.md</code>). Frame per <code>frame-spec.md</code>: midrib channel side profile (4" sides, top web on the string-anchor line, dash-dot centerline) from the pillar foot to the shoulder; pillar (Ø2" round tube) crown to floor through the open-bottom midrib; plates rest on the midrib shoulder steps and weld to its center tongue (ER-005), crown pads on the pillar; ISO 129 dims in mm.</p>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0v:.0f} 0 {x1v-x0v:.0f} {y1-y0:.0f}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 string band, Erard DXF geometry, true scale">
{BAND_STYLE}
{chr(10).join(band)}
</svg></div>

<h2>Cross sections — diameters at 5×, at each string's real position</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0v:.0f} 0 {x1v-x0v:.0f} 110" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="String cross sections at 5x">
<text x="{x0v+16:.0f}" y="100" style="font-size:15px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace">plain nylon → nylon-wrapped (#28 a3) → bronze-wound steel (#39 d2)</text>
{chr(10).join(xsec)}
</svg></div>

<h2>Frame — spec and ISO 128 sections</h2>
<h3 style="font-size:15px;margin:20px 0 6px">Frame members (see Erand49/frame-spec.md)</h3>
<table>
<tr><th>Member</th><th>Section (6061-T6)</th><th>Check @ welded-HAZ allowable</th></tr>
<tr><td class="k">Midrib</td><td>Rect tube 4" × 2" × 3/16" — strings through grommeted holes in the top face; knots concealed inside the sides; access holes in the bottom face; closed section, no torsion issue</td><td>0.88 kN·m mid-span → ~25 MPa, SF ~5.5</td></tr>
<tr><td class="k">Pillar</td><td>Square tube 2" × 2" × 1/8", top rebated 8 mm/side for the plates — cleat bolts to the flat +Y face</td><td>Euler ~39 kN vs few kN, ~8× margin</td></tr>
<tr><td class="k">Neck</td><td>2 plates per <code>Erand49.svg</code>, bolted flush onto the ±Y faces of pillar and midrib (both 50.8 mm wide → plate gap 50.8); no blocks; through-bolts with crush sleeves</td><td>pin-edge ≥ 16.2 mm, sensor-edge ≥ 7.1 mm verified</td></tr>
</table>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="0 0 1300 2130" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 frame ISO 128 sections">
<style>.fl{{font-size:11px;font-weight:700;fill:#111;font-family:ui-monospace,Menlo,Consolas,monospace}}.fs{{font-size:9px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace}}.fg{{font-size:10px;font-weight:700;fill:#a8700f;font-family:ui-monospace,Menlo,Consolas,monospace}}.dim{{stroke:#3b5a7a;stroke-width:1;fill:none}}.dmt{{font-size:9px;fill:#3b5a7a;font-family:ui-monospace,Menlo,Consolas,monospace}}.cl{{stroke:#c9553a;stroke-width:0.8;stroke-dasharray:12 3 3 3}}</style>
<defs>
<pattern id="hat" width="7" height="7" patternTransform="rotate(45)" patternUnits="userSpaceOnUse"><line x1="0" y1="0" x2="0" y2="7" stroke="#8d877a" stroke-width="1"/></pattern>
<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#3b5a7a"/></marker>
</defs>
<text x="20" y="20" class="fg">ER-001 — NECK, SECTION A–A AT A PIN STATION (first angle, dims mm, 2 px/mm)</text>
<!-- plates -->
<rect x="240.5" y="60" width="16" height="330" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<rect x="383.5" y="60" width="16" height="330" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<!-- through pin -->
<rect x="226" y="90" width="178" height="11" rx="2" fill="#6a6d74" stroke="#111"/>
<rect x="404" y="84" width="16" height="23" rx="2" fill="#6a6d74" stroke="#111"/>
<text x="426" y="100" class="fs">tuning head (alternates ±Y)</text>
<text x="245" y="82" class="fs">through-pin Ø5.5 — bears in BOTH plates</text>
<!-- string centerline -->
<line x1="320" y1="60" x2="320" y2="470" class="cl"/>
<circle cx="320" cy="300" r="2.6" fill="#111"/>
<text x="328" y="296" class="fs">string (XZ plane)</text>
<!-- sensors: crossed 45deg beams -->
<rect x="256.5" y="244" width="10" height="12" fill="#c58a1f"/><rect x="256.5" y="344" width="10" height="12" fill="#c58a1f"/>
<rect x="373.5" y="244" width="10" height="12" fill="#3b5a7a"/><rect x="373.5" y="344" width="10" height="12" fill="#3b5a7a"/>
<line x1="266.5" y1="250" x2="373.5" y2="357" stroke="#c58a1f" stroke-width="1.2" stroke-dasharray="5 4"/>
<line x1="266.5" y1="357" x2="373.5" y2="250" stroke="#c58a1f" stroke-width="1.2" stroke-dasharray="5 4"/>
<text x="180" y="252" class="fs" text-anchor="end">IR emit ×2</text>
<text x="415" y="352" class="fs">detect ×2 — X/Y beams cross</text>
<text x="415" y="364" class="fs">at ±45° on the sensor rail</text>
<!-- dims -->
<line x1="256.5" y1="430" x2="383.5" y2="430" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<line x1="256.5" y1="395" x2="256.5" y2="435" class="dim"/><line x1="383.5" y1="395" x2="383.5" y2="435" class="dim"/>
<text x="320" y="446" class="dmt" text-anchor="middle">63.5 (gap = midrib width)</text>
<line x1="240.5" y1="48" x2="256.5" y2="48" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="248" y="40" class="dmt" text-anchor="middle">8</text>
<line x1="256.5" y1="470" x2="320" y2="470" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="288" y="484" class="dmt" text-anchor="middle">31.75</text>
<text x="20" y="505" class="fs">Plates bolt flush onto the midrib ±Y faces (63.5 wide → gap 63.5). Crown: 6.35 pads per side between the Ø50.8 round pillar and the plates, through-bolts with crush sleeves through the tube.</text>

<text x="540" y="20" class="fg">ER-002 — PILLAR SECTION (Ø2" × 3/16" round tube)</text>
<circle cx="610.8" cy="170.8" r="50.8" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<circle cx="610.8" cy="170.8" r="41.3" fill="#fff" stroke="#111" stroke-width="1.2"/>
<line x1="560" y1="100" x2="661.6" y2="100" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="610" y="92" class="dmt" text-anchor="middle">Ø50.8</text>
<line x1="690" y1="136" x2="656" y2="140" class="dim" marker-end="url(#ar)"/>
<text x="694" y="140" class="dmt">4.76 wall</text>
<text x="540" y="270" class="fs">Euler ~31 kN over 2 m ⇒ ~6× margin</text>
<text x="540" y="284" class="fs">incl. hung PM console + lean loads</text>
<text x="540" y="304" class="fs">crown: 6.35 pads/side to the plates,</text>
<text x="540" y="318" class="fs">crush-sleeved bolts; cleat on a saddle</text>

<text x="810" y="20" class="fg">ER-003 — MIDRIB SECTION (C-channel: 2.5" web top + 4" sides × 3/16", open bottom)</text>
<path d="M860 293.2 L860 90 L987 90 L987 293.2 L977.5 293.2 L977.5 99.5 L869.5 99.5 L869.5 293.2 Z" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<line x1="923.5" y1="45" x2="923.5" y2="90" stroke="#3b3e44" stroke-width="2.3"/>
<rect x="916.7" y="88" width="13.6" height="12" fill="#fff" stroke="#111" stroke-width="1"/>
<circle cx="923.5" cy="120" r="6" fill="#3b3e44"/>
<line x1="923.5" y1="70" x2="923.5" y2="310" class="cl"/>
<line x1="840" y1="90" x2="840" y2="293.2" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="833" y="196" class="dmt" text-anchor="end" transform="rotate(-90 833 196)">101.6</text>
<line x1="860" y1="70" x2="987" y2="70" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="923" y="62" class="dmt" text-anchor="middle">63.5</text>
<line x1="1020" y1="99" x2="988" y2="95" class="dim" marker-end="url(#ar)"/>
<text x="1024" y="102" class="dmt">4.76 typ</text>
<text x="1005" y="130" class="fs">string through grommeted hole</text>
<text x="1005" y="142" class="fs">in the top face ℄; knot rests</text>
<text x="1005" y="154" class="fs">inside, concealed by the sides;</text>
<text x="1005" y="166" class="fs">OPEN BOTTOM — knots and wiring</text>
<text x="1005" y="178" class="fs">serviced directly, no access holes</text>
<text x="810" y="400" class="fs">0.88 kN·m mid-span → ~40 MPa, SF ~3.5 (parent); bow ~3.5 mm</text>
<text x="810" y="414" class="fs">section symmetric about the string plane ⇒ shear center on-plane, no string-load torsion</text>

<text x="20" y="545" class="fg">ER-004 — BASE: ROUND PILLAR THROUGH THE MIDRIB; BOTH FEET ON THE FLOOR (side view XZ, 1 px/mm)</text>
<!-- floor -->
<rect x="60" y="940" width="560" height="14" fill="url(#hat)" stroke="#111" stroke-width="1.2"/>
<text x="630" y="951" class="fs">floor / plinth deck</text>
<!-- midrib: side-wall silhouette continuous; top face holed at the pillar (dashed) -->
<line x1="90.4" y1="940" x2="274.6" y2="644.5" stroke="#111" stroke-width="1.8"/>
<line x1="274.6" y1="644.5" x2="325.4" y2="563.0" stroke="#111" stroke-width="1" stroke-dasharray="5 4"/>
<line x1="325.4" y1="563.0" x2="341.6" y2="537" stroke="#111" stroke-width="1.8"/>
<line x1="210.3" y1="940" x2="428" y2="591" stroke="#111" stroke-width="1.8"/>
<line x1="90.4" y1="940" x2="210.3" y2="940" stroke="#111" stroke-width="1.8"/>
<text x="440" y="600" class="fs">midrib C-channel 2.5"×4"×3/16" — Ø51 hole</text>
<text x="440" y="612" class="fs">in the top web (dashed); the OPEN BOTTOM</text>
<text x="440" y="624" class="fs">passes straight over the pillar —</text>
<text x="440" y="636" class="fs">no cutting; side walls continuous</text>
<text x="60" y="928" class="fs">horizontal end cut → flat floor foot</text>
<!-- round pillar, continuous crown->floor: solid outside the band, dashed inside -->
<line x1="274.6" y1="558" x2="274.6" y2="644.5" stroke="#111" stroke-width="1.8"/>
<line x1="274.6" y1="644.5" x2="274.6" y2="836.9" stroke="#111" stroke-width="1.2" stroke-dasharray="6 4"/>
<line x1="274.6" y1="836.9" x2="274.6" y2="940" stroke="#111" stroke-width="1.8"/>
<line x1="325.4" y1="558" x2="325.4" y2="563.0" stroke="#111" stroke-width="1.8"/>
<line x1="325.4" y1="563.0" x2="325.4" y2="755.4" stroke="#111" stroke-width="1.2" stroke-dasharray="6 4"/>
<line x1="325.4" y1="755.4" x2="325.4" y2="940" stroke="#111" stroke-width="1.8"/>
<line x1="300" y1="550" x2="300" y2="952" class="cl"/>
<text x="266" y="580" class="fs" text-anchor="end">pillar Ø2"×3/16", from the crown,</text>
<text x="266" y="592" class="fs" text-anchor="end">foot on the floor</text>
<!-- welds -->
<path d="M274.6 644.5 l-13 -4 l2 12 z" fill="#c9553a"/>
<path d="M325.4 563.0 l13 -4 l-2 12 z" fill="#c9553a"/>
<line x1="338.4" y1="561" x2="430" y2="530" stroke="#c9553a" stroke-width="1"/>
<text x="434" y="528" class="fs" style="fill:#c9553a">a5 fillet around the Ø51 top-face hole</text>
<path d="M274.6 836.9 l-13 4 l2 -12 z" fill="#c9553a"/>
<path d="M325.4 755.4 l13 4 l-2 -12 z" fill="#c9553a"/>
<line x1="338.4" y1="757" x2="430" y2="800" stroke="#c9553a" stroke-width="1"/>
<text x="434" y="804" class="fs" style="fill:#c9553a">a5 fillet, both side walls</text>
<text x="434" y="816" class="fs" style="fill:#c9553a">to the pillar</text>
<!-- dims -->
<path d="M300 700 A 55 55 0 0 1 335 668" fill="none" stroke="#3b5a7a" stroke-width="1"/>
<text x="343" y="688" class="dmt">58°</text>
<line x1="274.6" y1="552" x2="325.4" y2="552" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="300" y="544" class="dmt" text-anchor="middle">Ø50.8</text>
<!-- notes -->
<text x="20" y="990" class="fs">Assembly: slide the midrib down over the standing pillar — the open-bottom channel and the Ø51 top-web hole (in the</text>
<text x="20" y="1004" class="fs">string-free zone past a0) let it pass; self-fixturing. Weld the top-web rim and both side walls to the pillar. Both members</text>
<text x="20" y="1018" class="fs">stand on the floor: pillar foot plus the midrib horizontal end cut — a wide, stable base line with no base plate and no blocks.</text>

<text x="20" y="1075" class="fg">ER-005 — SHOULDER: PLATES LAP THE CHANNEL TOP ON AN 8 mm REBATE, WELDED TO THE PROUD WEB (section ⊥ member, 2 px/mm)</text>
<!-- tube below the step -->
<rect x="256.5" y="1300" width="127" height="120" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<rect x="266" y="1309.5" width="108" height="120" fill="#fff" stroke="#111" stroke-width="1.2"/>
<line x1="256.5" y1="1300" x2="383.5" y2="1300" stroke="#111" stroke-width="1.5"/>
<!-- tongue -->
<rect x="272.5" y="1180" width="95" height="120" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<!-- plates resting on the steps -->
<rect x="256.5" y="1160" width="16" height="140" fill="none" stroke="#3b5a7a" stroke-width="1.8"/>
<rect x="367.5" y="1160" width="16" height="140" fill="none" stroke="#3b5a7a" stroke-width="1.8"/>
<text x="248" y="1170" class="fs" text-anchor="end">neck plate (bottom edge on the channel top line)</text>
<text x="392" y="1170" class="fs">neck plate</text>
<!-- welds plate<->tongue -->
<path d="M272.5 1230 l12 -5 l0 12 z" fill="#c9553a"/>
<path d="M367.5 1230 l-12 -5 l0 12 z" fill="#c9553a"/>
<line x1="284.5" y1="1230" x2="210" y2="1210" stroke="#c9553a" stroke-width="1"/>
<text x="206" y="1206" class="fs" text-anchor="end" style="fill:#c9553a">horizontal fillet: plate bottom</text>
<text x="206" y="1218" class="fs" text-anchor="end" style="fill:#c9553a">edge to side wall, each plate</text>
<!-- bearing arrows at the steps -->
<path d="M264 1332 L264 1304" stroke="#3b5a7a" stroke-width="1.5" fill="none"/><path d="M259 1314 L264 1302 L269 1314 Z" fill="#3b5a7a"/>
<path d="M375.5 1332 L375.5 1304" stroke="#3b5a7a" stroke-width="1.5" fill="none"/><path d="M370.5 1314 L375.5 1302 L380.5 1314 Z" fill="#3b5a7a"/>
<text x="400" y="1330" class="fs" style="fill:#3b5a7a">plates bear on the rebate; the horizontal weld line</text>
<text x="400" y="1342" class="fs" style="fill:#3b5a7a">below the lap ties plate to side wall on each side</text>
<!-- dims -->
<line x1="256.5" y1="1445" x2="383.5" y2="1445" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="320" y="1461" class="dmt" text-anchor="middle">63.5</text>
<line x1="272.5" y1="1150" x2="367.5" y2="1150" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="320" y="1142" class="dmt" text-anchor="middle">47.5</text>
<line x1="236" y1="1290" x2="255" y2="1296" class="dim" marker-end="url(#ar)"/>
<text x="232" y="1292" class="dmt" text-anchor="end">rebate = 8 (one plate)</text>
<!-- notes -->
<text x="20" y="1510" class="fs">The rebate runs ALONG the channel top (inclined at the member angle) for the ~60 mm lap: mill 8 mm — one plate thickness — off each</text>
<text x="20" y="1524" class="fs">side wall's outer face at the top corner. The 47.5 mm center (web + wall remnants) stands proud between the plates and takes the</text>
<text x="20" y="1538" class="fs">welds. The neck's bottom edge lands ON the channel's top line — the classic harp shoulder corner — and the outer faces stay flush.</text>

<text x="20" y="1600" class="fg">ER-006 — HINGED OUTRIGGER LEGS AT THE MIDRIB FOOT (front view YZ, 1 px/mm)</text>
<!-- floor -->
<rect x="120" y="2010" width="800" height="14" fill="url(#hat)" stroke="#111" stroke-width="1.2"/>
<!-- midrib near the base, seen from the front: 63.5 wide band to the floor -->
<rect x="488" y="1660" width="63.5" height="350" fill="none" stroke="#111" stroke-width="1.8"/>
<text x="520" y="1648" class="fs" text-anchor="middle">midrib (front view), floor foot</text>
<!-- hinges -->
<circle cx="488" cy="1850" r="6" fill="#fff" stroke="#111" stroke-width="1.5"/>
<circle cx="551.5" cy="1850" r="6" fill="#fff" stroke="#111" stroke-width="1.5"/>
<!-- legs deployed -->
<line x1="488" y1="1850" x2="245" y2="2010" stroke="#111" stroke-width="5"/>
<line x1="551.5" y1="1850" x2="795" y2="2010" stroke="#111" stroke-width="5"/>
<rect x="225" y="2004" width="40" height="8" rx="3" fill="#2a2c30"/>
<rect x="775" y="2004" width="40" height="8" rx="3" fill="#2a2c30"/>
<text x="300" y="1990" class="fs">rubber foot</text>
<!-- folded position, dashed along the member -->
<line x1="488" y1="1850" x2="488" y2="1560" stroke="#111" stroke-width="2.5" stroke-dasharray="7 5"/>
<line x1="551.5" y1="1850" x2="551.5" y2="1560" stroke="#111" stroke-width="2.5" stroke-dasharray="7 5"/>
<text x="470" y="1550" class="fs" text-anchor="end">folded for travel — legs lie</text>
<text x="470" y="1562" class="fs" text-anchor="end">flat along the midrib sides</text>
<!-- lock -->
<line x1="470" y1="1905" x2="380" y2="1935" stroke="#c9553a" stroke-width="1"/>
<text x="376" y="1938" class="fs" text-anchor="end" style="fill:#c9553a">wing-bolt lock at each hinge</text>
<text x="376" y="1950" class="fs" text-anchor="end" style="fill:#c9553a">(deployed and folded detents)</text>
<!-- dims -->
<line x1="245" y1="2050" x2="795" y2="2050" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="520" y="2066" class="dmt" text-anchor="middle">~550 stance</text>
<line x1="600" y1="1868" x2="700" y2="1935" class="dim" marker-end="url(#ar)"/>
<text x="704" y="1940" class="dmt">leg ~295, 1"×1/8" flat bar</text>
<!-- notes -->
<text x="20" y="2095" class="fs">Without legs the frame's floor footprint in Y is zero — the harp cannot stand. Two legs hinge on shoulder bolts through the</text>
<text x="20" y="2109" class="fs">midrib side walls near the foot; deployed ~55° to a ~550 mm stance (CG ~0.8 m ⇒ tips only past ~19° of lean — kid-proof), they</text>
<text x="20" y="2123" class="fs">fold flat along the member for the travel case. Wing-bolt or detent locks both positions.</text>
</svg></div>

<p class="sub">Sources: <code>string-specs.md</code> (49-string spec, imperial + metric; band tension
1572.9 lbf ≈ 7.00 kN) · <code>frame-spec.md</code> (members, welds, build sequence) ·
<code>Erand49.svg</code> (hand-edited neck master) · regenerate this page:
<code>python3 gen_erand49.py</code>.</p>
</main></body></html>
"""
open(os.path.join(HERE, 'LAYOUT.html'), 'w').write(html)
print('wrote Erand49/LAYOUT.html and Erand49-generated.svg')
