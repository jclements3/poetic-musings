"""SIX problems, one per core pattern, in HackerRank function style.

Do them in order, out loud, before opening the solutions (SOLUTIONS=1).
Each has a checker; your job is to replace `raise NotImplementedError`.
Target: P1-P3 ~10 min each, P4-P6 ~20 min each, complexity stated aloud.

  P1 hashmap        P2 two pointers     P3 stack
  P4 sliding window P5 BFS on a grid    P6 memoized DP
"""
import os
from collections import Counter, deque
from functools import lru_cache

SOLUTIONS = os.environ.get("SOLUTIONS") == "1"

# --- P1 (hashmap): first non-repeating character, else '_' ------------------
def first_unique(s: str) -> str:
    if not SOLUTIONS: raise NotImplementedError
    counts = Counter(s)
    return next((ch for ch in s if counts[ch] == 1), "_")

# --- P2 (two pointers): does any pair in SORTED xs sum to t? ----------------
def pair_sum(xs: list, t: int) -> bool:
    if not SOLUTIONS: raise NotImplementedError
    lo, hi = 0, len(xs) - 1
    while lo < hi:
        s = xs[lo] + xs[hi]
        if s == t: return True
        if s < t: lo += 1
        else: hi -= 1
    return False

# --- P3 (stack): valid bracket string "([{}])" ------------------------------
def balanced(s: str) -> bool:
    if not SOLUTIONS: raise NotImplementedError
    pairs = {")": "(", "]": "[", "}": "{"}
    st = []
    for ch in s:
        if ch in "([{":
            st.append(ch)
        elif ch in pairs:
            if not st or st.pop() != pairs[ch]:
                return False
    return not st

# --- P4 (sliding window): longest substring with no repeated char -----------
def longest_unique(s: str) -> int:
    if not SOLUTIONS: raise NotImplementedError
    last, start, best = {}, 0, 0
    for i, ch in enumerate(s):
        if ch in last and last[ch] >= start:
            start = last[ch] + 1
        last[ch] = i
        best = max(best, i - start + 1)
    return best

# --- P5 (BFS): shortest path steps in a grid of '.' and '#', -1 if blocked --
def grid_bfs(grid: list, src=(0, 0)) -> int:
    """steps from src to bottom-right corner, 4-directional."""
    if not SOLUTIONS: raise NotImplementedError
    n, m = len(grid), len(grid[0])
    goal = (n - 1, m - 1)
    if grid[src[0]][src[1]] == "#" or grid[goal[0]][goal[1]] == "#":
        return -1
    q, seen = deque([(src, 0)]), {src}
    while q:
        (r, c), d = q.popleft()
        if (r, c) == goal:
            return d
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < n and 0 <= nc < m and grid[nr][nc] == "." \
                    and (nr, nc) not in seen:
                seen.add((nr, nc))
                q.append(((nr, nc), d + 1))
    return -1

# --- P6 (DP): coin change — fewest coins to make amount, -1 if impossible ---
def coin_change(coins: tuple, amount: int) -> int:
    if not SOLUTIONS: raise NotImplementedError
    @lru_cache(maxsize=None)
    def best(a):
        if a == 0: return 0
        picks = [best(a - c) for c in coins if c <= a]
        picks = [p for p in picks if p >= 0]
        return min(picks) + 1 if picks else -1
    return best(amount)

# --- checker ----------------------------------------------------------------
CASES = [
    (first_unique, ("swiss",), "w"),
    (first_unique, ("aabb",), "_"),
    (first_unique, ("",), "_"),
    (pair_sum, ([1, 2, 4, 7, 11], 9), True),
    (pair_sum, ([1, 2, 4, 7, 11], 10), False),
    (pair_sum, ([], 0), False),
    (balanced, ("([{}])",), True),
    (balanced, ("([)]",), False),
    (balanced, ("(((",), False),
    (balanced, ("",), True),
    (longest_unique, ("abcabcbb",), 3),
    (longest_unique, ("bbbbb",), 1),
    (longest_unique, ("",), 0),
    (longest_unique, ("abba",), 2),        # the classic trap case
    (grid_bfs, ([list(".."), list("..")],), 2),
    (grid_bfs, ([list(".#"), list("#.")],), -1),
    (grid_bfs, ([list(".")],), 0),
    (coin_change, ((1, 2, 5), 11), 3),
    (coin_change, ((2,), 3), -1),
    (coin_change, ((7,), 0), 0),
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
    if SOLUTIONS and failed == 0 and skipped == 0:
        print("all reference solutions green")
