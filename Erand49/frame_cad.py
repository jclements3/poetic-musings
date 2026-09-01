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

# ---- side-wall depth taper (gen_erand49.py taper_depth is the source of truth) ----
taper_depth = ns['taper_depth']
T0X_in, XR_in = ns['T0X'], ns['xr_m']
h2 = math.hypot(1, m_slope)
nrm = (-m_slope/h2, 1/h2)
def edge_pt_model(t_in, depth_in):
    x = (t_in - nrm[0]*0 ) * IN  # param t is x-position (inches)
    px = (t_in + (-m_slope/h2) * (-depth_in)) * IN
    pz = (m_slope*t_in + cxi + (1/h2) * (-depth_in) - y_floor) * IN
    return (px, pz)
cut_pts = []
ts = [T0X_in + k*(XR_in - T0X_in)/60 for k in range(61)]
for t in ts:
    cut_pts.append(edge_pt_model(t, taper_depth(t)))
for t in reversed(ts):
    cut_pts.append(edge_pt_model(t, 4.3))          # below the full-depth edge
with BuildPart() as taper_bp:
    with BuildSketch(Plane.XZ):
        with BuildLine():
            Polyline(*(cut_pts + [cut_pts[0]]))
        make_face()
    extrude(amount=200, both=True)
midrib = midrib - taper_bp.part
print('side-wall taper applied (4 -> 2.25 in at the shoulder)')

# analytic stress/deflection along the tapered member (walls dominate I)
WALLt = 3/16*IN
Lspan = (XR_in - T0X_in) * math.hypot(1, m_slope) * IN / 1000.0   # m, along axis
qload = 3700.0 / Lspan                                            # N/m transverse
Emod = 69e9
xsN = 200
worst = (0, 0)
integ = 0.0
for k in range(1, xsN):
    xi = k / xsN
    Mx = qload * (xi*Lspan) * (Lspan - xi*Lspan) / 2
    d_mm = taper_depth(T0X_in + xi*(XR_in - T0X_in)) * IN
    I_mm4 = 2 * (WALLt * d_mm**3 / 12) + (63.5 * 4.76**3/12 + 63.5*4.76*(d_mm/2)**2*0)
    S_mm3 = I_mm4 / (d_mm/2)
    sig = Mx*1000 / S_mm3
    if sig > worst[0]:
        worst = (sig, xi)
print(f"tapered-midrib max bending stress {worst[0]:.1f} MPa at xi={worst[1]:.2f} (allow 138 parent)")

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
edge_pt = lambda x: (x, 410.5669 + 1.600300*(1106.8856 - x))   # REAL band bottom edge (from mp)
weld_y = 429.7
x_weld_end = 1094.9296
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

# ---- 49 optical sensor stations: 60-deg beam pairs with PER-STATION YAW ----
# Sensor points sit near the plate's downhill edge, so a symmetric pair exits the
# outline on 19 stations. Fix: yaw each pair (psi) so both bores center in the
# locally available plate span; the pair stays 60 deg apart (independent X/Y via a
# per-string 2x2 calibration done at CAL). Optics mount on a PCB strip, so the
# per-station angle costs nothing mechanically.
sense_pts = [sv(px, py) for (px, py) in ns['sense_px']]
# plate boundary polygon (model XZ) sampled from the same curves used for the face
def _samp(segs):
    pts = []
    for a, c1, c2, b in segs:
        for k in range(0, 40):
            t = k/39; mt = 1-t
            x = mt**3*a[0]+3*mt*mt*t*c1[0]+3*mt*t*t*c2[0]+t**3*b[0]
            y = mt**3*a[1]+3*mt*mt*t*c1[1]+3*mt*t*t*c2[1]+t**3*b[1]
            pts.append(sv(x, y))
    return pts
