# optimize_rails.py — fit minimal-material neck rails: smooth G1 cubic chains
# (inline/colinear handles) at a constant buffer R around the tuner-pin and
# optical-axis dot arcs. Writes Erand49test.html (comparison figure + stats)
# and Erand49-optimized.svg (the master with ONLY the two rail paths replaced;
# Erand49.svg itself is never touched).
import os, re, math

HERE = os.path.dirname(os.path.abspath(__file__))
R_TUNER = 8.0    # mm: O10 tuner post (r5) + 3 mm edge shelf
R_OPTIC = 8.0    # mm: O16 optics pad footprint
ns = {'__file__': os.path.join(HERE, 'gen_erand49.py')}
exec(open(os.path.join(HERE, 'gen_erand49.py')).read(), ns)

tuners = sorted(ns['tuners_px'])
optics = sorted(ns['sense_px'])
svg = open(os.path.join(HERE, 'Erand49.svg')).read()

def path_d(color):
    p = [x for x in re.findall(r'<path[^>]*>', svg, re.S) if color in x][0]
    return re.search(r'\bd="([^"]+)"', p).group(1)

def sample_path(d, n_per=80):
    toks = re.findall(r'[mMcClLzZ]|-?\d+\.?\d*(?:e-?\d+)?', d)
    i = 0; cur = (0.0, 0.0); cmd = None; pts = []
    def f():
        nonlocal i; v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if toks[i] in 'mMcClLzZ': cmd = toks[i]; i += 1; continue
        if cmd in 'mM':
            x, y = f(), f()
            cur = (x, y) if cmd == 'M' else (cur[0]+x, cur[1]+y)
            pts.append(cur); cmd = 'l' if cmd == 'm' else 'L'
        elif cmd in 'cC':
            v = [f() for _ in range(6)]
            if cmd == 'c':
                c1 = (cur[0]+v[0], cur[1]+v[1]); c2 = (cur[0]+v[2], cur[1]+v[3]); e = (cur[0]+v[4], cur[1]+v[5])
            else:
                c1, c2, e = (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
            for k in range(1, n_per+1):
                t = k/n_per; mt = 1-t
                pts.append((mt**3*cur[0]+3*mt*mt*t*c1[0]+3*mt*t*t*c2[0]+t**3*e[0],
                            mt**3*cur[1]+3*mt*mt*t*c1[1]+3*mt*t*t*c2[1]+t**3*e[1]))
            cur = e
        elif cmd in 'lL':
            x, y = f(), f()
            cur = (x, y) if cmd == 'L' else (cur[0]+x, cur[1]+y)
            pts.append(cur)
    return pts

def end_handles(d):
    """(P0, H0, P1, H1): endpoints with their handle points, absolute."""
    toks = re.findall(r'[mMcClLzZ]|-?\d+\.?\d*(?:e-?\d+)?', d)
    i = 0; cur = (0.0, 0.0); cmd = None
    P0 = H0 = H1 = None
    def f():
        nonlocal i; v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if toks[i] in 'mMcClLzZ': cmd = toks[i]; i += 1; continue
        if cmd in 'mM':
            x, y = f(), f()
            cur = (x, y) if cmd == 'M' else (cur[0]+x, cur[1]+y)
            if P0 is None: P0 = cur
            cmd = 'l' if cmd == 'm' else 'L'
        elif cmd in 'cC':
            v = [f() for _ in range(6)]
            if cmd == 'c':
                c1 = (cur[0]+v[0], cur[1]+v[1]); c2 = (cur[0]+v[2], cur[1]+v[3]); e = (cur[0]+v[4], cur[1]+v[5])
            else:
                c1, c2, e = (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
            if H0 is None: H0 = c1
            H1 = c2; cur = e
    return P0, H0, cur, H1

cur_outer = sample_path(path_d('2e7d32'))
cur_inner = sample_path(path_d('66bb6a'))

# ---- smooth resample of a dot arc (Catmull-Rom through the dots) ----
def catmull(pts, n_per=24):
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P)-2):
        p0, p1, p2, p3 = P[i-1], P[i], P[i+1], P[i+2]
        for k in range(n_per):
            t = k/n_per
            out.append(tuple(
                0.5*((2*p1[j]) + (-p0[j]+p2[j])*t + (2*p0[j]-5*p1[j]+4*p2[j]-p3[j])*t*t
                     + (-p0[j]+3*p1[j]-3*p2[j]+p3[j])*t**3) for j in (0, 1)))
    out.append(pts[-1])
    return out

