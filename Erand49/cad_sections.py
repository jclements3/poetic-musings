# CAD-derived section views for the ER sheets — sliced from frame.step, not hand-drawn.
# Run: LD_LIBRARY_PATH=$HOME/miniconda3/lib python3 cad_sections.py
# Outputs: cad-sec-midrib.svg (⊥ member, mid-span), cad-sec-pillar.svg (horizontal),
#          cad-sec-neckstack.svg (vertical YZ at the shoulder lap: plates + channel)
import os, math
from build123d import *

HERE = os.path.dirname(os.path.abspath(__file__))
ns = {'__file__': os.path.join(HERE, 'gen_erand49.py')}
exec(open(os.path.join(HERE, 'gen_erand49.py')).read(), ns)
IN, m_slope, cxi = ns['IN'], ns['m'], ns['cxi']
pilc, y_floor = ns['pilc'], ns['y_floor']
xr_m = ns['xr_m']

asm = import_step(os.path.join(HERE, 'frame.step'))
T = 0.6   # slab thickness for sections, mm

def export_edges(shape, name, origin, up=(0, 0, 1)):
    visible, hidden = shape.project_to_viewport(origin, viewport_up=up)
    exp = ExportSVG(scale=1.0)
    exp.add_layer('cut', line_weight=0.35)
    exp.add_shape(visible, layer='cut')
    exp.write(os.path.join(HERE, name))
    print('wrote', name)

h = math.hypot(1, m_slope)
u = (1/h, m_slope/h)

# ER-003 CAD: midrib section perpendicular to the member at mid-span
x_mid = (pilc + xr_m) / 2
Pm = (x_mid*IN, (m_slope*x_mid + cxi - y_floor)*IN - 50)   # around the member center
slab = Plane(origin=(Pm[0], 0, Pm[1]), z_dir=(u[0], 0, u[1])) * Box(300, 300, T)
sec = asm & slab
export_edges(sec, 'cad-sec-midrib.svg', (Pm[0] + 3000*u[0], 0, Pm[1] + 3000*u[1]))

# ER-002 CAD: pillar horizontal section at half height
zc = 800
slab2 = Pos(pilc*IN, 0, zc) * Box(200, 200, T)
sec2 = asm & slab2
export_edges(sec2, 'cad-sec-pillar.svg', (pilc*IN, 0, zc + 3000))

# ER-001/ER-005 CAD: vertical YZ slice through the shoulder lap (plates + channel together)
x_lap = (xr_m - 0.75) * IN
slab3 = Pos(x_lap, 0, 900) * Box(T, 300, 1800)
sec3 = asm & slab3
export_edges(sec3, 'cad-sec-neckstack.svg', (x_lap + 3000, 0, 900))

# Crown plan (JC): horizontal slice just below the pillar top — the pillar
# tube between the two neck plates, showing the 6.35 mm side gaps that the
# crown joint (saddle/spacer, TBD) must close
import re as _re
_svg = open(os.path.join(HERE, 'Erand49.svg')).read()
_p = [x for x in _re.findall(r'<path[^>]*>', _svg, _re.S) if '2e7d32' in x][0]
_m = _re.search(r'\bd="[Mm]\s*([\d.eE+-]+)[, ]([\d.eE+-]+)', _p)
_y_start = float(_m.group(2))                      # plate top corner, svg mm
z_cr = ns['y1'] - _y_start - y_floor * IN - 25     # mid-collar / bolt zone
slab4 = Pos(pilc*IN, 0, z_cr) * Box(150, 110, T)   # tight crop: mm gaps visible
sec4 = asm & slab4
export_edges(sec4, 'cad-sec-crown.svg', (pilc*IN, 0, z_cr + 3000))

# annotate the joint gaps on the crown plan (root-gap detail, JC)
import re as _re2
_doc = open(os.path.join(HERE, 'cad-sec-crown.svg')).read()
_best, _cx, _cy = 0, 0, 0
for _d in _re2.findall(r'<path[^>]*d="([^"]+)"', _doc):
    _pts = [(float(a), float(b)) for a, b in _re2.findall(r'(-?\d+\.?\d*)[, ](-?\d+\.?\d*)', _d)]
    if not _pts: continue
    _xs = [p[0] for p in _pts]; _ys = [p[1] for p in _pts]
    _w = max(_xs) - min(_xs)
    if abs(_w - 50.8) < 0.5 and _w > _best:
        _best, _cx, _cy = _w, (min(_xs)+max(_xs))/2, (min(_ys)+max(_ys))/2
assert _best, 'tube circle not found in crown slice'
_ann = f'''<g font-family="ui-monospace,Consolas,monospace" font-size="4.2" fill="#3b5a7a" stroke="none">
<line x1="{_cx+8:.1f}" y1="{_cy+26.2:.1f}" x2="{_cx+34:.1f}" y2="{_cy+40:.1f}" stroke="#3b5a7a" stroke-width="0.3"/>
<text x="{_cx+35:.1f}" y="{_cy+41.5:.1f}">1.5 root gap, weld both verticals</text>
<line x1="{_cx+26.2:.1f}" y1="{_cy-6:.1f}" x2="{_cx+44:.1f}" y2="{_cy-16:.1f}" stroke="#3b5a7a" stroke-width="0.3"/>
<text x="{_cx+45:.1f}" y="{_cy-15:.1f}">1.6/side</text>
<text x="{_cx-12:.1f}" y="{_cy-30:.1f}">&#216;50.8</text>
</g>'''
_mvb = _re2.search(r'viewBox="([-\d. ]+)"', _doc)
_vx, _vy, _vw, _vh = map(float, _mvb.group(1).split())
_x1 = max(_vx + _vw, _cx + 110); _y1 = max(_vy + _vh, _cy + 46)
_doc = _doc.replace(_mvb.group(0), f'viewBox="{_vx:.1f} {_vy:.1f} {_x1-_vx:.1f} {_y1-_vy:.1f}"')
_doc = _re2.sub(r'width="[-\d.]+mm" height="[-\d.]+mm"',
                f'width="{_x1-_vx:.1f}mm" height="{_y1-_vy:.1f}mm"', _doc, count=1)
_doc = _doc.replace('</svg>', _ann + '</svg>')
open(os.path.join(HERE, 'cad-sec-crown.svg'), 'w').write(_doc)
print('crown plan annotated with the gap detail')
print('done')
