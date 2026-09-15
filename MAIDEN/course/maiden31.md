# maiden31 — Horn & analog chain [bench]

**Sprint goal.** Three lined horns and one complete two-channel LNA/AAF
board exist, with the radar module wired in and powered cleanly.

**Depends on.** maiden30 (parts arrived: CDM324 modules, op-amps/passives
kit) plus 3D-printer access. Desk fallback while printing: do the CAD and
board layout first.

**Read first.** lesson16.md § "Horn design from the gain spec", § Build 1
"Horn", § Build 2 "LNA + anti-alias board", § Build 3 "Module wiring".

## Tasks

- [ ] Parametric horn CAD for your band (mouth a×b, length, throat to
      module face) using the lesson's aperture numbers; export STL; commit
      CAD source + STL under `hardware/horn/`.
- [ ] Print three horns + one spare; line with copper tape (smooth,
      overlapping, conductive seams); photo committed.
- [ ] Optional but recommended: print the other band's horn too, so
      VT-05 can be a same-day A/B test.
- [ ] Build one two-channel (I and Q) LNA/AAF chain per the lesson's
      schematic: two ×10 stages (stage-1 gain on a trimmer), Sallen-Key
      LPF R = 8.2 kΩ / C1 = 2.2 nF / C2 = 1 nF, matched components from
      one batch; document values in `hardware/lna/`.
- [ ] Wire the module: RC-filtered quiet 5 V rail, star ground, IF_I and
      IF_Q each through 100 nF into its LNA channel.
- [ ] If your CDM324s turn out to be the single-IF variant, record it in
      `hardware/lna/README` and flag it for the maiden32/VT-05 decision
      per lesson 16's mono-IF note.

## Done when

- `hardware/horn/` holds CAD + STL + photos for the printed horns.
- `hardware/lna/` holds the schematic/values as built, trimmer noted
  *tune-on-bench*.
- Chain powers up; quiet-baseline scope check (lesson 16 Verify 1) shows
  tens-of-mV noise floor at full gain with no 60 Hz or switcher spurs —
  **observe on bench**, capture saved under `results/VT-04/rehearsal/`.

## Doc trace

GS-003 (toward), D6 §Radar front end, D5 risk R2; feeds VT-04/VT-05.
