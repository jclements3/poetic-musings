# Oracle — Phase 3 design (O · the brains of the root)

PLAN.md Phase 3: H2 Forth CPU on the ULX3S, eForth `ok` over USB serial, then on
the bar TFT with the laptop unplugged; SD block system; GPIO/ADC/timer/IRQ words;
the Clash port of H2 replacing the black-box VHDL as Lessons 12–14. Prereq none.
Personal ledger, $60 (TFT + HDMI board). **Gate:** all four stages of the ladder in
`eforth-pm.md` §5. **Demo:** a self-contained Forth computer — type on it, compute,
load a game from SD. *(2026-08-31: the whole ladder is pre-proven in simulation.)*

**Root framing (`../PROGRAM.md`):** Oracle is not a spoke. With Panel it *is* the root:
Panel is the body, Oracle is the nervous system — the CPU, the 0x40xx register bus,
storage and the console through which every library block is configured, driven and
read back at conversational speed. A block is "done" when Forth can drive it live;
Oracle is the on-silicon testbench. It owns **no demo of its own** beyond the ok
prompt on glass: the CW keyer that used to be listed under O is U's component
(`../UHF/DESIGN.md`), housed here in `pm-keyer` only because this is where the
register bus lives.

## What Oracle owns (the runtime)

| Piece | Where | Status |
|---|---|---|
| H2 stack CPU (howerj forth-cpu derivative), 16 K×16 program BRAM, stacks, IRQ, timer | `clash-h2/` (Clash; black-box VHDL in `forth-cpu-upstream/`) | ✓ boots the real eForth image in Clash sim |
| UART + FIFO | `clash-h2/src/H2/SystemUart.hs` | ✓ |
| Register bus 0x4020–0x40FF, `PM.RegFile` (FIFO-popping reads, command pulses, reset-muted audio, TX interlock AND) | `pm-lib` | ✓ 8 semantics asserted |
| SD block device over `PM.Spi`; block 0 owner greet, `1 load` | `pm-spi`, `clash-h2` sim card model | ✓ sim |
| 1920×480 text console, VT100 subset | `pm-video` | ✓ pixel-exact, ~200 LUT4 / 5 BRAM |
| CDC library (2-flop, pulse, Gray async FIFO) | `pm-lib` `PM.Cdc` | ✓ |
| eForth-PM capability layer: register map, kernel + per-letter vocabularies, boot flow, gateware-vs-Forth rule | `eforth-pm.md` | spec; first registers proven live from Forth |

## What Oracle hosts but does not own

The `pm-*` cabal packages are the **library's home** until a top-level `lib/` exists:
`PM.Matrix`/`PM.Zones` (Panel), `PM.Synth`/`PM.Audio` (Panel synth mode),
`PM.Keyer` (U), `PM.HarpLink` (E), `PM.SleighSpeed` (C), `PM.Gps` (G), `PM.Net` (N).
Each is listed under its spoke in `../CLASH-LIBRARY-MAP.md`; `../LIBRARY.md` is the
catalogue. Rule: a spoke's block may live here, but its gate and its design live in
the spoke's DESIGN.md. In the map's § Module list, O itself contributes the ✓ H2
stack CPU, UART with FIFO, SPI master, register file, CDC set (2-flop, pulse, Gray
async FIFO) and the 1920×480 text console; the ○ TMDS/HDMI encoder and SDRAM
controller land on this bus when their consumers arrive. Since 2026-09-15 the whole
program, including the `MAIDEN/` source archive and `Theremin/`, is one unified repo;
`forth-cpu-upstream/` is the only thing still fetched from outside
(`forth-cpu-notes.md`).

## The contract every spoke signs (eforth-pm.md)

- **Registers:** 16-bit, even addresses, one group per letter, addresses never move
  once published (0x4020 panel … 0x4036 harp, 0x4040 GPS/TOD, 0x4060 Imaging
  provisional, M and S groups TBD at their phase start).
- **Vocabulary:** one Forth vocabulary per mode, loaded from an SD block range;
  `cal` and `mode-go` are deferred words every vocabulary plugs.
- **Gateware vs Forth:** every-sample or every-scan-tick work is Clash; anything a
  human notices the latency of is Forth (§4). The snooker demo is the clearest case:
  centroids and CFAR in fabric, ball association and the table drawing in Forth/laptop.
- **Mode dispatch:** S3 zone + 1 s dwell + teardown word before `mode-go` — a bumped
  slider never yanks a demo (`../Panel/DESIGN.md`).

## Verification (the gate) — `eforth-pm.md` §5

3.1 `ok` over USB → 3.2 prompt on glass → 3.3 SD block 1 loads, zones read → 3.4
keyer round-trip with the interlock refusing arm outside C mode. Each stage is
demoable alone; Phase 3 closes on all four on the bench, USB unplugged.

## Out of scope

Any signal chain (those are spokes); games beyond "load one from SD" (content, not
gateware); Ethernet, video overlay, SDRAM controller (arrive with N, T/S views, and
Imaging respectively, on this bus).
