# FPGA project development plan — Panel+Oracle root and its spokes

Supersedes the pre-merge lettering (F/A/D/L/H/old S/old G). Legacy letter map at the bottom. Ledger: P = personal, W = work.

Build rule: root first, then spokes as hardware arrives. **O → P → T** (T is the regression gate), then E, I, C, then M, U, S, I, N, G in any order; funding decides timing, not dependency. Ledger column is bookkeeping only.

Milestones: Basic Plan Sep 2026 · Prototype Dec 2026 · Field Demo Feb 2027. Items marked ▲ must be pulled forward regardless of rank because December depends on them.

What each row leaves behind is a set of measured Clash modules — `CLASH-LIBRARY-MAP.md` § Module list (✓ / ◐ / ○ by family); each directory's `DESIGN.md` carries the gate detail and names its module-list entries, and `Panel/ORDERS.md` / `Erand49/ORDERS.md` carry the purchases. One unified repo since 2026-09-15.

## Root

| # | Proj | Difficulty | Cost | Ledger | Prereqs | Gate |
|---|---|---|---|---|---|---|
| 1 | **C** Coil — Santa Glide | 2 | parts in hand (opt. 2nd 24 AWG spool; 10-pin ribbon + connector ~$10) | P | O (board) | Slug glides house A→B→A continuously while show switch on; parks in place on pause; dwell profile tuned live from Forth. FSM in the box (`PM.Sleigh`), gates over a ribbon to the driver board; Cu retired. |
| 2 | **I** IRIG clock | 2 | $0 (GPSDO comes later, under G) | P | C (skills) | Spec-valid IRIG-B out, verified on scope/decoder. Free-running on board crystal until G disciplines it; time display added once O exists. |
| 3 | **O** Oracle console | 3 | $60 (8.8" bar TFT + HDMI board) | P | — | Forth prompt on bar TFT, no laptop; `1 2 + .` → 3; GPIO toggle, ADC read, SD block 1 loads; CW keyer sends, decoder prints. clash-h2 H2 port already started. ▲ |
| 4 | **T** Theremin | 1 (Clash port already passing) | $0 (ordered) | P | O (tuning UI) | Oscillator hardware on bench; port tracks pitch and volume from antennas through speaker. Stays the regression target for every library change. |
| 5 | **P** Panel (control surface) | 3 | ~$130 quality BOM (see Panel BOM below) | P | O, T | The 3D-printed keyboard per `README.html` (panel map) — VL-1-style flat button keys in a printed keyboard graphic, sliders, buttons, display band. Oracle is the brains behind its UI. Gates: 59 switches deliver clean press/release events (0x4024) and the ASCII layer types into Forth; S2–S4 zones never flicker across a boundary, S3 mode dwell hands off cleanly; V0 shows console + envelope/spectrum strip; every PM.Synth block (NCO, pulse osc, ADSSR, mixer, DAC) is driven from the keys and measured on ECP5; antennas + theremin source select. VL-1 synth mode plays but is not A/B-gated. |
| 6 | **E** Erand49 harp | 5 | ~$1,200 (13× ADC, 98 IR pairs, CNC rib, strings) | P | P, O | Gate 1: one string, one ADC eval, pluck on display. Gate 2: 49 strings, I²S 24/96 harp-master into the box, playable. |

## Spokes (continued)

| # | Proj | Difficulty | Cost | Ledger | Prereqs | Gate |
|---|---|---|---|---|---|---|
| 7 | **G** GPS | 3 | $30 (u-blox w/ PPS) + used GPSDO metrology ref (GS-101B or Thunderbolt-class) | W | O | PPS-locked 10 MHz; disciplines the I clock; station clock copies. ▲ |
| 8 | **N** Network | 3 | $25 (RMII PHY PMOD) | W | O | UDP stream of ADC samples to laptop, zero drops over 10 min; Ch.10 transport. ▲ |
| 9 | **U** UHF beacon | 3 | TBD | P (ham — personal ledger) | G | GPS-disciplined CW + WSPR on air; spot appears on wsprnet. |
| 10 | **S** SDR | 4 | ~$30 (AD9226-class ADC) | W | T, O | Direct-sampling HF on the theremin antennas; DDC (CIC/FIR) waterfall on O; decode a broadcast or WSPR signal. |
| 11 | **I** Imaging | 4 | OV9281 global-shutter module + lens + overhead mount (TBD after Sep FOV study) | W | N, G | Snooker table, part 1: overhead camera, external trigger, IRIG-stamped centroids in gateware over N. Gate: one rolled ball gives a gap-free track at 200 fps. Demo: ball paths drawn live on V0. Mono only, no colour ID. |
| 12 | **M** Motion radar | 4 | ~$60 (CDM324-class 24 GHz module + SPI ADC) | W | O, G, I(maging) | Snooker table, part 2: Doppler aimed down the table; CIC → FFT → CFAR → velocity records, IRIG-stamped, on V0 and over N. Gate: cue-ball speed matches the camera-derived speed within 5 %, timestamps aligned. Demo: one shot, position from camera + speed from radar on one screen. Black-box `MAIDEN/firmware/doppler` VHDL first, then Clash port, re-measure on ECP5. |

## Panel quality BOM (demo-grade, decided 2026-08-31)

Reliability rule: authorized distributors and name brands only — no clone switch packs,
no generic pots. Nothing may stick or misbehave in front of the grandkids.

Uniformity rule (decided 2026-08-31): one switch type, one pot type, one cutout each —
all 59 switches on identical 14×14 mm cutouts, all 5 sliders in identical 45 mm slots.
Variation lives only in printed caps, knobs, and silk: small caps P0–P7, double-size
caps on P8/P9 One Key Play (as on the VL-1), continuous silk under S0/S1, printed
detent zones under S2–S4. Any spare fits any position.

| Part | Qty | Spec / brand | Source | Est. |
|---|---|---|---|---|
| Key switches | 70 (59 used + spares) | **Cherry MX2A Silent Red** — decided 2026-08-31 (100M actuations, factory lube, quiet, authorized channel; Kailh BOX considered and passed over) | Mouser/DigiKey | ~$70 |
| Matrix diodes | 70 | 1N4148, onsemi or Vishay (name brand only) | Mouser | ~$5 |
| Slide pots S0–S4 | 7 (5 used + 2 spares) | Bourns PTA4543-2015CPB103, 45 mm travel, 10 k linear; Bourns knobs | Mouser/DigiKey | ~$25 |
| Panel + key caps + slider knobs | — | 3D-printed, **PETG or ASA (not PLA** — creeps under finger heat/pressure; a warped key well is a sticking key**)**. Key pitch **16 mm** (MX housing limit; decided 2026-08-31 over 13 mm mini pitch), body ≈ 504 mm, 14×14 mm plate cutouts | own printer | filament |
| Solder, wire, misc | — | switches soldered, **no hot-swap sockets** (a socket is one more contact to fail mid-demo); spares live in the lid pocket | on hand | ~$5 |

Firmware-side reliability, free: generous 10 ms debounce (as in Santa Glide), scan
tolerant of slow release, and hysteresis on the S2–S4 ADC zone thresholds so a slider
parked on a boundary can't flicker between modes during a demo. No velocity sensing —
period-correct (the VL-1 had none); velocity expression is the Erand49's job.

## Ordering rationale

C first: the cheapest complete trainer for Moore FSMs, counters, PWM, and MOSFET drive — and it is already at bring-up with all parts ordered.

I second: the same counter/framing skill family as C plus timecode serialization, with no platform dependency. "Finished" = spec-valid IRIG-B on the bench; GPS discipline is retrofitted when G lands.

O third: the platform. Old F and D merged here — H2 Forth CPU (black-box VHDL first, clash-h2 port in progress), bar TFT over GPDI, SD, CW keyer/decoder. Every project after O is brought up from the Forth console instead of a rebuilt bitstream.

T after O: the Clash port already passes; what remains is bench work on the LC oscillators, which goes faster with O's display for tuning.

P then E close out the personal group: P is the root's body — the 3D-printed control surface per `Panel/DESIGN.md` (fabrication + printer in `Panel/ORDERS.md`), with Oracle as the brains behind it. E consumes everything (ADC front end, DSP blocks, event link) and is the expensive one with no deadline.

Among the spokes, G goes first because trusted time unblocks U, Imaging and M — and closes I's free-running caveat. N before Imaging because Imaging needs the transport. The old standalone L (logic analyzer) is no longer a letter: its skills (SDRAM capture, async FIFO/CDC, trigger) get built as O bring-up tooling — Ethernet without capture on the bench is still a bad afternoon, so N's gate assumes that tooling exists.

## December path (pull-forward)

O → P (bench, no case) → I → G → N → Imaging + M snooker demo. C ships for Christmas regardless (standalone). T, E, U and S are off the critical path and wait their turn.

## PERT/CPM outcomes (carried forward)

- Cut C4 (FPGA pulse timing before Forth) — phone slow-mo until O exists.
- Buy 1 ADC eval + 5 IR pairs before 13 ADCs / 98 pairs (harp gate 1 = one string).
- Order harp rib at start of P after micrometer bore check.
- Case last; TFT + HDMI driver bought as a matched kit.

## Spend summary

Personal: ~$1,700, of which $1,200 is the harp; Santa Glide parts are already ordered (sunk). U (ham) is on the personal ledger, cost TBD. Work ledger: ~$200 for the spoke hardware (OV9281 camera + mount, CDM324 radar + ADC, RMII PHY, u-blox GPS, AD9226 ADC) plus plus the GPSDO reference and the Imaging sensor (TBD after the Sep study). Ledgers never commingle; hardware bought personal can be re-bought on the work ledger when M needs its own copies.

## Legacy letter map (pre-merge → current)

| Old | New home |
|---|---|
| F Forth CPU | **O** Oracle (with D absorbed) |
| D display | **O** Oracle |
| A ADC front end | split: **E** harp front end · **S** SDR sampling |
| L logic analyzer | no longer a letter — O bring-up tooling |
| G GPS/IRIG clock | split: **I** IRIG clock (personal) · **G** GPS discipline (work) |
| C launcher/catcher (v2, ballistic) | **C** Santa Glide (v4, 8-coil sequenced glide) |
| S snooker rig | **M** Motion radar + **I** Imaging — the snooker table is now the I/M demo fixture |
| H harp Erand49 | **E** Erand49 |
| P, T, N, M | unchanged letters: P, T, N, M |
