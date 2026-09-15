# Lesson 99 — The Validation Campaign [field]

*Where we are.* Everything before this lesson happened at a desk or a bench.
Three stations sit in their cases with serials in their TMATS records
(lesson 20). The logger flies on your aircraft and its logs convert cleanly
(lessons 21–22). The pipeline runs end-to-end against the twin, in CI, on
every commit (lessons 06–15, 23–24), and every bench VT has evidence under
`results/`. What you do not have is proof against reality: every residual
you have ever computed was against truth you synthesized yourself. This
lesson is where MAIDEN earns the right to score aircraft that carry nothing
— D1 scenario S3's exact bargain: your own instrumented aircraft flies the
campaign, the fused track is judged against 6-DOF truth, and only if the
gate passes do un-instrumented reports mean anything. It ends at the RCRC
flight line in February with reports in other pilots' hands.

## Objectives

- Pass the CDR+TRR self-review (D5 milestone table) and baseline D2 before
  the first campaign flight.
- Complete the field-dependent Phase 0 survey items, including the
  field-rule polygons that close D2's TBD on SYS-010.
- Fly ≥ 10 instrumented flights over ≥ 3 sessions per D7 §Validation
  campaign, reducing each flight the same evening.
- Run the gate: VT-10/11/12 on ≥ 8 of 10 flights; collect blind judge
  scores and run the VT-21 correlation.
- Fill D8 from campaign data, extract the confidence bands, close the
  remaining P2 VTs, and hold the February demo.

## Concepts

### Verification ends; validation begins

Every test so far answered "did we build it right?" against a criterion you
wrote. The campaign answers "did we build the right thing?" — and D7 is
explicit that truth data cannot answer all of it. The 6-DOF logger settles
SYS-002/003/004; only two human judges scoring the same flights blind can
settle SYS-008. Keep the two threads separate in your head and in your
directories: residuals are arithmetic, judge correlation is a claim about
whether MAIDEN's arithmetic captures what a judge values.

### Why the gate is 8 of 10, not 10 of 10

Field data has bad days: a PPS dropout, a low-sun tracker loss, a survey
bumped by a tripod leg. The gate (D7 §2 step 5) tolerates two failed
flights so that one anomaly doesn't sink a campaign — but every failed
flight still gets a written cause in D8's anomalies section. A failure you
can't explain is worse than a failure you can: it means the confidence
bands you're about to promise un-instrumented pilots are built on a
distribution you don't understand.

### The reduction cadence is the campaign

The single most important discipline here is D7's flight-card line: *same
evening — convert, fuse, residuals, append to campaign table.* A campaign
reduced weeks later is an archaeology project; a campaign reduced nightly
is a feedback loop. If flight 3 shows a survey problem, flights 4–10 get a
better survey. You built `maiden validate` to make an evening reduction a
one-command affair; use it that way.

### Judges are the ceiling, not the target

D8's caveat is load-bearing: judge-to-judge agreement bounds what any
scorer — human or MAIDEN — can achieve. Compute Judge 1 vs Judge 2 r first.
If the judges agree at r = 0.85, then VT-21's r ≥ 0.8 means "MAIDEN is
nearly as consistent with a judge as judges are with each other," which is
the honest claim the demo should make.

Judge-sheet capture format: `config/judge_sheets/README.md` (maiden54).

## Doc Trace

- **Governs this lesson:** D7 §Validation campaign, §Verification against
  6-DOF truth (steps 1–7), §Field demo exit criteria; D5 milestone table
  (Prototype = CDR+TRR, Field Demo = SVR with FCA/PCA) and risk register
  R4/R6/R9; D9 §Session workflow; D1 scenarios S3 and S4.
- **Requirements exercised:** SYS-002/003/004 (VT-10/11/12, the gate),
  SYS-006 (VT-02 field leg), SYS-008 (VT-21), SYS-009 (VT-22), SYS-010
  (VT-23), SYS-011 (VT-24), GS-006 (VT-30), GS-007 (VT-31 if not closed at
  bench).
- **TBD closed:** D2's TBD on SYS-010 — the RCRC field-rule geometry is
  digitized during the survey session below and lands in
  `config/field/rcrc.yaml`.
- **Documents filled/released:** D2 baselined at campaign start; D8 filled
  from campaign data; D9 finalized from what the drills actually taught
  you; tags `v0.2-prototype` at gate pass, `v1.0-field-demo` after the
  demo (D5 §Configuration management).

## Build

What you build in this lesson is procedure and evidence, not code. Each
artifact below is committed before the activity it governs.

### 1. Readiness review (one sitting, before any field day)

Write `results/reviews/CDR-TRR.md` and answer the D5 entry criteria as
verifiable facts, with links:

