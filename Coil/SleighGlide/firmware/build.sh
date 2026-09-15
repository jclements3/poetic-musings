#!/usr/bin/env bash
# build.sh — synthesize the Sleigh Glide bitstream for the Alchitry Cu.
#
# Toolchain: oss-cad-suite installed without sudo via apio
#   pip install --user apio && apio install oss-cad-suite
# Binaries land in ~/.apio/packages/tools-oss-cad-suite/bin (override with
# $FPGA_TOOLS, e.g. to point at a system yosys/nextpnr install).
#
# Prerequisite: the Clash-generated Verilog. Regenerate from Oracle/clash-h2:
#   cabal exec -- clash --verilog \
#     -fclash-hdldir "<repo>/Coil/SleighGlide/firmware/verilog" \
#     "<repo>/Coil/SleighGlide/firmware/SleighGlide.hs"
set -euo pipefail
cd "$(dirname "$0")"

TOOLS="${FPGA_TOOLS:-$HOME/.apio/packages/tools-oss-cad-suite/bin}"
SRC=verilog/SleighGlide.topEntity/sleigh_glide.v
OUT=build

[ -f "$SRC" ] || { echo "error: $SRC not found — regenerate with Clash (see header)"; exit 1; }
mkdir -p "$OUT"

# 1. Synthesis (yosys). Top is the board wrapper cu_top.v, which ties en=1
#    and adapts the Cu's active-low reset button.
"$TOOLS/yosys" -q -l "$OUT/yosys.log" \
  -p "read_verilog $SRC cu_top.v; synth_ice40 -top cu_top -json $OUT/sleigh_glide.json"

# 2. Place & route (nextpnr). Alchitry Cu = iCE40 HX8K, CB132 package.
#    The logic clock is 50 MHz (PLL in cu_top.v divides the 100 MHz
#    oscillator by 2 — the design's Fmax is ~60 MHz on HX fabric), so the
#    timing target is 50 MHz; nextpnr applies it to the derived clk50 net.
"$TOOLS/nextpnr-ice40" --hx8k --package cb132 --freq 50 \
  --json "$OUT/sleigh_glide.json" --pcf sleigh_glide.pcf \
  --asc "$OUT/sleigh_glide.asc" --log "$OUT/nextpnr.log"

# 3. Bitstream.
"$TOOLS/icepack" "$OUT/sleigh_glide.asc" "$OUT/sleigh_glide.bin"

echo
grep -E "Max frequency for clock" "$OUT/nextpnr.log" | tail -1
echo "bitstream: $OUT/sleigh_glide.bin"
