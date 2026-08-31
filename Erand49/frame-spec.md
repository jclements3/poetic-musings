# Erand49 frame spec — members, welds, neck stack (2026-08-31)

Material: 6061-T6 throughout. All strength checks use the **welded** (HAZ) allowable —
~140 MPa yield at 2x safety = 70 MPa working — because welding locally erases the T6
temper. Loads from `string-specs.md`: band pull 7.00 kN (49 strings), string angle
32 deg to the midrib (DXF).

| Member | Section | Governing load | Result |
|---|---|---|---|
| Midrib | **C-channel, 4 in x 1.75 in x 3/16 in** (web 4 in tall in the string plane, flanges +/-Y, open side lateral) | 5.9 kN axial toward shoulder + 3.7 kN transverse over ~1.9 m -> M ~ 0.88 kN-m mid-span | Sx ~ 30 cm3 class -> ~29 MPa bending, SF > 4 vs welded HAZ |
| Pillar | **square tube, 2 in x 2 in x 1/8 in** | few kN compression + hung PM console + lean loads | I ~ 2.3e5 mm4 -> Euler Pcr ~ 39 kN over ~2 m, ~8x margin; flat faces take the cleat halves directly, no welded rail |
| Shoulder block (neck rear) | machined block, **50 mm wide** | receives midrib weld | full-perimeter weld, made before plates install |
| Crown block (neck front) | machined block, **50 mm wide** | receives pillar weld | square tube welds flat-to-flat, easy fixturing |
| Neck plates x2 | per `Erand49.svg` hand-edited outline | pin + sensor mounting (verified: min pin-edge 16.2 mm, min sensor-edge 7.1 mm) | bolt to shoulder/crown blocks |

## Build sequence (weld access solved by order, not gap width)

1. With the neck plates OFF, weld midrib -> shoulder block and pillar -> crown block —
   open torch access all around both joints.
2. Bolt the two neck plates onto the blocks. The blocks are the plate spacers:
   **plate gap = 50 mm** (channel flange width 44.5 mm + margin). The channel section,
   unlike the old 76 mm round tube, no longer forces a wide neck.
3. Bolt the cleat halves to the pillar's flat +Y face for the PM console.

## Neck stack at the 50 mm gap

- **Tuner pins bridge both plates** (through-pins, supported both ends). "Alternating
  left/right" = which side the tuning head exits: odd strings +Y, even -Y; per-plate
  head spacing 26.6-35.9 mm. Use threaded harp pins or geared tuners (6-10 mm plate);
  tapered friction pins not recommended.
- **Sensor optics** in the plate inner faces, +/-25 mm from the string plane; X/Y IR
  beams cross at +/-45 deg on the string at the amber rail (1 in below each nut).
  ~50-70 mm beam path — shorter and better SNR than the 80 mm tube-era gap.

## C-channel notes

- Orient the 4 in web in the string plane; string terminations bolt through the web
  on its centerline. Open channels are torsionally soft, so keep the anchor line on
  the web centerline (minimal shear-center offset); if any twist shows up at full
  tension, bolt a flat closing strip across the flanges in the middle third — the
  channel becomes a box and the issue is gone.
- The open trough is the cable/hardware run: string tails, anchor nuts, and the
  gold-cable run to the plinth all live inside, serviceable with a screwdriver.

## Notes

- Aluminum CTE (23 ppm/C) vs steel strings (~12): mild thermal detuning; S4-CAL
  retunes digitally, no structural action needed.
- Damp channel ring if audible (foam strip in the trough doubles as cable retention).
