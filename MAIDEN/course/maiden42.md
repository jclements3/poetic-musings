# maiden42 — VT-01 / VT-03 [bench]

**Sprint goal.** Retire VT-01 and VT-03 with real bench recordings, and
fold the payload layouts you invented back into D4.

**Depends on.** maiden40, maiden41; FPGA time source locked (maiden39) and
radar chain feeding the UART (maiden36).

**Read first.** Lesson 19: Verify section (both procedures), and Explore 3
(kill test) and 4 (the Ch 4 under-specification).

**Tasks**

- [ ] **VT-01 session.** Record 5 minutes: radar on the bench fan, camera
      at anything, PPS locked. On the host run `i106stat`, a PyChapter10
      full-file iteration, and `maiden ingest --summary`.
- [ ] Commit the VT-01 evidence (i106stat capture + ingest summary) to
      `results/VT-01/`.
- [ ] **VT-03 soak.** Record 10 minutes of 1080p30. Write the checker as a
      permanent test in `software/tests/` (frame count ≥ 17 940, Ch 6 drop
      counters zero, IPTS strictly monotonic, median spacing within 1 % of
      33.33 ms) and run it against the soak.
- [ ] Commit the VT-03 evidence to `results/VT-03/`.
- [ ] **Kill test** (lesson 19 Explore 3): `kill -9` mid-session; decide
      and document in `PROTOCOL.md` whether ingest salvages complete
      packets from a torn file.
- [ ] **Stall injection** (Explore 1): `dd` against the recording disk;
      add ring high-water marks to Ch 6 and resize rings from the measured
      peak, not guesses.
- [ ] **D4 fold-back** (Explore 4): commit the Ch 4/Ch 5/Ch 6 payload
      layouts from `PROTOCOL.md` into D4 IF-1 per D5 change control.
- [ ] Fill D8's "Other verification results" rows for VT-01 and VT-03.

**Done when**

- VT-01 pass: all wired channels present, TMATS parses into a Station
  descriptor, checksums valid, ingest clean — evidence in `results/VT-01/`
  (**observe on bench**).
- VT-03 pass: zero drops, monotonic IPTS, ≥ 29.9 fps mean — evidence in
  `results/VT-03/`, checker committed (**observe on bench**).
- D4 revision committed; D8 rows filled.

**Doc trace.** SYS-005, GS-001; VT-01, VT-03; D4 IF-1 (revised), D8.
