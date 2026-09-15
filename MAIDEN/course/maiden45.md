# maiden45 — The HIL Dataset [bench]

**Sprint goal.** Record the first real hardware-in-the-loop dataset and
wire it into CI — closing the TODO maiden28 left in the CI matrix.

**Depends on.** maiden43 (Station 1 recording), maiden28 (CI harness with
the HIL session-directory interface designed and loudly skipping).

**Read first.** Lesson 20: *The HIL dataset* and Build step 5; lesson 15's
HIL interface section is the contract being fulfilled.

**Tasks**

- [ ] Stage the boring-on-purpose scene: radar viewing a box fan (steady
      Doppler), camera viewing a monitor looping twin-rendered frames or a
      swinging pendulum, everything PPS-locked.
- [ ] Record 5 minutes with Station 1; place the session under
      `data/HIL/<date>/` in the session-directory layout maiden28 defined.
- [ ] Extend the CI job to replay the HIL session (ingest → track →
      Doppler-output checks) alongside the twin set.
- [ ] Pin the metrics that must not regress: ingest sample counts per
      channel, track count, v_r distribution bounds. Store them beside the
      dataset, cited from CI.
- [ ] Prove the gate: a deliberately broken ingest on a branch turns the
      HIL job red; revert and confirm green.
- [ ] Decide and document how the (large) HIL session is stored — the D5
      rule is raw data never modified, derived products regenerable;
      lesson 00's data-directory policy says what is and isn't in git.

**Done when**

- `data/HIL/` exists with the recorded session and pinned metrics.
- CI replays it green on the next push, and the injected-regression
  branch goes red (evidence: link both runs in the commit message or
  `results/VT-18/`).
- maiden28's "HIL pending" skip marker is gone.

**Doc trace.** SW-005 (the HIL half), SYS-005; D5 §Hardware-in-the-loop
continuous integration; feeds VT-18's standing evidence.
