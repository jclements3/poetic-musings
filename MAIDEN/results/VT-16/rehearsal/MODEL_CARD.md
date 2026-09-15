# maneuver_mlp_v1 — model card

**Twin-rehearsal evidence only. VT-16 binds on validation flights.**

## What it is

Stage (b) of SW-003: a temporal-context MLP in NumPy standing in for the
D6 GRU (`segment_gru`'s name is the card-pinned contract; the
architecture note in `maiden/maneuver.py`'s docstring explains the
substitution — no torch on the build machine; the post-campaign
fine-tune pass revisits the architecture with field data in hand).

- Input: 9 windowed track features × (2·8+1) context windows (±0.8 s at
  10 Hz), attitude-free by design (FUSED tracks carry no attitude).
- Body: 153 → 64 → 32 → 6 softmax, class-weighted cross-entropy, Adam,
  250 epochs, deterministic seed 20260821. Training ≈ 60–90 s CPU.
- Weights: `software/maiden/data/maneuver_mlp_v1.npz` (versioned; bump
  the filename on retrain, never overwrite silently).

## Training data

14 twin seeds (`sportsman`, randomized Imperfections) as FUSED-like
tracks: 50 Hz, attitude dropped, Gaussian noise at the fusion-residual
scale (pos 0.25 m, vel 0.35 m/s per axis; results/lesson13 headline),
**roll-wobble augmentation 1.0 m** (see below), plus 2 long plain level
legs per seed as negatives. Labels from twin ground-truth Events.
Held-out: 6 entire seeds (100–105) — never windows (windows leak).

## Results (held-out seeds)

Segment-level per-class accuracy: loop 100%, roll 100%, stall_turn
100%, immelmann 100% (rules baseline, attitude-free: 100 / 17 / 100 /
83). Window confusion matrix in `confusion.md`. The ≥90% bar clears —
*at the 1.0 m augmentation point; read the caveats.*

## Caveats, in order of importance

1. **The roll number is bought with augmentation.** The twin sheds zero
   roll wobble; at zero injected wobble the model's roll recall is 0%
   (`sweeps.md`) — correctly, since a wobble-free roll is unobservable
   from pos/vel. The 1.0 m amplitude is a guess at physical reality;
   the campaign measures the real value and this card gets corrected.
2. **Duration-shortcut history.** The first training run scored 100%
   roll recall at zero wobble by memorizing "long straight segment =
   roll" (falsified by a plain 8 s level leg classifying as roll —
   probe in `sweeps.md`). Long-leg negatives in training plus a 2 s
   minimum roll duration at inference killed it: 0 false segments over
   the probe set. Any retrain must re-run that probe.
3. Trained and evaluated on noisy truth as a FUSED stand-in, not on
   full-pipeline FUSED tracks; the rules stage was verified on both.
4. `other` is untrained (the twin never emits it); real flights will.

## Reproduce

    python -m maiden.maneuver train        # weights + confusion
    python -m maiden.maneuver sweep        # wobble sweep + probes
