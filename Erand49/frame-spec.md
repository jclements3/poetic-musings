# Erand49 frame spec — members, welds, neck stack (2026-08-31)

**CAD master: `frame_cad.py` (build123d) → `frame.step`.** The solid model is the
dimensional source of truth; the ER sheets and figure 1 are being migrated to
projections from it (cad-front/side/top.svg are the first). Where a hand-drawn
sheet disagrees with the STEP, the STEP wins. cad-front.svg carries an ISO-129-style
dimension layer (overall height/length, pillar Ø, midrib depth) and cad-side.svg the
leg stance — post-processed into the SVGs as a `<g id="dimensions">` group by
frame_cad.py, every value measured from the solids.

Material: 6061-T6 throughout. All strength checks use the **welded** (HAZ) allowable —
~140 MPa yield at 2x safety = 70 MPa working — because welding locally erases the T6
temper. Loads from `string-specs.md`: band pull 7.00 kN (49 strings), string angle
32 deg to the midrib (DXF).

| Member | Section | Governing load | Result |
|---|---|---|---|
| Midrib | **C-channel: 2.5 in web on top + two side walls, 3/16 wall, OPEN BOTTOM — walls full 4 in through the base half, smoothstep TAPER to 2.25 in at the shoulder** (two saw cuts on the free lower edges; moment falls toward the supports) | 5.9 kN axial + 3.7 kN transverse over ~1.9 m | tapered: max ~78 MPa at xi~0.74 (allow 138 = yield/2; 3.5x vs yield), bow ~7.5 mm mid-span, ~0.7 kg saved; base half untapered for the pillar welds and leg hinges; symmetric section -> no string-load torsion |
| Pillar | **round tube, 2 in OD x 3/16 in wall**, crown to floor, passing through the midrib base | few kN compression + lean loads | Euler Pcr ~ 31 kN over ~2 m, ~6x margin |
| Neck plates x2 | per `Erand49.svg` hand-edited outline | pin + sensor mounting (verified: min pin-edge 16.2 mm, min sensor-edge 7.1 mm) | lap OUTSIDE the side walls at the shoulder (**ER-005**) — no milling, plates stand 8 mm proud each side; joined by two weld systems: the top seam (channel top corners to both plates along the ~60 mm lap) and the horizontal fillet (each plate bottom tab to its side wall); the neck edge lands ON the channel top line at the shoulder corner (**plate gap = 63.5 mm**). Crown: 6.35 mm pads per side to the round pillar, crush-sleeved bolts |

| Outrigger legs x2 | 1 in x 1/8 in flat bar, **550 mm, deployed 55 deg from vertical AND swept 55 deg in plan toward the treble**, shoulder-bolt hinges through the midrib side walls (**ER-006**): O10 h8 shoulder (M8 thread) bolt per side, O8.4 wall clearance hole, O10.1 leg/boss bore, flanged nut inside the open channel; hinge at x=308 z=325 mm | full static stability — the straight +/-Y legs left the base statically unstable forward (-10.3 deg) once the plinth dock was dropped (PM sits on the floor) | **CAD-measured** (frame_cad.py solids): assembly ~13.7 kg, CoM (443, 0, 1072) mm; support polygon x 129..693, stance 596 mm; tip angles: forward **+13.2 deg**, sideways **15.5 deg**, back **16.3 deg**, min hull-edge +9.2 deg. Fold flat for travel; wing-bolt locks |
| Crown infill (**ER-007**) | vertical run of the SAME 2.5 in x 3/16 channel at the pillar, walls 90 mm deep, **profile-cut to the neck curves** (top edge follows the tuner rail, bottom the sensor rail — intersected with the band profile in CAD); web faces FORWARD, wrapping the tube tangent, spanning the full plate front edge (z 1626-1773) | closes the 6.35 mm/side crown gap AND blocks the view of optics/strings from the front (YZ): outside faces 63.5 mm flat on both plates, walls 54 mm around the O50.8 tube (1.6 mm/side fillet welds) | two M8 bolts plate-wall-wall-plate at 15/45 mm below the plate corner, 21 mm behind the tube; CAD: ER-007 in frame.step, crown-plan slice shows the closed joint |

## Build sequence

1. One welded joint only (**ER-004**): stand the pillar, slide the midrib down over
   it — the open bottom and a O51 hole in the top web (string-free zone past a0)
   let the channel pass over the pillar and self-fixture. Weld the top-web rim
   and both side walls to the pillar. Both members
   stand on the floor: pillar foot + the midrib wedge tip — the channel runs out until the web top meets the floor (no end cut, sharp tip flush on the floor). No base plate.
2. Drill the midrib +/-Y faces for the neck-plate through-bolts (crush sleeves
   inside); make the two 6.35 mm crown pads.
3. Set the plates over the side walls at the shoulder lap (no milling): weld
   the top seam along the lap and the horizontal fillets along the plate bottom
   tabs (ER-005); at the crown, bolt via the 6.35 mm pads (crush sleeves
   through the round tube).

## Neck stack at the 63.5 mm gap

- **Tuner pins bridge both plates** (through-pins, supported both ends). "Alternating
  left/right" = which side the tuning head exits: odd strings +Y, even -Y; per-plate
  head spacing 26.6-35.9 mm; pins ~13 mm longer at this gap. Use threaded harp pins or geared tuners (6-10 mm plate);
  tapered friction pins not recommended.
- **Sensor optics** in the plate inner faces, +/-25 mm from the string plane; X/Y IR
  beams form a 60-deg pair (nominal +/-30 to Y) crossing on the string at the amber
  rail — the DXF optical points, 0.056*L below each flat pin — with a PER-STATION
  YAW of the pair chosen so all four bores land inside the plate outline (the
  sensor points sit near the plate's downhill edge). CAD bore-landing check:
  a 90-deg (+/-45) pair cannot fit 16 of 49 stations even with yaw; the 60-deg
  pair fits all 49. Per-station yaw and pair table: `sensor-stations.csv`
  (generated by frame_cad.py — the PCB placement input). The pair is two
  independent axes; X/Y solve is a per-string 2x2 calibrated at CAL
  (~15% noise penalty vs orthogonal.)
  ~73 mm beam path at +/-30 deg — routine for 3 mm IR pairs.

## Midrib channel notes

- Why 4 in deep: it is BENDING depth, not bulk — an unsupported 1.9 m beam under
  3.7 kN transverse needs depth^2. Walls stay 3/16 in — the section is skin and air.
- Taper (2026-09-01): depth is only needed where the moment is. Walls hold 4 in
  through the base half (pillar pass-through, leg hinges), then smoothstep to
  2.25 in at the shoulder. Fabrication is two saw cuts on the open channel's free
  lower edges. Source of truth: taper_depth() in gen_erand49.py; consumed by
  frame_cad.py and the drawings. Numbers: max 78 MPa @ xi=0.74, bow 7.5 mm.
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
