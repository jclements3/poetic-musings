# pm-video — V0 text-console video core (1920x480 bar TFT)

The gateware behind the PM's `0x4026` oTFT/iTFT register pair
(`../eforth-pm.md` §1): a 240x30 character text mode on the 8.8"
1920x480 HSD088IPW1-A00 bar TFT (V0 in `../../LAYOUT.html`), driven
over DVI/GPDI from the ULX3S.  This is the V0 *core* — timing, text
buffer, font, pixel pipeline — everything below the VT100 interpreter
and above the TMDS serializers.

```
cabal test timing-test --test-show-details=direct
cabal test render-test --test-show-details=direct
cabal build exe:clash && cabal exec -- clash -isrc PM.Video.Top --verilog
```

## Modules

| Module | What |
|---|---|
| `PM.Video.Timing` | Parameterized h/v counters, sync pulses (polarity per record), active-area strobe, line/frame strobes. Takes a `VideoTiming` record; knows nothing about 1920x480. |
| `PM.Video.TextConsole` | 240x30 character buffer (one 7200x8 block RAM; CPU port write-only: `{row, col, char}`), cursor register with readback, and the char→glyph-row→pixel pipeline (2-cycle latency, syncs delayed to match). |
| `PM.Video.Font` / `PM.Video.FontData` | 8x16 font ROM (2 KB, one block RAM). Classic IBM PC VGA ROM font, extracted by `tools/psf2hs.py` from Debian console-setup's `Uni2-VGA16.psf.gz`; bitmap glyphs are not copyrightable in the US (37 CFR 202.1(e)), treated as public domain. ASCII 0x20–0x7E populated. |
| `PM.Video.Top` | `pm_video` synthesis top at the real timing: parallel RGB (8:8:8, green-phosphor fg per the LAYOUT V0 mock) + DE + syncs + cursor readback, in a ~66.7 MHz `PixelDom`. |

## The 0x4026 contract, and what V0 deliberately is not

`eforth-pm.md` specifies oTFT as "the upstream vga.vhd text/VT100
interface reused verbatim at 1920x480 timing".  The upstream stack
(`../forth-cpu-upstream/vga.vhd`) is:

```
oVT100 byte  ->  vt100 interpreter  ->  {addr, char} writes + cursor  ->  vga_core scan-out
```

This package is the **right-hand half** re-done in Clash at 240x30:
`textConsole` exposes exactly the interface the upstream `vt100` entity
drives into `vga_top` — a character write port and a cursor register —
so the VT100 layer (escape parsing, scrolling, the `big` large-font
escape, wrap, bell) drops on top later without touching this core.
V0 has no attributes and one font; `CharWrite.cwChar` bit 7 and the
second font-select are reserved for that layer (chars ≥ 0x80 alias into
0x00–0x7F today).

**Integration plan with `../clash-h2`** (stage 3.2 of the bring-up
table): the H2 system decodes address `0x4026`; a write pushes the byte
into the VT100 layer, which emits `Maybe CharWrite` + cursor updates
into `textConsole`; the iTFT read returns `{ready/busy, cursor row·col}`
— busy is the VT100 interpreter's (a scroll takes many cycles), the
cursor readback is already provided here.  The char RAM's write port
lives in the pixel clock domain, so the H2 (100 MHz system) side needs
the CDC library's handshake/FIFO for the write stream — same pattern as
every other cross-domain peripheral (`../../fpga-resource-swag.md`,
clock-domain list).

## Timings: known vs ASSUMED

`VideoTiming` is a parameter record (active/front-porch/sync/back-porch
each axis, plus per-axis sync polarity); every module takes it as an
argument, so pinning the real numbers later is a one-record edit.

`pm1920x480` — **ASSUMED pending the HSD088IPW1-A00 datasheet**:

| | active | front | sync | back | total |
|---|---|---|---|---|---|
| h (px) | 1920 | 18 | 6 | 6 | 1950 |
| v (ln) | 480 | 30 | 30 | 30 | 570 |

Syncs active-low.  1950 x 570 = 1,111,500 clocks/frame → **66.69 MHz
for 60.0 Hz** (66.28 MHz → 59.63 Hz).  Provenance: the Waveshare
"8.8inch Side Monitor" — the same 8.8" 1920x480 HSD088IPW1-class panel,
driven portrait through an HDMI-to-MIPI board — documents
`hdmi_timings=480 0 30 30 30 1920 0 18 6 6 0 0 0 60 0 66280000 3`
(native portrait 480x1920, 66.28 MHz); this record is that timing
transposed to the landscape scan our TFT driver kit presents.  What is
*known*: 1920x480 active, ~60 Hz, and that the pixel clock is in the
62–67 MHz class.  What is *assumed*: the porch/sync split and
polarities.  If the driver board wants a standard mode instead, CVT-RB
1920x480@60 is h 1920/48/32/80, v 480/3/10/7, 62.4 MHz — again just a
record edit.

`sim48x12` (timing testbench, 1080 clocks/frame, opposite sync
polarities to exercise both senses) and `sim48x32` (renderer testbench;
6x2 characters — a 12-line frame can't hold a 16-line glyph) are the
simulation records.

## TMDS plan (why there are no serializers here)

`pm_video` outputs parallel RGB + DE + syncs.  On the ULX3S the GPDI
connector is driven by ECP5 primitives that Clash cannot simulate and
shouldn't wrap yet: a second PLL output at 5x the pixel clock
(~333 MHz), TMDS 8b/10b encoders, and `ODDRX1F` DDR serializers with
`fake_differential` single-ended pairs — the stock `vga2dvid` pattern
from emard's ulx3s-misc.  Integration is a thin VHDL/Verilog shim
instantiating `pm_video` next to `vga2dvid`: `r/g/b → in_red/green/blue`,
`hsync/vsync/de → in_hsync/vsync/blank(=not de)`, pixel clock from the
same PLL.  At 66.7 MHz the bit clock is ~333 MHz DDR — within ECP5
ODDR reach (the same headroom argument as `fpga-resource-swag.md`'s
"iCE40 can't, ECP5 ODDR can").

## Tests

* `timing-test` — asserts, for **both** `pm1920x480` and `sim48x12`:
  line length == hTotal, frame length == hTotal*vTotal, hsync/vsync
  asserted at exactly the record's position/width/polarity on every
  line/frame, active strobe exactly `[0..hActive-1]` on active lines,
  and that `toX/toY` mirror the sample position.
* `render-test` — writes "PM" at (0,0)/(0,1) through the CPU port,
  renders a full post-write frame into a Haskell frame buffer, and
  asserts pixel-exact equality of the whole 48x32 frame: the 'P' and
  'M' glyphs at pixels x 0–7/8–15, y 0–15 — checked against the font
  table *and* against hard-coded IBM-VGA byte rows so a broken font
  can't self-validate — everything else background; that the first DE
  pixel of every line is column 0, glyph pixel 0, and the whole
  DE/sync/strobe stream equals the raw timing generator delayed by
  exactly 2 cycles (the pipeline depth); out-of-range writes ignored;
  cursor readback.

## Resources (yosys 0.68 `synth_ecp5`, this core alone)

110 LUT4 + 46 CCU2C + 26 PFUMX + 18 L6MUX21 (~200 LUT4-equivalent),
83 FF, **5 DP16KD** (4 = 7200x8 char buffer, 1 = 2048x8 font ROM),
2 MULT18X18D (the `row*240` address computations; free at this scale,
swappable for shift-add if DSPs ever get tight).  Comfortably inside
the `fpga-resource-swag.md` video line (3k LUT / 16 KB BRAM for the
full text/VT100 + overlay + TMDS family).
