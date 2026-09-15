# maiden48 — Mount & Mass [bench]

**Sprint goal.** Put the logger in an airframe: CG cradle with proven
vibration isolation, installed mass at or under AB-003's limit, and the
Option 1/Option 2 decision made mechanically.

**Depends on.** maiden47 (logger logging, VT-08 passed); 3D printer;
access to both airframes and a scale.

**Read first.** Lesson 21: *Mass, CG, and vibration*, *Option 2, written
down like an engineer*, and Build steps 4–5 and 7.

**Tasks**

- [ ] CAD and print the CG cradle with foam interface; IMU axes aligned
      with airframe axes; record the mounting rotation in the cradle CAD
      and in `config/aircraft/` (maiden49's converter needs it).
- [ ] Install in the **large airframe first** (D7 flies truth on the
      larger airframe first — risk R5).
- [ ] Vibration A/B (lesson 21 Explore 3): bench run-up with and without
      the foam; compare VIBE levels and clip counts; keep both logs as
      evidence. Acceptance: zero clips with foam.
- [ ] **VT-13:** weigh the complete installed kit (logger, GNSS, power
      tap, cradle, foam, straps, cable); scale photo plus itemized table
      to `results/VT-13/`.
- [ ] If > 60 g on the pattern ship, or its CG can't be restored: invoke
      Option 2 mechanically per lesson 21 — Option 1 on the large
      airframe only, `.ubx`-logging M10 on the pattern ship (D4 IF-3's
      pyubx2 path), attitude truth absent there (D8 gets a dash, not a
      fudge) — and commit the D6/D7 revisions per D5 change control.
- [ ] Extend the serial scheme to airborne kit (MAIDEN-AB-001…) and the
      `config/aircraft/` schema; fold into D4/D6 per D5 change control
      (lesson 21 Explore 4).
- [ ] Print and laminate the preflight/post-flight card: power → 3D fix +
      sat count → log incrementing → clap in front of Station A → fly;
      post-flight: pull SD, `maiden log-inspect`, note anomalies. Into
      the field case.
- [ ] Fill D8's row for VT-13.

**Done when**

- VT-13 pass: ≤ 60 g installed — evidence in `results/VT-13/` (**observe
  on bench**) — or the Option 2 fallback is invoked with its D6/D7
  commits merged.
- Zero IMU clips during run-up with the foam interface; the A/B logs are
  kept.
- Mounting rotation and airborne serials are in `config/aircraft/`;
  preflight card is in the case.

**Doc trace.** AB-003 (VT-13), AB-001 (vibration protects the ATT truth);
D6 cradle/Option 2; D4 IF-3 TMATS fields (mass, mount position); D5
change control, risk R5.
