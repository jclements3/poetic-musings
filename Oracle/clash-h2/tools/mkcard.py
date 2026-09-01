#!/usr/bin/env python3
"""Build a PM card image: raw 1024-byte Forth blocks, no filesystem
(LAYOUT.html storage model; Oracle/eforth-pm.md sections 1 and 3).

Block 0 — identity/boot descriptor ("the card is the person"):

    offset 0-1   magic "PM"
    offset 2     owner-name length n
    offset 3..   owner name (ASCII), n bytes
    offset 16    default voice  (VL-1 voice 0-9)
    offset 17    default tempo
    offset 32..  block-range directory (reserved, zero for now)

Block 1 — boot source: eForth block format, 16 lines x 64 characters,
space-padded (embed.fth: c/l = $40, l/b = $10).  `1 load` evaluates each
line in turn; the demo source defines and runs a word so the transcript
proves the card content flowed SPI -> block buffer -> interpreter.

Usage: mkcard.py OUTFILE [--name NAME]
"""
import sys

BLOCK = 1024
C_PER_L = 64
L_PER_B = 16


def block0(name: str, voice: int = 0, tempo: int = 120) -> bytes:
    if not (1 <= len(name) <= 12):
        raise SystemExit("owner name must be 1..12 ASCII chars")
    b = bytearray(BLOCK)
    b[0:2] = b"PM"
    b[2] = len(name)
    b[3:3 + len(name)] = name.encode("ascii")
    b[16] = voice
    b[17] = tempo
    return bytes(b)


def block1(lines) -> bytes:
    if len(lines) > L_PER_B:
        raise SystemExit("boot source: at most 16 lines per block")
    out = bytearray()
    for i in range(L_PER_B):
        line = lines[i] if i < len(lines) else ""
        if len(line) > C_PER_L:
            raise SystemExit(f"boot source line {i} longer than 64 chars")
        out += line.ljust(C_PER_L).encode("ascii")
    assert len(out) == BLOCK
    return bytes(out)


BOOT_SOURCE = [
    ': hello ." PM card ok" cr ;',
    'hello',
]


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    out = args[0]
    name = "JC"
    if len(args) >= 3 and args[1] == "--name":
        name = args[2]
    image = block0(name) + block1(BOOT_SOURCE)
    with open(out, "wb") as f:
        f.write(image)
    print(f"wrote {out}: {len(image)} bytes "
          f"(block 0 identity '{name}', block 1 boot source)")


if __name__ == "__main__":
    main()
