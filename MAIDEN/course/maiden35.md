# maiden35 — FFT + CFAR in sim [desk]

**Sprint goal.** `fft512_serial`, `cfar`, and `doppler_top` simulate green
against the golden model, and the synthesis/timing budget verdict (hx8k or
the ECP5 hatch) is recorded.

**Depends on.** maiden34.

**Read first.** lesson17.md § "The FFT, honestly budgeted", § "CA-CFAR
from first principles", § Build 3–5, § Verify 1–2.

## Tasks

- [x] `fft512_serial.vhd` to the pinned port contract (sample_i/q +
      sample_stb at the decimated rate, `start` 50 Hz tick, streamed
      mag/mag_bin/mag_stb, done): circular input BRAM with sliding start
      pointer (the ~75%/~53% overlap is a feature — no fill-then-dump),
      ping-pong work BRAM, serialized shift-add butterfly, quarter-wave
      twiddle ROM, bit-reverse on readout.
- [x] FFT TB: impulse → flat magnitude; single tone → energy in the right
      bin; golden-model comparison within a stated tolerance.
- [x] Derive P_fa = (1 + α/N_t)^(−N_t) (three lines from the exponential
      CDF) and tabulate α for P_fa = 10⁻³ and 10⁻⁴ at N_t = 16; put the
      table in the cfar header comment.
- [x] `cfar.vhd`: streaming CA-CFAR over 512 magnitudes, generics
      TRAIN/GUARD/ALPHA_Q8; outputs peak bin, peak mag, noise estimate →
      SNR; magnitude via |I|+|Q|/2-style or α-max-plus-β-min (no square
      roots on iCE40). TB drives golden spectra at known injected P_fa.
- [x] `doppler_top.vhd`: ADC SPI master → cic_dec → fft512 → cfar → v_r
      scaling (λ generic, sign from spectrum half) → theremin `uart_tx`
      verbatim at 50 Hz (v_r, SNR, bin); no-detection ⇒ v_r held invalid
      with SNR-below-threshold report; raw I/Q pass-through for Ch 3;
      2-FF sync on all async. Frame the UART records per
      `firmware/recorder/PROTOCOL.md` — the shared tagged-record framing
      the recorder (maiden40) parses; create the file with the doppler
      record types if maiden40 hasn't yet.
- [x] Integration TB: golden I/Q file in, UART decoded out, v_r tracks a
      commanded velocity ramp — asserts tagged `GS-002`.
- [x] `make synth && make time` for hx8k; read the stat line (LUTs, EBR,
      fmax) and record it in the commit message. If it doesn't close,
      take the ECP5 hatch and revise D6 to say so.

## Done when

- `make sim` green for fft512_serial, cfar, and doppler_top, all
  GS-002-tagged, all driven by the committed golden model.
- The α/P_fa table and the magnitude-approximation choice are documented
  in the source headers.
- Synthesis + icetime numbers recorded; board decision (hx8k vs ECP5) is
  in the commit message and, if changed, in D6.

## Doc trace

GS-002, D6 §FPGA DSP, VT-04 (sim half — bench half is maiden36), SW-005
(TBs join the CI replay), D5 risk R2.

## Completion notes (executed 2026-08-21)

- `make sim` green for all four TBs (GS-002-tagged, golden-driven):
  - fft512_serial: impulse + tone frames, 512 bins each, worst delta
    0 LSB; tone peak lands at bin 37 as commanded.
  - cfar: 8 spectra, detections and rejections exact (incl. noise_est).
  - doppler_core (integration): 1.0 s golden 12→18 m/s ramp at 48 kS/s,
    51 UART records decoded, 48 checked, worst |v−cmd| **7 cm/s**.
- α/P_fa table (N_t=16: 1e-3→2212 Q8, 1e-4→3187 Q8) derived in the cfar
  header; max+min/2 magnitude choice documented in fft512_serial.
- `firmware/recorder/PROTOCOL.md` created: framing + DOPPLER_V (0x01);
  0x02/0x03 reserved for maiden38, 0x04 for maiden40. Invalid epochs
  still ship records (gap-free Ch 4, EKF skips explicitly).
- Synthesis verdict (yosys synth_ice40, 9 min): **139 008 SB_LUT4 /
  ~46 k FF, zero memories inferred** — behavioral arrays (FFT work RAM,
  circular buffer, CFAR spectrum) all became registers. ~18× over hx8k;
  does not fit ECP5-85F as written either. icetime not run (nothing to
  time at that size). Required next step recorded in D6: BRAM-explicit
  memory rewrite (true single-port access patterns), then the board
  call — ECP5/ULX3S likely — at maiden36 bench bring-up. Deviations:
  butterfly uses direct `*` (not serialized shift-add) and the twiddle
  ROM is unfolded half-spectrum — both flagged in source headers as
  budget work for the rewrite pass, not behavior changes.
