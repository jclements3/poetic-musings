"""MOCK TEST — 60 minutes, 4 problems, Zoom rules.

Setup: start a 60-minute timer, share your screen with someone (or record
yourself), and NARRATE. Write each solution in this file, then run it —
the checker reports per-problem. SOLUTIONS=1 shows references afterward.

Scoring yourself: 4/4 strong hire, 3/4 solid, 2/4 with good narration is
still a pass at many bars — process counts on Zoom.
"""
import os
from collections import Counter, defaultdict, deque

SOLUTIONS = os.environ.get("SOLUTIONS") == "1"

# --- M1 (10 min) ------------------------------------------------------------
# Given a list of log lines "user action", return the users whose action
# count is strictly greater than every OTHER user's count (list, sorted).
# e.g. ["jc tune","amy pluck","jc tune"] -> ["jc"]
def busiest_users(lines):
    if not SOLUTIONS: raise NotImplementedError
    c = Counter(line.split()[0] for line in lines)
    if not c: return []
    top = max(c.values())
    return sorted(u for u, n in c.items() if n == top)

# --- M2 (15 min) ------------------------------------------------------------
# 49 harp strings numbered 1..n. You get tuning sessions as (start, end)
# inclusive ranges. Return how many strings were tuned at least twice.
# Constraints: n up to 1e6, up to 1e5 ranges — O(n + q), not O(n*q)!
# (difference array / prefix sum trick)
def tuned_twice(n, ranges):
    if not SOLUTIONS: raise NotImplementedError
    diff = [0] * (n + 2)
    for a, b in ranges:
        diff[a] += 1
        diff[b + 1] -= 1
    cnt = twice = 0
    for i in range(1, n + 1):
        cnt += diff[i]
        twice += cnt >= 2
    return twice

# --- M3 (15 min) ------------------------------------------------------------
# A melody is a string of note letters. Two melodies are "equivalent" if one
# is a rotation of the other ("abcd" ~ "cdab"). Group a list of melodies
# into equivalence classes; return the size of the largest class.
# (canonical form trick: min over rotations, or doubled-string membership)
def largest_rotation_class(melodies):
    if not SOLUTIONS: raise NotImplementedError
    def canon(s):
        return min(s[i:] + s[:i] for i in range(len(s))) if s else s
    groups = defaultdict(int)
    for m in melodies:
        groups[(len(m), canon(m))] += 1
    return max(groups.values()) if melodies else 0

# --- M4 (20 min) ------------------------------------------------------------
# The harp's 49 stations form a line. station_ok[i] is True if station i's
# sensor responded. A "demo segment" is a maximal run of OK stations. Return
# (number_of_segments, length_of_longest, start_index_of_longest) with the
# FIRST longest winning ties; (0, 0, -1) if none OK.
def demo_segments(station_ok):
    if not SOLUTIONS: raise NotImplementedError
    segs = []
    i, n = 0, len(station_ok)
    while i < n:
        if station_ok[i]:
            j = i
            while j < n and station_ok[j]:
                j += 1
            segs.append((i, j - i))
            i = j
        else:
            i += 1
    if not segs:
        return (0, 0, -1)
    best_start, best_len = max(segs, key=lambda t: (t[1], -t[0]))
    return (len(segs), best_len, best_start)

# --- checker ----------------------------------------------------------------
CASES = [
    (busiest_users, (["jc tune", "amy pluck", "jc tune"],), ["jc"]),
    (busiest_users, (["a x", "b y"],), ["a", "b"]),
    (busiest_users, ([],), []),
    (tuned_twice, (10, [(1, 5), (4, 8), (5, 5)]), 2),   # stations 4 and 5
    (tuned_twice, (5, []), 0),
    (tuned_twice, (3, [(1, 3), (1, 3)]), 3),
    (largest_rotation_class, (["abcd", "cdab", "bcda", "abdc"],), 3),
    (largest_rotation_class, ([],), 0),
    (largest_rotation_class, (["a", "a", "b"],), 2),
    (demo_segments, ([True, True, False, True, True, True],), (2, 3, 3)),
    (demo_segments, ([False, False],), (0, 0, -1)),
    (demo_segments, ([True],), (1, 1, 0)),
    (demo_segments, ([True, False, True],), (2, 1, 0)),  # tie -> first
]

if __name__ == "__main__":
    passed = failed = skipped = 0
    for fn, args, want in CASES:
        try:
            got = fn(*args)
        except NotImplementedError:
            skipped += 1
            continue
        ok = got == want
        passed += ok; failed += (not ok)
        if not ok:
            print(f"FAIL {fn.__name__}{args} -> {got!r}, want {want!r}")
    print(f"passed={passed} failed={failed} not-attempted={skipped}")
    if failed == 0 and skipped == 0:
        print("mock complete — now review which narration moments felt shaky")
