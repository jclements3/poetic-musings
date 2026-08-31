# Erand49 frame spec — members, welds, neck stack (2026-08-31)

Material: 6061-T6 throughout. All strength checks use the **welded** (HAZ) allowable —
~140 MPa yield at 2x safety = 70 MPa working — because welding locally erases the T6
temper. Loads from `string-specs.md`: band pull 7.00 kN (49 strings), string angle
32 deg to the midrib (DXF).

| Member | Section | Governing load | Result |
|---|---|---|---|
| Midrib | **Rect tube, 4 in x 2 in x 3/16 in** — strings through grommeted holes in the top face on centerline; knots concealed inside the sides; threading-access holes in the bottom face | 5.9 kN axial + 3.7 kN transverse over ~1.9 m -> M ~ 0.88 kN-m mid-span | Sx ~ 34.6 cm3 -> ~25 MPa, SF ~5.5 vs welded HAZ; closed section = torsion solved |
| Pillar | **square tube, 2 in x 2 in x 1/8 in**, top rebated 8 mm each side for the neck plates | few kN compression + hung PM console + lean loads | Euler Pcr ~ 39 kN over ~2 m, ~8x margin; cleat bolts to the flat +Y face |
| Neck plates x2 | per `Erand49.svg` hand-edited outline | pin + sensor mounting (verified: min pin-edge 16.2 mm, min sensor-edge 7.1 mm) | bolt flush onto the +/-Y faces of pillar and midrib — both members are 50.8 mm wide, so **plate gap = 50.8 mm**; no crown or shoulder blocks; through-bolts with crush sleeves |

## Build sequence

1. One welded joint only (**ER-004**): the midrib continues past a0 down to the
   floor, its end cut horizontal to stand flat (it IS the rear foot). In that
   string-free zone, a 50.8 mm slot through the TOP face lets the pillar drop
   inside; the pillar tip, cut at 58 deg, bears flat on the bottom face — crown
   load crosses in pure compression. Welds only lock it: slot-edge fillets plus
   one plug weld through the bottom face. Self-fixturing; side walls and the
   string face stay continuous; HAZ at the moment minimum; no base plate.
2. Rebate the pillar top 8 mm per side (plate-profile pocket); drill both members'
   +/-Y faces for the neck-plate through-bolts (crush sleeves inside the tubes).
3. Bolt the neck plates flush onto pillar top and midrib upper end: the members
   themselves set the **50.8 mm plate gap** — no blocks, smooth transition.
4. Bolt the cleat halves to the pillar's flat +Y face for the PM console.

## Neck stack at the 50.8 mm gap

- **Tuner pins bridge both plates** (through-pins, supported both ends). "Alternating
  left/right" = which side the tuning head exits: odd strings +Y, even -Y; per-plate
  head spacing 26.6-35.9 mm. Use threaded harp pins or geared tuners (6-10 mm plate);
  tapered friction pins not recommended.
- **Sensor optics** in the plate inner faces, +/-25 mm from the string plane; X/Y IR
  beams cross at +/-45 deg on the string at the amber rail (L/20 below each nut — uniform 5% sampling fraction).
  ~50-70 mm beam path — shorter and better SNR than the 80 mm tube-era gap.

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
