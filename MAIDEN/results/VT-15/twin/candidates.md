# VT-15 twin rehearsal — candidate stage (maiden19)

**Twin evidence only** (renderer per lesson 10; not field performance).
Setup: station A pose (hdg 12.4, el 8), 960x540 render (intrinsics
scaled with resolution), frames 440-740 (first FOV pass), SkyModel(n=25,
stride=3), propose(k=4, min_area=3), seed 0.

| condition | recall >=6px | min 1s-window recall | false/frame |
|---|---|---|---|
| clean sky | 0.985 | 0.91 | 0.000 |
| sun on path (az 10.0, el 14.7, r=40px) | 0.901 | 0.43 | 0.000 |

Sun dip: windowed recall bottoms at 0.43; width below 0.5 recall
0.0 s. Trace: recall_trace.png. Mechanism: the disc+bloom
saturate the sensor and the target's contrast clips away (renderer draws
sun last for exactly this reason). This is D5 risk R1 quantified on twin
imagery; maiden20-21 (track coasting) and the saturation-mask Explore
inherit the job of shrinking it.

Throughput, 1080p, single core, no ROI tricks (SYS-011 will ask):
sky update 112.2 ms/frame, residual+propose
8.8 ms/frame (113.9 fps). The strided sky update
amortizes to ~37 ms/frame at stride 3; 30 fps
overall needs ROI processing around active tracks or downscaled proposal
with full-res confirmation — noted for maiden20.