# ---- x-monotone construction: exact dilation envelopes y(x) ----
# svg y grows DOWN. outer rail stays ABOVE the tuner dots (y smaller):
#   y(x) <= min over dots of dot_y - sqrt(R^2 - (x-dot_x)^2)
# inner rail stays BELOW the optic dots:  y(x) >= max of dot_y + sqrt(...)
def envelope(dots, R, side, x0, x1, n=500):
    xs = [x0 + (x1-x0)*k/(n-1) for k in range(n)]
    out = []
    for x in xs:
        # base line: chord through the two nearest dots, offset R
        (xa, ya), (xb, yb) = sorted(dots, key=lambda p: abs(p[0]-x))[:2]
        yl = ya if xb == xa else ya + (yb-ya)*(x-xa)/(xb-xa)
        b = yl - R if side == 'above' else yl + R
        for dx_, dy_ in dots:
            d = abs(x - dx_)
            if d < R:
                off = math.sqrt(R*R - d*d)
                b = min(b, dy_ - off) if side == 'above' else max(b, dy_ + off)
        out.append((x, b))
    return out

def sample_chain(segs, n_per=80):
    pts = []
    for V0, c1, c2, V3 in segs:
        for k in range(n_per+1):
            t = k/n_per; mt = 1-t
            pts.append((mt**3*V0[0]+3*mt*mt*t*c1[0]+3*mt*t*t*c2[0]+t**3*V3[0],
                        mt**3*V0[1]+3*mt*mt*t*c1[1]+3*mt*t*t*c2[1]+t**3*V3[1]))
    return pts

def build_rail(dots, R, side, P0, H0, P1, H1, n_nodes=7):
    lo_x, hi_x = min(P0[0], P1[0]), max(P0[0], P1[0])
    env = envelope(dots, R, side, lo_x, hi_x)
    if P0[0] > P1[0]:
        env = env[::-1]
    m = len(env); kb = max(3, int(0.10*m))
    env = list(env)
    for i in range(kb):                        # blend into the FIXED endpoints
        w = 1 - i/kb
        env[i]     = (env[i][0]     + (P0[0]-env[0][0])*w,  env[i][1]     + (P0[1]-env[0][1])*w)
        env[m-1-i] = (env[m-1-i][0] + (P1[0]-env[-1][0])*w, env[m-1-i][1] + (P1[1]-env[-1][1])*w)
    # interior nodes at equal turning-angle quantiles of the envelope
    turn = [0.0]
    for i in range(1, m-1):
        a = (env[i][0]-env[i-1][0], env[i][1]-env[i-1][1])
        b = (env[i+1][0]-env[i][0], env[i+1][1]-env[i][1])
        turn.append(turn[-1] + abs(math.atan2(a[0]*b[1]-a[1]*b[0], a[0]*b[0]+a[1]*b[1])))
    turn.append(turn[-1]); T = turn[-1] or 1.0
    idxs = sorted(set([0] + [min(range(m), key=lambda i: abs(turn[i]-T*q/(n_nodes-1)))
                             for q in range(1, n_nodes-1)] + [m-1]))
    nodes = [env[i] for i in idxs]
    nodes[0], nodes[-1] = P0, P1
    # END HANDLES: exact angle AND length from the master (hard constraint)
    v0 = (H0[0]-P0[0], H0[1]-P0[1]); L0 = math.hypot(*v0) or 1.0
    v1 = (P1[0]-H1[0], P1[1]-H1[1]); L1 = math.hypot(*v1) or 1.0
    t_first, t_last = (v0[0]/L0, v0[1]/L0), (v1[0]/L1, v1[1]/L1)
    def mk(nodes):
        tangents = [t_first]
        for k2 in range(1, len(nodes)-1):
            i = idxs[k2]
            a, b = env[max(0, i-6)], env[min(m-1, i+6)]
            vx, vy = b[0]-a[0], b[1]-a[1]; L = math.hypot(vx, vy) or 1.0
            tangents.append((vx/L, vy/L))
        tangents.append(t_last)
        segs = []
        for k2 in range(len(nodes)-1):
            V0, V3 = nodes[k2], nodes[k2+1]
            d = math.hypot(V3[0]-V0[0], V3[1]-V0[1])/3
            l0 = L0 if k2 == 0 else d
            l1 = L1 if k2 == len(nodes)-2 else d
            t0, t3 = tangents[k2], tangents[k2+1]
            segs.append((V0, (V0[0]+t0[0]*l0, V0[1]+t0[1]*l0),
                         (V3[0]-t3[0]*l1, V3[1]-t3[1]*l1), V3))
        return segs
    segs = mk(nodes)
    # bounded y-only correction for corner-cutting between nodes (skip dots
    # whose x falls in the endpoint blend zones - clearance tapers there by
    # construction, the junctions pin the rail)
    xbl0, xbl1 = env[kb][0], env[m-1-kb][0]
    sgn = -1.0 if side == 'above' else 1.0
    for _ in range(30):
        pts = sample_chain(segs, 40)
        worst = {}
        for dx_, dy_ in dots:
            in_blend = (min(xbl0, env[0][0]) <= dx_ <= max(xbl0, env[0][0])) or \
                       (min(xbl1, env[-1][0]) <= dx_ <= max(xbl1, env[-1][0]))
            if in_blend:
                continue
            j = min(range(len(pts)), key=lambda i: (pts[i][0]-dx_)**2 + (pts[i][1]-dy_)**2)
            d = math.hypot(pts[j][0]-dx_, pts[j][1]-dy_)
            wrong = (pts[j][1] > dy_) if side == 'above' else (pts[j][1] < dy_)
            deficit = (R + d) if wrong else (R - d)
            if deficit > 0.3:
                kk = min(range(1, len(nodes)-1), key=lambda k2: abs(nodes[k2][0]-dx_))
                worst[kk] = max(worst.get(kk, 0.0), deficit)
        if not worst:
            break
        for kk, dv in worst.items():
            nodes[kk] = (nodes[kk][0], nodes[kk][1] + sgn*(dv + 0.3))
        segs = mk(nodes)
    return segs

