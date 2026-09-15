# MAIDEN station timebase — simulation-only sprint (maiden37/38).
#
#   make sim     run timebase_tb (SYS-006-tagged, self-checking)
#   make wave    sim with .ghw waveform + GTKWave (long sim: big file)
#   make clean
#
# Synthesis targets arrive with the station top-level (maiden39+);
# never flash from this machine (dev/sim box — see theremin CLAUDE.md).

TB ?= timebase_tb

RTL    = rtl/pps_discipline.vhd rtl/irigb_gen.vhd rtl/strobe_latch.vhd
TB_SRC = tb/timebase_tb.vhd

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; this host (Ubuntu 22.04)
# has 2.35, so elaboration needs the __isoc23_* forwarding shim.
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

wave: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	-./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure
	gtkwave build/$(TB).ghw &

build:
	mkdir -p build

clean:
	rm -rf build
