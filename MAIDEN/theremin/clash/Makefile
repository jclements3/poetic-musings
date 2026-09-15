# Clash port of the fpga-theremin DSP blocks.
#
# GHDL/Yosys/nextpnr come from the pinned OSS CAD Suite; source its
# environment before any of the hdl targets:
#     source ~/tools/oss-cad-suite/environment

BUILD    := build

# The clash binary from the project's own build plan (built via
# build-tool-depends). A globally installed clash cannot be used: it refuses
# to run against any clash-prelude instance other than its own.
CLASH := $(shell ls -td $$HOME/.cabal/store/ghc-9.6.7/clash-ghc-1.8.5-e-clash-*/bin/clash 2>/dev/null | head -1)
TOP      ?= Theremin.IirNStage
ENTITY   ?= iir_nstage_pow2k

VHDL_DIR := $(BUILD)/vhdl
VLOG_DIR := $(BUILD)/verilog

# --- Target part -------------------------------------------------------
# MAIDEN's recommended board is the ULX3S 85F (hardware/BOM.md Note A):
# Lattice ECP5 LFE5U-85F, 85k LUT4s. The iCEstick/HX8K are bring-up boards
# only and are too small for the FFT datapath, so ECP5 is what resource
# numbers here are measured against.
DEVICE   ?= 85k
PACKAGE  ?= CABGA381
FREQ_MHZ ?= 100

# GHDL on Ubuntu 22.04 (glibc < 2.38) needs the __isoc23_* shim during
# elaboration; same workaround as the VHDL project's Makefile.
comma := ,
SHIM := $(HOME)/tools/glibc-isoc23-shim.o
GHDL_ELAB_FLAGS := $(if $(wildcard $(SHIM)),-Wl$(comma)$(SHIM),)
GHDL_FLAGS := --std=08 --workdir=$(BUILD)/work -fsynopsys

.PHONY: all build test vhdl verilog sim synth pnr report clean

all: test sim report

## Compile the library and test suite.
build:
	cabal build all

## Haskell-side behavioural tests (fast feedback loop).
test:
	cabal test --test-show-details=direct

## Generate VHDL (used for GHDL simulation and co-sim against the original).
vhdl:
	@mkdir -p $(VHDL_DIR)
	cabal exec -- $(CLASH) -isrc $(TOP) --vhdl -outputdir $(BUILD)/clash-out \
		-fclash-hdldir $(VHDL_DIR)

## Generate Verilog (used for the ECP5 open synthesis flow).
verilog:
	@mkdir -p $(VLOG_DIR)
	cabal exec -- $(CLASH) -isrc $(TOP) --verilog -outputdir $(BUILD)/clash-out \
		-fclash-hdldir $(VLOG_DIR)

## Analyse + elaborate the generated VHDL under GHDL: proves the output is
## valid, elaboratable VHDL-2008 before it reaches synthesis.
sim: vhdl
	@mkdir -p $(BUILD)/work
	ghdl -a $(GHDL_FLAGS) $$(find $(VHDL_DIR) -name '*_types.vhdl' | sort) \
	                      $$(find $(VHDL_DIR) \( -name '*.vhdl' -o -name '*.vhd' \) ! -name '*_types.vhdl' | sort)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) $(ENTITY)
	@echo "GHDL elaborated $(ENTITY) from Clash-generated VHDL."

## Synthesise to ECP5 and report cell usage.
synth: verilog
	yosys -p 'read_verilog -sv $$(find $(VLOG_DIR) -name "*.v" | sort | tr "\n" " "); \
	          synth_ecp5 -top $(ENTITY) -json $(BUILD)/$(ENTITY).json' \
	    | tee $(BUILD)/$(ENTITY).synth.log

## Place and route for the real part: this is the number that matters when
## judging whether a Clash datapath fits the MAIDEN board.
pnr: synth
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ_MHZ) \
	    --json $(BUILD)/$(ENTITY).json --textcfg $(BUILD)/$(ENTITY).config \
	    2>&1 | tee $(BUILD)/$(ENTITY).pnr.log

## --- iCE40 evaluation path (parallel to the ECP5 flow; same Verilog) ---
## Usage: make pnr-ice40 ICE_DEV=hx8k ICE_PKG=ct256 ICE_FREQ=48
ICE_DEV  ?= hx8k
ICE_PKG  ?= ct256
ICE_FREQ ?= 48

synth-ice40: verilog
	yosys -p 'read_verilog -sv $$(find $(VLOG_DIR) -name "*.v" | sort | tr "\n" " "); \
	          synth_ice40 -top $(ENTITY) -json $(BUILD)/$(ENTITY)-ice40.json' \
	    | tee $(BUILD)/$(ENTITY)-ice40.synth.log

pnr-ice40: synth-ice40
	nextpnr-ice40 --$(ICE_DEV) --package $(ICE_PKG) --freq $(ICE_FREQ) \
	    --json $(BUILD)/$(ENTITY)-ice40.json --pcf-allow-unconstrained \
	    --asc $(BUILD)/$(ENTITY)-$(ICE_DEV).asc \
	    2>&1 | tee $(BUILD)/$(ENTITY)-$(ICE_DEV).pnr.log

