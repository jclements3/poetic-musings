# Sleigh Glide — FPGA build (Alchitry Cu, iCE40 HX8K-CB132)

Rev B firmware, synthesized 2026-08-31. `./build.sh` produces
`build/sleigh_glide.bin` (135 KB). Bitstreams and the Clash `verilog/` dir are
gitignored — only sources, constraints, and this doc are committed.

## Toolchain (no sudo)

Open-source suite installed per-user via apio:

```
pip install --user apio          # apio 0.9.5
apio install oss-cad-suite       # -> ~/.apio/packages/tools-oss-cad-suite/bin
```

Gives Yosys 0.33+103, nextpnr-0.6-118, icestorm (icepack/icepll/icetime),
iverilog, openFPGALoader. `build.sh` finds it there automatically (override
with `FPGA_TOOLS=/path/to/bin`).

Flow: `yosys synth_ice40` → `nextpnr-ice40 --hx8k --package cb132 --freq 50`
→ `icepack`. Top module is `cu_top.v`, a thin board wrapper around the
Clash-generated `sleigh_glide` core.

## Clocking — the one thing to know

The Cu's oscillator is 100 MHz, but this design's 32-bit dwell
counters/comparators top out near 60 MHz on the HX8K fabric (best seen:
72 MHz across seed sweeps and abc9 experiments — 100 MHz is not reachable
without pipelining the counters). So the HANDOFF's documented fallback is in
effect:

- `cu_top.v` has an `SB_PLL40_CORE` dividing 100 MHz → **50 MHz** logic clock
  (`icepll -i 100 -o 50`: DIVR=0, DIVF=7, DIVQ=4, FILTER_RANGE=5).
- `SleighGlide.hs` `msTicks` is **50000** (1 ms @ 50 MHz), so all real-time
  behavior (dwell table, 2.5 s house rest, 10 ms debounce) is unchanged.
- Side effect: the 8-bit PWM carrier is now ~195 kHz instead of ~390 kHz —
  still far above audio and fine for the IRLZ44N gates.

While here, one timing fix went into the Clash source: `dwellMs coil *
msTicks` at a runtime `coil` inferred a genuine 32-bit multiplier (the
critical path). It is now `dwellTicks coil`, a 4-way mux of compile-time
constants — identical behavior, folded by Clash (verify: 20000000 / 12500000
/ 7500000 / 5000000 tick constants appear in the generated Verilog).

## Timing and utilization (nextpnr, default seed)

| Metric | Value |
|---|---|
| Fmax (clk50) | **59.84 MHz — PASS at 50 MHz** (~20 % margin) |
| Logic cells | 328 / 7680 (4 %) |
| Block RAM | 0 / 32 |
| SB_IO | 11 / 256 |
| Globals / PLL | 4 / 8 SB_GB, 1 / 2 PLL |

## Pin assignments (sleigh_glide.pcf)

Ball names verified against Alchitry's own board definition
(`CuPin.kt` in [alchitry/Alchitry-Labs-V2](https://github.com/alchitry/Alchitry-Labs-V2),
fetched 2026-08-31) — **no placeholders**. "Br pin" is the bank-A pin name
silk-screened on the Br prototyping element.

| Signal | Ball | Br pin | Notes |
|---|---|---|---|
| clk | P7 | — | 100 MHz on-board oscillator |
| rst_n | P8 | — | Cu reset button, LOW while pressed (wrapper inverts + syncs) |
| show_on | C1 | A14 | Internal pullup: floats HIGH = show runs. SPST switch pin→GND pauses when closed; use an SPDT to 3.3 V/GND for direct sense |
| gates[0] | M1 | A2 | → Q0 / coil station C0 (nearest house A, per SS-003) |
| gates[1] | L1 | A3 | → Q1 |
| gates[2] | J1 | A5 | → Q2 |
| gates[3] | J3 | A6 | → Q3 |
| gates[4] | G1 | A8 | → Q4 |
| gates[5] | G3 | A9 | → Q5 |
| gates[6] | E1 | A11 | → Q6 |
| gates[7] | D1 | A12 | → Q7 / station C7 (house B) |

All 3.3 V LVCMOS. Each gate goes through 100 Ω series into the IRLZ44N gate
with a 10 kΩ pulldown (SS-003) — the pulldown also keeps the MOSFETs off
during FPGA configuration, when the pins float.

## Flashing

The Cu is **not** supported by `iceprog` or `openFPGALoader` (even upstream
only lists the Au) — use Alchitry's loader:

- **Alchitry Labs V2** (alchitry.com/alchitry-labs, or the GitHub releases of
  `alchitry/Alchitry-Labs-V2`): unpack anywhere, no sudo; use its loader to
  write `build/sleigh_glide.bin` to the Cu's SPI flash (choose *flash*, not
  RAM-only, so the show survives power cycles).
- CLI alternative: `alchitry/alchitry-loader` (small C++ tool, plain `make`).

Practical note for this machine (WSL2): USB doesn't reach WSL without
usbipd-win, so the easy path is to build here and flash from Windows with
Alchitry Labs pointed at the `.bin`. On native Linux, FTDI access needs the
usual udev rule or group membership (one-time admin step).

## Regenerating the Verilog

From `Oracle/clash-h2` (GHC/Cabal in `~/.ghcup/bin`, `~/.cabal/bin`):

```
cabal exec -- clash --verilog \
  -fclash-hdldir <repo>/Coil/SleighGlide/firmware/verilog \
  <repo>/Coil/SleighGlide/firmware/SleighGlide.hs
```

## Post-retiming simulation check (2026-08-31)

The 100→50 MHz retiming (`msTicks` 50000, `dwellTicks` lookup) was verified in
clashi at the FSM level: ParkA holds while `rest>0`; GlideFwd advances the coil
exactly at `t = dwellTicks i`; coil 7 → ParkB reloads `rest = 125,000,000`
(= 2.5 s at 50 MHz, confirming the tick base); `showOn=False` freezes `t`/`coil`
and sets `paused`. Ready for first power-up per HANDOFF §7 step 3.

## Rev C — theremin speed control (SS-005)

The sleigh's speed is now driven by the One Box theremin: pitch maps to
speed 1..255, volume off (or cable out, or sender dead — 250 ms watchdog)
parks the sleigh at Hold duty. `PM.SleighSpeed` on the ULX3S sends (0xA5, speed)
frames at 250 kbaud, 50/s; this firmware receives on `sleigh_rx`.

Wiring: one wire from the ULX3S `sleigh_tx` GPIO to Br bank A pin A15
(ball B1 — VERIFY against CuPin.kt before first power), plus common ground
between the boards. The pin has a pullup: unplugged = idle line = watchdog
parks the sleigh. Show switch behavior is unchanged and still overrides.

Speed scaling is a virtual-tick pacer (rate speed/256): the SS-004 dwell
table is untouched, speed 255 is Rev B timing (-0.4 %), no multipliers were
added, and the Rev C bitstream closes timing at 59.1 MHz (PASS at 50).
Sim proof: `SleighSim.hs` (see header for the runghc invocation) — UART
decode at divisor 200, watchdog decay, exact pacer rates, FSM hold/step
semantics. The PM side is proven by pm-lib's `sleighspeed-test`.
