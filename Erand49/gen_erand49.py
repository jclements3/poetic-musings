# Generates Erand49.html — true-scale string band drawing.
# Lengths and line widths share one scale (viewBox units = mm), so the
# stroke width of each string IS its overall diameter (ODIA).
import os

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
# Erand49 is 49 strings (A0-G7); b0/a0 specs not in the tutorial — drawn dashed as placeholders.
GHOSTS = [(48,"b0",30.868,60.8),(49,"a0",27.500,62.0)]  # lengths extrapolated, TBD

IN = 25.4
PITCH = 15.0          # string spacing, mm
X0, YRIB = 45.0, 1580.0
W = X0 + PITCH*(len(ROWS)+len(GHOSTS)) + 45.0

def color(note):
    if note.startswith("c"): return "#c0392b"   # C = red (harp convention)
    if note.startswith("f"): return "#2e5fa3"   # F = blue
    return "#3b3e44"

band, xsec = [], []
for i,(n,note,f,Lin,cm,wm,od,t) in enumerate(ROWS):
    x = X0 + PITCH*i
    Lmm, odmm = Lin*IN, od*IN
    c = color(note)
    tip = f"#{n} {note} · {f:g} Hz · {Lin:.3f} in / {Lmm:.1f} mm · Ø {od:.3f} in / {odmm:.2f} mm · {t:.1f} lbf"
    band.append(f'<line x1="{x:.1f}" y1="{YRIB:.1f}" x2="{x:.1f}" y2="{YRIB-Lmm:.1f}" stroke="{c}" stroke-width="{odmm:.3f}"><title>{tip}</title></line>')
    if note.startswith(("c","f")) or n in (1,47):
        band.append(f'<text x="{x:.1f}" y="{YRIB+22:.0f}" class="nl" fill="{c}" text-anchor="middle">{note}</text>')
    xsec.append(f'<circle cx="{x:.1f}" cy="40" r="{odmm*10/2:.2f}" fill="{c}"><title>{tip}</title></circle>')
for j,(n,note,f,Lin) in enumerate(GHOSTS):
    x = X0 + PITCH*(len(ROWS)+j)
    band.append(f'<line x1="{x:.1f}" y1="{YRIB:.1f}" x2="{x:.1f}" y2="{YRIB-Lin*IN:.1f}" stroke="#8d877a" stroke-width="2.4" stroke-dasharray="10 8"><title>#{n} {note} · {f:g} Hz · spec TBD (not in Erard tutorial)</title></line>')
    band.append(f'<text x="{x:.1f}" y="{YRIB+22:.0f}" class="nl" fill="#8d877a" text-anchor="middle">{note}?</text>')

# neck profile through string tops
tops = [(X0+PITCH*i, YRIB-L*IN) for i,(_,_,_,L,_,_,_,_) in enumerate(ROWS)]
tops += [(X0+PITCH*(len(ROWS)+j), YRIB-L*IN) for j,(_,_,_,L) in enumerate(GHOSTS)]
neck = " ".join(f"{x:.1f},{y-8:.1f}" for x,y in tops)