## Pack the routed ECP5 design into a flashable bitstream. On the ULX3S:
##     openFPGALoader -b ulx3s $(BUILD)/$(ENTITY).bit      (SRAM, volatile)
##     openFPGALoader -b ulx3s -f $(BUILD)/$(ENTITY).bit   (flash, persistent)
## (fujprog works too if openFPGALoader lacks the board profile.)
## Note: pnr above runs unconstrained; a real board build needs --lpf with
## bringup/ulx3s/ulx3s_v20.lpf and top-level ports named to match it.
bit: pnr
	ecppack $(BUILD)/$(ENTITY).config $(BUILD)/$(ENTITY).bit

## ULX3S arrival-day blinky: proves board + cable + flow before any
## theremin logic. Pure Verilog, no Clash needed. Output is tracked in
## git so the lab machine can flash it with nothing but openFPGALoader.
ulx3s-blinky:
	@mkdir -p $(BUILD)/ulx3s
	yosys -p 'read_verilog bringup/ulx3s/blinky.v; synth_ecp5 -top blinky -json $(BUILD)/ulx3s/blinky.json' \
	    | tee $(BUILD)/ulx3s/blinky.synth.log
	nextpnr-ecp5 --85k --package CABGA381 --freq 25 \
	    --json $(BUILD)/ulx3s/blinky.json \
	    --lpf bringup/ulx3s/ulx3s_v20.lpf --lpf-allow-unconstrained \
	    --textcfg $(BUILD)/ulx3s/blinky.config \
	    2>&1 | tee $(BUILD)/ulx3s/blinky.pnr.log
	ecppack $(BUILD)/ulx3s/blinky.config bringup/bin/ulx3s-blinky.bit

## Summarise LUT/FF/DSP/BRAM usage and achieved Fmax.
report: pnr
	@echo "=== $(ENTITY) on ECP5 $(DEVICE) $(PACKAGE) ==="
	@grep -E 'TRELLIS_(FF|COMB)|MULT18X18|DP16KD|Max frequency' \
	    $(BUILD)/$(ENTITY).pnr.log || true

clean:
	rm -rf $(BUILD) dist-newstyle

## ---------------------------------------------------------------------------
## Alchitry Cu GUI build (bringup/BRINGUP.md section 6): the theremin core
## with the musical NoteMap, wrapped with a UART for the lab GUI.
NOTEMAP_DIR := $(BUILD)/notemap/Theremin.ThereminTop.topEntity

## The 1024-entry note table as $readmemb files, from defaultNoteMapParams.
notemap-files:
	cabal exec -- runghc -isrc -e 'Theremin.Audio.NoteMap.writeNoteTableFiles Theremin.Audio.NoteMap.defaultNoteMapParams "bringup/notemap_lo.bin" "bringup/notemap_hi.bin" Prelude.>> Theremin.Audio.NoteMap.writeAmpTableFiles Theremin.Audio.NoteMap.defaultAmpMapParams "bringup/ampmap_lo.bin" "bringup/ampmap_hi.bin"' 2>/dev/null || \
	  printf 'import Theremin.Audio.NoteMap\nwriteNoteTableFiles defaultNoteMapParams "bringup/notemap_lo.bin" "bringup/notemap_hi.bin"\nwriteAmpTableFiles defaultAmpMapParams "bringup/ampmap_lo.bin" "bringup/ampmap_hi.bin"\n' | cabal repl theremin-clash --repl-options=-v0

## Clash reads the .bin files via -ibringup and copies them beside the netlist.
$(NOTEMAP_DIR)/theremin_top.v: src/Theremin/ThereminTop.hs src/Theremin/Audio/NoteMap.hs bringup/notemap_lo.bin bringup/ampmap_lo.bin
	rm -rf $(BUILD)/notemap
	cabal exec -- $(CLASH) -isrc -ibringup Theremin.ThereminTop --verilog \
	    -outputdir $(BUILD)/notemap -fclash-hdldir $(BUILD)/notemap

cu-gui: $(NOTEMAP_DIR)/theremin_top.v bringup/cu_gui_top.v bringup/theremin-gui.pcf
	cd $(NOTEMAP_DIR) && yosys -q -p 'read_verilog theremin_top.v ../../../bringup/cu_gui_top.v; synth_ice40 -top cu_gui_top -json ../../arrival/gui.json'
	nextpnr-ice40 --hx8k --package cb132 --freq 50 --json $(BUILD)/arrival/gui.json \
	    --pcf bringup/theremin-gui.pcf --pcf-allow-unconstrained --asc $(BUILD)/arrival/gui.asc \
	    2>&1 | tee $(BUILD)/arrival/gui.pnr.log | grep -E 'ICESTORM_(LC|RAM):|Max frequency.*clk50'
	icepack $(BUILD)/arrival/gui.asc bringup/bin/theremin-gui.bin