poly = _samp(tuner_c) + [sv(*p) for p in close_pts] + _samp(sense_c)[::-1]
def x_interval(z, near_x=None):
    xs = []
    n = len(poly)
    for i in range(n):
        (x1, z1), (x2, z2) = poly[i], poly[(i+1) % n]
        if (z1 - z) * (z2 - z) <= 0 and z1 != z2:
            xs.append(x1 + (z - z1)/(z2 - z1)*(x2 - x1))
    xs.sort()
    ivs = [(xs[i], xs[i+1]) for i in range(0, len(xs)-1, 2)]
    if not ivs:
        return (0, 0)
    if near_x is None:
        return max(ivs, key=lambda iv: iv[1]-iv[0])
    inside = [iv for iv in ivs if iv[0] <= near_x <= iv[1]]
    if inside:
        return inside[0]
    return min(ivs, key=lambda iv: min(abs(near_x-iv[0]), abs(near_x-iv[1])))
YMID = GAP/2 + PLATE_T/2                     # 35.75
MARGIN = 1.6 + 5.0
beams = []
stations = []                                 # (idx, sx, sz, psi, sep) for the PCB table
misses = []
for idx, (sx, sz) in enumerate(sense_pts, 1):
    lo, hi = x_interval(sz, sx)
    lo += MARGIN; hi -= MARGIN
    found = None
    for sep in (60, 55, 50, 45, 40, 35, 30):  # pair separation, degrees; shrink only if the plate is tight
        half = sep / 2
        for step in range(0, 121):
            for sgn in ((1,) if step == 0 else (1, -1)):
                psi = sgn * step * 0.5
                a = YMID * math.tan(math.radians(psi + half))
                b = YMID * math.tan(math.radians(psi - half))
                if lo <= sx + min(a, b) and sx + max(a, b) <= hi:
                    found = (psi, sep)
                    break
            if found: break
        if found: break
    if not found:
        misses.append(idx)
        found = (0.0, 60)
    psi, sep = found
    stations.append((idx, sx, sz, psi, sep))
    for ang in (psi + sep/2, psi - sep/2):
        beams.append(Pos(sx, 0, sz) * Rot(0, 0, ang) * Rot(-90, 0, 0) * Cylinder(1.6, 130))
narrow = [(i, sep) for i, _, _, _, sep in stations if sep < 60]
print(f"pair separations: {len(stations)-len(narrow)} stations at 60 deg; narrowed: {narrow}")
print("bore landing:", "ALL 49 STATIONS FIT" if not misses else f"STILL MISSING: {misses}")
for i in (misses or [])[:6]:
    sx, sz = sense_pts[i-1]
    print(f"   station {i}: z={sz:.1f} span={x_interval(sz, sx)} sx={sx:.1f}")
with open(os.path.join(HERE, 'sensor-stations.csv'), 'w') as f:
    f.write("station,x_mm,z_mm,pair_yaw_deg,pair_separation_deg,bore_dia_mm\n")
    for idx, sx, sz, psi, sep in stations:
        f.write(f"{idx},{sx:.2f},{sz:.2f},{psi:.1f},{sep},3.2\n")
print("wrote sensor-stations.csv (PCB placement table)")
plates = plates.cut(*beams)
print("sensor beam bores drilled")

# note: Plane.XZ extrudes toward -Y in build123d; positions may need sign fixes on first run

# ---- ER-006 hinged outrigger legs, modeled DEPLOYED (the standing configuration) ----
# Two 1" x 1/8" 6061 flat-bar legs, one per midrib side wall, near the floor foot.
# Hinge: shoulder bolt per side — Ø10 h8 ground shoulder (M8 thread), leg eye and
# boss bored Ø10.1 (running fit on the shoulder), thread passing through a Ø8.4
# clearance hole in the side wall (ISO 273 medium fit for M8) into a flanged nut
# inside the open channel. A single coaxial Ø8.4 cut makes both wall holes.
LEG_W, LEG_T = 1.0 * IN, 0.125 * IN     # flat bar 25.4 x 3.175
LEG_L = 325.0                           # bar length hinge-eye -> foot end (295 was the
                                        # spec estimate; the measured CoM height 1088 mm
                                        # needs 325 to clear the 15 deg sideways tip)
