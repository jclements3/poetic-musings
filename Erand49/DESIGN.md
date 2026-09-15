# Erand49 — Phase 6 design (E · the silent 49-string optical harp)

PLAN.md Phase 6: 49 real strings (A0–G7, Erard band per `string-specs.md`) on a
welded 6061 frame (`frame-spec.md`, CAD master `frame_cad.py` → `frame.step`), each
string watched by an IR X/Y sensor pair; pluck detection and Karplus-Strong (KS)
synthesis in gateware; events to the box over a 3 Mbaud link; audio as I²S 24/96.
Prereqs P, O. Personal ledger, ~$1,200 (fpga-development-plan.md row 6).
**Gate 1 (cheap, first):** one string, one ADC eval, 5 IR pairs — pluck detected,
shown on V0, sounds a KS voice. **Gate 2:** 49 strings, harp-master I²S into the
box, 3 Mbaud event frames, playable. **Demo:** pluck real strings, the optical
sensors catch it, the box sings; harp events also drive the Panel synth.

**Spoke framing (PROGRAM.md):** E adds the most hardware of any spoke to the
Panel+Oracle root — 98 IR pairs, 13 multi-channel ADCs on a carrier PCB, and the
harp frame itself — and exercises the library's *detection* set: multi-channel
`PM.Spi` ADC sequencing, `Maiden.Cordic` (vectoring magnitude), `Maiden.Cfar`
(CA-CFAR, no divide), the planned KS waveguide with allpass fractional delay, the
ADSSR from `PM.Synth`, a planned I²S serializer (the `PM.HarpLink` event link ✓ is
kept for the harp's local controls only). The instrument is the mechanical layer (`LAYOUT.html`, `frame-spec.md`,
`string-specs.md`); this file is the gateware and the gates. The CORDIC + CFAR pair
is the same chain M uses for the snooker cue ball — one library, two sensors. In
`../CLASH-LIBRARY-MAP.md` § Module list, E consumes the ✓ CORDIC, CFAR, SPI master and
ADSSR, contributes the ✓ framed 8N1 event link (`PM.HarpLink`), and owns two ○ entries
to write: the Karplus-Strong waveguide with allpass fractional delay (DSP core) and the
I²S serializer (Audio). Staged purchases: `ORDERS.md`. The `MAIDEN/…` spec paths are
the library source archive, a plain directory in this unified repo since 2026-09-15.

## Signal path

```
49 strings ─ IR X/Y pair per string (60° pair, per-station yaw: sensor-stations.csv)
   → 98 photodiode channels → 13× ADS131M08 (8-ch, 24-bit, SPI) on the carrier PCB
   → 13 ADCs daisy-chained (SPI/LVDS) over the EtherCON link to the box → PM.Spi sequencer → DC HPF per channel
   → per-string 2×2 calibrated X/Y solve (CAL)        → CORDIC |x+jy| magnitude
   → CA-CFAR vs the string's own noise floor          → pluck event (string, velocity)
        ├─► KS waveguide ×49 @ 96 kHz (one pipelined engine, allpass fractional delay)
        │       → ADSSR → I²S 24/96 (harp is I²S master) → box oAudio harp source
        └─► PM.HarpLink 3 Mbaud 8-byte frames (A5 + cksum) → box 0x4036 iHarp FIFO
                → Forth: `.pluck` on V0 · `harp>synth` · `harp>midi`
```

- **One FPGA (decided 2026-09-15).** No harp-side board: the 13 ADS131M08s sit on
  the carrier PCB in the midrib and daisy-chain their SPI data over LVDS repeaters
  through the EtherCON cable; detection and KS run in the box. Cable length and noise
  floor are measured at gate 1 with the eval module on the real cable.
- **Detection = the radar chain at audio rate.** Velocity from the CFAR excess over
  threshold; the X/Y pair gives pluck direction (the ~15 % noise penalty of the 60°
  pair vs orthogonal is accepted for bore fit — `frame-spec.md`).
- **KS sizing** (fpga-resource-swag.md): delay lines ≈ 20k samples × 24 bit ≈ 80 KB
  BRAM; 49 strings @ 96 kHz = 4.7 M updates/s → one engine at 100 MHz, ~21 clocks
  per string per sample.

## Register / Forth interface (Oracle/eforth-pm.md)

| addr | write | read |
|---|---|---|
| 0x4036 | oHarp — event-link control (enable, reset, cal request) | iHarp — pluck event FIFO: string 0–48, velocity |
| 0x402C | oAudio source-select bit *harp I²S* | — |

Forth: `.pluck ( vel str -- )` show on V0 (gate-1 demo) · `harp>synth` events drive
KS/Panel voices · `harp>midi` re-emit as MIDI-style events · `cal` runs the sensor
null (S4 CAL position, per-string 2×2 solve).

## Verification (the gates)

1. **Sim:** CORDIC and CFAR hedgehog specs already green (`MAIDEN/theremin/clash`);
   HarpLink 3-frame byte-exact loop with corruption/resync asserted (`Oracle/pm-lib`);
   KS engine property-tested vs a NumPy reference (pitch within 1 cent across the
   band, decay time vs loop gain).
2. **Gate 1, one string:** ADC eval board + 5 IR pairs on the bench string; pluck →
   CFAR detection → `.pluck` on V0 → KS voice from the box speaker. False-alarm rate
   < 1/min at rest; no missed plucks in 100 tries. *Only then* buy 13 ADCs / 98 pairs.
3. **Gate 2, 49 strings:** full frame strung (rib ordered at P start after the bore
   check — PERT rule); I²S 24/96 harp-master into the box; 3 Mbaud events; playable
   glissando A0–G7 with no dropped or doubled events. Evidence to `Erand49/results/`.
4. **Demo:** pluck; the box sings; V0 shows string and velocity.

## Buy-late rule (PLAN standing rules)

1 ADC eval before 13 · 5 IR pairs before 98 · rib only after the micrometer bore
check · strings last.

## Out of scope

Pedals / semitone mechanism (fixed diatonic band), velocity from anything but the
optical pair, MIDI over DIN/USB (link is the PM 3 Mbaud frame; `harp>midi` re-emits
in software), acoustic soundboard (silent by design — the box is the voice).
