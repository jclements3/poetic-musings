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
y_base  = m*pilc + cxi - MHW - 0.8
xr_m = max(g[0] for _, g in strings) + 2.2       # midrib reaches the shoulder (treble end)
allx += [pilc-PW, pilc+PW, xr_m]; ally.append(y_base)

x0, x1 = (min(allx)-1.2)*IN, (max(allx)+1.2)*IN
y0, y1 = (min(ally)-3.0)*IN, (max(ally)+0.8)*IN
def X(v): return v*IN
def Y(v): return y1 - v*IN   # y-up inches -> y-down mm, 0-based for the viewBox

# classify the non-string lines: 0.25" ticks (47x3: sharp fret at 0.944L, nut at L,
# tuner at L+1.5), ~1.53" at 78 deg = tuner leads, rest = frame.
# The sharp-fret ticks are repositioned to the optical sensor axes near the rib:
SENSE_IN = 1.0   # sensor beam crossing, inches BELOW THE NUT (rail on the neck)
tops = [(g[0], g[2], color(r[1]), r[6]*IN) for r, g in strings]
geom = {g[0]: (g[1], g[2]) for _, g in strings}   # x -> (ylo, yhi)
marks, keys, outline, sense = [], [], [], []
for a, b, L in frame:
    if L < 0.5:
        mx, my = (a[0]+b[0])/2, (a[1]+b[1])/2
        sx = min(geom, key=lambda x: abs(x-mx))
        ylo, yhi = geom[sx]
        if my < yhi - 0.05:            # below the nut = the sharp-fret tick -> move to sensor axis
            sense.append((sx, yhi - SENSE_IN))
        else:
            marks.append((a, b))
    elif L < 2.0:
        lo = a if a[1] < b[1] else b
        best = min(tops, key=lambda t: (t[0]-lo[0])**2 + (t[1]-lo[1])**2)
        keys.append((a, b, best[2], best[3]))
    else: outline.append((a, b))
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    sense.append((gx, glo + Lg - SENSE_IN))
# ---- frame in side view: midrib C-channel band + pillar + ISO 129 dims ----
band = []
band.append('<defs><marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#3b5a7a"/></marker></defs>')
_h = math.hypot(1, m)
px_, py_ = -m/_h, 1/_h                            # unit perpendicular to midrib axis
def mp(t, off):
    return X(t + px_*off), Y(m*t + cxi + py_*off)
for off in (+MHW, -MHW):
    (xa, ya), (xb, yb) = mp(pilc, off), mp(xr_m, off)
    band.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#8d877a" stroke-width="2"/>')