LEG_ANG = 55.0                          # deployed angle from vertical, in the YZ plane
LEG_TAIL = 6.0                          # bar continues past the hinge eye (boss cover)
BOSS_D, BOSS_L = 22.0, 6.0              # hinge boss Ø and wall stand-off
BOLT_SHOULDER_D, BOLT_THREAD_CLR = 10.1, 8.4
PAD_D, PAD_H = 32.0, 8.0                # rubber foot pads (cylinders)
PAD_CLR = 1.0                           # bar end floats this far above the pad top

sa, ca = math.sin(math.radians(LEG_ANG)), math.cos(math.radians(LEG_ANG))
z_h = PAD_H + PAD_CLR + LEG_L * ca                       # hinge height so the pad lands on the floor
drop = DEPTH / h                                         # vertical height of the sloped side wall band
# hinge at mid-depth of the side wall: anchor_z(x) - drop/2 = z_h
x_h = (((z_h + drop / 2) / IN) - (cxi - y_floor)) / m_slope * IN   # mm
wall_top_z = (m_slope * (x_h / IN) + cxi - y_floor) * IN
assert wall_top_z - drop + BOSS_D / 2 < z_h < wall_top_z - BOSS_D / 2, "hinge boss must land on the side wall"
y_wall = WEB_W / 2                                       # side wall outer face
y_bar = y_wall + BOSS_L + LEG_T / 2                      # bar mid-plane stand-off

legs_parts, pads_parts = [], []
for sgn in (1, -1):
    d = (0, sgn * sa, -ca)                               # deployed leg direction, hinge -> foot
    p0 = (x_h, sgn * y_bar - d[1] * LEG_TAIL, z_h - d[2] * LEG_TAIL)
    with BuildPart() as leg_bp:
        with BuildSketch(Plane(origin=p0, x_dir=(1, 0, 0), z_dir=d)):
            Rectangle(LEG_W, LEG_T)
        extrude(amount=LEG_L + LEG_TAIL)
    boss = Pos(x_h, sgn * (y_wall + (BOSS_L + LEG_T) / 2), z_h) * Rot(90, 0, 0) * \
        Cylinder(BOSS_D / 2, BOSS_L + LEG_T)
    leg = leg_bp.part + boss
    leg -= Pos(x_h, sgn * y_bar, z_h) * Rot(90, 0, 0) * Cylinder(BOLT_SHOULDER_D / 2, 60)
    legs_parts.append(leg)
    foot_y = sgn * y_bar + d[1] * LEG_L                  # bar end centerline at the floor
    pads_parts.append(Pos(x_h, foot_y, 0) * Cylinder(PAD_D / 2, PAD_H,
                                                     align=(Align.CENTER, Align.CENTER, Align.MIN)))
legs = legs_parts[0] + legs_parts[1]
pads = pads_parts[0] + pads_parts[1]
# hinge clearance holes through BOTH side walls (one coaxial cut)
midrib = midrib - Pos(x_h, 0, z_h) * Rot(90, 0, 0) * Cylinder(BOLT_THREAD_CLR / 2, 2 * WEB_W)
print(f"ER-006 legs: hinge at x={x_h:.1f} z={z_h:.1f} mm, wall holes O{BOLT_THREAD_CLR} "
      f"(M8 shoulder bolt, O10 shoulder in O{BOLT_SHOULDER_D} leg bore), deployed {LEG_ANG:.0f} deg")

assembly = Compound([midrib, pillar, plates, legs, pads])

export_step(assembly, os.path.join(HERE, 'frame.step'))
print('frame.step written')

# ---- stability check from the solids (strings and plinth EXCLUDED) ----
DENS_AL = 2700e-9    # kg/mm^3, 6061 — frame, plates, legs
DENS_RUB = 1200e-9   # kg/mm^3, rubber pads
mass_items = [('midrib', midrib, DENS_AL), ('pillar', pillar, DENS_AL),
              ('plates', plates, DENS_AL), ('legs', legs, DENS_AL), ('pads', pads, DENS_RUB)]
