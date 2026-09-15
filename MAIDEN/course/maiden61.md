# maiden61 — Campaign session 1 [field]

**Sprint goal.** Fly and same-evening-reduce campaign flights 1–3: the
first real data MAIDEN has ever been judged against, with the reduction
cadence established from flight one.

**Depends on.** maiden60 (drill and field VT-02 passed), maiden47/48
(logger flight-ready on both airframes), maiden50 (converter). Gates:
daylight, wind ≤ 15 kt (D7 conditions); printed flight cards from
maiden58.

**Read first.** lesson99.md — Concepts §"The reduction cadence is the
campaign", Build §5 "The flight card (print ten)", §7 "Same-evening
reduction"; D7 §Validation campaign (content and conditions).

**Tasks**

- [ ] Session setup: deploy per the drilled checklist; run the LED sync
      check (per-session VT-02); confirm PPS lock on A/B/C via Ch 6.
- [ ] Flight 1 (larger ship, RTK logger): full Sportsman sequence; flight
      card filled in ink — sequence, wind, sun, anomalies.
- [ ] Flight 2: full Sportsman sequence, card filled.
- [ ] Flight 3: touch-and-go series, card filled.
- [ ] Pull all SD cards; photograph the filled cards into
      `results/campaign/cards/`.
- [ ] Same evening: `maiden convert` each airborne log, `maiden run
      --session`, `maiden validate --session`; append one row per flight
      (pos RMS, pos p95, vel RMS, continuity, sync, pass/fail) to
      `results/campaign/campaign.csv`.
- [ ] Read the residuals that night: if anything smells like survey or
      calibration error (D5 risk R4), schedule the fix before session 2 —
      that feedback loop is the point of the cadence.

**Done when**

- Three flights flown under D7 conditions with filled cards — observe in
  the field.
- `campaign.csv` has three rows, each reduced the *same evening* as its
  flight; raw `.ch10` archived unmodified under `data/` by date.
- Any anomaly has a written note on its card and, if actionable, a fix
  scheduled before session 2.

**Doc trace.** SYS-002/003/004 data (toward VT-10/11/12), SYS-006
(per-session VT-02), D7 §Validation campaign, D5 risks R4/R9; lesson99
Build §5, §7.
