# Erand49 frame spec — members, welds, neck stack (2026-08-31)

Material: 6061-T6 throughout. All strength checks use the **welded** (HAZ) allowable —
~140 MPa yield at 2x safety = 70 MPa working — because welding locally erases the T6
temper. Loads from `string-specs.md`: band pull 7.00 kN (49 strings), string angle
32 deg to the midrib (DXF).

| Member | Section | Governing load | Result |
|---|---|---|---|
| Midrib | **C-channel: 2.5 in web on top (string face) + two 4 in side walls, 3/16 wall, OPEN BOTTOM** — strings through grommeted web holes; knots inside, covered by the sides, serviced from the open bottom | 5.9 kN axial + 3.7 kN transverse over ~1.9 m -> M ~ 0.88 kN-m mid-span | ~40 MPa, SF ~3.5 parent; bow ~3.5 mm; symmetric about the string plane -> shear center on-plane, no string-load torsion |
| Pillar | **round tube, 2 in OD x 3/16 in wall**, crown to floor, passing through the midrib base | few kN compression + hung PM console + lean loads | Euler Pcr ~ 31 kN over ~2 m, ~6x margin; cleat on a saddle block |
| Neck plates x2 | per `Erand49.svg` hand-edited outline | pin + sensor mounting (verified: min pin-edge 16.2 mm, min sensor-edge 7.1 mm) | rest on the midrib shoulder steps and weld to its center tongue (**ER-005**): side walls milled down 8 mm each above a horizontal step, leaving a 47.5 mm tongue = the plates inner gap; plate outer faces flush at 63.5 (**plate gap = 63.5 mm**). Crown: 6.35 mm pads per side to the round pillar, crush-sleeved bolts |

| Outrigger legs x2 | 1 in x 1/8 in flat bar, ~295 mm, shoulder-bolt hinges through the midrib side walls near the floor foot (**ER-006**) | sideways stability: frame footprint in Y is otherwise zero | deployed ~55 deg -> ~550 mm stance; tips only past ~19 deg lean; fold flat for travel; wing-bolt locks |

## Build sequence

1. One welded joint only (**ER-004**): stand the pillar, slide the midrib down over
   it — the open bottom and a O51 hole in the top web (string-free zone past a0)
   let the channel pass over the pillar and self-fixture. Weld the top-web rim
   and both side walls to the pillar. Both members
   stand on the floor: pillar foot + the midrib horizontal end cut. No base plate.
2. Drill the midrib +/-Y faces for the neck-plate through-bolts (crush sleeves
   inside); make the two 6.35 mm crown pads.
3. Mill the shoulder: horizontal step in both side walls, center tongue 47.5 mm
   (ER-005). Set the plates on the steps, weld them to the tongue both sides;
   at the crown, bolt via the 6.35 mm pads (crush sleeves through the round tube).
4. Bolt the cleat saddle around the round pillar for the PM console.

## Neck stack at the 63.5 mm gap

- **Tuner pins bridge both plates** (through-pins, supported both ends). "Alternating
  left/right" = which side the tuning head exits: odd strings +Y, even -Y; per-plate
  head spacing 26.6-35.9 mm; pins ~13 mm longer at this gap. Use threaded harp pins or geared tuners (6-10 mm plate);
  tapered friction pins not recommended.
- **Sensor optics** in the plate inner faces, +/-25 mm from the string plane; X/Y IR
  beams cross at +/-45 deg on the string at the amber rail — the DXF optical points, 0.056*L below each flat pin (uniform semitone fraction).
  ~64-90 mm beam path at +/-45 deg — routine for 3 mm IR pairs.

## Midrib channel notes

- Why 4 in deep: it is BENDING depth, not bulk — an unsupported 1.9 m beam under
  3.7 kN transverse needs depth^2; at 1.75 in deep the welded-HAZ stress would be
  ~4x over allowable. Walls stay 3/16 in — the section is skin and air.
- String terminations: grommeted holes in the top web on the centerline; knot
  inside, covered by the 4 in sides; restringing and wiring serviced directly
  through the open bottom — no access holes.
- Torsion: the section is symmetric about the string plane, so the shear center
  lies in that plane — string loads produce no twist. A bolted closing strip
  across the wall tips remains available if any asymmetric load (legs, transport)
  ever shows twist.
- Cable run to the plinth lives inside the open channel.

## Notes

- Aluminum CTE (23 ppm/C) vs steel strings (~12): mild thermal detuning; S4-CAL
  retunes digitally, no structural action needed.
- Damp channel ring if audible: foam strip in the open bore (doubles as cable retention).
