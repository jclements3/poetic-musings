# VT-24 rehearsal — the 10-minute clock (compute half)

Host: VALKYRIE (WSL2, the sim/dev machine; field host TBD at
maiden43). Field criterion: SD pull -> PDF <= 10 min (stopwatch
at the field, VT-24). This measures the compute half on two twin
flights (Sportsman x2 + landings; second flight carries a full
1080p-class video channel).

## flight-1 (seed 404, no video)

```
stage        wall [s]
----------------------
ingest           0.05
track            0.00
fuse             1.04
maneuvers        0.03
approach         0.01
score            0.00
rules            0.13
report           0.20
----------------------
total            1.46
```
wall (incl. session overhead): 1.46 s
track: skipped — tracker channels present

## flight-2 (seed 606, 213 MB video ch)

```
stage        wall [s]
----------------------
ingest           0.05
track            0.00
fuse             1.06
maneuvers        0.03
approach         0.00
score            0.00
rules            0.13
report           0.21
----------------------
total            1.48
```
wall (incl. session overhead): 1.48 s
track: skipped — tracker channels present; Ch2 video present but TS extraction not wired (maiden41) — clips skipped

## Budget

| item | estimate |
|---|---|
| compute, 2 flights | 2.9 s |
| SD copy flight-1 (1 MB @ 80 MB/s) | 0.0 s |
| SD copy flight-2 (223 MB @ 80 MB/s) | 2.8 s |
| **total** | **5.7 s** of the 600 s budget |

Headroom is enormous on twin data because the tracker is skipped
(Ch 5 present) and twin video is never decoded. The field risk
remains video decode + host tracker (maiden41/42 measure that);
Phase 2 hardening owns any overrun (D5).
