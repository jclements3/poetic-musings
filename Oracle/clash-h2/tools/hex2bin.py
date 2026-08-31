#!/usr/bin/env python3
"""Convert forth-cpu's embed.hex (one 4-digit hex word per line) into the
one-binary-word-per-line format expected by Clash's blockRamFile.

    python3 tools/hex2bin.py embed.hex h2.bin
"""
import sys

DEPTH = 8192

def main(src, dst):
    words = []
    with open(src) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16) & 0xFFFF)
    if len(words) > DEPTH:
        sys.exit(f"{src}: {len(words)} words exceeds RAM depth {DEPTH}")
    words += [0] * (DEPTH - len(words))
    with open(dst, "w") as f:
        for w in words:
            f.write(format(w, "016b") + "\n")
    print(f"wrote {dst}: {len(words)} words")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
