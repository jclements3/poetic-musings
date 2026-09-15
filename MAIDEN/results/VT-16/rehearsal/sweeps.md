# Roll recall vs wobble amplitude (twin augmentation)

The twin sheds zero roll wobble (see maneuver.py docstring);
amplitude below is injected augmentation. The physical level
for the club airframes is a campaign question — record the
measured value here after the first instrumented flights.

| wobble (m) | rules roll recall | MLP roll recall |
|---|---|---|
| 0.0 | 0% | 0% |
| 0.25 | 0% | 17% |
| 0.5 | 0% | 33% |
| 1.0 | 0% | 100% |
| 2.0 | 50% | 100% |

# Ellipticity probe (maiden51 Explore)

- ovality 0.2: loop-window kappa CV = 0.174; stage (a) still classifies loop: True. (kappa variance moves first; vplane is unmoved — an elliptical loop is still planar.)
- ovality 0.05: loop-window kappa CV = 0.104; stage (a) still classifies loop: True. (kappa variance moves first; vplane is unmoved — an elliptical loop is still planar.)
