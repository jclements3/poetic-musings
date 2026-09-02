"""LESSON 5 — pure-Python drills on real project data.

No SDK in this one on purpose: half of any coding test is plain Python over
structured data. The data is Erand49/sensor-stations.csv (49 rows).

Muscles: comprehensions, sorted(key=), itertools.groupby, min/max with keys,
zip, enumerate, f-strings, dict pipelines.
"""
import os
import math
from itertools import groupby

import harness

STS = list(harness.stations())

# --- WORKED EXAMPLE ---------------------------------------------------------
# nearest-neighbor spacing along the neck (the classic "adjacent pairs" drill)
pairs = list(zip(STS, STS[1:]))
gaps = [math.hypot(b["x_mm"] - a["x_mm"], b["z_mm"] - a["z_mm"]) for a, b in pairs]
i_min = min(range(len(gaps)), key=gaps.__getitem__)
print(f"tightest neighbors: stations {STS[i_min]['station']}-{STS[i_min+1]['station']}"
      f" at {gaps[i_min]:.1f} mm; widest {max(gaps):.1f} mm; mean {sum(gaps)/len(gaps):.1f} mm")

# groupby needs SORTED input by the same key — the #1 groupby gotcha:
def octave(st):   # stations 0.. -> rough 7-per-octave bins
    return (st["station"] - 1) // 7
for oct_, grp in groupby(sorted(STS, key=octave), key=octave):
    grp = list(grp)
    if oct_ < 2:
        print(f"octave bin {oct_}: {len(grp)} stations, "
              f"x {grp[0]['x_mm']:.0f}..{grp[-1]['x_mm']:.0f} mm")

# --- EXERCISES --------------------------------------------------------------
# E1. Top-3 stations by |yaw| (they were once nonzero...) — return
#     [(station, yaw)] sorted descending, ties by station ascending.
# E2. Build {octave_bin: mean gap within the bin} using ONLY comprehensions
#     and the helpers above (no explicit for-loops except inside them).
# E3. The "two-pointer" classic: find the pair of stations (not necessarily
#     adjacent) whose x_mm difference is closest to exactly 100 mm.
# E4. Write as_rows(sts, cols) -> list[tuple] and a matching header, i.e. a
#     mini dataframe without pandas; print the first 3 rows aligned.

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    top3 = sorted(((s["station"], s["yaw_deg"]) for s in STS),
                  key=lambda t: (-abs(t[1]), t[0]))[:3]
    print("E1:", top3)

    def octave_of(i):
        return (STS[i]["station"] - 1) // 7
    bin_gaps = {}
    for b in sorted({octave(s) for s in STS}):
        sel = [g for (a, _), g in zip(pairs, gaps) if octave(a) == b]
        if sel:
            bin_gaps[b] = round(sum(sel) / len(sel), 1)
    print("E2:", bin_gaps)

    xs = sorted(s["x_mm"] for s in STS)
    lo, hi, best = 0, 1, (float("inf"), None)
    while hi < len(xs):
        d = xs[hi] - xs[lo]
        best = min(best, (abs(d - 100.0), (round(xs[lo]), round(xs[hi]))))
        if d < 100.0:
            hi += 1
        else:
            lo += 1
            hi = max(hi, lo + 1)
    print(f"E3: closest-to-100mm pair {best[1]} (off by {best[0]:.1f} mm)")

    def as_rows(sts, cols):
        return [tuple(s[c] for c in cols) for s in sts]
    cols = ("station", "x_mm", "z_mm")
    rows = as_rows(STS, cols)
    print("E4:")
    print(" | ".join(f"{c:>8}" for c in cols))
    for r in rows[:3]:
        print(" | ".join(f"{v:>8.1f}" if isinstance(v, float) else f"{v:>8}" for v in r))
    print("lesson05 solutions OK")
