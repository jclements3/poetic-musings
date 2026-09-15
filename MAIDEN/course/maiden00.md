# maiden00 — Sprint Index & Backlog

The MAIDEN Prototype build, decomposed into sprint-sized tasks. Each
`maidenNN.md` is one sprint: a chunk one person can finish in one desk
sitting (~1–3 h) or one bench/field session, with a crisp definition of
done. The `lessonNN.md` files are the textbook layer — the concepts, math,
and design reasoning; each sprint card points into its lesson. Sprints say
*do*; lessons say *how and why*.

Work sprints in numeric order unless the card's **Depends on** line says
otherwise. Desk sprints never block on hardware (SEMP twin-first rule).
The three milestone tags from D5 mark the arc: `v0.0-course-start`
(maiden01), `v0.2-prototype` (gate pass, maiden65), `v1.0-field-demo`
(maiden67).

## Sprint card format

Every `maidenNN.md` has exactly:

1. `# maidenNN — <Title> [track]` (desk / bench / field)
2. **Sprint goal** — one sentence.
3. **Depends on** — sprint numbers (and parts/weather gates for bench/field).
4. **Read first** — the lesson section(s) this card executes.
5. **Tasks** — a checkbox list, each item concrete and finishable.
6. **Done when** — verifiable acceptance criteria (the VT criterion where
   one applies; evidence path under `results/` where relevant).
7. **Doc trace** — requirement / VT / D-doc IDs.

## Backlog

| Sprint | Track | Lesson | Title | Deliverable |
|---|---|---|---|---|
| 01 | desk | 00 | Repo, environment, first green test | git repo, pyproject, CI skeleton, tag v0.0-course-start |
| 02 | desk | 01 | The field frame | `maiden/geo.py` + rcrc.yaml + known-answer tests |
| 03 | desk | 02 | Ch. 10 packets: read | packet parser, PyChapter10 cross-check |
| 04 | desk | 02 | Ch. 10 packets: write | writer core, round-trip test |
| 05 | desk | 03 | TMATS template & parser | `station.tmt`, `maiden/tmats.py`, fuzz tests |
| 06 | desk | 04 | TimeDecoder | RTC→UTC mapping, drift/gap tests |
| 07 | desk | 04 | VT-02 procedure | `results/VT-02/PROCEDURE.md` |
| 08 | desk | 05 | State-vector interface | `maiden/state.py`, adapter contract tests |
| 09 | desk | 06 | Maneuver primitives | twin primitives with seam asserts |
| 10 | desk | 06 | The Sportsman script | `sportsman()` truth + Events, physics tests |
| 11 | desk | 07 | Sensor models | az/el + v_r models with noise/dropouts |
| 12 | desk | 07 | Twin → .ch10 | `maiden twin` CLI writing real files |
| 13 | desk | 07 | Triangulation sanity | Monte-Carlo check of σ ≈ R²σ_θ/B |
| 14 | desk | 08 | Ingest decoders | `maiden/ingest.py` channel decoders |
| 15 | desk | 08 | Ingest round-trip & fuzz | twin round-trip, VT-14 suite |
| 16 | desk | 09 | Camera model | `maiden/camera.py`, px→az/el |
| 17 | bench | 09 | Calibration drill | webcam checkerboard run ≤ 0.5 px hold-out |
| 18 | desk | 10 | Twin frame renderer | `twin/render.py` ground-truthed frames |
| 19 | desk | 10 | Candidate pipeline | sky model → candidates + recall harness |
| 20 | desk | 11 | Detector & 2D Kalman | scored detections, per-station track filter |
| 21 | desk | 11 | Track management & metrics | tracks → az/el/conf, VT-15 rehearsal numbers |
| 22 | desk | 12 | EKF core | predict + az/el update + Jacobians + init |
| 23 | desk | 12 | Two-station fusion run | A+B vs twin truth, plots |
| 24 | desk | 13 | Radial-velocity updates | v_r model + chi-square gating |
| 25 | desk | 13 | Dropouts & continuity | full 3-station twin runs, SYS-002/003/004 rehearsal |
| 26 | desk | 14 | Residual pipeline | align → transform → residuals |
| 27 | desk | 14 | Metrics & the gate | D8-schema tables, `maiden validate` CLI |
| 28 | desk | 15 | CI workflow | Actions replay of twin set, thresholds |
| 29 | desk | 15 | VT-18 red-build drill | injected-bug branch goes red, evidence logged |
| 30 | desk | 16 | Order the hardware | BOM committed, orders placed |
| 31 | bench | 16 | Horn & analog chain | printed horn, LNA/AAF board built |
| 32 | bench | 16 | Radar bring-up | module alive on scope, fan/walk targets |
| 33 | desk | 17 | Decimation audit | unambiguous-velocity math, D6 revision commit |
| 34 | desk | 17 | CIC + golden model | `cic_dec` + NumPy golden TB green |
| 35 | desk | 17 | FFT + CFAR in sim | serial FFT, CA-CFAR, `doppler_top` TB green |
| 36 | bench | 17 | VT-04 velocity truth | car-vs-GPS run, ≤ 0.3 m/s, results/VT-04/ |
| 37 | desk | 18 | PPS discipline & RTC | `pps_discipline` sim incl. jitter/holdover |
| 38 | desk | 18 | IRIG-B generator | `irigb_gen` + strobe latch, TB green |
| 39 | bench | 18 | Time source on the bench | scoped IRIG-B, LED rig built |
| 40 | desk | 19 | Recorder core | ring buffers, RTC-ordered writer, rate budget |
| 41 | bench | 19 | Video path | strobe-stamped H.264 into Ch 2 |
| 42 | bench | 19 | VT-01 / VT-03 | 5-min + 10-min bench recordings pass, results/ |
| 43 | bench | 20 | Station 1 assembly | power tree, case, tripod, serials |
| 44 | field | 20 | Survey & calibration drill | VT-06/VT-07 for real, results/ |
| 45 | bench | 20 | The HIL dataset | data/HIL/ recorded, CI replay wired (closes maiden28 TBD) |
| 46 | bench | 20 | Stations 2 & 3, endurance | replicate ×3, VT-31, results/ |
| 47 | bench | 21 | Logger build & bench log | H743 log-only config, VT-08, results/ |
| 48 | bench | 21 | Mount & mass | cradle printed, VT-13 weigh-in, results/ |
| 49 | desk | 22 | .bin → Ch. 10 | pymavlink parser, GPS-time channel, TMATS |
| 50 | desk | 22 | VT-09 round-trip | lossless converter proof + ingest to TRUTH |
| 51 | desk | 23 | Features & rule segmenter | windowed features, template classifier on twin |
| 52 | desk | 23 | Learned classifier | GRU trained on twin seeds, ≥ 90% held-out |
| 53 | desk | 23 | Rubric scoring | geometry checks → 0–10 + deductions |
| 54 | desk | 23 | Calibration layer (untrained) | isotonic rubric→judge fit, awaiting maiden64 data |
| 55 | desk | 24 | The one-page report | PDF + overlays + JSON sidecar |
| 56 | desk | 24 | Approach metrics | glideslope, threshold speed, touchdown |
| 57 | desk | 24 | Field rules & `maiden run` | polygons, crossing Events, end-to-end CLI, 10-min profile |
| 58 | desk | 99 | Readiness review (CDR+TRR) | D5 entry-criteria checklist signed |
| 59 | field | 99 | Survey day | site marks, baselines, polygons digitized |
| 60 | field | 99 | Deploy drill & field VT-02 | VT-30 stopwatch ×3, LED-rig sync check |
| 61 | field | 99 | Campaign session 1 | flights 1–3 flown & reduced same evening |
| 62 | field | 99 | Campaign session 2 | flights 4–7 flown & reduced |
| 63 | field | 99 | Campaign session 3 | flights 8–10+ flown & reduced |
| 64 | desk | 99 | Judge scoring & calibration | blind judge sheets in, VT-21 r computed, maiden54 trained |
| 65 | desk | 99 | The gate & D8 | VT-10/11/12 verdict, D8 filled, tag v0.2-prototype |
| 66 | field | 99 | Phase-2 VTs | VT-23, VT-24, remaining VT-30/31, results/ |
| 67 | field | 99 | Field demo & after-action | D7 exit criteria met, D9 final, tag v1.0-field-demo |

