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
print('done')