M = Vector(0, 0, 0)
m_tot = 0.0
for nm, sh, rho in mass_items:
    mi = sh.volume * rho
    ci = sh.center(CenterOf.MASS)
    M += ci * mi
    m_tot += mi
    print(f"  {nm:7s} {mi:6.3f} kg  CoM ({ci.X:7.1f},{ci.Y:6.1f},{ci.Z:7.1f})")
com = M / m_tot
print(f"assembly mass {m_tot:.2f} kg (Al 2700, pads 1200 kg/m3; strings/plinth excluded)")
print(f"assembly CoM  x={com.X:.1f}  y={com.Y:.1f}  z={com.Z:.1f} mm  (CoM height {com.Z:.0f} mm)")

# support polygon: pillar foot + midrib floor foot + the two leg pads, from the solids
floor_slab = Box(6000, 3000, 1.5, align=(Align.CENTER, Align.CENTER, Align.MIN))
def circle_pts(bb2, n_=24):
    cx_, cy_, r_ = bb2.center().X, bb2.center().Y, max(bb2.size.X, bb2.size.Y) / 2
    return [(cx_ + r_ * math.cos(2 * math.pi * k / n_), cy_ + r_ * math.sin(2 * math.pi * k / n_))
            for k in range(n_)]
pil_f = (pillar & floor_slab).bounding_box()
mid_f = (midrib & floor_slab).bounding_box()
pad_bbs = [p.bounding_box() for p in pads_parts]
support = circle_pts(pil_f) \
    + [(mid_f.min.X, mid_f.min.Y), (mid_f.min.X, mid_f.max.Y),
       (mid_f.max.X, mid_f.max.Y), (mid_f.max.X, mid_f.min.Y)] \
    + sum((circle_pts(b) for b in pad_bbs), [])

def hull2d(pts):
    pts = sorted(set((round(x, 3), round(y, 3)) for x, y in pts))
    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and ((out[-1][0]-out[-2][0])*(p[1]-out[-2][1])
                                     - (out[-1][1]-out[-2][1])*(p[0]-out[-2][0])) <= 0:
                out.pop()
            out.append(p)
        return out
    lo, hi = half(pts), half(pts[::-1])
    return lo[:-1] + hi[:-1]           # CCW

hull = hull2d(support)
def edge_tip(P, Q):
    "tip angle (deg) rotating over hull edge P->Q; negative = CoM already outside"
    dx, dy = Q[0]-P[0], Q[1]-P[1]
    ln = math.hypot(dx, dy)
    nx, ny = dy/ln, -dx/ln                       # outward normal of the CCW hull
    s = (com.X-P[0])*nx + (com.Y-P[1])*ny        # >0 means outside
    return math.degrees(math.atan2(-s, com.Z)), (nx, ny)
edge_info = [(edge_tip(hull[i], hull[(i+1) % len(hull)]), hull[i], hull[(i+1) % len(hull)])
             for i in range(len(hull))]

# task metrics: sideways over a leg-pad line (parallel to X through a pad center),
# forward/back over the feet lines (parallel to Y through the extreme supports)
stance = pad_bbs[0].center().Y - pad_bbs[1].center().Y
tip_side = math.degrees(math.atan2(abs(stance) / 2 - abs(com.Y), com.Z))
x_support_max = max(p[0] for p in support)
x_support_min = min(p[0] for p in support)
tip_fwd = math.degrees(math.atan2(x_support_max - com.X, com.Z))
tip_back = math.degrees(math.atan2(com.X - x_support_min, com.Z))
print(f"support polygon x [{x_support_min:.0f}..{x_support_max:.0f}]  leg stance {abs(stance):.0f} mm "
      f"(pad centers), hull-edge tip angles: "
      + ", ".join(f"{deg:+.1f}" for (deg, _), _, _ in edge_info) + " deg")
print(f"tip angles: sideways {tip_side:.1f} deg over a leg-pad line | "
      f"forward {tip_fwd:.1f} deg | back {tip_back:.1f} deg over the feet lines")
if tip_fwd < 0:
    print("NOTE: CoM sits treble-ward of every floor support — fore-aft the harp relies on"
          " the plinth dock (excluded here); the legs solve the sideways (Y) footprint.")
