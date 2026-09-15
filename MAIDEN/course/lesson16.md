# Lesson 16 — Radar Front End [bench]

*Where we are.* Lessons 00–15 built the entire software spine — twin, ingest,
tracker, fusion, validation, CI — without touching a soldering iron. That was
the SEMP's twin-first bet, and it paid: from here on, every piece of hardware
you bring up drops into a pipeline that already knows what to do with its
data. The hardware track opens where the theremin course's epilogue pointed:
a CW Doppler module, an antenna, and an analog chain that turns motion into
an audio-band tone. This lesson builds and bench-proves the analog front end;
lesson 17 gives it the FPGA DSP that turns tones into velocities.

## Objectives

- Order (or unbox — you were told to order at lesson 06) every part the
  hardware track needs, against the list below.
- Recap CW Doppler physics well enough to predict IF frequency from target
  speed for both candidate modules, and check the predictions against D6.
- Design and print a ~15 dBi pyramidal horn for the chosen band.
- Build the two-stage LNA + anti-alias filter and wire the module's I/Q
  outputs into it.
- Verify the analog chain on the bench with moving targets — fan, walk,
  car — and log scope evidence toward VT-04 and VT-05.

## Concepts

### The shopping list (lessons 16–21)

You already own two HB100s, the iCEstick, and the HX8K breakout from the
theremin course. The rest of the hardware track, with rough 2026 prices:

