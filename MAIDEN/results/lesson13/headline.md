# maiden25 headline run (SIM REHEARSAL)

Twin seed 303, `--imperfect`, three stations, .ch10 round trip through ingest. VT-10/11/12 bind only in the field (lesson 99); these are necessary-not-sufficient numbers.

| metric | value | threshold (D2, sim rehearsal) |
|---|---|---|
| position RMS (valid epochs) | 0.219 m | <= 1.0 m (SYS-002) |
| velocity RMS (valid epochs) | 0.909 m/s | <= 1.0 m/s (SYS-003) |
| continuity | 1.0000 | >= 0.95 (SYS-004) |
| gate rate | 0.089% | < 1% |
| updates / gated | 14571 / 13 | |
| coast time | 0.00 s | |

v_r ablation: velocity RMS 1.608 m/s without radials vs 0.909 m/s with — the delta is D3's three-radar architecture decision, measured. (Layout note: the twin's collinear A-B-C leaves one velocity component to the cameras; see test_fuse_vr.py.)
