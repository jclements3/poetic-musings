"""blob_model -- golden model for PM.Blob (Imaging/DESIGN.md, Centroid per ball).

Contract:
    disc(cx, cy, r) -> [(x, y)]        lattice pixels with (x-cx)^2 + (y-cy)^2 <= r^2
    frame(shapes)   -> set of (x, y)   union of pixel lists, clipped to 640 x 400
    blobs(pixels, min_area, max_area)  -> [(count, cx_q4, cy_q4, minx, maxx, miny, maxy)]
        8-connected components of the foreground set; each component becomes one
        record with count = pixels, cx_q4 = round(16 * sum(x) / count) (ties up),
        bbox inclusive; components with count outside [min_area, max_area] are
        dropped; records sorted by (miny, minx) -- the gateware's order is its label
        order, so the Spec sorts both sides before comparing.
    vectors()       -> the four test frames (a)..(d) as (name, pixels, records)

    Running the file writes golden/vectors.txt next to it (one frame per block:
    `frame <name> <min_area> <max_area>`, `px x y` lines, `rec count cx_q4 cy_q4
    minx maxx miny maxy` lines, `end`) -- test/Spec.hs reads that file, drives the
    pixels through PM.Blob and compares the records. Centroids are unweighted
    (binary) centroids, the same quantity PM.Blob accumulates.

Hint:
    disc is a filter over a cross of ranges; components are dsu unions over
    neighbours8 of each pixel; per-component sums are one fromListWith fold of
    (root, (1, x, y, x, x, y, y)) with a component-wise combine.

>>> len(disc(100, 100, 4.5))
69
>>> blobs(frame([disc(100, 100, 4.5)]), 20, 200)
[(69, 1600, 1600, 96, 104, 96, 104)]
>>> blobs(frame([disc(300.5, 200.5, 4.5)]), 20, 200)
[(60, 4808, 3208, 297, 304, 197, 204)]
>>> blobs(frame([disc(600.25, 350.75, 4.5)]), 20, 200)
[(64, 9603, 5613, 596, 604, 347, 355)]
>>> blobs(frame([[(10, 10), (11, 10)], disc(100, 100, 4.5)]), 20, 200)
[(69, 1600, 1600, 96, 104, 96, 104)]
>>> blobs(frame([[(10, 10), (11, 10)], disc(100, 100, 4.5)]), 1, 200)
[(2, 168, 160, 10, 11, 10, 10), (69, 1600, 1600, 96, 104, 96, 104)]
>>> blobs(frame([disc(100, 100, 4.5), disc(105, 109, 4.5)]), 20, 200)
[(138, 1640, 1672, 96, 109, 96, 113)]
>>> [ (n, len(px), len(rs)) for n, px, rs in vectors() ]
[('a', 69, 1), ('b', 324, 5), ('c', 71, 1), ('d', 138, 1)]
"""

# -- prelude --
fst  = lambda p: p[0]
snd  = lambda p: p[1]

cross     = lambda a, b: [(x, y) for x in a for y in b]               # cartesian; `product` is the fold
filter_   = lambda crit, xs: [x for x in xs if crit(x)]
concat    = lambda xss: [x for xs in xss for x in xs]

sortOn = lambda f, xs: sorted(xs, key=f)   # sortOn (schwartzian, f called once per element)

def dsu(n):                                 # union-find, path halving; union -> False if already joined
    parent = list(range(n))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        ra, rb = find(a), find(b)
        if ra == rb:
            return False
        parent[ra] = rb
        return True
    return find, union

def fromListWith(f, pairs):                 # Data.Map fromListWith: THE dict-building fold; f(new, old)
    d = {}                                  # like insertWith -- so grouping with concat REVERSES each
    for k, v in pairs:                      # group (the classic Haskell gotcha); use add for counts
        d[k] = f(v, d[k]) if k in d else v
    return d                                # Counter == fromListWith(add) over (x, 1);
                                            # grouping == fromListWith(++) over (k, [v])

def neighbors8(r, c, R, C):                 # ... plus diagonals
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if (dr or dc) and 0 <= r + dr < R and 0 <= c + dc < C:
                yield r + dr, c + dc

# solution goes here
W, H = 640, 400

def disc(cx, cy, r):
    box = cross(range(int(cx - r) - 1, int(cx + r) + 2), range(int(cy - r) - 1, int(cy + r) + 2))
    return filter_(lambda p: (fst(p) - cx) ** 2 + (snd(p) - cy) ** 2 <= r * r, box)

frame = lambda shapes: set(filter_(lambda p: 0 <= fst(p) < W and 0 <= snd(p) < H, concat(shapes)))

q4 = lambda s, n: (16 * s + n // 2) // n     # round-to-nearest Q4, ties up -- PM.Blob's divide

def blobs(pixels, min_area, max_area):
    find, union = dsu(W * H)
    key = lambda p: snd(p) * W + fst(p)
    for x, y in pixels:                                       # 8-connectivity: union every neighbour
        for ny, nx in neighbors8(y, x, H, W):
            if (nx, ny) in pixels:
                union(key((x, y)), key((nx, ny)))
    combine = lambda a, b: (a[0] + b[0], a[1] + b[1], a[2] + b[2],
                            min(a[3], b[3]), max(a[4], b[4]), min(a[5], b[5]), max(a[6], b[6]))
    sums = fromListWith(combine, [(find(key(p)), (1, fst(p), snd(p), fst(p), fst(p), snd(p), snd(p)))
                                  for p in pixels])
    recs = [(n, q4(sx, n), q4(sy, n), x0, x1, y0, y1)
            for n, sx, sy, x0, x1, y0, y1 in sums.values() if min_area <= n <= max_area]
    return sortOn(lambda r: (r[5], r[3]), recs)

def vectors():
    r = 4.5
    frames = [
        ('a', [disc(100, 100, r)]),
        ('b', [disc(50, 50, r), disc(300.5, 200.5, r), disc(600.25, 350.75, r),
               disc(320, 40, r), disc(120.5, 380, r)]),
        ('c', [[(10, 10), (11, 10)], disc(100, 100, r)]),           # 2-px speck: below min area
        ('d', [disc(100, 100, r), disc(105, 109, r)]),               # diagonal touch at (102,104)/(103,105)
    ]
    return [(n, sorted(frame(s), key=lambda p: (snd(p), fst(p))), blobs(frame(s), 20, 200))
            for n, s in frames]

def write_vectors(path):
    with open(path, 'w') as f:
        for name, px, recs in vectors():
            f.write('frame %s 20 200\n' % name)
            f.writelines('px %d %d\n' % p for p in px)
            f.writelines('rec %d %d %d %d %d %d %d\n' % r for r in recs)
            f.write('end\n')


if __name__ == u'__main__':
    import doctest
    r = doctest.testmod()
    print(f"blob_model: {r.attempted - r.failed}/{r.attempted} doctests passing")
    write_vectors(__file__.rsplit('/', 1)[0] + '/vectors.txt' if '/' in __file__ else 'vectors.txt')