oP0, oH0, oP1, oH1 = end_handles(path_d('2e7d32'))
iP0, iH0, iP1, iH1 = end_handles(path_d('66bb6a'))
outer_segs = build_rail(tuners, R_TUNER, 'above', oP0, oH0, oP1, oH1)
inner_segs = build_rail(optics, R_OPTIC, 'below', iP0, iH0, iP1, iH1)

def chain_d(segs):
    d = f'M {segs[0][0][0]:.2f} {segs[0][0][1]:.2f}'
    for V0, c1, c2, V3 in segs:
        d += f' C {c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {V3[0]:.2f} {V3[1]:.2f}'
    return d

def clearance(dots, curve):
    ds = [min(math.hypot(p[0]-q[0], p[1]-q[1]) for q in curve) for p in dots]
    return min(ds), max(ds), sum(ds)/len(ds)

opt_outer, opt_inner = sample_chain(outer_segs), sample_chain(inner_segs)
stats = {
    'cur':  {'tuner': clearance(tuners, cur_outer), 'optic': clearance(optics, cur_inner)},
    'opt':  {'tuner': clearance(tuners, opt_outer), 'optic': clearance(optics, opt_inner)},
}
def bandw(outer, inner):
    ds = [min(math.hypot(p[0]-q[0], p[1]-q[1]) for q in inner) for p in outer[::10]]
    return sum(ds)/len(ds)
w_cur, w_opt = bandw(cur_outer, cur_inner), bandw(opt_outer, opt_inner)

# ---- outputs ----
d_out, d_in = chain_d(outer_segs), chain_d(inner_segs)
opt_svg = svg
for color, dnew in (('2e7d32', d_out), ('66bb6a', d_in)):
    pel = [x for x in re.findall(r'<path[^>]*>', opt_svg, re.S) if color in x][0]
    dold = re.search(r'\bd="([^"]+)"', pel).group(1)
    opt_svg = opt_svg.replace(dold, dnew)
open(os.path.join(HERE, 'Erand49-optimized.svg'), 'w').write(opt_svg)

def poly_svg(pts, step=4):
    return 'M ' + ' L '.join(f'{x:.1f} {y:.1f}' for x, y in pts[::step])

