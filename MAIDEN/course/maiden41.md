# maiden41 — Video Path [bench]

**Sprint goal.** Make `CameraSource` real: strobe-stamped frames,
hardware H.264 encode, and Ch 2 packets whose IPTS come from the FPGA's
latched RTC, not the SBC's clock.

**Depends on.** maiden40 (recorder core), maiden39 (strobe latch working on
the bench), camera + SBC on hand.

**Read first.** Lesson 19: *Frames meet timestamps*, plus the
`CameraSource` bullet in its Build section.

**Tasks**

- [ ] Wire the camera strobe output to the FPGA GPIO and confirm
      `(frame_index, rtc)` latch records arrive up the UART per
      `PROTOCOL.md`.
- [ ] Implement frame capture (V4L2 / Picamera2) with hardware H.264
      encode on the SBC.
- [ ] Implement the association queue: pair encoded frame *n* with latch
      record *n* **by index, never by arrival time** (the encode delay is
      ~2 frames), and assert pairing monotonicity.
- [ ] Emit Ch 2 video packets with per-frame IPTS from the paired RTC,
      through maiden40's ring + merge path.
- [ ] Optional (D6 allows skipping): the lightweight on-station Ch 5
      bright-blob detector as an aiming aid; if skipped, omit Ch 5 from
      this station's TMATS and confirm ingest tolerates its absence.
- [ ] Short recording (~1 min) of a scene with visible motion; spot-check
      frame count and IPTS spacing before the long soaks in maiden42.

**Done when**

- A bench recording's Ch 2 stream decodes (ffprobe/VLC) and its IPTS are
  strictly monotonic with median spacing within 1 % of 33.33 ms
  (**observe on bench**).
- Pulling the strobe wire mid-recording produces a detected association
  fault (loud error or flagged status), not silently mis-paired frames.

**Doc trace.** GS-001, SYS-005/SYS-006 (frame timestamps on the IRIG-B
timebase); D4 IF-1 Ch 2/Ch 5; D6 "Camera capture". Full VT-03 evidence is
maiden42.
