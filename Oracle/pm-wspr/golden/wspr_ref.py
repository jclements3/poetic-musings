"""wspr_ref -- an INDEPENDENT second WSPR type-1 encoder, written from the
published algorithm (WSJT-X wsprcode/genwspr: packcall, packgrid, encode232,
inter_mept, sync merge) without reading wspr_model.py's code.  Only the
public names of wspr_model were used, so the doctest at the bottom can call
both encoders and compare them field by field.

No WSJT-X binary (wsprsim/wsprcode/wsprd) was available on this machine, so
this file is the cross-check that UHF/DESIGN.md's test plan step 1 asks for.
It is NOT a recorded on-air vector: two independent readings of the same
spec agreeing raises confidence, it does not replace a wsprd decode.

Algorithm (K1JT, WSPR 2.0 / WSJT-X):
  callsign  : upper-case, if the 3rd char is not a digit prepend a space
              (so the digit is always char 3), right-pad with spaces to 6.
              c1 in 0..36 (0-9, A-Z, space), c2 in 0..35, c3 digit 0..9,
              c4..c6 letter or space -> 0..26.
              N = ((((c1*36 + c2)*10 + c3)*27 + c4)*27 + c5)*27 + c6
  locator   : "AB12":  M1 = (179 - 10*(A-'A') - int('1'))*180
                            + 10*(B-'A') + int('2')
  power     : M = M1*128 + dbm + 64
  message   : N (28 bits) ++ M (22 bits), MSB first, ++ 31 zero tail = 81 bits
  encoder   : reg <<= 1 | bit; out parity(reg & 0xF2D05351),
              parity(reg & 0xE4613C47) per input bit -> 162 bits
  interleave: p = 0; for i in 0..255: j = bitrev8(i); if j < 162:
              out[j] = in[p]; p += 1
  symbols   : sync[i] + 2*data[i]

Run:  python3 wspr_ref.py         (doctest; prints a summary)
      python3 wspr_ref.py CALL GRID DBM   (prints the 162 symbols)
"""

import sys

ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ "

# The published 162-bit pseudo-random sync vector (WSJT-X pr3).
SYNC_REF = [
    1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
    0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1,
    0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1,
    1, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1,
    0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0,
    0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1,
    0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0,
    0, 0,
]

POLY1 = 0xF2D05351
POLY2 = 0xE4613C47


def normalise_call(call):
    """Six-char field with the digit in position 3.

    >>> normalise_call("K1ABC")
    ' K1ABC'
    >>> normalise_call("AB1CDE")
    'AB1CDE'
    >>> normalise_call("W1A")
    ' W1A  '
    >>> normalise_call("k1abc")
    ' K1ABC'
    """
    c = call.upper().strip()
    if len(c) < 3 or not c[2].isdigit():
        c = " " + c
    c = c.ljust(6)
    if len(c) != 6 or not c[2].isdigit():
        raise ValueError("bad callsign %r" % call)
    return c


def ref_pack_callsign(call):
    """
    >>> ref_pack_callsign("K1ABC")
    259047992
    """
    c = normalise_call(call)
    n = ALPHABET.index(c[0])           # 0..36
    n = n * 36 + ALPHABET.index(c[1])  # 0..35 (no space allowed here)
    n = n * 10 + int(c[2])
    for ch in c[3:]:
        v = ALPHABET.index(ch)         # letter 10..35 or space 36
        if v < 10:
            raise ValueError("digit in suffix of %r" % call)
        n = n * 27 + (v - 10)
    return n


def ref_pack_locator_power(grid, dbm):
    """
    >>> ref_pack_locator_power("FN42", 37)
    2896997
    """
    g = grid.upper()
    m1 = (179 - 10 * (ord(g[0]) - 65) - int(g[2])) * 180 \
        + 10 * (ord(g[1]) - 65) + int(g[3])
    return m1 * 128 + dbm + 64


def ref_message_bits(call, grid, dbm):
    n = ref_pack_callsign(call)
    m = ref_pack_locator_power(grid, dbm)
    bits = [(n >> (27 - i)) & 1 for i in range(28)]
    bits += [(m >> (21 - i)) & 1 for i in range(22)]
    return bits


def ref_convolve(bits):
    """81 input bits (50 data + 31 zero tail) -> 162 output bits."""
    data = list(bits) + [0] * (81 - len(bits))
    reg = 0
    out = []
    for b in data:
        reg = ((reg << 1) | b) & 0xFFFFFFFF
        out.append(bin(reg & POLY1).count("1") & 1)
        out.append(bin(reg & POLY2).count("1") & 1)
    return out


def ref_interleave(bits):
    out = [None] * 162
    p = 0
    for i in range(256):
        j = int("{:08b}".format(i)[::-1], 2)
        if j < 162:
            out[j] = bits[p]
            p += 1
    return out


def ref_symbols(call, grid, dbm):
    data = ref_interleave(ref_convolve(ref_message_bits(call, grid, dbm)))
    return [SYNC_REF[i] + 2 * data[i] for i in range(162)]


# ---------------------------------------------------------------------------
# Cross-check against wspr_model (the golden model) on many messages.

CASES = [
    ("K1ABC", "FN42", 37), ("W1AW", "FN31", 30), ("AB1CDE", "EM12", 23),
    ("K1A", "CN87", 10), ("W1A", "JO01", 0), ("N0A", "RR99", 60),
    ("K1JT", "FN20", 37), ("G4ABC", "IO91", 20), ("VK3XYZ", "QF22", 27),
    ("JA1ABC", "PM95", 33), ("W6XYZ", "DM04", 0), ("K9AN", "EN50", 60),
    ("N2ABC", "FN30", 7), ("WA1ABC", "FN42", 13), ("KA9Q", "EM48", 17),
    ("ZL1ABC", "RF73", 43), ("VE3AB", "FN03", 47), ("DL1AB", "JN58", 50),
    ("A1BC", "AA00", 53), ("KH6A", "BL11", 57), ("W9A", "EN52", 3),
    ("N1A", "FN42", 37), ("WB2ABC", "FN20", 40), ("EA1ABC", "IN53", 37),
]


def cross_check():
    """Compare every stage of both encoders; return a list of mismatches.

    >>> cross_check()
    []
    >>> len(CASES) >= 20
    True
    >>> import wspr_model
    >>> wspr_model.SYNC == SYNC_REF
    True
    """
    import wspr_model as m
    bad = []
    for call, grid, dbm in CASES:
        pairs = [
            ("pack_callsign", m.pack_callsign(call), ref_pack_callsign(call)),
            ("pack_locator_power", m.pack_locator_power(grid, dbm),
             ref_pack_locator_power(grid, dbm)),
            ("message_bits", m.message_bits(call, grid, dbm),
             ref_message_bits(call, grid, dbm)),
        ]
        bits = ref_message_bits(call, grid, dbm)
        pairs.append(("convolve", m.convolve(bits), ref_convolve(bits)))
        pairs.append(("interleave", m.interleave(ref_convolve(bits)),
                      ref_interleave(ref_convolve(bits))))
        pairs.append(("wspr_symbols", m.wspr_symbols(call, grid, dbm),
                      ref_symbols(call, grid, dbm)))
        for name, a, b in pairs:
            if a != b:
                bad.append((call, grid, dbm, name, a, b))
    return bad


if __name__ == "__main__":
    if len(sys.argv) == 4:
        print(" ".join(str(s) for s in ref_symbols(sys.argv[1], sys.argv[2], int(sys.argv[3]))))
    else:
        import doctest
        r = doctest.testmod()
        print("wspr_ref: %d/%d doctests passing" % (r.attempted - r.failed, r.attempted))
