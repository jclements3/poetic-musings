# Lesson 19 — The Ch. 10 Recorder [bench]

*Where we are.* The station's organs all work in isolation: the radar chain
produces I/Q and v_r (lessons 16–17), the FPGA time source produces IRIG-B,
a 10 MHz RTC, and per-frame timestamps (lesson 18), and you have owned a
Ch. 10 writer core since lesson 02. This lesson builds the organ that makes
a station a *station*: the recorder process on the SBC that takes every
source, stamps it, and interleaves it into one standards-conforming file
per session. When this lesson's Verify passes, VT-01 and VT-03 are retired
and the file you record is indistinguishable, to your own ingest, from the
twin files you've been living on since lesson 07.

## Objectives

- State the IF-1 channel map from memory and defend each data-type choice.
- Compute the sustained write-rate budget and size the ring buffers.
- Build `firmware/recorder/` (Python, SBC-resident): capture threads per
  source, one writer thread, TMATS-first file layout, RTC ordering.
- Associate camera frames with lesson 18's strobe-latched RTC stamps and
  emit Ch. 2 video with per-frame IPTS.
- Record a 5-minute bench session and pass VT-01; record a 10-minute video
  soak and pass VT-03.

## Concepts

### One file, seven channels, one ordering rule

The recorder's contract is IF-1, exactly:

```
Ch 0  TMATS     0x01  once      setup record (lesson 03's template, filled)
Ch 1  TIME      0x11  1 Hz      IRIG-B day/h/m/s + RTC sync
Ch 2  VIDEO     0x40  30 fps    H.264 MPEG-2 TS, IPTS per frame
Ch 3  RADAR_IF  0x09  48 kS/s   I/Q int16 pairs, minor frame = 1 ms
Ch 4  RADAR_V   0x09  50 Hz     v_r float32, SNR dB, peak bin
Ch 5  TRACKER   0x30  per frame az, el, conf, bbox px
Ch 6  STATUS    0x30  1 Hz      battery V, temp °C, PPS lock, disk free
```

Two rules govern the file body. First: the TMATS packet is physically
first — every Ch. 10 tool assumes it. Second: packets are interleaved in
nondecreasing RTC order. Nothing else about layout is promised, which is
what makes the writer simple: it is a merge, not a scheduler.

Ch 5 deserves a caveat you already know from D6: the *full* tracker
(lessons 10–11) runs on the processing host after the session. The
on-station Ch 5 producer is an optional lightweight detector — bright-blob
centroid, no track continuity — useful as a live "am I aimed correctly"
aid. If you skip it, Ch 5 is simply absent from this station's TMATS and
ingest already tolerates that.

### The rate budget

Do this arithmetic before writing a line of code, because it decides the
architecture:

- Ch 3: 48 000 S/s × 2 (I, Q) × 2 B = **192 kB/s**
- Ch 2: 1080p30 H.264 at your encoder's bitrate; at 8 Mb/s = **1.0 MB/s**
  (this is the knob — verify your quality needs in Explore)
- Ch 4: 50 Hz × ~12 B ≈ **0.6 kB/s**
- Ch 5: 30 Hz × ~32 B ≈ **1 kB/s**
- Ch 1 + Ch 6: 2 Hz of small packets ≈ negligible
- Packet overhead: 24 B header + trailer per packet; with ~1 ms radar
  minor frames grouped ~100/packet, well under 1 %.

Aggregate ≈ **1.2 MB/s ≈ 4.4 GB/h**. A Pi 5's NVMe HAT or even a good
UHS-I SD sustains 10× that — but SD cards stall for hundreds of
milliseconds during internal garbage collection. That stall is why the
architecture below has deep buffers, not because of average rate.

### Threads, rings, and the never-drop discipline

```
 capture threads                 ring buffers            writer thread
 ┌────────────┐                 ┌───────────┐
 │ FPGA UART  │──v_r,IQ blk────▶│ ring: Ch3 │──┐
 │ (Ch 3, 4)  │                 │ ring: Ch4 │  │   pop min-RTC,
 ├────────────┤                 ├───────────┤  ├─▶ frame packet,   ──▶ .ch10
 │ camera     │──frame+RTC─────▶│ ring: Ch2 │  │   append, fsync
 │ (Ch 2, 5)  │                 │ ring: Ch5 │  │   every N MB
 ├────────────┤                 ├───────────┤  │
 │ time/status│──1 Hz──────────▶│ ring: Ch1 │──┘
 │ (Ch 1, 6)  │                 │ ring: Ch6 │
 └────────────┘                 └───────────┘
```

- One capture thread per hardware source; each does nothing but read,
  stamp, and push. Python threads are fine here — every capture thread is
  I/O-bound, so the GIL is not your enemy; if profiling later disagrees,
  the radar reader is the one to rewrite in C.
- Rings are sized for ≥ 2 s at channel rate (Ch 2 dominates: ~2.5 MB), so
  an SD stall is absorbed, not fatal.
- **Never-drop discipline:** a full ring increments a per-channel drop
  counter and discards the *newest* item, and the drop counters ride in
  every Ch 6 status message. A recording with drops is a degraded
  recording that says so in-band; a recorder that silently blocks its
  capture thread corrupts timing for everything downstream. VT-03's pass
  criterion is that the counter stays at zero.
- The writer thread pops whichever ring's head has the smallest RTC,
  packs it with lesson 02's writer core, and appends. That single rule
  yields the nondecreasing-RTC file the ICD demands.

### Frames meet timestamps

