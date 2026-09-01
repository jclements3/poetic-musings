# pm-lib — PM gateware library

The first real PM gateware package: [Clash](https://clash-lang.org) modules
for the panel peripherals behind the eForth-PM register map
(`Oracle/eforth-pm.md` section 1).  The H2 CPU itself lives in
`Oracle/clash-h2`; this library is the *peripheral* side — each module
implements one register pair's contract so the eventual register file just
wires them to the bus.

> **Status:** compiles with GHC 9.6.7 / Clash 1.8.5; both modules are
> sim-verified by their testbenches (`cabal test`) and generate clean
> Verilog.  Not yet synthesised or run on hardware, and not yet attached to
> the H2 I/O bus.

## Layout

| File               | Register pair | Notes |
| ------------------ | ------------- | ----- |
| `src/PM/Matrix.hs` | 0x4024 oMatrixCtrl / iKeys | 8×8 matrix scanner: one-hot active-low row strobes, columns sampled at end of each row dwell, per-key 10 ms integrating debounce, 16-deep event FIFO. Keycode fold per `LAYOUT.html`: A0–G7 = 0–48, P0–P9 = 49–58, keycode = 8·row + col. |
| `src/PM/Zones.hs`  | 0x4020 oPanelCtrl / iPanel | Slider zone decoder for S2 (3 zones) · S3 (6, P·O·E·T·I·C) · S4 (4, OFF·CAL·PLAY·REC) with Schmitt hysteresis, plus the LAYOUT 1 s S3 mode dwell (`mode` + one-cycle `modeChange`) and the packed iPanel word. Takes already-sampled `Unsigned 12` values; ADC sequencing is oPanelCtrl's job, elsewhere. |
| `src/PM/Ulx25.hs`  | — | The shared 25 MHz ULX3S clock domain for both top entities. |
| `test/MatrixSpec.hs` | — | Closed-loop testbench: simulated diode-per-switch matrix with bounce injection; asserts debounced single events, LAYOUT keycodes, FIFO order/format/empty flag, the 5 ms glitch rejection, scan-disable, FIFO clear. |
| `test/ZonesSpec.hs`  | — | Boundary sweeps, parked-on-boundary noise (no flicker), sub-hysteresis steps, the S3 dwell firing exactly once (and a 10-tick bump firing never), iPanel packing. |

Bit layouts are provisional exactly as eforth-pm says the addresses are —
only the grouping is contractual.  The iPanel S3/S4 fields match the
`clash-h2/src/H2/SystemUart.hs` sim model of 0x4020.

## Building

```sh
cabal build
cabal test matrix-test --test-show-details=direct
cabal test zones-test  --test-show-details=direct
cabal run clash -- -isrc PM.Matrix --verilog   # verilog/PM.Matrix.topEntity/pm_matrix.v
cabal run clash -- -isrc PM.Zones  --verilog   # verilog/PM.Zones.topEntity/pm_zones.v
```

## Design notes

* **Debounce** is an integrating counter per key, threshold in scan passes;
  one full pass = exactly 1 ms at 25 MHz (8 rows × 3125 ticks), so the
  oMatrixCtrl debounce field is directly in milliseconds (default 10 ms —
  the fpga-development-plan quality-BOM norm, as in Coil/SantaGlide).  Any
  agreeing sample resets the integrator: tolerant of slow, bouncy release;
  a sub-threshold glitch emits nothing.
* **One event per clock**: the 8 columns latched at a row's sample tick are
  processed one key per cycle during the next row's dwell, so the FIFO needs
  only a single write port and events land in scan order.
* **No boundary tables**: the zone Schmitt test is phrased through the
  decoder itself (`zoneOf (v ∓ H)` compared against the current zone), so
  hysteresis costs only comparators around one constant multiply per slider
  — no dividers, no stored thresholds.
* Both scanners' outputs are Moore (state-only): strobes and register words
  never glitch.
