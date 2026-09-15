# VT-16 rehearsal — twin-only evidence

Learned-classifier rehearsal on held-out twin seeds. **VT-16
binds on validation flights**; these are twin numbers.
Training: 14 seeds, held-out 6 seeds (split BY SEED), wobble augmentation 1.0 m,
epochs 250, deterministic seed 20260821, runtime 90 s CPU.

## Segment-level per-class accuracy (held-out seeds, %)

| class | rules (a), no att | MLP (b) |
|---|---|---|
| loop | 100.0 | 100.0 |
| roll | 16.666666666666664 | 100.0 |
| stall_turn | 100.0 | 100.0 |
| immelmann | 83.33333333333334 | 100.0 |

## Window confusion matrix (rows=truth, cols=pred)

| | level_leg | loop | roll | stall_turn | immelmann | other |
|---|---|---|---|---|---|---|
| level_leg | 1641 | 0 | 7 | 1 | 3 | 0 |
| loop | 0 | 574 | 0 | 1 | 0 | 0 |
| roll | 14 | 0 | 224 | 0 | 0 | 0 |
| stall_turn | 1 | 4 | 3 | 809 | 4 | 0 |
| immelmann | 0 | 0 | 0 | 0 | 371 | 0 |
| other | 0 | 0 | 0 | 0 | 0 | 0 |
