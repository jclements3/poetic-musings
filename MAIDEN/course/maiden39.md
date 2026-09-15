# maiden39 — Time source on the bench [bench]

**Sprint goal.** The disciplined time source runs on real hardware — IRIG-B
verified on the scope against PPS, two independent boards agreeing from one
sky — and the VT-02 LED rig is built with first alignment evidence banked.

**Depends on.** maiden38 (sim green — never flash what hasn't been
simulated); u-blox modules and FPGA boards from maiden30; maiden17's
webcam capture path for the VT-02 first pass (the real station camera
path arrives with maiden41).

**Read first.** lesson18.md § Build 5 "The VT-02 rig", § Verify 2–4; have
lesson 04's `results/VT-02/PROCEDURE.md` (maiden07) open — this sprint
executes its bench portion.

## Tasks

- [ ] Flash the timebase build; wire u-blox PPS in, IRIG-B and PPS to two
      scope channels.
- [ ] Scope the frame — **observe on bench**: confirm 2/5/8 ms symbol
      widths, the double-8 ms frame mark, and P_r's leading edge on the
      PPS edge (expect well under 1 µs; record what you actually see).
      Save captures.
- [ ] SBC → `tod_set` path: feed TOD once from NMEA at startup; hand-check
      one decoded frame against the lesson's bit layout.
- [ ] Two boards, one sky — **observe on bench**: two FPGAs, two GPS
      modules; measure P_r edge agreement (expect ±1 µs class — three
      orders of margin on the 5 ms budget). Log the measurement.
- [ ] Build the VT-02 rig (`hardware/vt02-rig/`): PPS → MOSFET → bright
      LED, 100 ms flash per top of second; header pin for a spare FPGA
      input; the solenoid clicker for the airborne IMU with its
      mechanical delay measured (scope + microphone) and marked
      *tune-on-bench*. Commit schematic + photos.
- [ ] VT-02 first pass — **observe on bench**: LED rig in view of one
      camera via the maiden17 capture path; compare the flash's stamped
      time to the PPS second. Remember the trap: 30 fps quantizes to
      ±16.7 ms, so the stamp must come from the strobe latch, not the
      frame index. Log to `results/VT-02/`.

## Done when

- Scope captures of symbol widths, frame mark, and P_r-vs-PPS alignment
  are committed — **observed, not asserted**.
- Two-board P_r agreement is measured and logged.
- `hardware/vt02-rig/` holds schematic, photos, and the measured clicker
  delay; the rig stays assembled (the full four-source VT-02 completes
  after maiden44/47).
- `results/VT-02/` holds the single-camera first-pass evidence against
  the |Δt| ≤ 5 ms criterion.

## Doc trace

SYS-006, VT-02 (bench portion executed; field/four-source completion in
maiden60), D4 §Time, D5 risk R3, D9 deploy-checklist PPS-lock step.
