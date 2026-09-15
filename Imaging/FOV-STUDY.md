# Imaging — Sep FOV / sensor / trigger study (Basic Plan input, 2026-09-15)

The study `DESIGN.md` § Sep study inputs calls for, with the snooker table as the fixed
target. Fixed inputs: 12 × 6 ft playing area (3569 × 1778 mm), 52.5 mm balls, ≤ 8 m/s,
200 fps, OV9281 (1/4" format, 1280 × 800 × 3 µm → 3.84 × 2.40 mm active, 4.5 mm diagonal;
the 640 × 400 @ 210 fps mode is 2 × 2 binned, so the FOV is the full die and the effective
pixel is 6 µm). Everything marked *verify* is checked at order time or on the bench.

## (a) Geometry — mount height vs focal length

Coverage rule: the 3569 mm long side plus 5 % margin (3747 mm) across the 640 px axis.
mm/px is then fixed at **5.85 mm/px** by the pixel count, independent of the lens; the
lens only sets the height: `H = f · 3747 / 3.84 mm`. Short axis at that scale covers
400 × 5.85 = 2342 mm — the 1778 mm cloth plus cushions and rails, 32 % spare. The table
surface is ~0.85 m off the floor, so add that to *H* for the ceiling check.

| f (M12) | HFOV | H above cloth | above floor | mm/px | ball px | σ centroid (0.1 px) | note |
|---|---|---|---|---|---|---|---|
| 1.7 mm | ~97° | 1.66 m | 2.5 m | 5.85 | 9.0 | 0.6 mm | fits an 8 ft ceiling; ~10 % barrel, calibrate out |
| **2.1 mm** | **85°** | **2.05 m** | **2.9 m** | **5.85** | **9.0** | **0.6 mm** | **pick — 9–10 ft ceiling or the light canopy** |
| 2.8 mm | 69° | 2.73 m | 3.6 m | 5.85 | 9.0 | 0.6 mm | needs a 12 ft ceiling |
| 3.6 mm | 56° | 3.51 m | 4.4 m | 5.85 | 9.0 | 0.6 mm | hall only |
| 4.0 mm | 51° | 3.90 m | 4.8 m | 5.85 | 9.0 | 0.6 mm | hall only |

σ centroid: a 9 px, ~64-pixel blob with ≥ 20 dB contrast gives 0.1–0.2 px from the
weighted sums (MAIDEN tabletop plan assumed 0.2 mrad; here 0.1 px × 6 µm / 2.1 mm =
0.29 mrad). **Recommendation: 2.1 mm f/2.0 M12 at 2.05 m over the cloth centre** — the
`DESIGN.md` "~2.5 m with a ~75° lens" row becomes 2.05 m / 85°; if the room has an 8 ft
ceiling, drop to 1.7 mm at 1.66 m (same mm/px, more distortion, calibrated out by the
checkerboard step). Lens choice never changes the ball-in-pixels figure — only the
sensor resolution does, and 640 px is the 200 fps mode.

## (b) Frame rate vs exposure, blur, light

At 200 fps the frame period is 5.0 ms. OV9281 global shutter exposes during the previous
readout, so up to ~4.5 ms is available; the blur budget, not the readout, sets exposure.
Blur = 8 m/s × t / 5.85 mm/px. Symmetric blur does not bias the centroid, it widens the
blob and moves the *time* the centroid stands for to mid-exposure — so the strobe/exposure
timestamp is taken at mid-exposure (`STROBE_STAMP` semantics unchanged; add t_exp/2 in
software).

| t exposure | blur @ 8 m/s | blur @ 2 m/s | lux needed, f/2, gain 4× (ISO≈800) | lux, gain 1× (ISO≈200) |
|---|---|---|---|---|
| 0.25 ms | 0.34 px (2 mm) | 0.09 px | 5,000 | 20,000 |
| **0.5 ms** | **0.68 px (4 mm)** | **0.17 px** | **2,500** | 10,000 |
| 1 ms | 1.37 px | 0.34 px | 1,250 | 5,000 |
| 2 ms | 2.7 px | 0.68 px | 625 | 2,500 |
| 4.5 ms | 6.2 px (ball smears to 15 px) | 1.5 px | 280 | 1,100 |