assert tip_side >= 15.0, f"sideways tip angle {tip_side:.1f} < 15 deg — widen the leg stance"

# ---- projected views with hidden-line removal (ISO 128 line conventions) ----
def view(shape, name, origin, up=(0, 0, 1)):
    visible, hidden = shape.project_to_viewport(origin, viewport_up=up)
    exp = ExportSVG(scale=1.0)
    exp.add_layer('visible', line_weight=0.5)
    exp.add_layer('hidden', line_weight=0.25, line_type=LineType.HIDDEN)
    exp.add_shape(visible, layer='visible')
    if hidden:
        exp.add_shape(hidden, layer='hidden')
    out = os.path.join(HERE, name)
    exp.write(out)
    print('wrote', name)
    return Compound(visible + hidden).bounding_box()        # projected (viewport) bbox

bb = assembly.bounding_box()
cx, cy, cz = bb.center().X, bb.center().Y, bb.center().Z
pbb_front = view(assembly, 'cad-front.svg', (cx, -8000, cz))   # front: looking along +Y
pbb_side = view(assembly, 'cad-side.svg',  (12000, cy, cz))    # side: along -X
view(assembly, 'cad-top.svg',   (cx, cy, 12000))               # top: along -Z
print('bbox size (mm):', bb.size)

# ---- ISO-129-style dimension layer, post-processed into the projected SVGs ----
# The projections above are PARALLEL projections whose viewport axes align with the
# model axes (front: x<-X y<-Z; side: x<-Y y<-Z) — asserted below by matching the
# projected bbox extents against the model bbox. We derive the exact viewport
# translation from that pair, then append a separate <g id="dimensions"> group
# (extension lines, filled arrowheads, mm text) to the SVG file, expanding its
# viewBox to fit. Every dimension VALUE is measured from the solids (bounding
# boxes / thin-slab sections) — nothing is hardcoded.
DIM_C = '#3b5a7a'
ARROW_L, ARROW_W = 12.0, 4.2
EXT_GAP, EXT_OVER, TEXT_H = 5.0, 8.0, 30.0

