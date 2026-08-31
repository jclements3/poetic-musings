# PERT/CPM — personal FPGA program (C → T → F → P → H)

Unit: weekends. Durations are optimistic/likely/pessimistic; expected = (o + 4m + p) / 6. Policy is serial (one project at a time), so the critical path is the whole chain by construction; CPM is used here to find where the serial rule is costing you and where purchases can be timed to hide lead times instead of paying for them.

## Task network

```
C1 plugs/masts/line ─► C2 elastic bounce ─► C3 coil + pulse loop ─► [C4 FPGA timing]*
                                                                          │
T1 oscillator hw ─► T2 antenna cal (existing bitstream)                   │
        │                                                                 │
        └────────────► F1 H2 on USB serial ─► F2 GPDI text ─► F3 SD blocks ─► F4 GPIO/ADC words
                                                                                   │
              ┌────────────────────────────────────────────────────────────────────┘
              ▼
P1 keybed matrix ─► P2 voice engine ─► P3 sequencer/rhythm ─► P4 overlay + A/B ─► P5 theremin ─► P6 case
                                                                                                   │
        H2 synthetic-string tests ◄─── can run inside P after P2 (no hardware)                     │
        H3 KS from keys          ◄─── can run inside P after P2                                    │
                                                                                                   ▼
                                       H1 one string + one ADC ─► H4 rib CNC + strings ─► H5 98 sensors ─► H6 integrate
```

`*` C4 is flagged below.

## Durations and float

| Task | o / m / p | E | Float under serial rule | Notes |
|---|---|---|---|---|
| C1 | 1/1/2 | 1.2 | 0 | fitting iteration is the only unknown |
| C2 | 1/1/2 | 1.2 | 0 | |
| C3 | 1/1/3 | 1.3 | 0 | coil winding + MOSFET loop |
| C4 | 1/2/3 | 2.0 | — | **rework risk, see R1** |
| T1 | 1/1/2 | 1.2 | 0 | parts ordered |
| T2 | 1/2/3 | 2.0 | 0 | |
| F1 | 1/1/3 | 1.3 | 0 | embed toolchain on WSL is the pessimistic case |
| F2 | 2/2/4 | 2.3 | 0 | TMDS timing closure |
| F3 | 1/1/2 | 1.2 | 0 | |
| F4 | 1/1/1 | 1.0 | 0 | |
| P1 | 1/1/3 | 1.3 | 0 | depends on keybed choice, R3 |
| P2 | 2/2/4 | 2.3 | 0 | |
| P3 | 1/2/3 | 2.0 | 0 | |
| P4 | 1/1/2 | 1.2 | 0 | |
| P5 | 1/1/2 | 1.2 | 0 | |
| P6 | 2/2/4 | 2.3 | 0 | case; last, R6 |
| H2 | 1/1/1 | 1.0 | 2–5 | slots into P after P2 |
| H3 | 1/1/2 | 1.2 | 2–5 | slots into P after P2 |
| H1 | 1/2/3 | 2.0 | 0 | one ADC eval, one string |
| H4 | 3/4/6 | 4.2 | 0 | **lead-time driven, R5** |
| H5 | 2/3/5 | 3.2 | 0 | |
| H6 | 2/2/4 | 2.3 | 0 | |

Expected chain: C 3.7 + T 3.2 + F 5.8 + P 10.3 + H 11.7 ≈ **35 weekends**, about 8–9 months of weekends. Standard deviation on the chain ≈ 3 weekends; 90% confidence ≈ 39.

## Exposures

**R1 — C4 is rework.** Writing pulse-timing/photogate HDL before F exists means writing it twice: once as a bare counter design, again as Forth words on the register bus. Cut C4 from C. Log transit times with phone slow-mo against the sheet grid for now (the desktop build doc already planned this). C4 becomes a one-evening task after F4. Saves ~2 weekends.

**R2 — F2 before F1 is a false gate.** If the TFT arrives before the H2 runs over USB serial, the temptation is to debug both at once. Hold F2 until F1 prints `ok`.

**R3 — Bad purchase: raw 49-key membrane matrix.** Membrane keys have no travel and their pitch rarely matches the 13 mm drawing. A used 49-key USB MIDI controller (~$40–60) gives a real keybed with a matrix already wired; you read its matrix and discard its brain. Also gives pitch bend/mod wheels for free. Buy that, not a membrane.

**R4 — Bad purchase: 13 ADCs and a carrier PCB before H1.** Order one ADS131M08 evaluation board for H1. Only after one string passes do you spin the 13-chip carrier. Same for IR pairs: 5, not 98, until H1 passes. Avoids ~$200 of parts that could be the wrong ADC or wrong emitter wavelength.

**R5 — H4 lead time is the real critical path in H.** CNC rib and strings are weeks of vendor time. Place the rib order at the *start* of P, not the start of H, once bores are verified by micrometer (standing rule). That's a purchase, not work, so it doesn't violate serial. Hides ~4 weeks.

**R6 — Case before panel verification is rework.** Don't cut the 55 mm display band until the TFT is on the bench and its active area measured. P6 stays last.

**R7 — Bar TFT + driver board mismatch.** Buy the panel and its HDMI driver as a matched kit with 1920×480 EDID. A panel alone invites a second order.

**R8 — Purchases that should not happen on this path.** Alchitry Cu, iCESugar UP5K, extra RMII PHY, GPS module: all IRAD-ledger station parts. They have no consumer until M. Leave them.

**R9 — Wasted effort: a second theremin bitstream.** T2 uses the existing ECP5 theremin port unchanged. Any temptation to "clean it up" before P5 is rework; P5 is where it gets refactored onto the register bus, once.

**R10 — Wasted effort: harp DSP without hardware.** H2/H3 look like they violate serial, but they are pure-HDL tests that only need the piano. Doing them inside P removes ~2 weekends from H and makes H1 a hardware-only gate. Do them.

## Purchase timing

| Buy | When | Why |
|---|---|---|
| AAs, coil form tube | now | C3 |
| Bar TFT + HDMI driver kit | during T | arrives for F2 |
| Used 49-key MIDI controller | during F | arrives for P1 |
| 1× ADS131M08 eval, 5× IR pairs | during P | arrives for H1 |
| CNC rib order (post-micrometer) | start of P | 4-week lead hidden |
| String set | after H1 | bores confirmed on one string |
| 13× ADC + carrier PCB, 93 IR pairs | after H1 passes | only then known-good |

## Net effect

Cutting C4, doing H2/H3 inside P, and hiding the rib lead time takes the expected chain from ~35 to ~31 weekends and removes about $250 of at-risk purchases. Nothing else on the path has float worth chasing; the rest is just doing the work in order.
