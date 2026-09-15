# firmware/doppler — GHDL + Yosys flow (theremin phase1 pattern).
#
#   make vectors      regenerate golden stimulus/expected (fixed seed)
#   make sim          run a testbench (default TB=cic_dec_tb) — FIRST, always
#   make sim TB=fft512_serial_tb | cfar_tb | doppler_core_tb
#   make sim-all      run every testbench in sequence
#   make wave         sim + GTKWave
#   make synth        VHDL -> netlist + yosys stat (resource budget read)
#   make time         place/route + icetime static timing (hx8k)
#   make clean
#
# Simulation only on this machine — never flash unsimulated, never flash
# from the WSL2 box at all (see theremin CLAUDE.md two-machine rule).

TB    ?= cic_dec_tb
TOP    = doppler_top
VENVPY = ../../.venv/bin/python

RTL    = rtl/cic_dec.vhd rtl/fft512_serial.vhd rtl/cfar.vhd \
         rtl/uart_tx.vhd rtl/doppler_core.vhd rtl/doppler_top.vhd
TB_SRC = tb/cic_dec_tb.vhd tb/fft512_serial_tb.vhd tb/cfar_tb.vhd \
         tb/doppler_core_tb.vhd

DEVICE  = hx8k
PACKAGE = ct256
PCF     = constraints/hx8k.pcf

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; this host has 2.35, so
# elaboration needs the __isoc23_* forwarding shim (see fpga/ROADMAP.md).
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: vectors sim sim-all wave synth time clean

vectors: | build
	$(VENVPY) golden/model.py --vectors build/vectors

sim: vectors
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

sim-all:
	$(MAKE) sim TB=cic_dec_tb
	$(MAKE) sim TB=fft512_serial_tb
	$(MAKE) sim TB=cfar_tb
	$(MAKE) sim TB=doppler_core_tb

wave:
	-$(MAKE) sim TB=$(TB)
	gtkwave build/$(TB).ghw &

synth: build/$(TOP).json

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@; stat'

build/$(TOP).asc: build/$(TOP).json
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

time: build/$(TOP).asc
	icetime -d $(DEVICE) -t $<

build:
	mkdir -p build

clean:
	rm -rf build