class DimLayer:
    def __init__(self):
        self.el, self.xs, self.ys = [], [], []
    def _track(self, x, y):
        self.xs.append(x); self.ys.append(y)
    def _arrow(self, tip, dirc):
        (tx, ty), (dx, dy) = tip, dirc                    # dirc: unit, points INTO the line
        px, py = -dy, dx
        b1 = (tx + dx*ARROW_L + px*ARROW_W, ty + dy*ARROW_L + py*ARROW_W)
        b2 = (tx + dx*ARROW_L - px*ARROW_W, ty + dy*ARROW_L - py*ARROW_W)
        self.el.append(f'<path d="M {tx:.2f} {ty:.2f} L {b1[0]:.2f} {b1[1]:.2f} '
                       f'L {b2[0]:.2f} {b2[1]:.2f} Z" fill="{DIM_C}" stroke="none"/>')
        for x, y in (tip, b1, b2):
            self._track(x, y)
    def text(self, pos, label, ang=0.0, anchor='middle'):
        x, y = pos
        rot = f' transform="rotate({ang:.1f} {x:.2f} {y:.2f})"' if abs(ang) > 0.01 else ''
        self.el.append(f'<text x="{x:.2f}" y="{y:.2f}" font-size="{TEXT_H}" fill="{DIM_C}" '
                       f'text-anchor="{anchor}" font-family="ui-monospace,Consolas,monospace"'
                       f'{rot}>{label}</text>')
        w = 0.62 * TEXT_H * len(label)
        c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        for ddx in (-w/2, w/2):                 # text bbox corners, rotated
            for ddy in (-TEXT_H, TEXT_H * 0.4):
                self._track(x + ddx*c - ddy*s, y + ddx*s + ddy*c)
    def linear(self, fa, fb, A, B, label, text_pos=None, text_anchor='middle'):
        "extension lines fa->A, fb->B; dimension line A-B with arrows; label in mm"
        for (px, py), (qx, qy) in ((fa, A), (fb, B)):
            ln = math.hypot(qx-px, qy-py)
            if ln > EXT_GAP:
                ux, uy = (qx-px)/ln, (qy-py)/ln
                self.el.append(f'<line x1="{px+ux*EXT_GAP:.2f}" y1="{py+uy*EXT_GAP:.2f}" '
                               f'x2="{qx+ux*EXT_OVER:.2f}" y2="{qy+uy*EXT_OVER:.2f}" '
                               f'stroke="{DIM_C}" stroke-width="0.7"/>')
                self._track(qx+ux*EXT_OVER, qy+uy*EXT_OVER)
        self.el.append(f'<line x1="{A[0]:.2f}" y1="{A[1]:.2f}" x2="{B[0]:.2f}" y2="{B[1]:.2f}" '
                       f'stroke="{DIM_C}" stroke-width="0.9"/>')
        L = math.hypot(B[0]-A[0], B[1]-A[1])
        t = ((B[0]-A[0])/L, (B[1]-A[1])/L)
        if L > 4 * ARROW_L:
            self._arrow(A, t); self._arrow(B, (-t[0], -t[1]))
        else:                                             # arrows outside a tight dimension
            self._arrow(A, (-t[0], -t[1])); self._arrow(B, t)
            for P, sgn_ in ((A, -1), (B, 1)):
                self.el.append(f'<line x1="{P[0]:.2f}" y1="{P[1]:.2f}" '
                               f'x2="{P[0]+sgn_*t[0]*2.2*ARROW_L:.2f}" '
                               f'y2="{P[1]+sgn_*t[1]*2.2*ARROW_L:.2f}" '
                               f'stroke="{DIM_C}" stroke-width="0.9"/>')
                self._track(P[0]+sgn_*t[0]*2.2*ARROW_L, P[1]+sgn_*t[1]*2.2*ARROW_L)
        ang = math.degrees(math.atan2(t[1], t[0]))
        ang = ((ang + 90) % 180) - 90                     # keep text upright
        if text_pos is None:
            n = (math.sin(math.radians(ang)), -math.cos(math.radians(ang)))
            text_pos = ((A[0]+B[0])/2 + n[0]*TEXT_H*0.45, (A[1]+B[1])/2 + n[1]*TEXT_H*0.45)
        self.text(text_pos, label, ang, text_anchor)

def add_dim_layer(name, layer):
    path = os.path.join(HERE, name)
    doc = open(path).read()
    mvb = re.search(r'viewBox="([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)"', doc)
    vx, vy, vw, vh = map(float, mvb.groups())
    x0, y0 = min(vx, min(layer.xs) - 6), min(vy, min(layer.ys) - 6)
    x1, y1 = max(vx + vw, max(layer.xs) + 6), max(vy + vh, max(layer.ys) + 6)
    doc = doc.replace(mvb.group(0), f'viewBox="{x0:.2f} {y0:.2f} {x1-x0:.2f} {y1-y0:.2f}"')
    doc = re.sub(r'width="[-\d.]+mm" height="[-\d.]+mm"',
                 f'width="{x1-x0:.2f}mm" height="{y1-y0:.2f}mm"', doc, count=1)
    doc = doc.replace('</svg>', '<g id="dimensions">\n' + '\n'.join(layer.el) + '\n</g>\n</svg>')
    open(path, 'w').write(doc)
    print(f'appended dimension layer to {name} ({len(layer.el)} elements)')

def feature_bb(slab):
    return (assembly & slab).bounding_box()

big = 10000
# front view maps model (X, Z). The projected extents match the model's up to
# HLR arc/bezier tessellation noise (the plate top curves overshoot a few mm);
# the MIN corner is formed by exactly-projected straight edges (midrib foot,
# floor line), so anchor the translation there at scale 1:1 (parallel projection).
assert abs(pbb_front.size.X - bb.size.X) < 10 and abs(pbb_front.size.Y - bb.size.Z) < 10
TXf, TYf = pbb_front.min.X - bb.min.X, pbb_front.min.Y - bb.min.Z
f2s = lambda x, z: (x + TXf, -(z + TYf))                  # ExportSVG writes y mirrored

