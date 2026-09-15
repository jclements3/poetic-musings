# maiden07 — VT-02 procedure [desk]

**Sprint goal.** Write the end-to-end time-alignment test procedure while
the timebase design is fresh — the document you will execute on the bench
(maiden39) and again in the field (maiden60).

**Depends on.** maiden06.

**Read first.** lesson04.md §Build (*results/VT-02/PROCEDURE.md*) and
§Concepts (*Degraded sync*); D7's VT-02 row.

## Tasks

- [x] Write `results/VT-02/PROCEDURE.md` specifying, per D7's VT-02 row:
      - the stimulus: an LED driven directly by a GPS-PPS edge, positioned
        in view of all three cameras; the same PPS edge logged on the
        airborne IMU (tap or interrupt line);
      - extraction: stamped LED-onset time from each video (first frame
        where the LED pixel block crosses half brightness, minus half a
        frame interval as the uncertainty statement) and from the IMU
        stream;
      - the pass criterion: |Δt| ≤ 5 ms across all four sources;
      - evidence: exactly what files/plots get committed under
        `results/VT-02/` for the bench run and the field run.
- [x] Explore 1: write the 5 ms budget table (PPS accuracy, FPGA latch
      granularity, camera exposure midpoint vs strobe, fit residual) with
      your estimates; identify the dominant term; include the table in
      the procedure.
- [x] Explore 2: estimate the clap-fallback alignment error
      (33 ms frame quantization) and add a short "degraded sync" section
      explaining why clap-aligned sessions are flagged, not rejected.
- [ ] Commit: `VT-02: end-to-end time alignment procedure`.

## Done when

- `results/VT-02/PROCEDURE.md` is committed and names all four time
  sources, the extraction method with uncertainty, the ≤ 5 ms criterion,
  the evidence list, and the timing budget table.
- A stranger with the hardware could execute it without asking you
  anything — read it once as that stranger before committing.

## Doc trace

SYS-006 · VT-02 (this is its controlling procedure; executed at
maiden39 bench, maiden60 field) · D4 §Time and synchronization
(clap fallback) · D5 risk R3.
