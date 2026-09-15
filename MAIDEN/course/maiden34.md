# maiden34 — CIC + golden model [desk]

**Sprint goal.** The NumPy golden model exists and `cic_dec.vhd` simulates
green against it with GS-002-tagged asserts and its bit growth written
down.

**Depends on.** maiden33 (R default), theremin toolchain (pinned OSS CAD
Suite, `fpga` alias).

**Read first.** lesson17.md § "CIC, with the growth written down",
§ Build 1 "Golden model first", § Build 2 "cic_dec.vhd".

## Tasks

- [x] `firmware/doppler/golden/model.py`: synthesize I/Q for a commanded
      v_r + noise at commanded SNR; float CIC → FFT → CFAR reference;
      emit (a) stimulus as signed 16-bit text files, (b) expected
      v_r/SNR/bin per 20 ms epoch. Fixed seed; importable from
      `software/tests/` so CI (maiden28) can regenerate stimulus
      deterministically.
- [x] Derive and write down the internal width: N·log2(R·M) growth over
      16-bit input (N = 3: 22 bits at R = 4, 25 at R = 8); put the chosen
      numbers and the output truncation statement in the entity header
      comment — the fixed-point-formats-written-down habit.
- [x] Implement `cic_dec.vhd` to the lesson's pinned entity (generics
      N/R/W_IN; ports clk, rst, in_i/q, in_stb, out_i/q, out_stb),
      house style: numeric_std only, sync active-high reset, registered
      outputs, one entity per file.
- [x] Testbench: golden sine in, compare against model output within
      ±2 LSB, asserts tagged `GS-002`; Makefile per the theremin phase1
      pattern (`sim`, `wave` targets).
- [x] Lesson 17 Explore 1 while you're here: run the golden model with
      R = 8 and 24 GHz constants at 30 m/s, capture the fold plot, and
      link it into `docs/notes/decimation-audit.md` (closes maiden33's
      TODO).

## Done when

- `make sim` in `firmware/doppler/` passes the cic_dec TB: all
  `GS-002 pass:` lines, deltas within ±2 LSB of the golden model.
- Golden model committed with fixed seed; regenerating stimulus twice
  produces identical files.
- The alias fold plot is committed and linked from the audit note.

## Doc trace

GS-002, D6 §FPGA DSP (as revised by maiden33), SW-005 (golden stimulus
feeds the CI replay), theremin-roadmap fixed-point discipline.

## Completion notes (executed 2026-08-21)

- Golden model at `firmware/doppler/golden/model.py` — bit-true integer
  mirror of the RTL, fixed seed 20260821, regeneration byte-identical.
- `make sim TB=cic_dec_tb`: GS-002 pass, 1024 outputs, worst delta
  **0 LSB** (tol 2) — bit-true by construction.
- Widths in the entity header: R=4 → 22-bit internal, R=8 → 25-bit;
  truncating unity-DC-gain output stated.
- Alias fold exhibit: `results/design-notes/alias-fold.png`, linked from
  the audit note (closes maiden33's TODO).
