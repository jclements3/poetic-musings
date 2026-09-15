# SDR — Phase 10 design (direct-sampling HF on the theremin antennas)

Phase 10 of PLAN.md: an AD9226-class ADC direct-samples HF off the theremin antennas;
a DDC (NCO/mixer → CIC → FIR) brings one channel down to audio; waterfall on V0 via
Oracle. Work ledger (W), ~$30 hardware (fpga-development-plan.md row 10). Prereqs T and O.
Gate: **decode a broadcast or WSPR signal.** Demo: the theremin's antennas become a
radio receiver — same box, new mode, entered from the O-mode script menu.

**Spoke framing (PROGRAM.md):** S adds exactly one piece of hardware to the
Panel+Oracle root — the AD9226 ADC board plus the antenna relay — and exercises the
library's DDC set: `Theremin.Nco`, `Maiden.Cic`, `Maiden.Fir`, `Theremin.Fft`, CORDIC
magnitude for AM. The `MAIDEN/…` paths below are the library source archive — a plain
directory in this unified repo since 2026-09-15, not a dependency on another program;
blocks are consumed in place or ported per LIBRARY.md. In `../CLASH-LIBRARY-MAP.md`
§ Module list, S consumes the ✓ DSP core (CIC, FIR, FFT512, CORDIC, NCO) and owns the
○ entries it must write: DDC wiring at 65 MSPS and the AM envelope demod.
The Fft instance is shared with M (Motion radar) and the O spectrum view — one
arbitered copy (fpga-resource-swag.md).

## Signal path

```
pitch rod / volume loop ─ antenna relay ─ protection ─ high-Z buffer ─ 32 MHz LPF
  (end panels, LAYOUT)     (T ↔ S)        (clamp)      (JFET/opamp)    (anti-alias)
        → AD9226 @ 65 MSPS → NCO/mixer → CIC ÷512 → FIR comp ÷~4 → 32 kS/s I/Q
        → { AM/CW demod → oAudio SDR source → speaker/LINE OUT
           { 512-pt FFT → waterfall rows on V0 }
```

## Antennas and front end

Per LAYOUT.html end panels: **an internal relay hands both theremin antennas to the
SDR front end in S mode** (T mode hands them back to the Colpitts oscillator boards;
the relay must fully disconnect the oscillators — an LC tank hanging on the antenna
would both detune and radiate). The pitch rod is an electrically short probe — exactly
the PA0RDT "mini-whip" situation — so the front end is an **active-probe buffer**:
back-to-back protection diodes + series R at the relay, then a high-input-Z JFET or
FET-input-opamp follower driving the ADC input network through a 7-pole ~32 MHz
anti-alias LPF. The volume loop is the secondary input (small magnetic loop — useful
indoors where E-field noise swamps the rod); select via the second relay pole and one
mux bit. Nothing here needs gain flatness — WSPR/AM don't care, and calibration is a
lesson, not a spec.

## ADC — AD9226 class

12-bit, 65 MSPS, parallel CMOS output; the ubiquitous ~$30 eval modules fit the
"rear, at antennas" slot in the LAYOUT board table. Clocking: 65 MHz from an ECP5 PLL.
Once G exists, derive the PLL reference from the disciplined 10 MHz so the frequency
readout is calibrated — the WSPR-decode gate effectively requires this (a free-running
±30 ppm clock is ±420 Hz at 14 MHz, and the tuned station lands outside the 200 Hz
WSPR window). Direct sampling covers 0–32.5 MHz: the entire HF spectrum, no mixer
hardware, which is the whole point of the demo.

Data ingest: registered input DDR-safe capture at 65 MHz into the DSP clock domain
via an async FIFO (the CDC library blocks called load-bearing in fpga-resource-swag.md).

## DDC architecture

- **NCO**: 32-bit phase accumulator at 65 MHz, quarter-wave sin/cos LUT → 0.015 Hz
  tuning resolution. Phase increment written by Forth (`f!`).
- **I/Q mixer**: two 12×16 multiplies at 65 MSPS (2 DSP slices).
- **CIC decimator**: N=3, R=512 → 126.95 kS/s. **Reuse:
  `MAIDEN/firmware/doppler/rtl/cic_dec.vhd`** — parameterized N/R/W_IN with the bit-
  growth arithmetic documented in its header and a bit-true golden model. It was
  proven at 48 kS/s input; here the integrator section runs at 65 MHz and the growth
  math must be re-run (N=3, R=512 → 27 growth bits → ~39-bit integrators — wide but
  cheap). A Clash port with type-level ratio already exists
  (`MAIDEN/theremin/clash/src/Maiden/Cic.hs`); LIBRARY.md owns the catalog — this
  doc just claims the block.
