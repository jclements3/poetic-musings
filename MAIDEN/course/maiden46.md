# maiden46 — Stations 2 & 3, Endurance [bench]

**Sprint goal.** Replicate Station 1 into MAIDEN-STA-002 and -003 from a
written checklist, calibrate each serial independently, and retire VT-31.

**Depends on.** maiden43–44 (Station 1 assembled, procedure drilled);
parts for two more stations, including Station B's 35° lens.

**Read first.** Lesson 20: Build step 6 (replicate ×3) and the VT-31
procedure in its Verify section.

**Tasks**

- [ ] Write `hardware/stations/BUILD-CHECKLIST.md` *while* building -002 —
      unit two is where the gaps in your memory of unit one surface.
- [ ] Build -002 and -003 per the checklist; Station B gets the 35° lens
      per D6, so its `station.yaml` and intrinsics differ — nothing else
      should.
- [ ] Create `config/stations/MAIDEN-STA-002/` and `-003/`; calibrate each
      serial independently (never copy an intrinsics file); extend the
      schema pytest to reject two stations with byte-identical intrinsics.
- [ ] Rerun the VT-07 hold-out check on -002 and -003 in their cases;
      append per-serial reports to `results/VT-07/`.
- [ ] **VT-31:** full-load recording until the 5 V rail sags or 4 h
      elapses, Ch 6 telemetry as the log — outdoors on a cold day if you
      can arrange it; note the temperature. Log the discharge curve to
      `results/VT-31/`.
- [ ] Thermal soak (lesson 20 Explore 2): closed case, sun or heat lamp,
      full load, 1 h; plot SoC temperature from Ch 6; add a vent or
      heatsink now if the Pi throttles.
- [ ] Dress-rehearse the solo three-station deploy in the yard, stopwatch
      running (lesson 20 Explore 1); feed the top two time sinks back into
      the checklist.
- [ ] Fill D8's rows for VT-07 (all serials) and VT-31.

**Done when**

- Three stations record simultaneously on battery power (**observe on
  bench**).
- VT-31 pass: ≥ 3 h at full load — discharge curve in `results/VT-31/`.
- VT-07 pass on all three serials; schema pytest enforces independent
  calibration.
- The build checklist is complete enough to build station 4 without
  lesson 20 open.

**Doc trace.** GS-007 (VT-31), GS-005 (VT-07 ×3), GS-006 groundwork; D6
station roles (B's lens); D5 risks R4/R8; D8 rows.