The camera's strobe output is wired to the FPGA (lesson 18), which latches
RTC per exposure and streams `(frame_index, rtc)` records up the same UART.
The capture thread holds a small association queue: encoded frame *n* from
the camera pairs with latch record *n*. Off-by-one here is a classic — the
strobe fires at exposure start, the encoded frame arrives ~2 frames later.
Associate by index, never by arrival time, and assert the pairing
monotonicity. The paired RTC becomes the frame's IPTS in the Ch. 2 packet.

## Doc Trace

- **Implements:** SYS-005 (everything is Ch. 10 + TMATS) at station level;
  GS-001's timestamping half (capture itself came with lesson 09's camera
  work).
- **Governed by:** D4 IF-1 (channel map — this lesson's contract), IF-2
  (the TMATS you emit), D6 "Ch. 10 recorder" (SBC + Python/C on the
  lesson 02 core, one file per session).
- **Verified by:** VT-01 (file conformance) and VT-03 (video capture and
  stamping), both retired at this bench.
- **Feeds:** lesson 20 (Station 1 integration) and the HIL dataset that
  lesson 15's CI has been waiting for.

## Build

Create `firmware/recorder/` (it runs on the station, so it lives with
firmware, not in the analysis package):

- `rings.py` — a bounded deque with drop counter; ~30 lines, test it
  first.
- `sources.py` — capture threads: `FpgaSource` (UART framing from
  lesson 17/18: v_r records, I/Q blocks, time and latch records
  demultiplexed by record tag), `CameraSource` (frame grab via V4L2/
  Picamera2, hardware H.264 encode, strobe association queue),
  `StatusSource` (INA219 battery monitor, SoC temp, PPS-lock flag from
  the FPGA status record, `statvfs` disk free).
- `writer.py` — the min-RTC merge loop over `maiden.ch10.writer` from
  lesson 02. TMATS packet first, built by `maiden.tmats` from this
  station's `config/` serial + calibration files (lesson 20 formalizes
  those; for now, bench values).
- `record.py` — CLI: `python -m recorder --station A --out
  STATION_A_$(date +%Y%m%d_%H%M).ch10`; clean shutdown on SIGINT flushes
  all rings, then closes.

Wire format note: define the UART record framing once, in
`firmware/recorder/PROTOCOL.md`, and cite it from both the VHDL and the
Python — it is an interface, and interfaces get written down (that habit
is the whole point of D4).

Skeleton for the merge, the only subtle loop in the lesson:

```python
def run(self):                      # writer thread — skeleton
    while not self.stopping or any(r for r in self.rings if len(r)):
        ring = min((r for r in self.rings if len(r)),
                   key=lambda r: r.head_rtc(), default=None)
        if ring is None:
            time.sleep(0.005); continue
        item = ring.pop()
        self.ch10.append(self.pack[ring.chan](item))   # lesson 02 core
```

## Verify

**VT-01 — file conformance.** Record a 5-minute bench session: radar
looking at the bench fan, camera at anything, FPGA time source locked.
Then, on the host:

```bash
i106stat STATION_A_*.ch10          # every channel present, counts sane
python -c "from chapter10 import C10; [p for p in C10('STATION_A_....ch10')]"
maiden ingest STATION_A_*.ch10 --summary
```

Pass = all seven channels (six if you skipped Ch 5) present, TMATS parses
into a Station descriptor, packet checksums valid, ingest emits
StateSamples without complaint. **Observe on bench**; commit the summary
and `i106stat` capture to `results/VT-01/`.

**VT-03 — video capture and stamping.** Record 10 minutes of 1080p30.
Write a small checker (add it to `software/tests/` — it will run against
every future session too): frame count ≥ 17 940 (29.9 fps mean), Ch 6
drop counters zero, IPTS strictly monotonic, median inter-frame IPTS
within 1 % of 33.33 ms. **Observe on bench**; log to `results/VT-03/`.

## Explore

1. **Stall injection.** During a recording, run `dd` against the same disk
   to force write stalls. Watch ring high-water marks (add them to Ch 6).
   How deep did Ch 2's ring actually get? Resize with data, not guesses.
2. **Bitrate audit.** Record the same scene at 4/8/12 Mb/s and run
   lesson 11's tracker on each. Where does az/el accuracy stop improving?
   That number, not the encoder default, belongs in the recorder config.
3. **Kill test.** `kill -9` the recorder mid-session. What does
   PyChapter10 make of the truncated file? Decide — and document in
   PROTOCOL.md — whether ingest should salvage complete packets from a
   torn file (hint: the sync pattern makes this cheap, and a field session
   ended by a dead battery is a *when*, not an *if*).
4. **Design friction, minor:** IF-1 says Ch 4's payload is
   "v_r float32 m/s, SNR dB, peak bin" but does not pin the SNR encoding
   or the record layout bit-for-bit. You just had to invent it in
   PROTOCOL.md. Fold the layout back into D4 IF-1 per D5 change control —
   an ICD that under-specifies an interface you had to guess at is a bug
   in the ICD.

## Checkpoint

- `firmware/recorder/` records all wired sources into one `.ch10`,
  TMATS-first, RTC-ordered; `rings.py` has its own passing pytest.
- VT-01 evidence in `results/VT-01/`: `i106stat` output, PyChapter10
  load, `maiden ingest --summary` all clean on a real 5-minute bench
  recording.
- VT-03 evidence in `results/VT-03/`: 10-minute soak with zero drops and
  monotonic IPTS, checked by a committed test script.
- `firmware/recorder/PROTOCOL.md` defines the UART record framing and the
  Ch 4/Ch 5/Ch 6 payload layouts; D4 updated to match.
- D8's "Other verification results" rows for VT-01 and VT-03 are filled.
