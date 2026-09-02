# HackerRank-on-Zoom track

The Lattice lessons cover the job; THIS folder covers the test format: timed
Python problems in the HackerRank editor while you talk through your thinking
on Zoom.

## Run everything with any python3 (pure stdlib):

    python3 lattice-lessons/hackerrank/drill01_stdlib_weapons.py
    python3 lattice-lessons/hackerrank/drill02_io_formats.py
    SOLUTIONS=1 python3 lattice-lessons/hackerrank/problems.py   # after attempting
    python3 lattice-lessons/hackerrank/mock_test.py              # 60-minute mock

## The seven tools that win HackerRank Python

| Tool | Beats | One-liner |
|---|---|---|
| `collections.Counter` | hand-rolled frequency dicts | `Counter(s).most_common(3)` |
| `collections.defaultdict` | key-exists dances | `d[k].append(v)` just works |
| `collections.deque` | list.pop(0) (O(n)!) | O(1) both ends; BFS queue |
| `heapq` | sorting repeatedly | running top-k, k-way merge |
| `bisect` | linear scans of sorted data | `bisect_left` = lower_bound |
| `itertools` | nested loop soup | `groupby`, `accumulate`, `pairwise` |
| `functools.lru_cache` | hand-rolled memo dicts | decorate the recursion, done |

## HackerRank mechanics (know these cold)

- Two formats: **function completion** (they call your function) and **raw
  stdin/stdout** (you own `input()`/`print`). drill02 covers both plus the
  multi-line/matrix/edge-case parses.
- The editor is plain: no real autocomplete, weak linting. Practice typing
  imports from memory: `from collections import Counter, defaultdict, deque`.
- "Custom input" box = your best friend: paste the sample, run, THEN submit.
- Hidden tests love: empty input, single element, all-equal values, max-size
  input (so mind O(n²) at n=1e5 — that's 1e10 ops = timeout).
- Python-specific timeout savers: `sys.stdin` readline over `input()` for big
  inputs, join-once instead of string += in loops, set membership not list.

## Zoom protocol (rehearse out loud — literally, alone, spoken)

1. **Restate** the problem in one sentence; confirm with the interviewer.
2. **Example first**: walk the sample input by hand before typing.
3. **State the plan + complexity** BEFORE coding: "hashmap pass, O(n) time,
   O(n) space — acceptable for n up to 1e5?"
4. Narrate WHILE typing, but silence is fine for 20-second bursts — announce
   it: "let me just type this out."
5. **Test before declaring done**: sample case, then one edge case you invent
   (empty, single, duplicate-heavy). Say what you're testing and why.
6. If stuck 3+ minutes: say the honest state — "brute force works at O(n²);
   let me ship that, then optimize." Shipping brute force beats frozen.
7. Bugs are points: debug by printing intermediates, narrating hypotheses —
   interviewers score the process.

## Suggested week

| Day | Do |
|---|---|
| 1 | drill01 + drill02, no timer |
| 2 | problems.py P1–P3 untimed, then read solutions critically |
| 3 | problems.py P4–P6, 20 min each, out loud |
| 4 | redo any misses from scratch; drill01 typing-from-memory pass |
| 5 | mock_test.py under a real 60-min timer, out loud, no pauses |
| 6 | review mock; rewrite the ugliest solution cleanly |
| 7 | rest, or one lesson from the Lattice track to stay warm for job talk |
