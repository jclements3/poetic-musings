# maiden52 — Learned Classifier [desk]

**Sprint goal.** Train the D6 temporal GRU on twin sequences with
randomized imperfections and beat (or honestly fail to beat) the rule
baseline on held-out twin seeds.

**Depends on.** maiden51 (features + rule baseline + Event contract),
maiden12 (`maiden twin --imperfect --seed N`).

**Read first.** lesson23.md — *Two classifiers, in the right order*
(stage (b)), and the `train/train_maneuver.py` item in the Build section.

**Tasks**

- [x] `segment_gru(ff, model_path) -> list[Event]` — same Event contract
      as `segment_rules`, so downstream code can't tell which ran.
- [x] `train/train_maneuver.py`: generate N twin sessions across seeds
      with imperfections; build (features, label) windows from twin
      Events; train a small GRU (PyTorch, ~2 layers, hidden ≤ 64 — must
      run on your CPU).
- [x] Hold out **entire seeds**, never windows — windows leak.
- [x] Evaluate on ≥ 5 held-out seeds; write the model, per-class
      accuracy, and confusion matrix to `results/VT-16/rehearsal/`.
- [x] Compare against maiden51's rule baseline in one table (baseline
      row first — that's what it's for).
- [x] Explore: the roll-recall sweep — shrink the twin's roll
      lateral-wobble amplitude toward zero, plot both classifiers' roll
      recall, and record the wobble level you believe is physical for
      your airframe in the model card (campaign will correct you).
- [x] Doc friction check from lesson 23's Explore: compare SW-003's
      class list against the current AMA Sportsman schedule; if drifted,
      revise D2/D6/D7 per D5 change control now.

**Done when**

- A trained model + confusion matrix + baseline comparison are committed
  under `results/VT-16/rehearsal/`; you know your per-class numbers.
- Held-out per-class accuracy clears the ≥ 90% bar on twin data (the
  VT-16 rehearsal — if the twin can't clear it, iterate features before
  reaching for a bigger model).
- Training is reproducible: seeded, one command, documented runtime.

**Doc trace.** SW-003; VT-16 (rehearsal — the binding test is on
validation flights, fine-tuning happens after the campaign); D6
§Maneuver segmentation; D5 change control if the class list drifted.

---

**Execution notes (maiden52, desk).** Model = temporal-context MLP in
NumPy (no torch on this machine; name `segment_gru` kept per the card's
contract; MODEL_CARD.md documents the substitution and the
post-campaign revisit). Held-out (6 whole seeds): loop/roll/stall_turn/
immelmann all 100% at the 1.0 m wobble-augmentation training point vs
rules baseline 100/17/100/83. THE FINDING OF RECORD: the first model
scored 100% roll recall at zero wobble by memorizing "long straight
segment = roll" — falsified by a plain 8 s level leg classifying as
roll. Fixed with long-leg training negatives + a 2 s minimum roll
duration; the probe and the now-honest sweep (0% recall at zero wobble,
100% at 1.0 m) are pinned as regression tests. The twin itself sheds
zero roll wobble — fold-back flagged: a wobble knob belongs in
twin.Imperfections. AMA class-list drift check deferred to maiden53's
rulebook fetch (no rulebook on disk yet; classes in SW-003 unchanged
from D2 Rev 0.1). Training: `python -m maiden.maneuver train` (~60-90 s
CPU, seed 20260821); weights software/maiden/data/maneuver_mlp_v1.npz.