- **Compensating FIR**: droop correction + final ÷4 → **~32 kS/s complex baseband**,
  ~30 kHz usable span per tuning. (The doppler chain skipped compensation — audit in
  its header — but a receiver's passband is audible, so S includes it.)
- **Demod**: AM = |I+jQ| (the fft512 header's max/min magnitude approximation is
  fine) → DC block → oAudio "SDR" source bit (already allocated at 0x402C in
  eforth-pm.md). CW/SSB = ±800 Hz BFO shift, USB/LSB via I/Q sign — stretch, not gate.

Resource check (fpga-resource-swag.md): SDR DDC ≈ 4k LUT / 16 KB / 12 DSP, the
DSP-hungry row — FIR time-sharing is limited at 65 MHz, so the FIR runs post-CIC at
127 kS/s where one DSP slice time-shares all taps easily. Fits the 85F with margin.

## Waterfall on V0 (via Oracle)

**Reuse: `MAIDEN/firmware/doppler/rtl/fft512_serial.vhd`** — 512-pt serial FFT with
sliding-window input, magnitudes in natural bin order, formats documented, golden-
model verified (a measured Clash R2SDF port also exists, per LIBRARY.md — 5.5% of the
85F); fpga-resource-swag.md already plans it as the *shared* FFT (spectrum
view + SDR waterfall, one instance, arbitered). Fed at 32 kS/s complex → 62.5 Hz/bin
over ±16 kHz. Each epoch writes one pixel row into the waterfall region of the video
overlay compositor (gateware); Oracle draws axes/legends as text and reads the peak
bins for a "strongest signal" readout. Scrolling, palette, and dB mapping are gateware;
*everything a human touches* — tuning, band presets, span, markers — is Forth, per the
eforth-pm.md gateware/Forth rule.

## Registers and Forth words

Provisional register block **0x4050–0x4056** (oSdrFreq lo/hi · oSdrCtrl: relay,
antenna select, demod mode, FFT tap select · iSdrPeak · iSdrStat). Deliberately clear
of eforth-pm.md's 0x4020–0x4036 map, of the IRIG-set/oHarp collision at 0x4036–0x403A
(flagged in GPS/DESIGN.md and LIBRARY.md), and of the 0x4040–0x4048 group GPS claims;
`forth-cpu-notes.md` pins the final map.

`SDR` vocabulary (SD-loaded): `f! ( hz-lo hz-hi -- )` tune · `band ( n -- )` presets
(WWV 10/15 MHz, 20 m/30 m WSPR, local AM) · `ant ( n -- )` rod/loop · `wf` waterfall
on V0 · `am` `cw` demod select + unmute via `source!` · `sdr-log` `spot` a reception.
The S3 slider has no SDR zone (P·O·E·T·I·C only) — SDR is reached from the O-mode
script menu, exactly as the LAYOUT modes table lists it ("SDR waterfall" under O);
entering the SDR script is what throws the antenna relay, leaving T mode's oscillators
untouched in every other mode.

## Verification and the gate

1. Simulation: DDC against a synthetic two-tone input; bit-true CIC vs its golden
   model (already exists in the MAIDEN tree); FFT bin placement vs known input.
2. Bench: signal generator (or the T-mode oscillator leakage itself) visible on the
   waterfall at the right frequency — this checks the whole clock/NCO arithmetic.
3. **Gate, per PLAN: decode a broadcast or WSPR signal.** Pragmatic split:
   - *In-box (the gate):* AM broadcast — tune a local station, hear program audio
     from the PM speaker. Unambiguous, laptop-free, grandkid-legible.
   - *Stretch:* WSPR decode — pipe the 32 kS/s channel as audio out LINE OUT into
     WSJT-X, decode a station; full in-box WSPR decode (FFT + Fano/Jelinek in Forth)
     is a future lesson, not gated. Receiving U's own beacon on a dummy-load whisper
     is the natural joint demo with Phase 9.

## Explicitly out of scope for Phase 10

Transmit anything (that is U — and the TX interlock hardware doesn't pass RF in
S/O mode), multi-channel DDC, panadapter-wide waterfalls (span is one DDC channel),
front-end preselectors beyond the single LPF, and in-box WSPR decoding.
