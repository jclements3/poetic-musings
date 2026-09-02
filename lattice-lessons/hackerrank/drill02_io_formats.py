"""DRILL 2 — every stdin shape HackerRank throws at you.

Each parser runs here against an embedded sample via io.StringIO, exactly as
it would run against real stdin. In the test, replace `data` with sys.stdin.
"""
import io
import sys

def with_stdin(text, fn):
    old, sys.stdin = sys.stdin, io.StringIO(text)
    try:
        return fn()
    finally:
        sys.stdin = old

# Shape 1: first line n, then n lines of ints
def parse_n_lines():
    n = int(input())
    return [int(input()) for _ in range(n)]
assert with_stdin("3\n10\n20\n30\n", parse_n_lines) == [10, 20, 30]

# Shape 2: one line of space-separated ints (the most common line ever)
def parse_row():
    return list(map(int, input().split()))
assert with_stdin("3 1 4 1 5\n", parse_row) == [3, 1, 4, 1, 5]

# Shape 3: n m header, then an n x m matrix
def parse_matrix():
    n, m = map(int, input().split())
    grid = [list(map(int, input().split())) for _ in range(n)]
    assert all(len(r) == m for r in grid)
    return grid
assert with_stdin("2 3\n1 2 3\n4 5 6\n", parse_matrix) == [[1, 2, 3], [4, 5, 6]]

# Shape 4: read EVERYTHING (token stream) — safest under weird spacing,
# and the fast path for big inputs (sys.stdin.read once, not input() loops)
def parse_tokens():
    toks = sys.stdin.read().split()
    it = iter(toks)
    n = int(next(it))
    return [(next(it), int(next(it))) for _ in range(n)]
assert with_stdin("2\nalice 30\nbob 25\n", parse_tokens) == [("alice", 30), ("bob", 25)]

# Shape 5: queries until EOF (no count given)
def parse_until_eof():
    return [line.split() for line in sys.stdin.read().splitlines() if line.strip()]
assert with_stdin("add 3\nrm 2\n\n", parse_until_eof) == [["add", "3"], ["rm", "2"]]

# Output discipline: build once, print once (string += in a loop is a
# timeout generator on big cases)
rows = [[1, 2], [3, 4]]
out = "\n".join(" ".join(map(str, r)) for r in rows)
assert out == "1 2\n3 4"

# The function-completion format: HackerRank often gives
#   def solve(arr): ...
# and hides the IO. Practice keeping ALL logic in the function so both
# formats are the same problem:
def solve(arr):
    return max(arr) - min(arr)
def main():                      # the stdin wrapper you may have to write
    _ = input()
    print(solve(list(map(int, input().split()))))
assert with_stdin("5\n3 1 4 1 5\n", lambda: (main(), None)[1]) is None  # prints 4 above

print("drill02: all five stdin shapes + output discipline verified")