front = DimLayer()
H, LX = bb.size.Z, bb.size.X
# overall height, dimension line left of the frame
top_f = feature_bb(Pos(0, 0, bb.max.Z) * Box(big, big, 3, align=(Align.CENTER, Align.CENTER, Align.MAX)))
bot_f = feature_bb(floor_slab)
xdim = bb.min.X - 70
front.linear(f2s(top_f.center().X, bb.max.Z), f2s(bot_f.center().X, bb.min.Z),
             f2s(xdim, bb.max.Z), f2s(xdim, bb.min.Z), f"{H:.0f}")
# overall length, dimension line below the floor
lx_f = feature_bb(Pos(bb.min.X, 0, 0) * Box(3, big, big, align=(Align.MIN, Align.CENTER, Align.MIN)))
rx_f = feature_bb(Pos(bb.max.X, 0, 0) * Box(3, big, big, align=(Align.MAX, Align.CENTER, Align.MIN)))
zdim = bb.min.Z - 70
front.linear(f2s(bb.min.X, lx_f.min.Z), f2s(bb.max.X, rx_f.min.Z),
             f2s(bb.min.X, zdim), f2s(bb.max.X, zdim), f"{LX:.0f}")
# pillar OD, measured across the pillar solid
pil_bb = pillar.bounding_box()
z_pd = 0.62 * H
front.linear(f2s(pil_bb.min.X, z_pd), f2s(pil_bb.max.X, z_pd),
             f2s(pil_bb.min.X, z_pd), f2s(pil_bb.max.X, z_pd),
             f"Ø{pil_bb.size.X:.1f}",
             text_pos=f2s(pil_bb.max.X + 32, z_pd + 10), text_anchor='start')
# midrib channel depth, aligned dimension perpendicular to the member at mid-span
x_mid_ax = (x_base_in + xr_m) / 2
Pmid = (x_mid_ax * IN, (m_slope * x_mid_ax + cxi - y_floor) * IN)
sec_slab = Plane(origin=(Pmid[0], 0, Pmid[1]), z_dir=(u[0], 0, u[1])) * Box(300, 300, 0.8)
mid_sec = midrib & sec_slab
vts = [(v.X, v.Z) for v in mid_sec.vertices()]
dots = [n[0]*vx + n[1]*vz for vx, vz in vts]
D_meas = max(dots) - min(dots)
va, vb = vts[dots.index(max(dots))], vts[dots.index(min(dots))]
OFFD = 80
front.linear(f2s(*va), f2s(*vb),
             f2s(va[0] + u[0]*OFFD, va[1] + u[1]*OFFD),
             f2s(vb[0] + u[0]*OFFD, vb[1] + u[1]*OFFD), f"{D_meas:.1f}")
add_dim_layer('cad-front.svg', front)

# side view maps model (Y, Z): the leg stance width lives here — it is a Y
# dimension, invisible in the front (XZ) projection
assert abs(pbb_side.size.X - bb.size.Y) < 10 and abs(pbb_side.size.Y - bb.size.Z) < 10
TXs, TYs = pbb_side.min.X - bb.min.Y, pbb_side.min.Y - bb.min.Z
s2s = lambda y, z: (y + TXs, -(z + TYs))
side = DimLayer()
padL_c, padR_c = pad_bbs[1].center().Y, pad_bbs[0].center().Y
zdim2 = bb.min.Z - 60
side.linear(s2s(padL_c, 0), s2s(padR_c, 0),
            s2s(padL_c, zdim2), s2s(padR_c, zdim2), f"{abs(stance):.0f} stance")
add_dim_layer('cad-side.svg', side)
print(f"dims: H={H:.0f} L={LX:.0f} stance={abs(stance):.0f} pillar O{pil_bb.size.X:.1f} "
      f"midrib depth={D_meas:.1f} (all measured from the solids)")