- [ ] Three stations built, serials MAIDEN-STA-001…003, calibration files
      versioned per serial (D5 §CM).
- [ ] Every P1 bench VT (VT-01…VT-09, VT-13…VT-18) has a result sheet and
      raw evidence under `results/VT-nn/`.
- [ ] D4, D6, D7 complete; D2 baselined — from this commit forward a
      requirement change is a D2 commit with D6/D7 rows updated alongside
      (D5 change control).
- [ ] Twin replay green in CI at the tagged commit you will fly.
- [ ] Flight cards printed (below); consent cards in the case lid (D9).

An unchecked box is a no-go. You are the customer proxy (D5 §Tailoring);
be a difficult one.

### 2. Field survey completion (first field session, no flying)

- Set and photograph permanent marks for A, B, C; 5-min GNSS average at
  each (RTK if the base is up); record in `config/field/rcrc.yaml` and in
  each station's TMATS.
- Tape-measure the A–B baseline as a sanity check on the GNSS solution —
  σ_range scales as R²/B (D3 Figure 2), so this number carries the whole
  error budget.
- Walk the flight line and no-fly boundary with the GNSS receiver;
  digitize the polygons into `config/field/rcrc.yaml`. Commit closes the
  SYS-010 TBD in D2 (one commit: D2 row + config file).
- Note sun azimuth/elevation for your usual session hours; pick which
  session will deliberately face the low sun (D7 conditions).

### 3. Deploy drill — VT-30

Three stopwatch attempts, different days, steps 1–4 of D9's workflow
(deploy → survey → calibrate → record-ready), one person. Pass ≤ 15 min.
Log each attempt's time and what snagged; the snags become D9 edits.

### 4. Field time check — VT-02

The lesson-18 LED rig, outdoors: GPS-PPS-driven LED visible to all three
cameras, same edge logged on the airborne IMU (tap the logger against the
LED mast). Reduce with `maiden.timebase`; pass |Δt| ≤ 5 ms across all four
sources. Do this once per campaign session, not once per campaign.

### 5. The flight card (print ten)

Verbatim from D7, one card per flight, filled in ink at the field:

```
MAIDEN CAMPAIGN FLIGHT ___ / 10        date ______  session ______
[ ] Stations deployed, surveyed, recording; PPS lock A/B/C (Ch 6)
[ ] Logger armed; GPS fix; clap in front of Station A
[ ] Takeoff; sequence per card; land
    sequence flown: ______________________  wind ____ kt  sun ______
    anomalies: ________________________________________________
[ ] Airborne SD pulled
[ ] SAME EVENING: convert, fuse, residuals, appended to campaign table
```

Campaign content per D7: full Sportsman sequence × 6, touch-and-go
series × 2, safety-rule edge cases × 2 flown at a safe margin (these
double as VT-23 data). Conditions: daylight, wind ≤ 15 kt, at least one
low-sun session on purpose. Both airframes fly: the larger ship with the
RTK-capable logger, the pattern ship with the ≤ 60 g build.

### 6. Judge protocol

Recruit two club Pattern judges. They score the six Sportsman flights
blind from Station A video only — no fused track, no MAIDEN scores, no
each other. Standard AMA sheets, one per flight per judge, scanned to
`results/VT-21/`. Consent per D1/D9 applies to everyone who appears on
video. Judge sheets feed two things: the lesson-23 calibration layer's
monotone regression, and the VT-21 correlation itself — fit on a subset,
correlate on the held-out flights, and say so in D8.

### 7. Same-evening reduction

Per flight: `maiden convert` the airborne log, `maiden run --session` the
station files, `maiden validate --session` for residuals, and append the
row — pos RMS, pos p95, vel RMS, continuity, sync status, pass/fail — to
`results/campaign/campaign.csv`, which is D8's accuracy table in raw form.

## Verify

The campaign's verify section *is* the gate, plus the P2 stragglers.

- **The gate (VT-10, VT-11, VT-12).** Across all ten flights: pos RMS
  ≤ 1.0 m at 150 m, vel RMS ≤ 1.0 m/s, continuity ≥ 95 % of sequence
  duration — each on ≥ 8 of 10 flights. `maiden validate --campaign
  results/campaign/` prints the verdict; the verdict plus the table is
  D8's summary block. **Observe in the field** — no number in this course
  predicts your residuals.
- **On failure:** do not lower the thresholds; they are D2's. Work the D5
  mitigations in order of the risk register: R4 first (re-survey, RTK the
  marks, recalibrate intrinsics — survey error swamps fusion), then
  sensor-side (re-aim B, narrower lens), then scope (descope C to
  radar-only per R9 and re-run). Two extra flights beat one excuse.
- **VT-21.** Pearson r between MAIDEN and each judge across maneuvers,
  r ≥ 0.8; report judge-vs-judge r beside it (the ceiling).
