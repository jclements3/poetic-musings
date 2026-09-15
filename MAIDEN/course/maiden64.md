# maiden64 — Judge scoring & calibration [desk]

**Sprint goal.** Collect blind judge scores on the six Sportsman flights,
compute the VT-21 correlation with the judge-to-judge ceiling beside it,
and train the sprint-54 calibration layer on a fit subset with honest
held-out reporting.

**Data contract.** Judge sheets follow `config/judge_sheets/README.md` (one row per maneuver per judge per flight; contract defined in maiden54).

**Depends on.** maiden63 (six Sportsman flights recorded), maiden54
(untrained isotonic calibration layer), maiden57 (MAIDEN scores per
flight). Gates: two club Pattern judges recruited; signed consent from
everyone appearing on Station A video.

**Read first.** lesson99.md — Concepts §"Judges are the ceiling, not the
target", Build §6 "Judge protocol"; D8 §Judge correlation (the caveat
row); D1 §Users (contest director, consent).

**Tasks**

- [ ] Prepare the blind package: Station A video per Sportsman flight —
      no fused track, no MAIDEN scores, judges isolated from each other.
- [ ] Each judge scores all six flights on standard AMA sheets, one sheet
      per flight per judge.
- [ ] Scan every sheet to `results/VT-21/`; transcribe to
      `results/VT-21/judges.csv`.
- [ ] Compute Judge 1 vs Judge 2 r per maneuver and overall — the ceiling
      goes in the table first.
- [ ] Split flights into a calibration-fit subset and held-out flights;
      record the split before fitting.
- [ ] Train the lesson-23 monotone (isotonic) regression on the fit
      subset; commit the fitted layer with its provenance.
- [ ] Compute MAIDEN vs each judge Pearson r on the held-out flights, per
      maneuver and overall (VT-21); state the fit/holdout split in the
      write-up.
- [ ] Run the judge-disagreement autopsy (lesson99 Explore 3): worst
      judge-vs-judge maneuver vs MAIDEN's deduction list; three sentences
      into the D8 §Lessons-learned notes.

**Done when**

- All sheets scanned, `judges.csv` committed, consent forms on file.
- VT-21 result recorded: held-out r ≥ 0.8 target, reported next to the
  judge-to-judge ceiling — a miss is reported, not massaged.
- The calibration layer is trained, committed, and future reports use it.
- The autopsy paragraph exists for D8.

**Doc trace.** SYS-008 (VT-21), SYS-007 (scores under judgment), D5 risk
R6, D8 §Judge correlation, D1/D9 consent; lesson99 Build §6, Explore 3.
