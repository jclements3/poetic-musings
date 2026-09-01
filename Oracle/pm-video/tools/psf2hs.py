#!/usr/bin/env python3
"""Extract an 8x16 glyph table from a PSF1 console font into a Clash Vec.

Used once to generate src/PM/Video/Font.hs from the classic VGA 8x16
console font shipped by Debian/Ubuntu console-setup:

    zcat /usr/share/consolefonts/Uni2-VGA16.psf.gz > vga16.psf
    python3 tools/psf2hs.py vga16.psf > src/PM/Video/Font.hs   # then edit header

The glyphs are the classic IBM PC VGA ROM 8x16 bitmap font (CP437 layout in
the PSF; the ASCII range 0x20-0x7E maps identically).  Bitmap glyph shapes
are not subject to copyright in the US (typeface designs / bitmap fonts are
not copyrightable subject matter, 37 CFR 202.1(e)); the table below is
therefore treated as public domain.  Only glyphs 0x20-0x7E are populated;
0x00-0x1F and 0x7F render blank.

PSF1 format: 4-byte header (36 04 mode charsize), then nglyphs*charsize
bytes of bitmaps, then (mode&2) a unicode table: per glyph a list of u16le
codepoints, 0xFFFE starting combining sequences, 0xFFFF terminating the
glyph's list.
"""
import struct
import sys


def parse_psf1(data):
    assert data[:2] == b"\x36\x04", "not a PSF1 font"
    mode, charsize = data[2], data[3]
    nglyphs = 512 if mode & 1 else 256
    glyphs = [data[4 + i * charsize: 4 + (i + 1) * charsize]
              for i in range(nglyphs)]
    cp2glyph = {}
    if mode & 2:
        table = data[4 + nglyphs * charsize:]
        gi = i = 0
        while i + 1 < len(table) and gi < nglyphs:
            v = struct.unpack("<H", table[i:i + 2])[0]
            i += 2
            if v == 0xFFFF:
                gi += 1
            elif v == 0xFFFE:
                while i + 1 < len(table):
                    v2 = struct.unpack("<H", table[i:i + 2])[0]
                    i += 2
                    if v2 == 0xFFFF:
                        gi += 1
                        break
            else:
                cp2glyph.setdefault(v, gi)
    else:
        cp2glyph = {i: i for i in range(nglyphs)}
    return glyphs, cp2glyph, charsize


def main():
    data = open(sys.argv[1], "rb").read()
    glyphs, cp2glyph, charsize = parse_psf1(data)
    assert charsize == 16, "want an 8x16 font"
    rows = []
    for code in range(128):
        if 0x20 <= code <= 0x7E:
            g = glyphs[cp2glyph[code]]
        else:
            g = bytes(16)
        rows.append((code, g))
    print("fontList :: [BitVector 8]")
    print("fontList =")
    first = True
    for code, g in rows:
        label = chr(code) if 0x20 <= code <= 0x7E else "blank"
        hexes = ",".join("0x%02x" % b for b in g)
        lead = "  [" if first else "  ,"
        print("%s %s -- 0x%02x %s" % (lead, hexes, code, label))
        first = False
    print("  ]")


if __name__ == "__main__":
    main()