- **VT-22.** Threshold speed within 1 m/s of truth on campaign landings;
  glideslope reported with its band.
- **VT-23.** The safety-edge flights: crossing flagged with time and
  location against the polygons you surveyed.
- **VT-24.** Stopwatch, SD pull to PDF in hand, ≤ 10 min.
- **VT-30 / VT-31.** Deploy drill above; battery run ≥ 3 h at full load if
  not already closed at bench.
- **Filling D8.** Every table in the template gets campaign data or a
  dash with a reason: accuracy table (from `campaign.csv`), by-maneuver
  rollup, judge correlation, other-VT table (import your `results/`
  sheets), anomalies — every degraded-sync or tracker-loss flight with
  cause and handling. Then extract the confidence bands: residual p95s
  become the ± bands on every future un-instrumented report, widening
  automatically when EKF covariance exceeds the campaign median (D8
  §Confidence bands). Tag `v0.2-prototype` when the gate passes.

### The demo (February)

Runbook, per D7 exit criteria and D1 S4: solo dry run first (full D9
workflow, no audience); demo day — deploy before the crowd arrives,
consent cards before props turn, record ≥ 3 members' flights, reports
delivered the same session, feedback captured on paper. After-action:
accuracy vs. D3's expectations, tracker behavior in the sun you got,
deploy time reality vs. GS-006 — into D8 §Lessons learned and the D5
successor list (contest assist, member app, live on-station processing).
Release D8 and D9; tag `v1.0-field-demo`. Hold SVR against the D5
checklist: FCA (does the built system match D6?) and PCA (does the
configuration match the tags and serials?). Sign it yourself; you earned
the signature.

## Explore

1. **Cheap truth check.** Before trusting the logger as truth, park the
   aircraft on the surveyed Station A mark for two minutes mid-campaign.
   The fused "track" of a stationary target and the logger's position
   should both sit on a point you know to 0.1 m. Any offset is a frame or
   survey bug that residual RMS would have laundered into noise.
2. **Break the gate on purpose.** Re-run `maiden validate` with Station B
   deleted from one flight's inputs. How far does pos RMS degrade, and
   does the EKF covariance widen enough that the report's bands would
   have confessed? This is D3's R²/B claim, measured instead of derived.
3. **Judge disagreement autopsy.** Find the maneuver where Judge 1 and
   Judge 2 differ most, then look at MAIDEN's deduction list for it.
   Whose side is the geometry on? Write three sentences in D8 §Lessons
   learned; this is R6's mitigation actually happening.
4. **Design friction, one last time.** D7 gates on RMS and continuity but
   the demo's credibility rides on the *worst* maneuver, not the mean.
   Should a p95-per-maneuver criterion join D2 for Phase 2? If yes, make
   the case as a D2 change commit for the successor list — the discipline
   outlives the milestone.

## Checkpoint

- `results/reviews/CDR-TRR.md` exists with every entry criterion checked
  and linked; D2 is baselined; the flown commit is tagged.
- `config/field/rcrc.yaml` holds surveyed station marks, baseline, and
  field-rule polygons; the SYS-010 TBD is closed in D2.
- Three VT-30 drill times ≤ 15 min are logged; VT-02 passed in the field
  each session.
- `results/campaign/campaign.csv` has ≥ 10 flight rows, each reduced the
  same evening; the gate verdict is recorded and — pass or documented
  mitigation cycle — VT-10/11/12 hold on ≥ 8 of 10 flights.
- Judge sheets are scanned; VT-21 r computed with the judge-to-judge
  ceiling beside it; VT-22/23/24/30/31 all have evidence in `results/`.
- D8 is filled, D9 finalized, `v1.0-field-demo` tagged, and at least
  three club members are holding reports MAIDEN wrote about aircraft that
  carried nothing.

---

*Epilogue.* Stand at Station A after the demo and look at what is actually
running: three coherent sensors on a surveyed baseline, a Doppler chain
you built from the mixer up, an EKF fusing angles and radial velocities
into tracks, CFAR heritage in the detector, and a validation report that
traces every claim to a numbered requirement and a flight. Swap the foam
airplane for a quadcopter that doesn't want to be seen, and the same
chain — multi-sensor fusion under weak SNR, track-before-detect pressure,
confidence bands you can defend to a review board — is the counter-UAS
problem the theremin roadmap was aiming at from its first phase
accumulator. The theremin taught you to hear a beat frequency; MAIDEN
taught you to prove one. That proof discipline — requirements, residuals,
evidence directories a stranger could audit — is the artifact an SBIR
reviewer will recognize before they read a single line of VHDL. Write the
proposal. You have the prototype, and the prototype has a paper trail.
