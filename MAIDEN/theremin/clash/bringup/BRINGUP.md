# Alchitry Cu arrival-day runbook — flash and listen

Prebuilt bitstreams in `bin/` (iCE40HX8K-CB132, timing-clean at 50 MHz:
selftest 58.3 MHz, jumper 62.5 MHz). Lab machine needs only git and
`openFPGALoader`, plus a micro-USB DATA cable.

## 0. Solder check
If the Br arrived without headers, solder a strip of 0.1" headers first.

## 1. Smoke test (ships-with demo)
Plug in the Cu alone. Its factory demo should light LEDs.
    openFPGALoader --detect          # should list an FTDI device
If not: try the other cable — most micro-USB cables are charge-only.

## 2. Blinky (proves OUR flow end-to-end)
    openFPGALoader -b alchitry_cu bin/blinky.bin
One LED walks along the bank about once per second.
(If `-b alchitry_cu` is not in your openFPGALoader build, fall back to
`iceprog bin/blinky.bin`.)

## 3. Theremin self-test — zero wiring
    openFPGALoader -b alchitry_cu bin/theremin-selftest.bin
Synthetic oscillators are inside: pitch sweeps on a ~1.5 s triangle.
Expect: led[3:0] flicker as a level meter (the 4-bit DAC), led[7]
shimmers (the 1-bit DSM). Audio: probe the `audio` pin (see pin caveat)
through 1 kOhm + 10 nF to a powered speaker -> a slowly sweeping tone.
This audibly validates the ENTIRE digital instrument.

## 4. Jumper test — one wire
    openFPGALoader -b alchitry_cu bin/theremin-jumper.bin
Jumper `fake_osc` to `pitch_in`: steady tone. Remove it: tone stops.
That is the real input path working.

## 5. Only now, the Colpitts breadboard (ORDERS.md section 2)
Scope each oscillator near 600 kHz BEFORE connecting; then replace the
jumper with the real oscillator output. Any new problem is analog.

## Pin caveat (the one thing to verify)
`blinky.pcf` clock/LED pins are from the Alchitry base project (high
confidence). The three Br-bank pins in `theremin.pcf` (`audio` A5,
`fake_osc` A6, `pitch_in` A7) are BEST GUESSES — verify against the
Alchitry Cu schematic/pinout before wiring; a wrong guess means
silence, never damage. To fix pins, edit `theremin.pcf`, then re-run
P&R on either machine:
    cd theremin/clash
    source ~/tools/oss-cad-suite/environment
    nextpnr-ice40 --hx8k --package cb132 --freq 50 \
      --json build/arrival/selftest.json --pcf bringup/theremin.pcf \
      --pcf-allow-unconstrained --asc /tmp/a.asc && icepack /tmp/a.asc \
      bringup/bin/theremin-selftest.bin
(The .json netlists rebuild with the commands in the Makefile if absent.)

## Note on step 3 sound
The pitch map constants are the simulation-calibrated first cut; the
sweep is designed inside their tested band (half-periods 14..29 at
50 MHz), so you should hear a sweep, but absolute pitch may be odd —
that is a constants recalibration, not a bug.

## 6. GUI build — the theremin on the lab screen, no antennas (11 Sep 2026)

    iceprog bin/theremin-gui.bin
    python3 gui/theremin_gui.py /dev/ttyUSB1 --sweep

`cu_gui_top.v` wraps the SAME `theremin_top` core with a UART on the Cu's
FT2232 channel B (`usb_rx P14`, `usb_tx M9`, hardware-verified) at 115200.
The pitch "oscillator" is an NCO square wave whose period the GUI sets to a
millionth of a tick; the volume oscillator is the self-test counter. The
board streams back the measured audio period, amplitude and DSM density
every 20 ms; the GUI reads it as a note on a log axis.

The GUI's pitch slider is the HAND POSITION (0 away, 1 closest). The GUI
applies upstream's hand-distance curve (linearizationK 4.5) between the
calibrated periods (84 ticks -> A0, 80 ticks -> G7) and the FPGA's NoteMap
undoes it, so `--sweep` should draw a straight line A0 -> G7. Measured on
the Cu 11 Sep: A0 +9 c, F1 +2 c, F#2 +1 c, D4 +0.4 c, A#5 0 c, B6 -0.3 c,
G7 -0.3 c. (The far end is the steep end of the curve, as upstream.)

The volume slider is the other hand over the loop (0 away = full, 1 on the
loop = mute), through upstream's (1 - linear)^2 AmpMap (calibrated 92 ->
88 ticks; NB the volume channel's stage-2 reading is 2^20 x period, four
times the pitch channel's 2^18). Measured on the Cu 11 Sep, v = 0.1 / 0.25 /
0.5 / 0.75 / 0.9: -1.9 / -5.0 / -12.0 / -24.1 / -40.0 dB against -1.8 /
-5.0 / -12.0 / -24.1 / -40.0 expected. The telemetry's 16-bit peak is the
amplitude readout; the pitch readout (4-bit PCM crossings) drops out below
about -20 dB.

No link for 250 ms -> the board sweeps the pitch period on its own at full
volume, so this bitstream doubles as step 3. led[4] = link, led[5] = rx activity, led[6] =
byte decoded, led[3:0] level meter, led[7] DSM.

Rebuild after changing `NoteMap.hs` (needs the cabal toolchain; ~3 min in
Clash, the 1024-entry note table goes through `$readmemb` files):

    make notemap-files     # writes bringup/{notemap,ampmap}_{lo,hi}.bin
    make cu-gui            # clash -> yosys -> nextpnr -> bin/theremin-gui.bin

Resources on the HX8K: 5473 LC (71 %), 19 BRAM, 8/8 SB_GB, Fmax 52-54 MHz at 50.
All eight global buffers are now used - the next high-fanout enable needs care.