(68–98 unused; 99 reserved: `lesson99.md` is the campaign textbook these
final sprints execute.)

## Reading the split

- Sprints 01–29 are the desk software track — the SEMP's "software
  progresses while hardware iterates." Nothing in them needs a part.
- Sprint 30 (ordering) should happen around the time you start sprint 09,
  so parts arrive before sprint 31.
- Sprints 30–48 are the hardware track; 33–35, 37–38, 40 are desk-side
  VHDL/software you can do while waiting on solder or weather.
- Sprints 49–57 close the pipeline; 58–67 are the campaign and demo.

## Status — desk build run, 21 Aug 2026

Executed autonomously against this backlog (evidence in `results/`, one
commit per sprint batch, suite 214 tests green, `make ci` GREEN).

- **Done (desk):** 01–16, 18–30 (30 = BOM only; orders are yours),
  33–35, 37–38, 40, 49, 51–57. The desk software track is
  feature-complete: `maiden twin | ingest | fuse | validate | run` all
  work end to end; firmware doppler + timebase are sim-verified under
  GHDL.
- **Blocked on hardware/field (yours):** 17 (webcam drill), 31–32, 36,
  39 (bench), 41–48 (bench/field), 50 (needs maiden47's real log),
  58–67 (campaign + demo). VT-09's real pass, VT-01/02/03/04, and
  everything with an "observe on bench" marker are waiting on parts
  from `hardware/BOM.md`.
- **Findings of record (all pinned as tests or doc revisions):** CIC ↓8
  aliases at 24 GHz → D6 revised to R=4; default A-B-C collinear layout
  makes 3-radial velocity rank-2 → survey note for maiden59; classifier
  schedule-memorization caught by level-leg probe; FFT is 139k LUTs
  behavioral → BRAM rewrite before PnR (BOM recommends ULX3S);
  count-only hysteresis boundary flaw in the rules checker; lesson04
  fit() and lesson18 IRIG-B layout errata fixed.
- **One manual step:** `gh auth refresh -h github.com -s workflow`, then
  `git mv ci/github-ci.yml .github/workflows/ci.yml` to activate GitHub
  Actions (local `make ci` is the identical gate meanwhile).