| Item | For | ~Cost |
|---|---|---|
| CDM324 24 GHz modules ×3 (+1 spare) | radar, all stations | $40 |
| (HB100 10.5 GHz ×2 — already owned) | fallback per VT-05 | $0 |
| NE5532 / MCP6022 op-amps, passives kit, trimmers | LNA + AAF ×3 | $25 |
| 1080p30 global-shutter USB3 machine-vision cameras ×3 + lenses (60°, 35°, 60°) | GS-001 | $450 |
| u-blox MAX-M10S breakouts with PPS pin ×4 (3 stations + logger) | SYS-006, AB-001 | $80 |
| Raspberry Pi 5 (8 GB) ×3 + SSDs + SD cards | Ch. 10 recorders | $360 |
| iCE40/ECP5 dev boards ×3 (ULX3S if lesson 17's audit says so) | DSP + timebase | $180–540 |
| Matek H743 + M10 GNSS (logger, lesson 21) | AB-001 | $110 |
| 4S LiFePO₄ 10 Ah packs ×3 + buck converters | GS-007 | $270 |
| Surveyor tripods + leveling heads + sighting rails ×3 | GS-004 | $300 |
| Weatherproof cases ×3, 74HC14s, corner-reflector foil, checkerboard print | misc | $120 |

Order of magnitude: ~$2k for three stations plus the logger. The single
costliest line is cameras; do not cheap out there — rolling shutter turns a
30 m/s aircraft into a smear with a per-row timestamp, and GS-001 assumes you
didn't.

### Doppler arithmetic, one more time

From the theremin radar interludes: a CW radar transmits f₀, the moving
target returns f₀ + f_d, and the module's internal mixer hands you the
difference. The Doppler shift is

```
f_d = 2 v_r / λ = 2 v_r f0 / c
```

Per m/s of radial velocity: **≈ 161 Hz at 24.125 GHz** (λ ≈ 12.4 mm) and
**≈ 70 Hz at 10.525 GHz** (λ ≈ 28.5 mm). A pattern ship crossing at 30 m/s
radial is ≈ 4.8 kHz at 24 GHz, ≈ 2.1 kHz at 10.5 GHz — exactly the numbers
D6 quotes in its radar front-end section. Everything in the IF chain is
audio-band; your theremin ears transfer directly.

Why prefer 24 GHz at all? More Hz per m/s means finer velocity resolution
per FFT bin (lesson 17), and the horn for a given gain is half the linear
size. The risk — D5 risk R2 — is detection range on a low-RCS foam target,
and that is decided by measurement (VT-05), not preference.

### The target is terrible, and that's the point

A 1.5 m foam electric aircraft is mostly radar-transparent. What reflects:
the motor, the battery, servos, carbon spar if present, and the spinning
prop (which also gives beautiful blade-flash modulation — you will see it).
Plausible RCS is 0.01–0.1 m², orders below a car. The radar equation says
received power falls as R⁴; a module that pings a car at 300 m may lose a
foamie at 80. This is why GS-003's range number carries a TBD in D2 and why
this lesson ends with evidence, not opinion.

### Horn design from the gain spec

Gain relates to effective aperture: G = 4πA_e/λ². For 15 dBi, G ≈ 31.6, so
A_e ≈ 31.6·λ²/4π. With a realistic pyramidal-horn aperture efficiency of
~0.5, physical mouth area A ≈ 2·A_e:

- 24.125 GHz: A_e ≈ 3.9 cm² → mouth ≈ 8 cm², e.g. **36 mm × 22 mm**, axial
  length ≈ 50 mm (≈ 4λ for low phase error).
- 10.525 GHz: scale by (λ ratio)² → mouth ≈ 42 cm², e.g. **84 mm × 50 mm**,
  length ≈ 115 mm.

Print in PLA, line the inside with smooth overlapping copper tape (conductive
adhesive or soldered seams), and mount so the module's patch array sits at
the throat. A sloppy horn still beats no horn by ~10 dB; mark the exact gain
*tune-on-bench* and don't lose sleep — VT-05 measures the system, not the
horn.

## Doc Trace

- **Implements:** the D6 "Radar front end" design element (module, horn,
  LNA/AAF) toward GS-003.
- **Verified by:** VT-04 (Doppler velocity accuracy — completed after
  lesson 17 adds the DSP) and VT-05 (detection range — field, this
  hardware).
- **Risk:** D5 risk R2 (radar range on low-RCS foam) — this lesson and
  VT-05 are its mitigation.
- **Closes:** D2's TBD on GS-003 ("HB100 vs. CDM324; set after bench test
  VT-05"). When VT-05 data is in, commit the module decision to D2 and the
  affected D6 rows *in the same commit*, per D5 change control.

## Build

### 1 · Horn (`hardware/horn/`)

Model the pyramidal horn for your band in CAD (parametric: mouth a×b,
length, throat sized to the module face). Export STL, print, line with
copper tape. Commit CAD source, STL, and a photo. One horn per station plus
a spare; print the 10.5 GHz version too if you want VT-05 to be a same-day
A/B test.

### 2 · LNA + anti-alias board (`hardware/lna/`)

Per D6: gain 40 dB, 2nd-order low-pass at 20 kHz, two channels (I and Q).
One channel:

```
                +------------------ stage 1: G = 20 dB ------------------+
  module IF o---||--+                                                    |
            100n    |   +-------+          R2 100k                       |
                    +---| +     |     +----/\/\/----+                    |
             R1 10k |   |  op   |-----+             |                    |
        vref o--/\/\+---| -     |     |             |    stage 2 (same,  |
                        +-------+     +-- R3 10k ---+--> G = 20 dB) --+  |
                                                                      |  |
        +--------------- Sallen-Key LPF, fc ≈ 20 kHz ---------------+ |  |
        |   R 8.2k     R 8.2k                                       | v  |
   in o-+--/\/\/--+--/\/\/--+---| + \                               |    |
                  |         |   |    >---+---o  to ADC (lesson 17)  |    |
                 C1 2n2    C2 1n|   | - /   |                       |    |
                  |         +---+---+-------+                       |    |
                 gnd                                                +----+
```

Component notes: NE5532 (5 V single-supply with a 2.5 V vref divider) or
MCP6022 rail-to-rail. R1/R2 set each stage's gain (×10 each, 40 dB total);
Sallen-Key with R = 8.2 kΩ, C1 = 2.2 nF, C2 = 1 nF gives fc ≈ 19–20 kHz,
Q ≈ 0.7 (Butterworth-ish). All *tune-on-bench*: module IF amplitude varies
unit-to-unit, so make stage-1 gain a trimmer and set it so a hand-wave at
3 m doesn't clip. Build two channels per station (I and Q), matched
components from the same batch.

### 3 · Module wiring

The CDM324 variant D6 baselines exposes I and Q IF pins (quadrature outputs
from offset mixers). Wire: VCC 5 V *quiet* (RC-filter the rail — these
modules hate switcher hash), GND star to the LNA board, IF_I and IF_Q each
through a 100 nF into its LNA channel. If your modules turn out to be the
common single-IF CDM324, note it now: you lose Doppler sign at the antenna
and lesson 17's sign-recovery becomes a mono fallback — flag it for the
Explore exercise and the VT-05 decision.

### 4 · Bench targets

- A desk fan: blade flash at blade-rate multiples, a lovely first signal.
- Yourself, walking: ~1.4 m/s → ≈ 225 Hz (24 GHz) / ≈ 98 Hz (10.5 GHz).
- A car at crawl speed with a GPS phone log: the VT-04 rehearsal.

## Verify

All **observe on bench** — scope evidence, logged to `results/`:

1. **Quiet baseline.** Chain powered, no motion: scope the LNA output.
   Noise floor should be tens of mV at full gain; 60 Hz or switcher spurs
   mean your supply filtering failed. Fix before proceeding.
2. **Fan test.** Point the horn at the fan from 2 m. Expect a strong tone
   cluster at blade-pass Doppler; screenshot the scope FFT. Confirm I and Q
   look similar in amplitude and ~90° apart in phase (X-Y mode draws a
   rough circle for a single mover).
3. **Walk test.** Walk toward the horn at a steady pace; verify the tone
   frequency against the per-m/s constants above within ~20 %. Walking away
   should flip the I/Q phase rotation direction — that is the sign
   information lesson 17 will exploit.
4. **Range rehearsal.** In a parking lot, drive a car radially at a steady
   GPS-logged speed from 50–150 m. Note the range where the tone is still
   clearly above the floor on the scope FFT. This is not yet VT-05 (that
   needs the real airframe and SNR from the DSP), but it calibrates your
   expectations for both modules. Log scope captures + GPS trace to
   `results/VT-04/rehearsal/`.

VT-04's numeric pass (|error| ≤ 0.3 m/s at 50 Hz output) waits for
lesson 17. VT-05 (foam aircraft, ≥ 100 m, SNR ≥ 10 dB) is a field test —
schedule it with lesson 20's first field outing.

## Explore

1. **A/B the bands.** Same fan, same distance, CDM324 horn vs HB100 horn.
   Compare tone SNR on the scope FFT. Which band's *analog* chain looks
   healthier before you've even built the DSP?
2. **Kill the horn.** Repeat the walk test bare-module. Estimate the horn's
   real gain from the SNR delta and compare to the 15 dBi design value.
3. **Mono-IF contingency.** Suppose VT-05 forces a module with one IF pin.
   Write half a page on what MAIDEN loses (sign of v_r per station) and how
   three stations of |v_r| still constrain the fused velocity in lesson 13's
   EKF. File it in `docs/notes/` — it may become a D6 revision.
4. **Prop signature.** Scope the spectrum of the fan at constant RPM.
   Identify blade-flash lines vs the hub line. On the real aircraft this
   modulation rides on top of body Doppler — will lesson 17's CFAR pick the
   body line or the strongest blade line? Note your prediction; check it in
   lesson 99.

## Checkpoint

- All lesson 16–21 hardware is ordered or on the bench.
- Three horns printed and lined; CAD committed under `hardware/horn/`.
- One complete two-channel LNA/AAF chain built; quiet-baseline, fan, and
  walk tests logged with scope captures under `results/VT-04/rehearsal/`.
- Walk-test tone frequency matches the per-m/s constant for your band
  within ~20 %, and I/Q phase rotation flips with direction.
- You know which module is *leading* for GS-003 and what evidence (VT-05)
  will make it final — and where in D2/D6 that decision gets committed.
