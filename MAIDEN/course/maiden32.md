# maiden32 — Radar bring-up [bench]

**Sprint goal.** The analog front end demonstrably sees moving targets:
fan, walking human, and a GPS-logged car, with scope evidence banked.

**Depends on.** maiden31.

**Read first.** lesson16.md § Build 4 "Bench targets", § Verify (all four
steps), § "The target is terrible, and that's the point".

## Tasks

- [ ] Fan test at 2 m: scope-FFT screenshot of the blade-flash tone
      cluster; confirm I and Q similar in amplitude and ~90° apart
      (X-Y mode draws a rough circle for a single mover).
- [ ] Walk test: steady pace toward the horn; check tone frequency
      against the band's per-m/s constant (≈161 Hz/(m/s) at 24 GHz,
      ≈70 at 10.5 GHz) within ~20%; confirm the I/Q rotation direction
      flips when walking away.
- [ ] Car rehearsal: parking lot, steady GPS-logged radial passes at
      50–150 m; note the range where the tone still clears the floor on
      the scope FFT. Save scope captures + GPS trace.
- [ ] Explore A/B (lesson 16 Explore 1): same fan, same distance, CDM324
      horn vs HB100 horn; compare tone SNR and record which band's analog
      chain looks healthier.
- [ ] Explore horn check (Explore 2): repeat the walk test bare-module;
      estimate real horn gain from the SNR delta vs the 15 dBi design
      value; note it in `hardware/horn/`.
- [ ] Write down the current *leading* module for GS-003 and what VT-05
      evidence will make it final (decision commits to D2 + D6 together,
      per D5 change control — the commit itself happens when VT-05 runs
      at the field with lesson 20's outing).

## Done when

- All results are **observe on bench**: quiet-baseline, fan, walk, and
  car-rehearsal captures logged under `results/VT-04/rehearsal/` with a
  short README naming the setup for each.
- Walk-test frequency matches the per-m/s constant within ~20% and the
  sign behavior (rotation flip) is demonstrated.
- The band A/B comparison and the provisional GS-003 module choice are
  written down where maiden36/VT-05 will find them.

## Doc trace

GS-003 (evidence toward), VT-04 (rehearsal), VT-05 (expectations set),
D5 risk R2, D2 TBD on GS-003 (closure deferred to VT-05 field data).
