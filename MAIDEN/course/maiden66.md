# maiden66 — Phase-2 VTs [field]

**Sprint goal.** Close the remaining Phase-2 verification tests — VT-23
(field-rule flag), VT-24 (report turnaround), and any VT-30/VT-31 still
open — so the demo's exit-criteria checklist has no verification gaps.

**Depends on.** maiden65 (gate passed; report path carries bands),
maiden60 (VT-30 attempts, if any remain), maiden46 (VT-31, if not closed
at bench), maiden63 (safety-edge flight data; fly the second edge case
here if it was deferred). Gates: one field session; safe-margin plan for
any remaining edge-case flight.

**Read first.** lesson99.md — Verify items VT-23, VT-24, VT-30/VT-31; D9
§Session workflow step 6 and §Reading the pilot report (field-rule flags
are informational — MAIDEN does not adjudicate).

**Tasks**

- [ ] VT-23: reduce the safety-edge flights against the maiden59 polygons;
      confirm each deliberate crossing is flagged with time and location
      in the report; fly the second edge case first if maiden63 deferred
      it. Evidence to `results/VT-23/`.
- [ ] VT-24: stopwatch a full turnaround at the field — SD pull to PDF in
      hand — on a real session's data; ≤ 10 min. Record the split times
      (ingest, track, fuse, score, render) so a miss points at its stage.
      Evidence to `results/VT-24/`.
- [ ] VT-30: if fewer than three ≤ 15 min drill attempts are on file from
      maiden60, run the remainder now; evidence to `results/VT-30/`.
- [ ] VT-31: if not closed at bench in maiden46, run one station ≥ 3 h at
      full load (recording, radar, camera) on battery; log voltage curve
      to `results/VT-31/`.
- [ ] Update D8's other-VT table with all four results.

**Done when**

- VT-23, VT-24, VT-30, VT-31 each have a pass result and raw evidence
  under `results/` — observe in the field; a miss is logged with cause
  and a fix plan, not reworded.
- D8's other-VT table is complete for every P1 and P2 test.
- Nothing on D7's field-demo exit-criteria list is blocked by a missing
  verification result.

**Doc trace.** SYS-010 (VT-23), SYS-011 (VT-24), GS-006 (VT-30), GS-007
(VT-31), D7 §Field demo exit criteria, D9 §Session workflow; lesson99
Verify.
