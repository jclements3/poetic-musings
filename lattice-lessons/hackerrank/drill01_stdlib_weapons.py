"""DRILL 1 — the stdlib weapons, each proven on a micro-case.

Read a block, cover it, retype it from memory. The imports themselves are
half the drill: the HackerRank editor won't autocomplete them for you.
"""
from collections import Counter, defaultdict, deque
from itertools import groupby, accumulate, combinations
from functools import lru_cache
import heapq
import bisect

# Counter — frequencies, top-k, multiset subtract
votes = "abacabadabacaba"
c = Counter(votes)
assert c.most_common(2) == [("a", 8), ("b", 4)]
assert list((c - Counter("aaaa")).elements()).count("a") == 4

# defaultdict — grouping without key checks
by_len = defaultdict(list)
for w in "the quick brown fox the lazy dog the end".split():
    by_len[len(w)].append(w)
assert by_len[3] == ["the", "fox", "the", "dog", "the", "end"]

# deque — O(1) both ends; the BFS queue; the sliding window
d = deque([1, 2, 3]); d.appendleft(0); d.append(4)
assert (d.popleft(), d.pop()) == (0, 4)

# heapq — running k largest without sorting everything
nums = [5, 1, 8, 3, 9, 2, 7]
assert heapq.nlargest(3, nums) == [9, 8, 7]
h = []
for x in nums:
    heapq.heappush(h, x)
    if len(h) > 3:
        heapq.heappop(h)          # h holds the 3 largest, min on top
assert sorted(h) == [7, 8, 9]

# bisect — binary search on sorted data (lower_bound / insertion point)
xs = [10, 20, 20, 30]
assert bisect.bisect_left(xs, 20) == 1
assert bisect.bisect_right(xs, 20) == 3
bisect.insort(xs, 25); assert xs == [10, 20, 20, 25, 30]

# groupby — run-length encode (input must be sorted/grouped already!)
rle = [(ch, len(list(g))) for ch, g in groupby("aaabbc")]
assert rle == [("a", 3), ("b", 2), ("c", 1)]

# accumulate — prefix sums = range-sum queries in O(1)
pref = [0] + list(accumulate([3, 1, 4, 1, 5]))
def range_sum(i, j):              # sum of a[i:j]
    return pref[j] - pref[i]
assert range_sum(1, 4) == 1 + 4 + 1

# lru_cache — recursion + decorator = DP
@lru_cache(maxsize=None)
def ways(n):                      # climb stairs 1 or 2 at a time
    return 1 if n <= 1 else ways(n - 1) + ways(n - 2)
assert ways(30) == 1346269

# combinations — pairs without index bookkeeping
assert sum(1 for _ in combinations(range(5), 2)) == 10

# sorted with a compound key — THE most-used line in any test
words = ["bb", "a", "ccc", "dd"]
assert sorted(words, key=lambda w: (-len(w), w)) == ["ccc", "bb", "dd", "a"]

print("drill01: all stdlib weapons verified — now retype them from memory")
