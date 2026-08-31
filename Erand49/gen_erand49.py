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

x0, x1 = (min(allx)-1.2)*IN, (max(allx)+1.2)*IN
y0, y1 = (min(ally)-1.6)*IN, (max(ally)+0.8)*IN
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
band = ['<g stroke="#b9b3a3" stroke-width="1.2" fill="none">']
band += [f'<line x1="{X(a[0]):.1f}" y1="{Y(a[1]):.1f}" x2="{X(b[0]):.1f}" y2="{Y(b[1]):.1f}"/>' for a, b in outline]
band.append('</g>')
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
for n, note, fg, Lg, odg, tg, gx, glo in gpts:
    tip = f"#{n} {note} · {fg:g} Hz · {Lg:.3f} in / {Lg*IN:.1f} mm · Ø {odg:.4f} in / {odg*IN:.2f} mm · {tg:.1f} lbf — EXTRAPOLATED from c1 (see string-specs.md)"
    band.append(f'<line x1="{X(gx):.1f}" y1="{Y(glo):.1f}" x2="{X(gx):.1f}" y2="{Y(glo+Lg):.1f}" stroke="{color(note)}" stroke-width="{odg*IN:.3f}" stroke-dasharray="10 8"><title>{tip}</title></line>')
    band.append(f'<text x="{X(gx):.1f}" y="{Y(glo)+24:.1f}" class="nl" fill="#8d877a" text-anchor="middle">{note}*</text>')

# ---- cross sections at 5x, aligned to real string x positions ----
xsec = []
for (n, note, f, Lin, cm, wm, od, t), (x, ylo, yhi) in strings:
    tip = f"#{n} {note} · Ø {od:.3f} in / {od*IN:.2f} mm"
    xsec.append(f'<circle cx="{X(x):.1f}" cy="40" r="{od*IN*5/2:.2f}" fill="{color(note)}"><title>{tip}</title></circle>')

# ---- full DXF render (lines + text) ----
fx, fy = [], []
for a, b, _ in dxf_lines:
    fx += [a[0], b[0]]; fy += [a[1], b[1]]
fx0, fx1, fy0, fy1 = min(fx)-1, max(fx)+1, min(fy)-1, max(fy)+1
def FF(v): return (fy1+fy0) - v
el = [f'<line x1="{a[0]:.3f}" y1="{FF(a[1]):.3f}" x2="{b[0]:.3f}" y2="{FF(b[1]):.3f}"/>' for a, b, _ in dxf_lines]
tx = [f'<text x="{e.dxf.insert.x:.2f}" y="{FF(e.dxf.insert.y):.2f}" font-size="{e.dxf.height:.2f}">{e.dxf.text}</text>'
      for e in msp.query('TEXT')]

html = f'''<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=6, user-scalable=yes">
<title>Erand49 string band</title>
<style>
html,body{{margin:0;background:#fff !important;color:#111 !important;font:16px/1.5 ui-monospace,Menlo,Consolas,monospace}}
main{{max-width:1100px;margin:0 auto;padding:16px}}
h1{{font-size:22px;margin:0 0 4px}} h2{{font-size:17px;margin:28px 0 8px;border-bottom:2px solid #111;padding-bottom:4px}}
p{{margin:0 0 10px}} .sub{{color:#444}}
.wrap{{overflow:auto;border:1px solid #ccc;margin:8px 0}} .wrap svg{{min-width:900px}}
.leg{{font-weight:700}}
</style></head><body><main>
<h1>ERAND49 — STRING BAND, ERARD GEOMETRY, TRUE SCALE</h1>
<p class="sub">Geometry straight from <code>erard original stringband tutorial.dxf</code> (all 47 strings
matched to the spec table by length): the DXF's variable spacing (13.325→17.94 mm, ratio 1.025) and
sloped soundboard anchors, in millimetres, with <b>each stroke width the string's actual overall
diameter</b>. Colors per harp convention: <span class="leg" style="color:#c0392b">C red</span> ·
<span class="leg" style="color:#2e5fa3">F blue</span> · others dark gray. Hover any string for its spec.
The Erand49 spans 49 strings, the tutorial 47. Dark ticks on each string, from the DXF: the nut (vibrating-point start) and the
tuner pin; the angled top segment — 1.5 in at 12° off vertical, in the string's own color and
diameter — is its lead to the tuner. The amber crosshairs low on every string are the <b>optical
X/Y sensor axes</b> — the point in the rib where each string's two orthogonal IR beams cross,
1.0 in / 25.4 mm below each nut — the sensor rail mounts on the neck (the DXF's sharp-fret ticks were
repositioned there). b0/a0 dashed in their string colors: full spec extrapolated from c1 physics
(marked * — see string-specs.md), lengths continuing the bass trend, tensions 53.4 / 54.0 lbf,
Ø 0.0955 / 0.1060 in.</p>

<h2>String band — DXF geometry, lengths and diameters to one scale</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0:.0f} 0 {x1-x0:.0f} {y1-y0:.0f}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 string band, Erard DXF geometry, true scale">
<style>.nl{{font-size:13px;font-weight:700;font-family:ui-monospace,Menlo,Consolas,monospace}}</style>
{chr(10).join(band)}
</svg></div>

<h2>Cross sections — diameters at 5×, at each string's real position</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0:.0f} 0 {x1-x0:.0f} 110" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="String cross sections at 5x">
<text x="{x0+16:.0f}" y="100" style="font-size:15px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace">plain nylon → nylon-wrapped (#28 a3) → bronze-wound steel (#39 d2)</text>
{chr(10).join(xsec)}
</svg></div>

<p class="sub">Source: <code>string-specs.md</code> (imperial + metric) and
<code>erard original stringband tutorial.dxf</code>. Regenerate: <code>python3 gen_erand49.py</code>.
Band tension 1465.5 lbf ≈ 6.52 kN excluding b0/a0.</p>
</main></body></html>
'''
open(os.path.join(HERE, 'Erand49.html'), 'w').write(html)
print('wrote Erand49.html')
