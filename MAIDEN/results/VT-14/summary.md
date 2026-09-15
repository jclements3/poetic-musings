# VT-14 evidence — ingest interface (desk half)

- Code: commit 407b9dd (+ maiden14/15 working tree at capture time)
- Suite: `pytest software/tests/test_ingest.py test_ingest_fuzz.py`
  → **12 passed** (full repo suite: 87 passed; ruff clean)
- Fuzz: **500 seeded TMATS mutations** (seed 20260821, flip/delete/insert/
  truncate/junk) — every case returned a descriptor or raised `TmatsError`;
  no other exception type escaped. Both outcomes exercised.
- Truncation: 10 seeded chop offsets — only complete, valid samples
  yielded; clean termination each time.
- Hold-back: >2 s of data before the first Ch 1 time packet raises the
  IF-1 `IngestError` (fail-hard decision recorded in `ingest.py`'s module
  docstring; maiden26 holds us to it).
- Round-trip vs pre-noise twin truth (seed 101, Station A,
  1837 tracker / 3059 radar samples):
  - az residual: mean +7.9e-04 deg, std 0.02938 deg (injected sigma 0.02865)
  - el residual: mean +4.5e-04 deg, std 0.02870 deg
  - v_r residual: mean -3.7e-03 m/s, std 0.1502 m/s (injected sigma 0.15)
  All zero-mean within 0.1 sigma; std within [0.7, 1.3]x sigma. No unit slips.
- Walker memory: tracemalloc peak < 64 KiB over a 216 KiB file
  (packet-sized, not file-sized). Bench-scale RSS check deferred to a
  real multi-GB session (maiden42+).
- SNR decision (lesson 08 Explore 3): D4 IF-4 left frozen — rationale in
  `ingest.py` docstring; revisit after VT-04/VT-05 bench data.
- Defect found & fixed en route: twin writer leaked `np.float64` reprs
  into TMATS survey attributes (caught by `describe()` round-trip).
