# VT-20 rehearsal: rubric layer output on twin sessions (maiden53)

All numbers from real runs at build time (seed 0, 50 Hz truth samples,
ground-truth events; deterministic — see test_determinism_bit_for_bit).

Clean session — the null test:

    loop        10.0  no deductions
    roll        10.0  no deductions
    stall_turn  10.0  no deductions
    immelmann   10.0  no deductions

Imperfect (loop_ovality=0.15, roll_drift_deg=8, alt_mismatch_m=6,
center_offset_m=40):

    loop         2.4  loop radius varies 2.3 m about the 47 m fit; loop
                      13.7 m taller than wide; loop centered 41 m from
                      the centerline; loop exits 6.0 m above entry altitude
    roll         8.8  roll exits 8.0 deg off entry heading
    stall_turn   9.5  stall turn exit line 8.0 deg off the box axis
    immelmann   10.0  no deductions

Notes of record: (1) VT-20 binds as a Demonstration on recorded field
data; this is the twin rehearsal of its shape. (2) Downgrade magnitudes
are MAIDEN's own (config/rubric.yaml provenance header) until maiden64
trains the calibration layer. (3) The four-knob loop stacking to 2.4 is
deliberate: it shows itemization, not a claim about how a judge would
total the same flight — that claim is SYS-008's, at VT-21.