# --- Érard tutorial drawing, rendered from the DXF (ezdxf) ---
dxf_section = ''
try:
    import ezdxf
    doc = ezdxf.readfile(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      'erard original stringband tutorial.dxf'))
    msp = doc.modelspace()
    xs, ys = [], []
    for e in msp.query('LINE'):
        xs += [e.dxf.start.x, e.dxf.end.x]; ys += [e.dxf.start.y, e.dxf.end.y]
    x0, x1, y0, y1 = min(xs)-1, max(xs)+1, min(ys)-1, max(ys)+1
    def F(y): return (y1+y0) - y   # DXF is y-up; SVG is y-down
    el = []
    for e in msp.query('LINE'):
        a, b = e.dxf.start, e.dxf.end
        el.append(f'<line x1="{a.x:.3f}" y1="{F(a.y):.3f}" x2="{b.x:.3f}" y2="{F(b.y):.3f}"/>')
    tx = []
    for e in msp.query('TEXT'):
        d = e.dxf
        tx.append(f'<text x="{d.insert.x:.2f}" y="{F(d.insert.y):.2f}" font-size="{d.height:.2f}">{e.dxf.text}</text>')
    dxf_section = f'''
<h2>Érard original — rendered from the DXF</h2>
<p class="sub">Parsed with ezdxf from <code>erard original stringband tutorial.dxf</code>
({len(el)} lines, {len(tx)} labels; units inches, y-flipped for SVG). Note the real band uses
<b>variable string spacing</b> — 13.325 mm in the treble opening to 17.94 mm at the bass, ratio 1.025 —
where the true-scale drawing above uses a uniform 15 mm pitch; string angle 32°, soundboard 52.81 in.</p>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="{x0:.1f} {y0:.1f} {x1-x0:.1f} {y1-y0:.1f}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erard string band drawing from DXF">
<g stroke="#3b3e44" stroke-width="0.045" fill="none">{''.join(el)}</g>
<g fill="#7a5a2a" font-family="ui-monospace,Menlo,Consolas,monospace">{''.join(tx)}</g>
</svg></div>
'''
except Exception as ex:
    dxf_section = f'<p class="sub">(DXF section skipped: {ex})</p>'

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
<h1>ERAND49 — STRING BAND, TRUE SCALE</h1>
<p class="sub">Erard tutorial stringing (47 strings, g7→c1). Drawing units are millimetres: string lengths
and <b>line widths are the same scale — each stroke width is the string's actual overall diameter</b>
(0.64 mm nylon treble to 2.64 mm wrapped bass). Colors per harp convention:
<span class="leg" style="color:#c0392b">C strings red</span> ·
<span class="leg" style="color:#2e5fa3">F strings blue</span> · others dark gray.
Hover any string for its full spec. b0/a0 dashed: Erand49 spans 49 strings but the tutorial specs 47 —
the two lowest await extrapolation (Gate 2).</p>

<h2>String band — lengths and diameters to one scale</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="0 0 {W:.0f} 1650" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Erand49 string band, true scale">
<style>.nl{{font-size:13px;font-weight:700;font-family:ui-monospace,Menlo,Consolas,monospace}}.an{{font-size:15px;fill:#333;font-family:ui-monospace,Menlo,Consolas,monospace}}</style>
<polyline points="{neck}" fill="none" stroke="#7a5a2a" stroke-width="10" stroke-linecap="round" opacity="0.6"/>
<rect x="{X0-25:.0f}" y="{YRIB:.0f}" width="{W-2*(X0-25):.0f}" height="26" rx="6" fill="#a8700f" fill-opacity="0.35" stroke="#7a5a2a" stroke-width="1.5"/>
<text x="{X0-10:.0f}" y="{YRIB+60:.0f}" class="an">rib — 49 sensor pairs, one per string anchor</text>
<text x="{W-40:.0f}" y="{YRIB-1560:.0f}" class="an" text-anchor="end">neck profile = envelope of speaking lengths</text>
{chr(10).join(band)}
</svg></div>

<h2>Cross sections — diameters at 10×</h2>
<div class="wrap"><svg style="width:100%;height:auto;display:block" viewBox="0 0 {W:.0f} 110" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="String cross sections at 10x">
<text x="{X0-10:.0f}" y="100" class="an" style="font-size:15px">plain nylon → nylon-wrapped → bronze-wound steel; the step at #28 (a3) and #39 (d2) is the winding starting</text>
{chr(10).join(xsec)}
</svg></div>

{dxf_section}
<p class="sub">Source: <code>string-specs.md</code> (imperial + metric) and
<code>erard original stringband tutorial.dxf</code>. Regenerate: <code>python3 gen_erand49.py</code>.
Band tension 1465.5 lbf ≈ 6.52 kN excluding b0/a0. Speaking-length scale honest to the drawing;
string spacing drawn at 15 mm pitch.</p>
</main></body></html>
'''
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Erand49.html')
open(out,'w').write(html)
print('wrote', out)
