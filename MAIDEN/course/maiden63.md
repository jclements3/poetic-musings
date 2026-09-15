# maiden63 — Campaign session 3 [field]

**Sprint goal.** Complete the campaign: flights 8–10+ including the two
safety-rule edge cases and any outstanding low-sun obligation, closing
D7's content mix with every flight reduced the same evening.

**Depends on.** maiden62. Gates: daylight, wind ≤ 15 kt; low sun
scheduled here if not already flown; safe-margin plan for the edge-case
flights reviewed on the ground first.

**Read first.** lesson99.md — Build §5, §7; Concepts §"Why the gate is
8 of 10, not 10 of 10"; D7 §Validation campaign (safety-edge content,
conditions).

**Tasks**

- [ ] Session setup per checklist: deploy, LED sync check, PPS lock.
- [ ] Flights 8–9: the two remaining full Sportsman sequences (six total
      across the campaign).
- [ ] Flight 10: safety-rule edge case flown at a safe margin — a
      deliberate flight-line approach/cross on the safe side; this doubles
      as VT-23 data.
- [ ] Flight 11 (if light and battery allow): second safety-edge case per
      D7's ×2; otherwise schedule it into maiden66.
- [ ] If any earlier flight already looks like a gate failure, fly a
      replacement flight now — two extra flights beat one excuse.
- [ ] Pull cards, photograph, archive raw data by date.
- [ ] Same evening: convert, run, validate, append all rows;
      `campaign.csv` now holds the full campaign (≥ 10 flights).
- [ ] Write the first-pass anomalies list: every degraded-sync, tracker
      loss, or procedure deviation across all sessions, with cause where
      known — this becomes D8 §Anomalies.

**Done when**

- `campaign.csv` has ≥ 10 same-evening-reduced rows covering D7's mix:
  Sportsman × 6, touch-and-go × 2, safety-edge × 2 (or the second edge
  case explicitly moved to maiden66) — observe in the field.
- At least one session faced the low sun on purpose, and it is marked in
  the notes.
- The anomalies list exists with a cause (or "unexplained — investigate")
  for every flagged flight.

**Doc trace.** SYS-002/003/004 (full VT-10/11/12 dataset), SYS-010 data
(VT-23), D7 §Validation campaign; lesson99 Build §5/§7.
