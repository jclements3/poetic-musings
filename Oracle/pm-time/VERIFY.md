# pm-time — verification (LIBRARY.md porting rule, Lesson 09's three checks)

Toolchain: `export PATH=$HOME/.ghcup/bin:$HOME/.cabal/bin:$HOME/tools/oss-cad-suite/bin:$PATH`
(GHC 9.6.7, Clash 1.8.5, GHDL from oss-cad-suite). Run everything from `Oracle/pm-time`.

## 1. Hedgehog vs reference model (`time-prop`)

    cabal test time-prop --test-show-details=direct

`test/Prop.hs`: 300 random cases each. PM.StrobeLatch vs a pure list model of
the 2-FF sync / edge / 16-deep FIFO / seq / sticky-overflow semantics of
`strobe_latch.vhd`; PM.PpsDiscipline (RTC_HZ 200, LOCK_TOL 3) vs a pure
Integer model written from `pps_discipline.vhd` in VHDL assignment order
(quirks Q1-Q4 from the module header included). Random PPS intervals cover
good, slightly bad, wild and watchdog-length periods; `cover` guards make
sure lock and watchdog-length gaps are exercised.

## 2. Cycle-exact scenarios (`time-test`, `dpll-test`)

    cabal test --test-show-details=direct

`test/Spec.hs`: the SYS-006 cases of MAIDEN's `timebase_tb.vhd` (scaled RTC).
`test/DpllSpec.hs`: PpsDiscipline + Dpll composed at clk_sys 500 kHz /
out 100 kHz with a +30 ppm crystal: convergence to -30 000 ppb +/-100 ppb
(0.1 ppm), lock, holdover freeze, relock, tick-spacing step <= 1 system
clock, 1 PPS out on ticks, measurement layer unchanged. The property lists in
both file headers are the pass criteria; the suites print the numbers.

## 3. GHDL elaboration of the generated VHDL

    OUT=/tmp/pm-time-vhdl
    for m in PM.StrobeLatch PM.PpsDiscipline PM.Dpll; do       # one module per run:
      cabal run clash -- -isrc $m --vhdl -outputdir $OUT         # clash only compiles the
    done                                                         # first topEntity it is given
    for top in strobe_latch pps_discipline dpll_10mhz; do
      d=$(dirname $(find $OUT -name $top.vhdl))   # <outputdir>/PM.<Module>.topEntity/
      ( cd $d && ghdl -a --std=08 ${top}_types.vhdl && ghdl -a --std=08 $top.vhdl \
             && ghdl -e --std=08 -Wl,$HOME/tools/glibc-isoc23-shim.o $top )
    done

The `-Wl,...shim.o` is the Ubuntu 22.04 glibc 2.35 workaround from
`Theremin/fpga/ROADMAP.md` (oss-cad-suite's GHDL runtime wants glibc >= 2.38);
drop it on a newer distro. Generated HDL is not committed.

Run `cabal run clash`, not the bare binary from `cabal list-bin` (it cannot
load the modules without cabal's environment). Each run loads clash-prelude
(~6 min on a loaded box); run them sequentially, the box has 7 GB.

## Status (2026-09-15, GHC 9.6.7 / Clash 1.8.5 / oss-cad-suite GHDL)

- time-prop: 2 properties x 300 cases PASS (coverage: locked 48 %, watchdog gap 22 %).
- time-test: 21/21 PASS (unchanged).
- dpll-test: 9/9 PASS. Numbers: trim -29997 ppb at 30 s (target -30000 +/-100),
  phase error 27 ns/s at 30 s; 1 000 000 ticks over 10 PPS seconds (0.0 ppm);
  tick spacing 5/6 system clocks, max step 1; holdover trim -29998 frozen 52..60 s;
  relocked with trim -29998 at 80 s. DPLL locks ~16 s after PpsDiscipline lock.
  The suite simulates 40M cycles (~10 min, ~0.9 GB residency).
- GHDL: `ghdl -a --std=08` + `ghdl -e` OK for strobe_latch, pps_discipline and
  dpll_10mhz (with the glibc shim). No generated HDL is committed.
