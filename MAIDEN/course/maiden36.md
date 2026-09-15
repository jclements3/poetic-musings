# maiden36 — VT-04 velocity truth [bench]

**Sprint goal.** The full radar chain — horn, LNA/AAF, ADC, FPGA DSP,
UART — reports live velocities on the bench, and the VT-04 car test is
captured against GPS truth.

**Depends on.** maiden32 (analog chain proven), maiden35 (DSP sim green —
never flash what hasn't been simulated), ADC from maiden30's order; a car,
a passenger or tripod, and a dry parking lot.

**Read first.** lesson17.md § Verify 3 "Bench, fan target" and § Verify 4
"Car test = VT-04"; skim § Explore 2 and 4 for the extra captures worth
taking while set up.

## Tasks

- [ ] Flash `doppler_top`; wire lesson 16's chain → ADC → board → UART →
      laptop. Confirm 50 Hz reports arrive and parse per
      `firmware/recorder/PROTOCOL.md`.
- [ ] Fan target — **observe on bench**: plausible blade-flash
      velocities; SNR collapses when the horn is blocked; save a capture.
- [ ] CFAR check while on the fan (lesson 17 Explore 4): does it pick the
      hub or the strongest blade line? Reconcile with your maiden32
      prediction; note implications for approach-speed scoring
      (resurfaces in maiden56).
- [ ] Car test = VT-04 — **observe on bench**: steady GPS-logged passes
      at 2–3 speeds, both directions (the sign must be right). Log UART
      captures, GPS trace, and a comparison notebook to `results/VT-04/`.
- [ ] Compare reported v_r to GPS speed against the D7 criterion
      (|error| ≤ 0.3 m/s, 50 Hz output). Pass or fail, write the result
      sheet — a fail with a diagnosis is evidence too.
- [ ] Empirical P_fa spot-check if time allows (lesson 17 Explore 2):
      noise-only capture vs the derived α table.

## Done when

- `results/VT-04/` holds UART captures, the GPS trace, the comparison
  notebook, and a one-page result sheet stating measured error vs the
  ≤ 0.3 m/s / 50 Hz criterion — **observed, not asserted**.
- Sign correctness is demonstrated in both directions.
- D8's "Other verification results" row for VT-04 can be filled from
  this directory alone.

## Doc trace

VT-04 (executed), GS-002 (verified), D7 test matrix row VT-04, D8
evidence trail, D5 risk R2.
