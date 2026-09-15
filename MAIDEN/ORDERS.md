# MAIDEN — things to order

Shopping list for the theremin build (the de-risking vehicle for MAIDEN's
FPGA/DSP work). Spend gets recorded in `LEDGER.md` as receipts come in.

> **On the links.** I cannot browse, so I have **not** verified any specific
> product page, price, or availability — a link to a particular ASIN would be
> a guess dressed up as a fact. Every link below is an **Amazon search URL**
> for the exact part spec, which is stable and lands you on real current
> listings. Where the part is genuinely spec-critical, the requirement is
> called out in the notes so you can check the listing yourself.
>
> For the passives, Digi-Key or Mouser will be cheaper, faster to get *right*,
> and far less ambiguous than Amazon — Amazon passive kits are frequently
> mislabelled. Amazon is fine for tubing, wire, and tools.

## 1. FPGA board — ORDERED

| Item | Qty | Status |
|---|---|---|
| ULX3S 85F (Lattice ECP5 LFE5U-85F, CABGA381) | 1 | **on order** |

Not from Amazon — ULX3S ships from Radiona/Mouser/Crowd Supply. BOM #7,
Note A. The ×3 in the BOM is for the MAIDEN build; one is enough for the
theremin spike.

## 2. Oscillator circuit — ×2 (pitch and volume axes)

Values are from upstream's LTspice model,
`theremin/fpga-theremin/hardware/oscillator/2018_09_colpitts_npn_oscillator_v3.asc`
(Colpitts, NPN, 3.3 V).

