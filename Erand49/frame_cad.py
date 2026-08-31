# Erand49 frame in build123d — the parametric source of truth.
# Model space: X along the band (bass -> treble), Y across the plates, Z up, floor at Z=0.
# Geometry parameters come from gen_erand49.py (DXF-derived); the neck plate profile
# comes from the hand-edited curves in Erand49.svg. Run:
#   LD_LIBRARY_PATH=$HOME/miniconda3/lib python3 frame_cad.py
# Outputs: frame.step, cad-front.svg, cad-side.svg, cad-top.svg
import os, re, math
from build123d import *

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- parameters from the generator (single source of truth) ----
ns = {'__file__': os.path.join(HERE, 'gen_erand49.py')}
exec(open(os.path.join(HERE, 'gen_erand49.py')).read(), ns)
IN = ns['IN']
m_slope, cxi = ns['m'], ns['cxi']          # anchor line (z per x), inches
pilc, PW, MHW = ns['pilc'], ns['PW'], ns['MHW']
y_floor, y_crown, xr_m = ns['y_floor'], ns['y_crown'], ns['xr_m']
y1 = ns['y1']                              # svg y-mapping constant (mm)
ZF = y_floor * IN                          # floor height in the v-coordinate, mm

def sv(sx, sy):
    "svg (x,y) mm -> model (x,z) mm, floor at z=0"
    return (sx, (y1 - sy) - ZF)

# ---- sections/sizes (frame-spec.md) ----
WEB_W   = 2.5 * IN      # 63.5  channel width (Y)
DEPTH   = 4.0 * IN      # 101.6 channel depth (in the string plane)
WALL    = 3/16 * IN     # 4.76
PLATE_T = 8.0
PIL_OD  = 2.0 * IN      # 50.8
PIL_WALL = 3/16 * IN
GAP     = WEB_W         # plate inner faces at +/-31.75

# ---- midrib channel (open bottom), along the anchor-line axis ----
h = math.hypot(1, m_slope)
u = (1/h, m_slope/h)                        # axis unit in XZ (toward treble/shoulder)
n = (-m_slope/h, 1/h)                       # unit normal (toward the strings)
# base point: on the centerline (web top is +0 offset -> centerline is web; the section
# is built with the web top ON the anchor line, body hanging below)
x_base_in = pilc - PW/ h - 2.0              # start beyond the pillar toward the floor
P0 = ((x_base_in) * IN, (m_slope * x_base_in + cxi - y_floor) * IN)
L_axis = (xr_m - x_base_in) * h * IN        # generous; floor/end cuts trim it

sec_plane = Plane(origin=(P0[0], 0, P0[1]), x_dir=(0, 1, 0), z_dir=(u[0], 0, u[1]))
with BuildPart() as midrib_bp:
    with BuildSketch(sec_plane):
        # local x = global Y, local y = -n direction (into the body below the web)
        # datum: the web TOP sits ON the anchor line (local y=0), body hangs below
        with Locations((0, -WALL/2)):
            Rectangle(WEB_W, WALL)                        # web (top face)
        with Locations((-(WEB_W - WALL)/2, -DEPTH/2), ((WEB_W - WALL)/2, -DEPTH/2)):
            Rectangle(WALL, DEPTH)                        # side walls
    extrude(amount=L_axis)
midrib = midrib_bp.part
# orient: the sketch's local +y ran along -n? Fix orientation by construction check below.

# floor cut: keep z >= 0
big = 10000
midrib = midrib & Box(big, big, big, align=(Align.CENTER, Align.CENTER, Align.MIN))
# shoulder end cut: plane perpendicular to the axis at xr_m (through the anchor line point)
Pend = (xr_m * IN, (m_slope * xr_m + cxi - y_floor) * IN)
end_cut = Plane(origin=(Pend[0], 0, Pend[1]), z_dir=(u[0], 0, u[1]))
midrib = split(midrib, bisect_by=end_cut, keep=Keep.BOTTOM)

# ---- pillar (round tube) with the web hole made honestly by boolean ----
crownZ = (y_crown - y_floor) * IN
pillar = Cylinder(PIL_OD/2, crownZ, align=(Align.CENTER, Align.CENTER, Align.MIN)) \
       - Cylinder(PIL_OD/2 - PIL_WALL, crownZ, align=(Align.CENTER, Align.CENTER, Align.MIN))
pillar = Pos(pilc * IN, 0, 0) * pillar
# the pillar clearance hole through the midrib web (0.5 mm radial clearance)
midrib = midrib - Pos(pilc * IN, 0, 0) * Cylinder(PIL_OD/2 + 0.5, crownZ,
                                                  align=(Align.CENTER, Align.CENTER, Align.MIN))

