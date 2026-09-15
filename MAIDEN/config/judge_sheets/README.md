# Judge-sheet CSV contract (SYS-008 / VT-21; maiden64 produces these)

One CSV per session under this directory, named
`judges_<flightdate>_<session>.csv`. This is a **contract, not a wish**:
`maiden.score.Calibration.fit` and maiden64's correlation analysis both
parse exactly this shape, and the campaign's blind-scoring procedure
(lesson 99; AMA §18.7: two judges, scored individually, no consultation)
fills it in.

## Columns

```
flight_id,judge_id,maneuver_index,maneuver_class,judge_score
F03,J1,2,loop,7.5
F03,J2,2,loop,8.0
```

- `flight_id` — campaign flight card id (F01…F10+), matches the session
  directory and D8's accuracy-table Flight column.
- `judge_id` — J1/J2 (anonymized; the mapping to names stays on paper
  with the consent forms).
- `maneuver_index` — 0-based index into that flight's `score_sequence`
  output in schedule order; rubric rows and judge rows join on
  (flight_id, maneuver_index).
- `maneuver_class` — one of maiden.maneuver.CLASSES; must agree with the
  rubric row it joins to (disagreement = recognition error, log it, do
  not silently drop).
- `judge_score` — 0–10, half-points allowed. One row per maneuver per
  judge per flight; never average judges in this file (J1-vs-J2
  agreement is the VT-21 ceiling and D8 reports it).

Rows with unscored maneuvers (judge wrote "NO" / not observed) are
omitted, not zero-filled.
