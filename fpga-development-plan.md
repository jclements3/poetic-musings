# FPGA project development plan — POETIC + MUSING

Supersedes the pre-merge lettering (F/A/D/L/H/old S/old G). Legacy letter map at the bottom. Ledger: P = personal, I = IRAD.

Build rule: serial, finish before start. Personal: **C → I → O → T → P → E**. IRAD: **G → N → U → S → I → M**, interleaved as funding allows; U/S slip after E if IRAD funding is delayed.

Milestones: Basic Plan Sep 2026 · Prototype Dec 2026 · Field Demo Feb 2027. Items marked ▲ must be pulled forward regardless of rank because December depends on them.

## POETIC (personal)

| # | Proj | Difficulty | Cost | Ledger | Prereqs | Gate |
|---|---|---|---|---|---|---|
| 1 | **C** Coil — Santa Glide | 2 | parts ordered (opt. 2nd 24 AWG spool) | P | — | Slug glides house A→B→A continuously while show switch on; parks in place on pause; dwell profile tuned. Standalone on Alchitry Cu. |
| 2 | **I** IRIG clock | 2 | $0 (GPSDO comes later, under G) | P | C (skills) | Spec-valid IRIG-B out, verified on scope/decoder. Free-running on board crystal until G disciplines it; time display added once O exists. |
| 3 | **O** Oracle console | 3 | $60 (8.8" bar TFT + HDMI board) | P | — | Forth prompt on bar TFT, no laptop; `1 2 + .` → 3; GPIO toggle, ADC read, SD block 1 loads; CW keyer sends, decoder prints. clash-h2 H2 port already started. ▲ |
| 4 | **T** Theremin | 1 (Clash port already passing) | $0 (ordered) | P | O (tuning UI) | Oscillator hardware on bench; port tracks pitch and volume from antennas through speaker. Stays the regression target for every library change. |
| 5 | **P** Piano VL-49 | 3 | $150 (used 49-key MIDI keybed, 3D-printed panel/case) | P | O, T | The 3D-printed keyboard per `README.html` (panel map) — keys, sliders, buttons, display band. Oracle is the brains behind its UI. 49 keys scan; `90099914 patch!` plays; Da Da Da on One Key Play; A/B vs real VL-1; antennas + theremin source select. |
| 6 | **E** Erand49 harp | 5 | ~$1,200 (13× ADC, 98 IR pairs, CNC rib, strings) | P | P, O | Gate 1: one string, one ADC eval, pluck on display. Gate 2: 49 strings, I²S 24/96 harp-master into the box, playable. |

## MUSING (IRAD)

| # | Proj | Difficulty | Cost | Ledger | Prereqs | Gate |
|---|---|---|---|---|---|---|
| 7 | **G** GPS | 3 | $30 (u-blox w/ PPS) + used GPSDO metrology ref (GS-101B or Thunderbolt-class) | I | O | PPS-locked 10 MHz; disciplines the I clock; station clock copies. ▲ |
| 8 | **N** Network | 3 | $25 (RMII PHY PMOD) | I | O | UDP stream of ADC samples to laptop, zero drops over 10 min; Ch.10 transport. ▲ |
| 9 | **U** UHF beacon | 3 | TBD | P (ham — personal ledger) | G | GPS-disciplined CW + WSPR on air; spot appears on wsprnet. |
| 10 | **S** SDR | 4 | ~$30 (AD9226-class ADC) | I | T, O | Direct-sampling HF on the theremin antennas; DDC (CIC/FIR) waterfall on O; decode a broadcast or WSPR signal. |
| 11 | **I** Imaging | 4 | TBD — global-shutter sensor / trigger / FOV-range study first (Sep Basic Plan) | I | N, G | External-trigger capture, IRIG-timestamped, centroid stream over N. |
| 12 | **M** MAIDEN | 5 | ~$400/station × 3 | I | everything above | Tabletop testbed (elastic draw-stop rig) first; one station records IRIG-stamped Doppler + video into Ch.10; three-station fusion at RCRC. ▲ |

## Ordering rationale

C first: the cheapest complete trainer for Moore FSMs, counters, PWM, and MOSFET drive — and it is already at bring-up with all parts ordered.

I second: the same counter/framing skill family as C plus timecode serialization, with no platform dependency. "Finished" = spec-valid IRIG-B on the bench; GPS discipline is retrofitted when G lands.

O third: the platform. Old F and D merged here — H2 Forth CPU (black-box VHDL first, clash-h2 port in progress), bar TFT over GPDI, SD, CW keyer/decoder. Every project after O is brought up from the Forth console instead of a rebuilt bitstream.

T after O: the Clash port already passes; what remains is bench work on the LC oscillators, which goes faster with O's display for tuning.

P then E close out personal, per the handoff: P is the platform demo — the 3D-printed 49-key keyboard from the panel drawing, with Oracle as the brains behind its user interface. E consumes everything (ADC front end, DSP blocks, event link) and is the expensive one with no deadline.

On the IRAD side, G goes first because trusted time unblocks U, Imaging, and M — and closes I's free-running caveat. N before Imaging because Imaging needs the transport. The old standalone L (logic analyzer) is no longer a letter: its skills (SDRAM capture, async FIFO/CDC, trigger) get built as O bring-up tooling and MAIDEN unit integration — Ethernet without capture on the bench is still a bad afternoon, so N's gate assumes that tooling exists.

## December path (pull-forward)

C → I → O → G → N → single-station M. T, P, E, U, S, and Imaging are off the critical path and wait their turn.

## PERT/CPM outcomes (carried forward)

- Cut C4 (FPGA pulse timing before Forth) — phone slow-mo until O exists.
- Buy 1 ADC eval + 5 IR pairs before 13 ADCs / 98 pairs (harp gate 1 = one string).
- Order harp rib at start of P after micrometer bore check.
- Case last; TFT + HDMI driver bought as a matched kit.

## Spend summary

Personal: ~$1,700, of which $1,200 is the harp; Santa Glide parts are already ordered (sunk). U (ham) is on the personal ledger, cost TBD. IRAD: ~$1,225 for three stations plus PHY, plus the GPSDO reference and the Imaging sensor (TBD after the Sep study). Ledgers never commingle; hardware bought personal can be re-bought on IRAD when M needs its own copies.

## Legacy letter map (pre-merge → current)

| Old | New home |
|---|---|
| F Forth CPU | **O** Oracle (with D absorbed) |
| D display | **O** Oracle |
| A ADC front end | split: **E** harp front end · **S** SDR sampling |
| L logic analyzer | no longer a letter — O bring-up tooling + M unit integration |
| G GPS/IRIG clock | split: **I** IRIG clock (personal) · **G** GPS discipline (IRAD) |
| C launcher/catcher (v2, ballistic) | **C** Santa Glide (v4, 8-coil sequenced glide) |
| S snooker rig | **M** tabletop testbed |
| H harp Erand49 | **E** Erand49 |
| P, T, N, M | unchanged letters: P, T, N, M |