dots_svg = ''.join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.2" fill="#2e7d32"/>' for x, y in tuners) \
         + ''.join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.2" fill="#3b6fb5"/>' for x, y in optics)
nodes_svg = ''
for segs in (outer_segs, inner_segs):
    for k, (V0, c1, c2, V3) in enumerate(segs):
        for h in ((V0, c1),) + (((V3, c2),) if k == len(segs)-1 else ()):
            nodes_svg += (f'<line x1="{h[0][0]:.1f}" y1="{h[0][1]:.1f}" x2="{h[1][0]:.1f}" y2="{h[1][1]:.1f}" stroke="#c9a" stroke-width="0.8"/>'
                          f'<circle cx="{h[1][0]:.1f}" cy="{h[1][1]:.1f}" r="1.6" fill="none" stroke="#c9a" stroke-width="0.8"/>')
        nodes_svg += f'<rect x="{V0[0]-2.5:.1f}" y="{V0[1]-2.5:.1f}" width="5" height="5" fill="#7b1fa2"/>'
    nodes_svg += f'<rect x="{segs[-1][3][0]-2.5:.1f}" y="{segs[-1][3][1]-2.5:.1f}" width="5" height="5" fill="#7b1fa2"/>'

fmt = lambda t: f'{t[0]:.1f} / {t[2]:.1f} / {t[1]:.1f}'
html = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>Erand49 — optimized neck rails (TEST)</title>
<style>body{{font-family:system-ui;margin:24px;color:#222}} table{{border-collapse:collapse}}
td,th{{border:1px solid #ccc;padding:6px 12px;font-size:14px}} .wrap{{border:1px solid #ddd;margin:14px 0}}</style></head><body>
<h1>Erand49 — optimized neck rails (TEST — master untouched)</h1>
<p>Rails refit as 5-node G1 cubic chains (inline/colinear handles, purple squares = nodes,
circles = handles) hugging a constant {R_TUNER:.0f} mm buffer envelope around the tuner pins
(green dots) and optical axes (blue dots). Structural endpoints kept: crown starts and both
shoulder junctions. Old rails shown dashed grey. Saved as <code>Erand49-optimized.svg</code> —
merge into <code>Erand49.svg</code> in Inkscape only if you like it.</p>
<table><tr><th>buffer to nearest rail, mm (min / avg / max)</th><th>current</th><th>optimized</th></tr>
<tr><td>tuner pins → outer rail</td><td>{fmt(stats['cur']['tuner'])}</td><td><b>{fmt(stats['opt']['tuner'])}</b></td></tr>
<tr><td>optic axes → inner rail</td><td>{fmt(stats['cur']['optic'])}</td><td><b>{fmt(stats['opt']['optic'])}</b></td></tr>
<tr><td>mean band width (material)</td><td>{w_cur:.1f} mm</td><td><b>{w_opt:.1f} mm</b> ({100*(1-w_opt/w_cur):.0f}% less)</td></tr></table>
<div class="wrap"><svg viewBox="60 0 1060 620" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;display:block">
<path d="{poly_svg(cur_outer)}" fill="none" stroke="#999" stroke-width="1.5" stroke-dasharray="6 4"/>
<path d="{poly_svg(cur_inner)}" fill="none" stroke="#999" stroke-width="1.5" stroke-dasharray="6 4"/>
<path d="{d_out}" fill="none" stroke="#2e7d32" stroke-width="2.5"/>
<path d="{d_in}" fill="none" stroke="#66bb6a" stroke-width="2.5"/>
{dots_svg}{nodes_svg}
</svg></div></body></html>"""
open(os.path.join(HERE, 'Erand49test.html'), 'w').write(html)
print('nodes: outer', len(outer_segs)+1, 'inner', len(inner_segs)+1)
print('tuner buffer  cur min/avg/max:', fmt(stats['cur']['tuner']), ' opt:', fmt(stats['opt']['tuner']))
print('optic buffer  cur min/avg/max:', fmt(stats['cur']['optic']), ' opt:', fmt(stats['opt']['optic']))
print(f'mean band width: {w_cur:.1f} -> {w_opt:.1f} mm')
print('wrote Erand49test.html and Erand49-optimized.svg')
