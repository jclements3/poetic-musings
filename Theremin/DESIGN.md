# Theremin — Phase 4 design (T · antennas on the box, and the library's regression gate)

PLAN.md Phase 4 (in `../`): bench the LC oscillator hardware; the Clash port already
passes. Pitch and volume from the antennas through the speaker; envelope/spectrum view
on V0 via Oracle. Prereq O (tuning UI). Personal ledger, $0 (parts ordered).
**Gate:** oscillator hardware on the bench; the ECP5 port tracks pitch and volume from
the antennas through the speaker. **Demo:** play music from thin air; watch the pitch
track on the display. **Standing rule from here on:** the theremin suite is the
regression target for every shared-library change.

**Spoke framing (`../PROGRAM.md`):** T adds one piece of hardware to the Panel+Oracle
root — the pitch rod (~18") and volume loop (~10") on the end-plate studs, with a
Colpitts oscillator board at each — and exercises the library's *sensor and
synthesis* set: `Theremin.EdgeSampler`, `EdgeToPulsePosition`, `SensorPeriodMeasure`,
`DelayDiffFilter`, `IirNStage` (175 LUT4 @ 132 MHz), `SensorTop`, the NCO and quarter-
wave sine LUT, the volume curve, `Pwm`/ΣΔ DAC, and `ThereminTop` (1,816 LUT4 / 452 FF
/ 2 BRAM measured). Its antennas are shared with S (SDR) through the internal relay;
its NCO is shared with S's DDC; its output is a Panel voice via `t>synth`.

## Where the code is (two directories, one spoke — unified repo since 2026-09-15)

| What | Where | Status |
|---|---|---|
| **Measured Clash port** — the load-bearing gateware | `../MAIDEN/theremin/clash/src/Theremin/` + `Maiden/{Cic,Fir,Cordic,Cfar}` and hedgehog specs in `test/` | ✓ sim-verified, area measured on ECP5; volume curve ported, NoteMap A0..G7 (2026-09 lab days) |
| This directory (`Theremin/`; formerly its own repo at github.com/jclements3/theremin, now archived) | `fpga/phase1/` VHDL NCO + testbench, `fpga/ROADMAP.md`, explainer artifacts, D-Lev reference files | older VHDL/iCE40-era learning path; **reference only** for the spoke — no `clash/` here |
| Explainers | `theremin.html`, `diagrams/`, `floorplan.txt`, `tutorial/`, `course/` | teaching assets; keep the physics accurate (see CLAUDE.md) |

`../LIBRARY.md` owns the block catalogue; do not fork blocks between the two directories.
The per-family module list is `../CLASH-LIBRARY-MAP.md` § Module list — T contributes the
sensor chain, IIR, NCO/LUT, DAC/PWM and the measured `ThereminTop`.

## Signal path

```
pitch rod ─ Colpitts osc A ─┐                      volume loop ─ Colpitts osc B ─┐
 (hand = capacitor plate)   ├─► EdgeSampler ─► EdgeToPulsePosition ─► SensorPeriodMeasure
                            │      (fast clock domain)                    │
                            └────────────────── DelayDiffFilter ─► IirNStage ─► SensorTop
                                                                                    │ pitch, volume (fixed point)
   NoteMap A0..G7 (optional quantise / display) ◄───────────────────────────────────┤
   NCO (phase acc) ─► quarter-wave sine LUT (BRAM) ─► × volume curve ─► ΣΔ/PWM DAC ─► speaker / oAudio theremin source
   FFT512 tap ─► spectrum strip on V0          pitch track ─► envelope strip on V0
```

- **Heterodyne stays physical:** the audible note is the *difference* of two RF
  oscillators; the FPGA measures period, it does not synthesise the RF. Octave span
  comes from the oscillator circuit, not antenna height.
- **CDC:** the edge sampler runs in the fast domain; `PM.Cdc` (2-flop, pulse sync)
  carries measurements to the audio/bus domain.
- **Bringup:** `bringup/` in the Clash tree; `t-cal` at S4 CAL retunes both
  oscillators to the room.

## Register / Forth interface (`../Oracle/eforth-pm.md`)

| addr | write | read |
|---|---|---|
| 0x402C | oAudio source-select bit *theremin* | — |
| (T group, TBD at Phase 4 start) | oTher — cal request, NoteMap on/off, FFT tap select | iTher — pitch (Hz Q), volume, osc lock flags |

Forth `THEREMIN` vocabulary: `t-cal` · envelope/spectrum view on V0 · `t>synth ( f -- )`
route the theremin as a Panel voice.

## Verification (the gate)

1. **Sim (already green):** hedgehog specs for every block in `test/` (`SensorSpec`,
   `SensorTopSpec`, `IirSpec`, `AudioSpec`, `NoteMapSpec`, `FftSpec`, plus the
   Maiden DSP specs); cycle-exact equivalence and GHDL elaboration of generated HDL
   per the Lesson 09 checks.
2. **Area (already measured):** `theremin_top` 1,816 LUT4 / 452 FF / 2 BRAM on
   ECP5-85F; IirNStage 175 LUT4 @ 132 MHz. Re-measure after any library change —
   this is the regression number.
3. **Bench (the gate):** both oscillators on the end plates; pitch tracks the hand
   over ≥ 3 octaves without dropouts; volume loop mutes to silence; `t-cal` recovers
   tuning after moving the box. Evidence to `Theremin/results/`.
4. **Demo:** play a tune from thin air; V0 shows pitch track + spectrum.

## Regression-gate rule (PLAN standing rule)

Every change to a shared library block (`Maiden.*`, `PM.Cdc`, NCO/DAC, FFT) must keep
the theremin specs green and the measured area within the recorded budget before it
lands. The theremin is the library's canary because it is the one spoke that is
already fully measured end to end.

## Out of scope

D-Lev's full feature set (presets, LCD UI, formant synthesis — reference only),
MIDI out (route through `t>synth`/Panel), anything SDR (the relay hands the antennas
to S; T's oscillators must be fully disconnected in S mode — `../SDR/DESIGN.md`).