(xa, ya), (xb, yb) = mp(pilc, 0), mp(xr_m, 0)
band.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#c9553a" stroke-width="0.8" stroke-dasharray="12 3 3 3"><title>midrib centerline = string anchor line</title></line>')
lx, ly = mp(pilc+4.5, -MHW)
band.append(f'<text x="{lx:.0f}" y="{ly+30:.0f}" class="nl" fill="#8d877a">midrib — C 4"×1.75"×3/16" 6061-T6, web shown (ER-003)</text>')
band.append(f'<rect x="{X(pilc-PW):.1f}" y="{Y(y_crown):.1f}" width="{2*PW*IN:.1f}" height="{Y(y_base)-Y(y_crown):.1f}" fill="none" stroke="#8d877a" stroke-width="2"><title>pillar — 2"×2"×1/8" square tube, base to crown (ER-002)</title></rect>')
band.append(f'<text x="{X(pilc)+35:.0f}" y="{(Y(y_crown)+Y(y_base))/2:.0f}" class="nl" fill="#8d877a">pillar 2"×2"×1/8"</text>')
band.append(f'<rect x="{X(pilc-PW)-4:.1f}" y="{Y(y_crown)-14:.1f}" width="{2*PW*IN+8:.1f}" height="14" fill="#d9d3c2" stroke="#8d877a" stroke-width="1.5"><title>crown block — pillar weld, plates bolt on</title></rect>')
sbx, sby = mp(xr_m-0.6, MHW)
band.append(f'<rect x="{sbx-24:.1f}" y="{sby-14:.1f}" width="48" height="20" fill="#d9d3c2" stroke="#8d877a" stroke-width="1.5" transform="rotate({-math.degrees(math.atan2(m,1)):.1f} {sbx:.1f} {sby:.1f})"><title>shoulder block — midrib weld, plates bolt on</title></rect>')
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
for sx, sy in sense:
    band.append(f'<g stroke="#a8700f" stroke-width="1.4"><line x1="{X(sx)-3.2:.1f}" y1="{Y(sy):.1f}" x2="{X(sx)+3.2:.1f}" y2="{Y(sy):.1f}"/><line x1="{X(sx):.1f}" y1="{Y(sy)-3.2:.1f}" x2="{X(sx):.1f}" y2="{Y(sy)+3.2:.1f}"/><title>optical X/Y sensor axis — {SENSE_IN:.1f} in / {SENSE_IN*IN:.1f} mm below the nut, sensor rail on the neck</title></g>')
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
 f'viewBox="{x0:.0f} 0 {x1-x0:.0f} {y1-y0:.0f}">\n'
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
(<code>string-specs.md</code>). Frame per <code>frame-spec.md</code>: midrib C-channel side profile (4" web band, red dash-dot centerline on the anchor line) from the pillar foot to the shoulder; pillar (2"×2" square tube) base to crown at the bass end, with crown/shoulder blocks; ISO 129 dims in mm.</p>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0:.0f} 0 {x1-x0:.0f} {y1-y0:.0f}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 string band, Erard DXF geometry, true scale">
{BAND_STYLE}
{chr(10).join(band)}
</svg></div>

<h2>Cross sections — diameters at 5×, at each string's real position</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0:.0f} 0 {x1-x0:.0f} 110" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="String cross sections at 5x">
<text x="{x0+16:.0f}" y="100" style="font-size:15px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace">plain nylon → nylon-wrapped (#28 a3) → bronze-wound steel (#39 d2)</text>
{chr(10).join(xsec)}
</svg></div>

<h2>Frame — spec and ISO 128 sections</h2>
<h3 style="font-size:15px;margin:20px 0 6px">Frame members (see Erand49/frame-spec.md)</h3>
<table>
<tr><th>Member</th><th>Section (6061-T6)</th><th>Check @ welded-HAZ allowable</th></tr>
<tr><td class="k">Midrib</td><td>C-channel 4" × 1.75" × 3/16" — web in the string plane, flanges ±Y, open trough = cable/anchor run</td><td>0.88 kN·m mid-span → ~29 MPa, SF > 4</td></tr>
<tr><td class="k">Pillar</td><td>Square tube 2" × 2" × 1/8" — cleat bolts to the flat +Y face</td><td>Euler ~39 kN vs few kN, ~8× margin</td></tr>
<tr><td class="k">Neck</td><td>2 plates per <code>Erand49.svg</code>, bolted to 50 mm shoulder/crown blocks (pre-welded to midrib/pillar)</td><td>pin-edge ≥ 16.2 mm, sensor-edge ≥ 7.1 mm verified</td></tr>
</table>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="0 0 1300 520" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 frame ISO 128 sections">
<style>.fl{{font-size:11px;font-weight:700;fill:#111;font-family:ui-monospace,Menlo,Consolas,monospace}}.fs{{font-size:9px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace}}.fg{{font-size:10px;font-weight:700;fill:#a8700f;font-family:ui-monospace,Menlo,Consolas,monospace}}.dim{{stroke:#3b5a7a;stroke-width:1;fill:none}}.dmt{{font-size:9px;fill:#3b5a7a;font-family:ui-monospace,Menlo,Consolas,monospace}}.cl{{stroke:#c9553a;stroke-width:0.8;stroke-dasharray:12 3 3 3}}</style>
<defs>
<pattern id="hat" width="7" height="7" patternTransform="rotate(45)" patternUnits="userSpaceOnUse"><line x1="0" y1="0" x2="0" y2="7" stroke="#8d877a" stroke-width="1"/></pattern>
<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#3b5a7a"/></marker>
</defs>
<text x="20" y="20" class="fg">ER-001 — NECK, SECTION A–A AT A PIN STATION (first angle, dims mm, 2 px/mm)</text>
<!-- plates -->
<rect x="254" y="60" width="16" height="330" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<rect x="370" y="60" width="16" height="330" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<!-- through pin -->
<rect x="240" y="90" width="150" height="11" rx="2" fill="#6a6d74" stroke="#111"/>
<rect x="390" y="84" width="16" height="23" rx="2" fill="#6a6d74" stroke="#111"/>
<text x="412" y="100" class="fs">tuning head (alternates ±Y)</text>
<text x="245" y="82" class="fs">through-pin Ø5.5 — bears in BOTH plates</text>
<!-- string centerline -->
<line x1="320" y1="60" x2="320" y2="470" class="cl"/>
<circle cx="320" cy="300" r="2.6" fill="#111"/>
<text x="328" y="296" class="fs">string (XZ plane)</text>
<!-- sensors: crossed 45deg beams -->
<rect x="270" y="244" width="10" height="12" fill="#c58a1f"/><rect x="270" y="344" width="10" height="12" fill="#c58a1f"/>
<rect x="360" y="244" width="10" height="12" fill="#3b5a7a"/><rect x="360" y="344" width="10" height="12" fill="#3b5a7a"/>
<line x1="280" y1="250" x2="360" y2="350" stroke="#c58a1f" stroke-width="1.2" stroke-dasharray="5 4"/>
<line x1="280" y1="350" x2="360" y2="250" stroke="#c58a1f" stroke-width="1.2" stroke-dasharray="5 4"/>
<text x="180" y="252" class="fs" text-anchor="end">IR emit ×2</text>
<text x="415" y="352" class="fs">detect ×2 — X/Y beams cross</text>
<text x="415" y="364" class="fs">at ±45° on the sensor rail</text>
<!-- dims -->
<line x1="270" y1="430" x2="370" y2="430" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<line x1="270" y1="395" x2="270" y2="435" class="dim"/><line x1="370" y1="395" x2="370" y2="435" class="dim"/>
<text x="320" y="446" class="dmt" text-anchor="middle">50 (gap = block width)</text>
<line x1="254" y1="48" x2="270" y2="48" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="262" y="40" class="dmt" text-anchor="middle">8</text>
<line x1="270" y1="470" x2="320" y2="470" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="295" y="484" class="dmt" text-anchor="middle">25</text>
<text x="20" y="505" class="fs">Plates bolt to shoulder/crown blocks; blocks pre-welded to midrib/pillar (weld first, plate after — torch access solved by sequence).</text>

<text x="540" y="20" class="fg">ER-002 — PILLAR SECTION (2" × 2" × 1/8" sq tube)</text>
<rect x="560" y="120" width="101.6" height="101.6" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<rect x="566.4" y="126.4" width="88.8" height="88.8" fill="#fff" stroke="#111" stroke-width="1.2"/>
<line x1="560" y1="100" x2="661.6" y2="100" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="610" y="92" class="dmt" text-anchor="middle">50.8</text>
<line x1="690" y1="126" x2="662" y2="126" class="dim" marker-end="url(#ar)"/>
<text x="694" y="130" class="dmt">3.2 wall</text>
<line x1="560" y1="120" x2="530" y2="150" class="dim" marker-start="url(#ar)"/>
<text x="470" y="162" class="dmt">+Y face — cleat</text>
<text x="470" y="174" class="dmt">bolts here</text>
<text x="540" y="270" class="fs">Euler ~39 kN over 2 m ⇒ ~8× margin</text>
<text x="540" y="284" class="fs">incl. hung PM console + lean loads</text>

<text x="810" y="20" class="fg">ER-003 — MIDRIB SECTION (C 4" × 1.75" × 3/16")</text>
<path d="M860 90 h89 v9.5 h-79.5 v184.6 h79.5 v9.5 h-89 z" fill="url(#hat)" stroke="#111" stroke-width="1.5"/>
<line x1="840" y1="90" x2="840" y2="293.6" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="833" y="196" class="dmt" text-anchor="end" transform="rotate(-90 833 196)">101.6</text>
<line x1="860" y1="70" x2="949" y2="70" class="dim" marker-start="url(#ar)" marker-end="url(#ar)"/>
<text x="905" y="62" class="dmt" text-anchor="middle">44.5</text>
<line x1="990" y1="99" x2="950" y2="95" class="dim" marker-end="url(#ar)"/>
<text x="994" y="102" class="dmt">4.76 typ</text>
<line x1="864.75" y1="80" x2="864.75" y2="303" class="cl"/>
<text x="875" y="320" class="fs">web in the string plane — anchors bolt</text>
<text x="875" y="332" class="fs">through web ℄ (shear-center discipline);</text>
<text x="875" y="344" class="fs">open trough ±Y = cable + anchor run;</text>
<text x="875" y="356" class="fs">bolt-on closing strip mid-span if any</text>
<text x="875" y="368" class="fs">twist at full tension (channel → box)</text>
<text x="810" y="400" class="fs">0.88 kN·m mid-span → ~29 MPa, SF &gt; 4</text>
<text x="810" y="414" class="fs">(welded-HAZ allowable 70 MPa)</text>
</svg></div>

<p class="sub">Sources: <code>string-specs.md</code> (49-string spec, imperial + metric; band tension
1572.9 lbf ≈ 7.00 kN) · <code>frame-spec.md</code> (members, welds, build sequence) ·
<code>Erand49.svg</code> (hand-edited neck master) · regenerate this page:
<code>python3 gen_erand49.py</code>.</p>
</main></body></html>
"""
open(os.path.join(HERE, 'LAYOUT.html'), 'w').write(html)
print('wrote Erand49/LAYOUT.html and Erand49-generated.svg')