Lux from E = 250 · N² / (t · S) (incident-light exposure rule). A club table canopy gives
800–1,500 lux at the cloth, a home room 300–500. So **room light works at 1–2 ms**
(≤ 2.7 px blur only on a full-power break; ordinary shots < 1 px) and **0.5 ms wants
~2,500 lux, i.e. a strobe**. Two 10 W 850 nm CCTV illuminators (~2,000 lux-equivalent
at 2 m combined, radiant) pulsed 0.5 ms at 200 Hz (10 % duty, can be overdriven 3×) from
the FPGA's strobe line do it.

**IR-cut vs 850 nm:** prefer **850 nm strobe + 850 nm bandpass** on the lens: exposure
becomes independent of room lighting and flicker (mains-lit canopies flicker at 100/120 Hz,
which beats against 200 fps), and phenolic balls of every colour reflect NIR strongly, so
reds and the black threshold like the white — under visible light in mono the red and
brown balls sit close to green baize. *Verify first* with the module and a torch: the
baize's NIR reflectance (some wool dyes go bright at 850 nm). Fallback: IR-cut filter
(stock on most modules), 2 ms exposure, canopy light.

## (c) Sensor and interface — DVP vs MIPI, modules

DVP: 8 data + PCLK/HREF/VSYNC straight into the ✓ `PM.Dvp` capture block; at 640 × 400 ×
200 fps with blanking PCLK ≈ 65 MHz, cable **≤ 20 cm**, and OV9281 I/O is 1.8 V — two
SN74AVC8T245 level shifters on a breakout. MIPI CSI-2: one lane at ~800 Mb/s needs an
ECP5 soft D-PHY (LVDS input + resistor network + Lattice CSI-2 RX or the open-source
port) — "a deserializer and a lane of risk" (`DESIGN.md` § Out of scope). **Pick DVP.**
*Verify* in the OV9281 datasheet that DVP reaches 640 × 400 ≥ 200 fps (the 210 fps figure
is quoted for MIPI); if DVP caps lower, 1-lane MIPI is the fallback and the ECP5 D-PHY
work goes on the library map as ○.

| Module | Interface | FSIN trigger | STROBE | Price | Link |
|---|---|---|---|---|---|
| **Arducam OV9281 1 MP mono, M12 mount, external-trigger version** | MIPI 2-lane (Pi CSI) | yes — FSIN pad, Arducam external-trigger app note | not broken out (*verify*) | ~$35–45 | https://www.arducam.com/?s=OV9281 · https://docs.arducam.com/Raspberry-Pi-Camera/Native-camera/External-Trigger/ |
| Waveshare OV9281-110/120/160 | MIPI 2-lane | no | no | ~$25 | https://www.waveshare.com/ov9281-110-camera.htm |
| innomaker OV9281 MIPI / USB2 | MIPI or USB (not FPGA-native) | no | no | ~$30–40 | https://www.inno-maker.com/?s=OV9281 |
| **OV9281 DVP module, 24-pin ESP32-CAM-style FPC, M12** | **8-bit DVP** | FSIN on the FPC on most listings (*verify pinout*) | VSYNC serves — see (d) | ~$15–25 | https://www.aliexpress.com/w/wholesale-ov9281-dvp.html |

**Pick: the OV9281 DVP module** (M12, FSIN on the FPC) plus a 24-pin FPC breakout, with
the **Arducam trigger version as the MIPI fallback** if DVP cannot do 200 fps. Buy both;
together they are under $70.

## (d) Trigger and strobe, both directions

- **Slave (primary):** FPGA drives FSIN at PPS ÷ 200 phase-locked to G; the sensor's
  snapshot mode (`0x3006`/`0x3660`-group registers over SCCB, *verify* against the
  datasheet) exposes one frame per FSIN edge. Frame time is known by construction.
