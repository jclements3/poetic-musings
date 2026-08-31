# Erand49 frame spec — members, welds, neck stack (2026-08-31)

Material: 6061-T6 throughout. All strength checks use the **welded** (HAZ) allowable —
~140 MPa yield at 2x safety = 70 MPa working — because welding locally erases the T6
temper. Loads from `string-specs.md`: band pull 7.00 kN (49 strings), string angle
32 deg to the midrib (DXF).

| Member | Section | Governing load | Result |
|---|---|---|---|
| Midrib | **Rect tube, 4 in x 2.5 in x 3/16 in** — strings through grommeted holes in the top face; knots concealed inside; access holes in the bottom face; bottom face cut away in the base zone only (ER-004) | 5.9 kN axial + 3.7 kN transverse over ~1.9 m -> M ~ 0.88 kN-m mid-span | ~24 MPa, SF ~5.7; closed section over the string band = torsion solved |
| Pillar | **round tube, 2 in OD x 3/16 in wall**, crown to floor, passing through the midrib base | few kN compression + hung PM console + lean loads | Euler Pcr ~ 31 kN over ~2 m, ~6x margin; cleat on a saddle block |
| Neck plates x2 | per `Erand49.svg` hand-edited outline | pin + sensor mounting (verified: min pin-edge 16.2 mm, min sensor-edge 7.1 mm) | bolt flush onto the midrib +/-Y faces (63.5 mm wide -> **plate gap = 63.5 mm**); at the crown, 6.35 mm pads per side between the round pillar and the plates, through-bolts with crush sleeves through the tube |

## Build sequence

1. One welded joint only (**ER-004**): stand the pillar, slide the midrib down over
   it — the bottom face is cut away and the top face holed Ø51 in the string-free
   zone past a0, so the tube passes over the pillar and self-fixtures. Weld the
   top-face rim and the bottom cut edges/side walls to the pillar. Both members
   stand on the floor: pillar foot + the midrib horizontal end cut. No base plate.
2. Drill the midrib +/-Y faces for the neck-plate through-bolts (crush sleeves
   inside); make the two 6.35 mm crown pads.
3. Bolt the neck plates flush onto the midrib upper end (gap = 63.5 mm) and onto
   the pillar crown via the pads (crush-sleeved bolts through the round tube).
4. Bolt the cleat saddle around the round pillar for the PM console.

## Neck stack at the 63.5 mm gap

- **Tuner pins bridge both plates** (through-pins, supported both ends). "Alternating
  left/right" = which side the tuning head exits: odd strings +Y, even -Y; per-plate
  head spacing 26.6-35.9 mm; pins ~13 mm longer at this gap. Use threaded harp pins or geared tuners (6-10 mm plate);
  tapered friction pins not recommended.
- **Sensor optics** in the plate inner faces, +/-25 mm from the string plane; X/Y IR
  beams cross at +/-45 deg on the string at the amber rail — the DXF optical points, 0.056*L below each flat pin (uniform semitone fraction).
  ~64-90 mm beam path at +/-45 deg — routine for 3 mm IR pairs.

## Midrib tube notes

- Why 4 in deep: it is BENDING depth, not bulk — an unsupported 1.9 m beam under
  3.7 kN transverse needs depth^2; at 1.75 in deep the welded-HAZ stress would be
  ~4x over allowable. Walls stay 3/16 in — the section is skin and air.
- String terminations: grommeted holes in the top face on the centerline (no
  shear-center offset by construction); knot inside, concealed by the sides;
  1/2 in threading-access holes in the bottom face opposite each anchor.
- Closed section: torsionally rigid — the C-channel closing-strip contingency is
  deleted. Cable run to the plinth clips along the bottom face outside.

## Notes

- Aluminum CTE (23 ppm/C) vs steel strings (~12): mild thermal detuning; S4-CAL
  retunes digitally, no structural action needed.
- Damp tube ring if audible: expanding foam or a sand/epoxy slug in the midrib bore.
