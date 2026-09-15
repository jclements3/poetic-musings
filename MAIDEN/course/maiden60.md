# maiden60 — Deploy drill & field VT-02 [field]

**Sprint goal.** Prove one person can stand up all three stations in
≤ 15 minutes (VT-30, three stopwatch attempts) and that end-to-end time
alignment holds in the field (VT-02 with the LED rig) before any campaign
flight is spent.

**Depends on.** maiden59 (surveyed marks), maiden39 (LED rig built),
maiden46 (all three stations). Gates: field access on ≥ 2 different days
(the three drill attempts must not all share one day's luck); flyable
weather not required.

**Read first.** lesson99.md — Build §3 "Deploy drill — VT-30" and §4
"Field time check — VT-02"; D9 §Session workflow steps 1–4.

**Tasks**

- [ ] Drill attempt 1: solo, stopwatch, D9 steps 1–4 (deploy → survey →
      calibrate → record-ready) on the surveyed marks; log the time and
      every snag.
- [ ] Fix the snags (case packing, cable dressing, checklist wording) and
      fold them into D9 as edits.
- [ ] Drill attempts 2 and 3 on different days; log times to
      `results/VT-30/`.
- [ ] Set up the lesson-18 LED rig outdoors: GPS-PPS-driven LED visible to
      all three cameras; tap the logger against the LED mast so the same
      edge lands on the airborne IMU.
- [ ] Record the sync event, reduce with `maiden.timebase`, and compute
      the four-way |Δt|; log to `results/VT-02/`.
- [ ] Add "LED sync check" to the per-session setup checklist — lesson99
      requires it once per campaign session, not once per campaign.

**Done when**

- Three logged drill attempts, each ≤ 15 min, with snag notes — observe in
  the field, evidence in `results/VT-30/`.
- Field VT-02 passes: |Δt| ≤ 5 ms across all three cameras and the
  airborne IMU, evidence in `results/VT-02/`.
- D9 carries the drill-taught edits; the session checklist includes the
  per-session sync check.

**Doc trace.** GS-006 (VT-30), SYS-006 (VT-02 field leg), D9 §Session
workflow, D5 risk R8; lesson99 Build §3–§4.