- **Master (fallback):** sensor free-runs; the FPGA stamps **VSYNC** (DVP has it as a
  wire — no STROBE pin needed) through `strobe_latch`; exposure start = VSYNC − t_readout
  offset from the register set, so a missing STROBE pin costs nothing on DVP. On the MIPI
  fallback, VSYNC is recovered from the frame-start packet.
- Bench proof: scope FSIN and VSYNC against G's PPS — a 200 Hz comb with a fixed phase
  (slave) or a walking phase logged by `STROBE_STAMP` (master).

## (e) Error law check

`DESIGN.md` quotes σ ≈ R² · σθ / B — that is the *stereo range* law (baseline B). Here the
ball lies on a known plane, so range is fixed and the lateral error is the single-camera
law σ = R · σθ: at R = 2.5 m, σθ = 0.2 mrad → **0.5 mm**; at the picked 2.05 m with the
measured 0.29 mrad → 0.6 mm (the 0.6 mm column above). For reference, if a second camera
were added at B = 1 m, range error would be 2.5² × 0.2e-3 / 1 = 1.25 mm — still under a
tenth of a ball. Speed from Δcentroid/Δt at 5 ms: 0.6 mm √2 / 5 ms = 0.17 m/s single-frame
noise, 0.02 m/s over a 10-frame fit — well inside M's 5 % gate at 2 m/s and above.

## (f) Lens and mount

M12 2.1 mm f/2.0 (5 MP-rated, ~$10; the DVP module usually ships with a 2.8 mm — swap).
Overhead mount: **Manfrotto 035 Super Clamp + 143 Magic Arm** (or the Neewer/SmallRig
equivalents at a third of the price) on the light canopy rail or a ceiling joist; a
3D-printed housing (Panel printer) with a ¼"-20 heat-set insert holds the sensor board
and the FPC breakout. The **≤ 20 cm DVP cable rule** means the ULX3S sits at the camera
for the Imaging gate — the box on the canopy or a shelf, HDMI/UDP running down — or, as
an upgrade, an SN65LVDS93/94 serializer pair carries the 11 DVP signals over one Cat-6
(the same LVDS trick as Erand49 row E5, ~$20).

## (g) Bill of materials — replaces ORDERS.md row I2 "TBD"

| Item | Qty | Est. | Link |
|---|---|---|---|
| OV9281 DVP module, M12, 24-pin FPC | 1 | ~$20 | https://www.aliexpress.com/w/wholesale-ov9281-dvp.html |
| Arducam OV9281 external-trigger MIPI (fallback) | 1 | ~$40 | https://www.arducam.com/?s=OV9281 |
| 24-pin 0.5 mm FPC breakout + FPC 15 cm | 1 | ~$8 | https://www.aliexpress.com/w/wholesale-24-pin-0.5mm-fpc-breakout.html |
| SN74AVC8T245 level-shifter breakout (1.8 ↔ 3.3 V) | 2 | ~$10 | https://www.mouser.com/c/?q=SN74AVC8T245 |
| M12 2.1 mm f/2.0 lens + M12 850 nm bandpass filter | 1 + 1 | ~$18 | https://www.aliexpress.com/w/wholesale-m12-2.1mm-lens.html |
| 850 nm 10 W LED illuminator | 2 | ~$30 | https://www.amazon.com/s?k=850nm+10w+ir+illuminator |
| Strobe driver: IRLZ44N + gate resistor, 12 V supply | 1 | ~$8 | https://www.mouser.com/c/?q=IRLZ44N |
| Super Clamp + Magic Arm (Neewer clone) | 1 | ~$35 | https://www.amazon.com/s?k=super+clamp+magic+arm |
| Printed housing, ¼"-20 insert, checkerboard print | — | ~$3 | Panel printer |
| **Total** | | **~$170** | ledger W |

Order after G1/N1 (row order in ORDERS.md); the DVP module and lens can come first for
the datasheet/fps *verify* on the bench the week the ULX3S lands.
