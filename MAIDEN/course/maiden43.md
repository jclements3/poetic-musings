# maiden43 — Station 1 Assembly [bench]

**Sprint goal.** Turn the bench pile into MAIDEN-STA-001: powered from one
pack, cased, on a tripod, with its serial and per-serial calibration files
under configuration management.

**Depends on.** maiden31–32, maiden36, maiden39, maiden42 (every subsystem
bench-proven); parts on hand (case, tripod, leveling head, bucks, INA219,
LiFePO₄ pack).

**Read first.** Lesson 20: *The power tree*, *Serials and per-serial
calibration — CM for hardware*, and Build steps 1–3.

**Tasks**

- [ ] Wire the power tree (4S LiFePO₄ → fuse → 12 V and 5 V bucks, INA219
      shunt on the 5 V loads) on the bench.
- [ ] Measure every rail at idle and while recording; size the blade fuse
      at 2× measured peak; log dated draws in
      `hardware/stations/power-budget.md`.
- [ ] Mount into the weatherproof case with glands for antenna, camera,
      and GNSS; fit tripod, leveling head, and sighting rail along the
      camera boresight.
- [ ] Photograph the internal layout before closing the lid (goes into the
      build checklist in maiden46).
- [ ] Create `config/stations/MAIDEN-STA-001/` (`station.yaml`,
      `intrinsics.yaml`, `boresight.yaml`) and point the recorder's TMATS
      builder at it.
- [ ] Add the pytest schema check over `config/stations/` (required keys,
      dated calibrations) — D5 risk R4's cheap insurance.
- [ ] Confirm survey values (position, heading) are per-*session* entry at
      deploy, not baked into per-serial files, and build the entry path
      (host-app CLI per lesson 20 Explore 4); update D6 and D9 step 2 to
      match what you built.

**Done when**

- Station 1 records a full session on battery power, cased, on the tripod
  (**observe on bench**).
- Measured power budget committed; projected endurance ≥ 3× GS-007's 3 h
  at measured draw.
- Schema pytest green; the recorder's TMATS carries serial
  MAIDEN-STA-001 and the per-serial calibration values.
- D6/D9 survey-entry revision committed per D5 change control.

**Doc trace.** GS-006/GS-007 (hardware form), GS-001–GS-005 (physical
completion); D6 "Power and enclosure"; D5 §CM, risks R4/R8. Endurance
pass/fail (VT-31) is maiden46; deploy-time pass/fail (VT-30) is maiden60.
