# clash-h2 — the H2 Forth CPU in Clash

A [Clash](https://clash-lang.org) port of the **H2** CPU from
[howerj/forth-cpu](https://github.com/howerj/forth-cpu): a 16-bit,
single-cycle J1 derivative built to run eForth.

`src/H2.hs` is a direct translation of `h2.vhd`; it keeps the same
instruction encoding, port list, stack/RAM timing, hold line and interrupt
behaviour, so the existing `embed.hex` images and the C simulator/debugger
in the original project remain valid references.

> **Status:** compiles with GHC 9.6 / Clash 1.8 and **boots the real eForth
> image in Haskell simulation**: `cabal run h2-boot` loads `h2.bin`, runs the
> system with a functional UART register model (`src/H2/SystemUart.hs`),
> feeds `2 3 + . cr` to the console and checks the banner and the printed
> `5` in the captured transcript. The RTL has not yet been synthesised or
> run on hardware.

## Layout

| File                 | Corresponds to | Notes |
| -------------------- | -------------- | ----- |
| `src/H2.hs`          | `h2.vhd`       | The core. `h2` is the reusable component, `step` the combinational logic, `topEntity` a stand-alone synthesis target. |
| `src/H2/System.hs`   | `top.vhd` + `ram.vhd` (tiny subset) | Core + 8K×16 program RAM from `h2.bin` + LEDs/switches at `0x4004`. |
| `src/H2/SystemUart.hs` | `top.vhd` + `uart.vhd` (simulation-only register model) | Core + RAM + the iUart/oUart register contract; rx fed from a Haskell byte list, tx collected per cycle. No baud clock, no serdes, no FIFO depth — see the module haddock. |
| `test/Spec.hs`       | `tb.vhd` (smoke test only) | Runs a 5-word program that writes `0xA5` to `oLeds`. |
| `test/BootSpec.hs`   | — | Boots the real eForth image (`h2.bin`) in Haskell simulation, types `2 3 + . cr` at the console and checks the transcript (`cabal run h2-boot`, from this directory). |
| `tools/hex2bin.py`   | —              | Converts `embed.hex` into the format `blockRamFile` loads. |

## How the VHDL maps to Clash

| VHDL                                   | Clash |
| -------------------------------------- | ----- |
| generic `stack_size_log2`              | type parameter `n` (`h2 @dom @6 @3 …`) |
| generic `interrupt_address_length`     | type parameter `i` |
| generics `cpu_id`, `start_address`, `use_interrupts` | `H2Config` record |
| generic `asynchronous_reset`           | decided by the Clash domain's `ResetKind` |
| `*_c` / `*_n` register pairs           | one `register (resetState cfg) st'` holding `H2State` |
| `vstk_ram` / `rstk_ram` (async read, sync write) | `asyncRamPow2` — infers distributed RAM as before |
| `decode`, `alu_select`, `alu_unit`, `stack_update`, `pc_update` processes | the `where` block of `step` |
| `pc <= pc_n`, `daddr <= tos_n`         | `pcOut = pc'`, `daddr = … tos'` — still the *next* addresses, so a 1-cycle-latency block RAM lines up |

Things intentionally kept identical:

* Literal is ALU op `0b10101`; conditional branch forces op `N`.
* Shifts use only the low 4 bits of `T`.
* A load (`[T]`) from `0x4000` and above reads `io_din` and pulses `io_re`;
  below it reads `din`.
* Stores go out on `dwe`/`io_wr` split by `T(15..14) = "00"`.
* On interrupt, a `CALL irq_addr` is injected and the return address is the
  *current* PC (the pre-empted instruction re-executes on return).
* The core comes out of reset with `stop` asserted for one cycle.

## Building

Requires GHC 9.x and Clash 1.8 (the usual `clash-starter` setup):

```sh
cabal build
cabal run h2-test              # smoke test in Haskell simulation
cabal run clash -- H2 --vhdl   # generate vhdl/H2.topEntity/h2.vhdl
cabal run clash -- H2 --verilog
```

To synthesise the small system with a real eForth image:

```sh
# in the forth-cpu repo:  make embed.hex
python3 tools/hex2bin.py path/to/embed.hex h2.bin
cabal run clash -- H2.System --vhdl
```

Interactive poking:

```sh
cabal run clashi
> import H2
> sampleN @System 8 (h2 @System @6 @3 defaultConfig (pure (H2In False 0 False 0 0x80A5 0)))
```

## What's not ported (yet)

Only the CPU, the trivial LED/switch registers and the *simulation-only*
UART register model are here (the latter has no baud clock, serdes or
finite FIFOs, so it is not synthesisable I/O). The original
SoC also has a real UART with FIFOs, the VGA/VT100 text terminal, PS/2 keyboard,
timer, 7-segment driver, external SRAM/flash controller and the interrupt
controller (`core.vhd`, `uart.vhd`, `vga.vhd`, `kbd.vhd`, `timer.vhd`,
`util.vhd`). The `H2In`/`H2Out` interface is the same as `h2.vhd`, so those
can be added around the core one at a time, or the Clash core can be dropped
into the existing VHDL `top.vhd` via the generated `h2.vhdl` (port names
match the original entity).

`H2.System` uses two `blockRamFile` instances sharing one write port to get
an initialisable dual-port RAM; use `trueDualPortBlockRam` if you need to
halve the BRAM usage.

## License

MIT, matching the original `h2.vhd` (© Richard James Howe). This port is
derived from it.
