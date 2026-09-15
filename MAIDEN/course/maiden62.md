# maiden62 — Campaign session 2 [field]

**Sprint goal.** Fly and same-evening-reduce flights 4–7, including the
second airframe and the stationary truth check that catches frame and
survey bugs residual RMS would launder into noise.

**Depends on.** maiden61 (session 1 reduced, fixes applied). Gates:
daylight, wind ≤ 15 kt; if maiden59's sun notes picked this session for
the deliberate low-sun run, schedule accordingly.

**Read first.** lesson99.md — Build §5, §7; Explore 1 "Cheap truth
check"; D7 §Validation campaign (both airframes fly).

**Tasks**

- [ ] Session setup per checklist: deploy, LED sync check, PPS lock
      confirmed.
- [ ] Stationary truth check (lesson99 Explore 1): park the instrumented
      aircraft on the surveyed Station A mark for two minutes mid-session;
      later verify fused track and logger both sit on the known point to
      ~0.1 m. Any offset is a frame/survey bug — stop and fix before
      trusting more flights.
- [ ] Flights 4–5 (pattern ship, ≤ 60 g logger build): full Sportsman
      sequences, cards filled.
- [ ] Flight 6: full Sportsman sequence.
- [ ] Flight 7: touch-and-go series (second of two per D7's content mix).
- [ ] Pull cards, photograph, archive raw data by date.
- [ ] Same evening: convert, run, validate, append flights 4–7 to
      `campaign.csv`; compare residuals across the two airframes and note
      any logger-grade difference (feeds the D2 RTK TBD discussion).

**Done when**

- `campaign.csv` has seven rows, all same-evening reductions.
- The stationary truth check is logged in `results/campaign/` with the
  measured offset — observe in the field.
- Both airframes have flown; per-airframe residual notes exist.
- The low-sun session obligation is either satisfied or explicitly
  assigned to session 3.

**Doc trace.** SYS-002/003/004 data, AB-001/AB-003 (second airframe in
anger), D7 §Validation campaign, D5 risk R4; lesson99 Build §5/§7,
Explore 1.
