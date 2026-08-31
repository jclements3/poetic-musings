# forth-cpu upstream notes (for the Clash H2 port)

Upstream: https://github.com/howerj/forth-cpu, shallow-cloned to
`Oracle/forth-cpu-upstream/` (git-ignored, not a submodule).

## How the eForth image was built

No gforth or sudo needed — everything is plain C:

```sh
cd Oracle/forth-cpu-upstream
make h2 embed h2.hex          # gcc builds h2 (SoC simulator) and embed (metacompiler VM)
                              # h2.hex: ./embed embed.blk h2.hex embed.fth
python3 ../clash-h2/tools/hex2bin.py h2.hex ../clash-h2/h2.bin
```

`embed` is a tiny 16-bit VM that runs the prebuilt `embed.blk` eForth image,
which metacompiles `embed.fth` into the H2 image `h2.hex` (3334 words, one
4-hex-digit word per line — the file the docs also call `embed.hex`).
`hex2bin.py` pads it to 8192 words of 16-bit binary text for `blockRamFile`.

Verified boot in the upstream simulator (`./h2 -H -r h2.hex`; `-H` enables
simulator-friendly hacks, needs `text.hex`+`nvram.blk` via `make run` deps):

```
eFORTH vDEAD
 1A0C 25F4
loading... ok
 ok
2 3 + . cr 5
 ok
```

## Memory map (h2.c / h2.vhd)

* Program RAM: 8192 x 16-bit words (`MAX_CORE`), start address 0 (`START_ADDR`).
* Software uses **byte addresses**; the core drops the low bit for RAM:
  `daddr <= tos(13 downto 1)` (write: `tos_c`, read: `tos_n`). Calls push
  `pc << 1` on the return stack; return does `npc = rstk >> 1`.
* Address decode is on `T` bit 14: loads/stores with `T(15..14) = "00"` hit
  RAM; `T & 0x4000` (0x4000-0x7FFF) hits I/O (`io_din`/`io_re`/`io_wr`,
  full 16-bit `io_daddr = tos_c`).
* External SRAM/flash is windowed through oMemDout/oMemControl/oMemAddrLow,
  not memory-mapped directly.

## I/O register map (h2.h)

Reads (io_re):
| addr   | name      | contents |
|--------|-----------|----------|
| 0x4000 | iUart     | bit8 rx-fifo-empty, bit9 rx-fifo-full, bit11 tx-fifo-empty, bit12 tx-fifo-full; low 8 bits last rx byte |
| 0x4002 | iVT100    | same layout for PS/2 kbd char (bit8 = new char in HW) |
| 0x4004 | iTimerDin | 13-bit timer counter |
| 0x4006 | iSwitches | dpad buttons + slide switches |
| 0x4008 | iMemDin   | SRAM/flash read data |

Writes (io_wr):
| addr   | name         | function |
|--------|--------------|----------|
| 0x4000 | oUart        | bit13 UART_TX_WE strobes tx of low 8 bits; bit10 UART_RX_RE pops rx fifo into getchar register |
| 0x4002 | oVT100       | same strobes for VGA/VT100 terminal (write char) / kbd pop |
| 0x4004 | oTimerCtrl   | bit15 enable, bit14 reset, bit13 irq enable, bits12..0 compare value |
| 0x4006 | oLeds        | 8 LEDs |
| 0x4008 | oMemDout     | SRAM write data |
| 0x400A | oMemControl  | bit12 flash wait, bit11 SRAM cs, bit10 flash cs, bit9 we, bit8 oe, bits8..0(0x1ff) addr high |
| 0x400C | oMemAddrLow  | SRAM/flash addr low 16 |
| 0x400E | o7SegLED     | 4 hex digits |
| 0x4010 | oIrcMask     | interrupt controller mask (1 bit per source) |
| 0x4012 | oUartTxBaud  | tx baud clock divisor |
| 0x4014 | oUartRxBaud  | rx baud clock divisor |
| 0x4016 | oUartControl | UART control (stop bits etc.) |

## Interrupt vectors (interrupt_address_length = 3 -> word addresses 0-7)

0 isrEntry (reset), 1 isrRxFifoNotEmpty, 2 isrRxFifoFull,
3 isrTxFifoNotEmpty, 4 isrTxFifoFull, 5 isrKbdNew, 6 isrTimer,
7 isrDPadButton. On IRQ a `CALL vector` is injected; the return address is
the current PC, so the pre-empted instruction re-executes on `rti`.

## What the Clash port must honor

* 1-cycle block-RAM read latency: `daddr` is driven from the *next* TOS/PC
  so data lines up — already matched in `src/H2.hs`.
* The byte/word addressing split above (RAM word-addressed via T>>1, I/O
  addressed with the full 16-bit T).
* eForth polls iUart status bits before oUart strobes; a Clash UART must
  implement the FIFO-status bit layout exactly, and reads must be
  side-effect free (the pop happens via the UART_RX_RE *write* strobe).
* The image assumes start address 0 and words 0-7 free for vectors; the
  interrupt controller (`oIrcMask`) gates sources before `irq`/`irq_addr`.
* h2.bin here is the full padded 8192-word image; unused words are 0
  (opcode 0 = `jump 0`, harmless — never reached).
