# VT-15 twin rehearsal — track level (maiden21)

Twin evidence only; the VT-15 field column stays open until the campaign (D7). Camera 960x540, fx=831.5, eval window frames (440, 740), TrackerCfg defaults.

## Clean sky
- track recall >=6px: **0.985** (target >= 0.90; candidate-level was 0.985)
- recall 4-6px: None
- false tracks/frame: 0.0394

## Sun crossing
- sun at az/el = (5.4, 14.9) deg (target line of sight, mid-window)
- track recall >=6px: **0.951** (candidate-level sun run was 0.901, windowed dip 0.43)
- windowed recall minimum: 0.77
- frames emitted while COASTING near the dip: 16
- reacquisition delay after dip minimum: 0.03 s

## False-track pressure (renderer noise_sigma = 0.03, 3x, full session)
- false CONFIRMED/COASTING tracks: 0 in 1.0 min -> **0.00/min** (target <= 1/min)
- bird/junk injection: renderer has no bird model yet — deferred with lesson 10 Explore 3; rate above is noise-only and labeled as such.
