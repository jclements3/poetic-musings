# maiden50 — VT-09 Round-Trip [desk]

**Sprint goal.** Prove the converter lossless: values and GPS-aligned
times survive `.bin` → `.ch10` → ingest untouched, and the converted file
loads as TRUTH StateSamples in the field frame.

**Depends on.** maiden49 (converter), maiden15 (ingest round-trip suite),
maiden47 (a bench log with GPS lock — the balcony capture, not the
basement one).

**Read first.** lesson22.md — the Verify section, plus the Build
section's paragraph on the ingest-side `Aircraft` descriptor branch.

**Tasks**

- [ ] Extend lesson 08's TMATS handling with the `Aircraft` descriptor
      branch: converted files load as `source="TRUTH"` StateSamples with
      `pos_enu`/`vel_enu` through `maiden.geo` (field-frame origin comes
      from the *session's station* TMATS, not the aircraft file) and
      `att_rpy` from ATT.
- [ ] `software/tests/test_convert_roundtrip.py`: parse the `.bin`
      directly with pymavlink, read the `.ch10` back through
      `maiden.ingest`, compare stream by stream — identical sample
      counts, values equal within float32 quantization, timestamps equal
      within the fit residual. A dropped or duplicated sample fails.
- [ ] Time-alignment assertion: first Ch 1 packet UTC == first GPS fix
      UTC (leap included) to the millisecond.
- [ ] Rate check on the converted file (VT-08 evidence): GPS ≥ 10 Hz,
      IMU ≥ 100 Hz, baro ≥ 10 Hz, no gaps > 2× nominal interval.
- [ ] Run the whole thing on the bench log; record the fit residual and
      the result sheet under `results/VT-09/` (observe on bench log —
      your number, not a typed one).
- [ ] Explore (pick one): the leap-second injection drill from
      lesson 22 — add 1 s, predict the position error at 30 m/s before
      running, confirm which check catches it; or the truncated-log
      policy decision, documented in the converter docstring.

**Done when**

- `pytest software/tests/test_convert_roundtrip.py` passes: lossless
  values, GPS-aligned times, VT-08 rates.
- `maiden.ingest.load()` yields TRUTH StateSamples from the converted
  bench log, in the field frame, with `att_rpy` populated.
- Result sheet + fit residual committed under `results/VT-09/`.

**Doc trace.** AB-002 verified by VT-09; VT-08 evidence on the converted
file; SYS-006 airborne clause demonstrated; feeds lesson 14's truth side.
