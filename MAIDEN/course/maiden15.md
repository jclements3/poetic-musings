# maiden15 — Ingest round-trip & fuzz [desk]

**Sprint goal.** Close SW-001's desk verification: the twin round-trip
proves values and time survive the full write→read cycle, and the fuzz +
truncation suite proves malformed input cannot crash ingest — VT-14's
desk half, with evidence logged.

**Depends on:** maiden13 (a trusted twin dataset), maiden14.

**Read first:** lesson08.md §Concepts (*Malformed input is a requirement,
not an edge case*), the `test_ingest.py` spec in §Build, §Verify, and
Explore 1–3.

## Tasks

- [x] Round-trip test: run the twin at a fixed `--seed`, ingest Station A,
      join ingested az/el and v_r to `truth.npz` pre-noise values by
      timestamp; assert residual std within [0.7×, 1.3×] of the injected σ
      and residual mean ≈ 0 (the degrees/radians slip detector).
- [x] Ordering test: `t_utc` non-decreasing per source, via
      `check_adapter_stream` from maiden08 — unchanged.
- [x] Fuzz: corrupt the TMATS payload ≥ 500 ways (hypothesis or seeded
      byte-mangler); assert `describe()` raises `TmatsError` or returns a
      descriptor — no other exception type escapes.
- [x] Truncation: chop a twin file at ten random offsets; `load()` yields
      only complete samples and terminates cleanly.
- [x] Explore 1: reorder a copy so data precedes the first time packet
      beyond the queue bound; confirm the `IngestError`; write the
      fail-hard-vs-degrade decision as the `ingest.py` comment maiden26
      will hold you to.
- [x] Explore 3: decide the SNR question — either commit the one-line D4
      IF-4 addition (plus `state.py`) per D5 change control, or write down
      why fusion shouldn't see SNR. No silent information loss.
- [x] Log the passing pytest summary + fuzz case count + git hash to
      `results/VT-14/`.

## Done when

- `pytest software/tests/test_ingest.py -v` is green including fuzz and
  truncation; evidence in `results/VT-14/`.
- Round-trip residuals are zero-mean and match injected σ for both angles
  and v_r.
- The SNR decision exists in writing (a commit either way).

## Doc trace

SW-001 verified (desk) · VT-14 evidence logged · D4 IF-4 change control
exercised · unblocks the EKF sprints (maiden22+) with trusted data.

**Build notes (executed).** Evidence with real numbers in
`results/VT-14/summary.md`. Explore 1 decision: fail hard (recorder
IF-1 violation ≠ degraded sync) — recorded in `ingest.py`'s docstring.
Explore 3 decision: IF-4 stays frozen, SNR not forwarded (tracker SNR
already reaches fusion via `conf`; radar SNR weighting waits for
VT-04/VT-05 bench statistics) — recorded in `ingest.py`'s docstring.
Bonus defect fixed: twin writer leaked `np.float64` reprs into TMATS
survey attributes; one-line producer-side cast in `twin/writer.py`.