# ---- neck plates from the hand-edited curves ----
svg = open(os.path.join(HERE, 'Erand49.svg')).read()
def path_d(colorhex):
    for p in re.findall(r'<path[^>]*>', svg, re.S):
        if colorhex in p:
            return re.search(r'\bd="([^"]+)"', p).group(1)
def cubics(dstr):
    toks = re.findall(r'[mMcClLzZ]|-?\d+\.?\d*(?:e-?\d+)?', dstr)
    i = 0; cur = (0, 0); segs = []; cmd = None
    def f():
        nonlocal i; v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if toks[i] in 'mMcClLzZ': cmd = toks[i]; i += 1
        if cmd in 'mM':
            x, y = f(), f(); cur = (x, y) if cmd == 'M' else (cur[0]+x, cur[1]+y)
            cmd = 'l' if cmd == 'm' else 'L'
        elif cmd in 'cC':
            while i < len(toks) and toks[i] not in 'mMcClLzZ':
                v = [f() for _ in range(6)]
                if cmd == 'c':
                    c1 = (cur[0]+v[0], cur[1]+v[1]); c2 = (cur[0]+v[2], cur[1]+v[3]); e = (cur[0]+v[4], cur[1]+v[5])
                else:
                    c1, c2, e = (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
                segs.append((cur, c1, c2, e)); cur = e
        elif cmd in 'lL':
            while i < len(toks) and toks[i] not in 'mMcClLzZ':
                x, y = f(), f(); e = (x, y) if cmd == 'L' else (cur[0]+x, cur[1]+y)
                segs.append((cur, cur, e, e)); cur = e
        else:
            i += 1
    return segs
tuner_c = cubics(path_d('2e7d32'))
sense_c = cubics(path_d('66bb6a'))
t_end = tuner_c[-1][3]                     # on the band bottom edge
s_end = sense_c[-1][3]                     # on the channel top (shoulder corner)
t_start, s_start = tuner_c[0][0], sense_c[0][0]
# shoulder closing per the agreed joint: bottom edge -> weld corner -> weld line -> corner
edge_pt = lambda x: (x, 417.7 - 1.61*(x - 1042))    # svg coords of the band bottom edge
weld_y = 429.7
x_weld_end = 1042 - (weld_y - 417.7)/1.61 * -1 if False else 1042 - 12/1.61
close_pts = [t_end, edge_pt(x_weld_end), (990.0, weld_y), s_end]

with BuildPart() as plate_bp:
    with BuildSketch(Plane.XZ):
        with BuildLine():
            for a, c1, c2, b in tuner_c:
                Bezier(sv(*a), sv(*c1), sv(*c2), sv(*b))
            pl = [sv(*p) for p in close_pts]
            Polyline(*pl)
            for a, c1, c2, b in reversed(sense_c):
                Bezier(sv(*b), sv(*c2), sv(*c1), sv(*a))
            Line(sv(*s_start), sv(*t_start))
        make_face()
    extrude(amount=PLATE_T)
plate = plate_bp.part
plates = Pos(0, GAP/2 + PLATE_T, 0) * plate + Pos(0, -GAP/2, 0) * plate
# note: Plane.XZ extrudes toward -Y in build123d; positions may need sign fixes on first run

assembly = Compound(children=[
    copy_it := midrib, pillar, plates
]) if False else Compound([midrib, pillar, plates])

export_step(assembly, os.path.join(HERE, 'frame.step'))
print('frame.step written')

# ---- projected views with hidden-line removal (ISO 128 line conventions) ----
def view(shape, name, origin, up=(0, 0, 1)):
    visible, hidden = shape.project_to_viewport(origin, viewport_up=up)
    mx = max(*Compound(visible + hidden).bounding_box().size)
    exp = ExportSVG(scale=1.0)
    exp.add_layer('visible', line_weight=0.5)
    exp.add_layer('hidden', line_weight=0.25, line_type=LineType.HIDDEN)
    exp.add_shape(visible, layer='visible')
    if hidden:
        exp.add_shape(hidden, layer='hidden')
    out = os.path.join(HERE, name)
    exp.write(out)
    print('wrote', name)

bb = assembly.bounding_box()
cx, cy, cz = bb.center().X, bb.center().Y, bb.center().Z
view(assembly, 'cad-front.svg', (cx, -8000, cz))            # front: looking along +Y
view(assembly, 'cad-side.svg',  (12000, cy, cz))            # side: along -X
view(assembly, 'cad-top.svg',   (cx, cy, 12000))            # top: along -Z
print('bbox size (mm):', bb.size)