| Part | Value | Qty total | Notes | Search |
|---|---|---|---|---|
| L1 | 1.45 mH | 2 | **Spec-critical.** Model assumes Rser ≈ 65 Ω. Low Q may stop the oscillator starting. | [1.45 mH inductor](https://www.amazon.com/s?k=1.45mH+inductor) · [1.5 mH RF inductor](https://www.amazon.com/s?k=1.5mH+RF+inductor) |
| C2, C3 | 220 pF | 4 | **Must be C0G/NP0.** These set the tank frequency; X7R drift = audible pitch wander. | [220pF C0G NP0 capacitor](https://www.amazon.com/s?k=220pF+C0G+NP0+capacitor) |
| C1 | 4.7 pF | 2 | **Must be C0G/NP0**, same reason. | [4.7pF C0G NP0 capacitor](https://www.amazon.com/s?k=4.7pF+C0G+NP0+capacitor) |
| C4 | 1 µF | 2 | Decoupling; dielectric not critical. | [1uF ceramic capacitor kit](https://www.amazon.com/s?k=1uF+ceramic+capacitor) |
| R1 | 470 kΩ | 2 | 1/4 W, 1% | [470k ohm resistor 1%](https://www.amazon.com/s?k=470k+ohm+resistor+1%25) |
| R2 | 2.7 kΩ | 2 | 1/4 W, 1% | [2.7k ohm resistor 1%](https://www.amazon.com/s?k=2.7k+ohm+resistor+1%25) |
| Rant | 10 MΩ | 2 | Antenna bleed resistor | [10M ohm resistor](https://www.amazon.com/s?k=10M+ohm+resistor) |
| U1 | BC547C | 2 | Buy extras, they're pennies | [BC547C transistor](https://www.amazon.com/s?k=BC547C+transistor) |
| U2 | 74HC04 | 2 | Hex inverter, **3.3 V operation** | [74HC04 hex inverter](https://www.amazon.com/s?k=74HC04+hex+inverter) |

**PCBs:** upstream ships fabricable gerbers at
`hardware/oscillator/npn_oscillator_2018_v6_gerber.zip`. Send to JLCPCB /
PCBWay (~$5 for five) rather than Amazon. Or breadboard the first one — but
note breadboard stray capacitance will shift the tank frequency, so expect to
re-tune when you move to a board.

## 2a. ORDER SHEET — everything still missing for the theremin (11 Sep 2026)

Status check in the lab, 11 Sep 2026: the Alchitry Cu and Br are in hand and
the Cu is seen by the lab machine (`/dev/ttyUSB0/1`, `iceprog` works). Every
line in `LEDGER.md` with a price has been received. **Nothing in the analog
chain has been ordered yet.** This section is the complete cart. Three
vendors, three carts; check the box when the order is placed, then add the
row to `LEDGER.md` when the receipt lands.

The BOM below is read straight from the LTspice source
(`theremin/fpga-theremin/hardware/oscillator/2018_09_colpitts_npn_oscillator_v3.asc`)
and is *longer* than the table in section 2: the schematic also has an output
buffer stage (R3-R5, C5, C8, C10) and an ESD array that section 2 omitted.
Quantities are for **two** oscillators (pitch + volume) plus spares.

Link style: `DK` = Digi-Key keyword search, `M` = Mouser search, `AMZ` =
Amazon search. Same caveat as the header: these are search URLs, not
verified product pages. The one part number given below (the inductor) was
confirmed to exist at Newark/Octopart on 11 Sep 2026.

### Cart A — Digi-Key or Mouser (the tank + buffer; do NOT buy these on Amazon)

The tank parts set the frequency and the pitch stability. Buy them where the
dielectric and the coil specs are in the parametric filter, not the listing
title.

| [ ] | Ref | Part | Qty (2 osc + spare) | Spec to filter on | Links |
|---|---|---|---|---|---|
| [ ] | L1 | Inductor 1.5 mH (nearest E-series to the model's 1.45 mH; the 3 % shift is absorbed by the FPGA's frequency measurement) | 4 | Through-hole, +/-5 % or +/-10 %, **SRF >= 1 MHz** (tank runs ~400-600 kHz; the model's Cpar is 0.85 pF), DCR <= 65 ohm (lower is fine - higher Q starts more easily). **Bourns RLB9012-152KL** ($0.62, 1.5 mH, 3.8 ohm, 430 mA, SRF 1.10 MHz per datasheet - works, ~14 pF self-C pulls the tank ~6 % low, calibrated away). Better if stocked: **Murata 22R155C** (SRF 1.9 MHz, 6.5 ohm). | [DK](https://www.digikey.com/en/products/result?keywords=1.5mH%20inductor%20through%20hole) . [M](https://www.mouser.com/c/?q=1.5mH%20inductor%20radial) . [DK RLB9012-152KL](https://www.digikey.com/en/products/result?keywords=RLB9012-152KL) |
| [ ] | C2, C3 | 220 pF ceramic | 8 (4 needed) | **C0G/NP0**, 50 V, 5 %, through-hole radial. Filter: Temperature Coefficient = C0G, NP0. | [DK](https://www.digikey.com/en/products/result?keywords=220pF%20C0G%20radial%2050V) . [M](https://www.mouser.com/c/?q=220pF%20C0G%20radial) |
| [ ] | C1 | 4.7 pF ceramic | 4 (2 needed) | **C0G/NP0**, 50 V, +/-0.25 pF or 5 %. | [DK](https://www.digikey.com/en/products/result?keywords=4.7pF%20C0G%20radial%2050V) . [M](https://www.mouser.com/c/?q=4.7pF%20C0G%20radial) |
| [ ] | C10 | 1 pF ceramic (buffer input coupling) | 4 (2 needed) | **C0G/NP0**, 50 V. | [DK](https://www.digikey.com/en/products/result?keywords=1pF%20C0G%20radial%2050V) . [M](https://www.mouser.com/c/?q=1pF%20C0G%20radial) |
| [ ] | C4 | 1 uF ceramic (decoupling) | 4 | Any dielectric, >= 10 V. | [DK](https://www.digikey.com/en/products/result?keywords=1uF%20ceramic%20radial%2050V) |
| [ ] | C5 | 0.1 uF ceramic (74HC04 decoupling) | 4 | Any dielectric. | [DK](https://www.digikey.com/en/products/result?keywords=0.1uF%20ceramic%20radial%2050V) |
| [ ] | C8 | 10 nF ceramic | 4 | Any dielectric. | [DK](https://www.digikey.com/en/products/result?keywords=10nF%20ceramic%20radial%2050V) |
| [ ] | R1 | 470 kohm | 4 | 1/4 W, 1 % metal film. | [DK](https://www.digikey.com/en/products/result?keywords=470k%20ohm%201%25%201%2F4W%20metal%20film) |
| [ ] | R2 | 2.7 kohm | 4 | 1/4 W, 1 %. | [DK](https://www.digikey.com/en/products/result?keywords=2.7k%20ohm%201%25%201%2F4W%20metal%20film) |
| [ ] | R3 | 100 ohm (output series) | 4 | 1/4 W. | [DK](https://www.digikey.com/en/products/result?keywords=100%20ohm%201%25%201%2F4W%20metal%20film) |
| [ ] | R4, R5 | 1 Mohm (inverter bias) | 8 (4 needed) | 1/4 W. | [DK](https://www.digikey.com/en/products/result?keywords=1M%20ohm%201%25%201%2F4W%20metal%20film) |
| [ ] | Rant | 10 Mohm (antenna bleed) | 4 | 1/4 W; 5 % is fine. | [DK](https://www.digikey.com/en/products/result?keywords=10M%20ohm%201%2F4W%20resistor) |
| [ ] | U1 | BC547C NPN | 10 | TO-92, "C" gain grade. | [DK](https://www.digikey.com/en/products/result?keywords=BC547C) . [M](https://www.mouser.com/c/?q=BC547C) |
| [ ] | U2 | 74HC04 hex inverter | 4 | DIP-14 for the breadboard (SN74HC04N or equivalent), **3.3 V operation** - HC, not HCT. | [DK](https://www.digikey.com/en/products/result?keywords=SN74HC04N) . [M](https://www.mouser.com/c/?q=SN74HC04N) |
| [ ] | ESD | DALC208SC6 diode array (optional; the schematic's D1/D2/D7/D8 + 3.5 pF are its model) | 2 | Skip on the breadboard; fit on the PCB if the antenna will be touched a lot. | [DK](https://www.digikey.com/en/products/result?keywords=DALC208SC6) |

Priced 11 Sep 2026 (Mouser breaks; buy 10 of the 220 pF and 1 M - the
10-piece price beats 8 singles): **$23.90 + ~$8 shipping = ~$32**. One order
covers both oscillators. A $11 1280-piece 1 % metal-film resistor kit
(Amazon) replaces the five resistor lines; keep the three C0G tank caps from
Mouser - Amazon capacitor kits don't state the dielectric and have no 1 pF.

### Cart A, VERIFIED against the upstream PCB (11 Sep 2026)

The gerbers were parsed (63 drills, silkscreen rendered) and every part's
datasheet checked for lead spacing and grade. Board: 1.95 x 2.35 in, ONE
oscillator per board, silk "Theremin Sensor Oscillator rev0.1 (c) Vadim
Lopatin 2018". Buy for TWO boards. Corrections to the table above:

| Ref | Footprint on the PCB | Verdict on the part above | Buy instead / note |
|---|---|---|---|
| L1 | 2-pin, **2.54 mm** pitch | RLB9012-152KL is 5.0 mm pitch, 9 mm body: bend-to-fit, crowds the 1 M lead - stand it 2 mm off | **Murata 22R155C** (3.5 mm pitch, SRF 1.9 MHz) if stocked (TME/RS); else keep the Bourns and bend |
| C1, C2 220 pF | **5.08 mm** | K221J15C0GF5TH5 is 5.0 mm: FIT | as listed, qty 10 |
| 4.7 pF, 1 pF | 5.08 mm | KEMET C315 are 2.54 mm: splay to fit | native 5 mm, tighter tolerance: **TDK FG28C0G1H4R7CNT06** and **FG28C0G1H010CNT06** (C0G, 50 V, +/-0.25 pF). Board has a 2nd optional 4.7 pF position (C10, antenna-GND) |
| 1 uF | **2.54 mm radial electrolytic** footprint | C322C105K5R5TA is 5.08 mm: awkward | **KEMET C320C105K5R5TA** (same cap, 2.54 mm) |
| 0.1 uF | 5.08 mm, **three positions per board** | K104K15X7RF5TL2 is 2.5 mm | **K104K15X7RF5TH5** (5.0 mm), **qty 8** (6 needed) |
| 10 nF | 5.08 mm | K103K15X7RF5TL2 is 2.5 mm | **K103K15X7RF5TH5** (5.0 mm) |
| 470 k, 2.7 k, 100, 1 M x2 | axial, **10.16 mm** | Yageo MFR-25: FIT | as listed |
| Rant 10 M | **no footprint** - it is the antenna model in the .asc, not a part | drop | **don't buy** |
| U1 BC547C | TO-92 in-line 2.54 mm, square pad = collector | BC547CTA: FIT (C grade confirmed, hFE 420-800) | as listed; silk also allows 2N3904 |
| U2 74HC04 | DIP-14, pin 1 square, notch on the right | SN74HC04N: FIT, HC (2-6 V) | as listed |
| ESD DALC208SC6 | **SOT-23-6 pads present** | FIT | orientation: pin 2 (REF2/VCC) goes on the pad column nearer U1; reversed = diode short across the rail |
| J1 | 3-pin 2.54 mm: +3.3 V / OSC_OUT / GND (GND square) | - | Cart B header strip covers it |

**Layout trap, verified in the copper:** as shipped, L1's two pads are
bridged by a 0.66 mm top-side trace and the antenna block (2x2 pad, left
L1, C10) has no path to the tank. To get the LTspice topology (ANT - L1 -
C1 4.7 pF -> base, 1 pF -> inverter), **cut the ~1 mm trace between the two
right-hand L1 pads** and wire the antenna to the lower L1 pad. Everything
else on the board matches the schematic.

**PCM5102A DAC** (Cart B addition): 3.3 V I2S in, **no MCLK** (tie SCK to
GND, the PLL locks to BCK; BCK must be 32x or 64x fs). Concrete listing:
HiLetgo GY-PCM5102 pHAT with 3.5 mm jack, Amazon B07Q9K5MT8, $11.99
(2-pack B0B3T9995S $8.59-11.99). Back-side pads: H1L=L, H2L=L,
**H3L=H (unmute)**, H4L=L (I2S). Power VIN 5 V or the 3.3 V pin.

### Cart B — Amazon (mechanical, wire, test gear, audio)

Priced 11 Sep 2026: tube $26, RG316 25 ft $20 (1 m listings were all
unavailable), breadboard kit $8, Dupont $7, speakers $10, headers $7,
1 Hz-50 MHz counter module $13 = **$91 without a scope**. Scopes: FNIRSI
1014D $180 (cheapest), Hantek DSO2C10 $200 (cheapest credible bench),
Siglent SDS1202X-E $379. The PLJ-8LED counters start at 0.1 MHz and cannot
read the tank - the 1 Hz-50 MHz module is the right class.

**Don't-waste-money version (11 Sep):** skip the breadboard - the upstream
PCB is through-hole (63 holes, 0.7-1.0 mm) and takes Cart A's parts as
listed, and the breadboard is what detunes the tank. Add a **PCM5102 I2S
DAC board (~$8)**: the 1-bit DSM on a GPIO pin is the crappy-sounding part
of the current build, not the sensor. That cart is ~**$110** (A $32 +
PCBs $7 + tube $26 + coax $20 + speakers $10 + headers $7 + DAC $8), plus
the $13 counter if the lab has no scope. Everything in it is a keeper.

| [ ] | Item | Qty | Spec | Links |
|---|---|---|---|---|
| [ ] | Antenna tube, aluminium or brass, 1/2" OD | 1 length, >= 4 ft | 18" straight rod (pitch) + ~32" formed into a ~10" loop (volume); hardware store is equally good | [AMZ Al](https://www.amazon.com/s?k=1%2F2+inch+aluminum+tubing+round) . [AMZ brass](https://www.amazon.com/s?k=brass+tubing+1%2F2+inch) |
| [ ] | Shielded coax RG178 or RG316 | 1 m | Antenna to oscillator; keep runs short | [AMZ](https://www.amazon.com/s?k=RG316+coaxial+cable) |
| [ ] | Oscilloscope (or frequency counter) | 1 | **Skip if there is one on the bench.** Any 2-channel scope >= 20 MHz sees a 600 kHz square wave; a counter module works too. ORDERS section 4: the most likely bring-up blocker | [AMZ scope](https://www.amazon.com/s?k=digital+oscilloscope+2+channel) . [AMZ counter](https://www.amazon.com/s?k=frequency+counter+module) |
| [ ] | Breadboard + jumper kit | 1 | Full-size, with jumpers | [AMZ](https://www.amazon.com/s?k=breadboard+jumper+wire+kit) |
| [ ] | Dupont wire, M-F and M-M | 1 kit | Br bank to breadboard | [AMZ](https://www.amazon.com/s?k=dupont+jumper+wire+kit) |
| [ ] | Powered speaker with 3.5 mm input + cable | 1 | For runbook steps 3-5 (`audio` pin through 1 kohm + 10 nF - the R and C are in Cart A's kit values, or any junk-box parts) | [AMZ](https://www.amazon.com/s?k=small+powered+speaker+3.5mm+aux) |
| [ ] | 0.1" header strip (only if the Br bank shipped bare) | 1 | 40-pin breakaway male | [AMZ](https://www.amazon.com/s?k=2.54mm+male+header+strip+40+pin) |

### Cart C — JLCPCB / PCBWay (optional, after the breadboard runs)

| [ ] | Item | Qty | Notes |
|---|---|---|---|
| [ ] | Oscillator PCB from `hardware/oscillator/npn_oscillator_2018_v6_gerber.zip` | min order (5) | $2 for 5 + $1.50-6.59 shipping + US duty collected by JLCPCB = **~$7** (11 Sep quote). Through-hole footprints. |

### Order of use once it all arrives

Runbook `theremin/clash/bringup/BRINGUP.md` steps 2-4 need **nothing from
these carts** (LEDs only; a speaker to hear it). Step 5 needs Cart A + the
scope + one antenna rod. The volume axis needs the second oscillator and the
loop; it can wait until the pitch axis plays.

## 3. Antennas

The schematic models the antenna only as `Cant = 7 pF`, so physical dimensions
are a free choice. These are conventional theremin proportions:

| Item | Spec | Qty | Search |
|---|---|---|---|
| Pitch antenna | ~1/2" (12 mm) OD tube, ~18" long, aluminium or brass | 1 | [1/2 inch aluminum tube](https://www.amazon.com/s?k=1%2F2+inch+aluminum+tubing+round) · [brass tubing 1/2 inch](https://www.amazon.com/s?k=brass+tubing+1%2F2+inch) |
| Volume antenna | Same tubing, formed into a ~10" diameter loop | 1 | (same stock as above — buy enough length for both) |
| Shielded coax | Short runs, antenna to oscillator | 1 | [RG178 coax cable](https://www.amazon.com/s?k=RG178+coaxial+cable) · [RG316 coax](https://www.amazon.com/s?k=RG316+coaxial+cable) |

**This matters more than the part numbers:** the antenna-to-oscillator lead is
*part of the tank capacitance*. Keep each run short, mechanically rigid, and
identical between builds — a lead that flexes is a pitch that drifts. Ground
the coax shield at the oscillator end only.

## 4. Test equipment

| Item | Why | Search |
|---|---|---|
| Oscilloscope or frequency counter | **Most likely bring-up blocker.** You must confirm each oscillator starts and runs near design frequency, and that the two aren't pulling each other. Invisible from the FPGA side. | [digital oscilloscope 100MHz](https://www.amazon.com/s?k=digital+oscilloscope+100MHz) · [frequency counter 10MHz](https://www.amazon.com/s?k=frequency+counter+module) |
| Breadboard + jumpers | First oscillator bring-up | [breadboard jumper wire kit](https://www.amazon.com/s?k=breadboard+jumper+wire+kit) |
| Dupont / header wire | Board to oscillator | [dupont wire kit](https://www.amazon.com/s?k=dupont+jumper+wire+kit) |

If you already have a scope on the bench, skip this section entirely.

## 5. Audio output

The ULX3S has a 3.5 mm jack driven by an on-board resistor DAC. That is very
likely good enough to hear the thing work, so **buy nothing here until the
sensor path runs**. Only if the resistor DAC proves too noisy would you add an
I²S DAC board ([I2S DAC module](https://www.amazon.com/s?k=I2S+DAC+module+PCM5102)).

## 6. Cables, power, and interconnect (gap check — added 25 Aug)

Audit of everything between the boxes. Good news first: **no special FPGA
programmer is needed** — the ULX3S programs and talks UART over its onboard
USB-serial (FT231X); `fujprog` or `openFPGALoader` on the lab machine plus an
ordinary cable is the whole path.

| Item | Why | Search |
|---|---|---|
| Micro-USB **data** cable ×2 | ULX3S programming/UART — many micro-USB cables are charge-only; a bad one looks like a dead board | [micro USB data cable](https://www.amazon.com/s?k=micro+usb+data+cable+short) |
| 0.1" header strips + solder | ULX3S GPIO holes ship unpopulated on some batches; needed to jumper oscillators/ADC | [2.54mm header strip](https://www.amazon.com/s?k=2.54mm+male+female+header+strip) |
| 3.5 mm audio cable + small powered speaker | The theremin has an audio jack and nothing listed to hear it with | [powered speaker 3.5mm](https://www.amazon.com/s?k=small+powered+speaker+3.5mm+aux) |
| USB-C PSU 5 V/5 A (or buck output cable) ×3 | Pi 5 recorders — BOM #6 lists Pi+SSD+SD but no supply; on-station the 4S pack + buck covers it, at the desk you need the PSU | [Raspberry Pi 5 power supply 27W](https://www.amazon.com/s?k=raspberry+pi+5+official+power+supply+27W) |
| USB3 camera cables (check what ships) | Machine-vision cameras often ship bare; confirm cable + locking screws at order time (note on BOM #4) | vendor page at camera order |
| GNSS antennas (check breakout) | MAX-M10S breakouts vary: some include a patch antenna, some need an active antenna + u.FL/SMA pigtail | [GNSS active antenna u.FL](https://www.amazon.com/s?k=GNSS+active+antenna+uFL+SMA) |

Rough add: ~$60–120. This is exactly what the whitepaper's
spares/contingency reserve exists for — no budget-line change needed.

## 7. Not needed

- **iCE40 boards** — you already own the iCEstick and HX8K breakout (BOM #8,
  marked OWNED). They are bring-up boards and too small for the FFT anyway.
- **Xilinx/Zynq board** — would let you run upstream's ISERDES front end
  unmodified, but proves the toolchain on hardware MAIDEN will never use.
  Deliberately rejected.
- **Anything for the ISERDES gap** — resolved in software. See
  `theremin/clash/src/Theremin/EdgeSampler.hs`: plain 1x sampling plus the
  existing 512-tap averaging gives ~0.02 cent resolution, so no exotic
  front-end hardware is required.

## Cameras (MAIDEN proper, not the theremin)

BOM #4, Note B — global shutter, hardware strobe out, USB3, C/CS mount, three
lens fields (60°/35°/60° per D6). Model not yet selected; the rolling-shutter
warning in lesson 16 is the reason for the global-shutter requirement. Not an
Amazon purchase — machine-vision vendors (FLIR, Basler, IDS).
