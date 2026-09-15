"""wspr_model -- WSPR type-1 message encoder, the golden model for PM.Wspr.

Callsign + 4-char Maidenhead locator + power (dBm) -> 162 symbols in 0..3.
This is the job the Forth side does on the H2 (UHF/DESIGN.md, "Encode
path"); the gateware sequencer in Oracle/pm-wspr only replays the table.

Contract:
    pack_callsign(call: str) -> int             28-bit integer N
    pack_locator_power(grid: str, dbm: int) -> int   22-bit integer M
    message_bits(call, grid, dbm) -> [int]      50 bits, MSB first
    convolve(bits: [int]) -> [int]              162 bits, K=32 r=1/2,
                                                polys 0xF2D05351 / 0xE4613C47
    interleave(bits: [int]) -> [int]            162 bits, 8-bit bit-reversal
    wspr_symbols(call, grid, dbm) -> [int]      162 symbols, sync + 2*data

Hint:
    Packing is a base-mixed fold (foldl over characters); the encoder is an
    unfoldr over a shift register; the interleave is a scatter driven by
    bitreverse8 over 0..255 keeping targets < 162.  No imports.

Known-good vector: none is embedded -- the author does not trust a
from-memory 162-symbol table, so the doctests check structure (length,
alphabet, sync-bit parity against the published sync vector, tail-bit
determinism, packing arithmetic against the WSJT-X formulae) rather than a
recorded transmission.  Cross-check against `wsprsim`/`wsprd` from WSJT-X
before first on-air use (UHF/DESIGN.md test plan step 1).

>>> pack_callsign("K1ABC")
259047992
>>> pack_locator_power("FN42", 37)
2896997
>>> len(message_bits("K1ABC", "FN42", 37))
50
>>> len(SYNC)
162
>>> syms = wspr_symbols("K1ABC", "FN42", 37)
>>> len(syms)
162
>>> all(0 <= s <= 3 for s in syms)
True
>>> [s & 1 for s in syms] == SYNC
True
>>> [s >> 1 for s in syms] == interleave(convolve(message_bits("K1ABC", "FN42", 37)))
True
>>> len(convolve([0] * 50)), len(interleave(list(range(162))))
(162, 162)
>>> convolve([0] * 50) == [0] * 162
True
>>> sorted(interleave(list(range(162)))) == list(range(162))
True
>>> bitreverse8(1), bitreverse8(0x80), bitreverse8(0xA5)
(128, 1, 165)
>>> parity(0), parity(0xF2D05351), parity(0b1011)
(0, 1, 1)
>>> pack_callsign("K1ABC") == pack_callsign(" K1ABC")
True
>>> wspr_symbols("K1ABC", "FN42", 37) != wspr_symbols("K1ABC", "FN42", 30)
True
>>> pack_callsign("AB1CDE") % 27, pack_callsign("AB1CD") % 27   # E=4, pad space=26
(4, 26)
"""

# -- prelude --
NOTHING   = object()                                  # Maybe's Nothing: "no arg given"; test with `is`

def foldl(f, xs, base=NOTHING):  # THE left fold; Python buried its own in functools as reduce
    it = iter(xs)
    if base is NOTHING:
        try:
            acc = next(it)
        except StopIteration:
            raise TypeError("fold of empty sequence with no initial value")
    else:
        acc = base
    for x in it:
        acc = f(acc, x)
    return acc

def unfoldr(f, seed):                       # Data.List unfoldr: f(seed) -> None | (value, seed')
    out = []                                # iterate's finite twin: grows a list until f says stop --
    step = f(seed)                          # no more threading (state, acc) tuples through until
    while step is not None:
        val, seed = step
        out.append(val)
        step = f(seed)
    return out

# -- the standard 162-bit WSPR sync vector (WSJT-X wsprsim / genwspr) --
SYNC = [1,1,0,0,0,0,0,0,1,0,0,0,1,1,1,0,0,0,1,0,0,1,0,1,1,1,1,0,0,0,0,0,
        0,0,1,0,0,1,0,1,0,0,0,0,0,0,1,0,1,1,0,0,1,1,0,1,0,0,0,1,1,0,1,0,
        0,0,0,1,1,0,1,0,1,0,1,0,1,0,0,1,0,0,1,0,1,1,0,0,0,1,1,0,1,0,1,0,
        0,0,1,0,0,0,0,0,1,0,0,1,0,0,1,1,1,0,1,1,0,0,1,1,0,1,0,0,0,1,1,1,
        0,0,0,0,0,1,0,1,0,0,1,1,0,0,0,0,0,0,0,1,1,0,1,0,1,1,0,0,0,1,1,0,
        0,0]

POLY_A = 0xF2D05351
POLY_B = 0xE4613C47

def char_val(c):                            # WSPR alphabet: '0'..'9' -> 0..9, 'A'..'Z' -> 10..35, ' ' -> 36
    if c == ' ':
        return 36
    if '0' <= c <= '9':
        return ord(c) - ord('0')
    return ord(c) - ord('A') + 10

def pack_callsign(call):                    # 28-bit N; pad so the third char is the digit, right-pad to 6
    call = call.upper().strip()
    if not call[2:3].isdigit():
        call = ' ' + call
    call = call.ljust(6)
    c = [char_val(ch) for ch in call]
    n = c[0]
    n = n * 36 + c[1]
    n = n * 10 + c[2]
    return foldl(lambda acc, x: acc * 27 + (x - 10), c[3:], n)   # letters/space: A=0..Z=25, ' '=26

def pack_locator_power(grid, dbm):          # 22-bit M: locator (15 bits) then power+64 (7 bits)
    g = grid.upper()
    m = (179 - 10 * (ord(g[0]) - ord('A')) - (ord(g[2]) - ord('0'))) * 180 \
        + 10 * (ord(g[1]) - ord('A')) + (ord(g[3]) - ord('0'))
    return m * 128 + dbm + 64

def to_bits(n, width):                      # MSB first
    return [(n >> (width - 1 - i)) & 1 for i in range(width)]

def message_bits(call, grid, dbm):          # 50 bits: N (28) ++ M (22)
    return to_bits(pack_callsign(call), 28) + to_bits(pack_locator_power(grid, dbm), 22)

def parity(x):                              # popcount mod 2
    return bin(x).count('1') & 1

def convolve(bits):                         # K=32 r=1/2: 50 data + 31 zero tail = 81 in, 162 out
    src = bits + [0] * 31
    def step(seed):
        reg, i = seed
        if i == len(src):
            return None
        reg = ((reg << 1) | src[i]) & 0xFFFFFFFF
        return ([parity(reg & POLY_A), parity(reg & POLY_B)], (reg, i + 1))
    return [b for pair in unfoldr(step, (0, 0)) for b in pair]

def bitreverse8(i):
    return int(format(i, '08b')[::-1], 2)

def interleave(bits):                       # scatter: source order, target = bitreverse8(i) for i in 0..255, target < 162
    out = [None] * 162
    targets = [j for j in (bitreverse8(i) for i in range(256)) if j < 162]
    for src, dst in zip(bits, targets):
        out[dst] = src
    return out

def wspr_symbols(call, grid, dbm):          # 162 symbols 0..3: bit 0 = sync, bit 1 = data
    data = interleave(convolve(message_bits(call, grid, dbm)))
    return [s + 2 * d for s, d in zip(SYNC, data)]


if __name__ == u'__main__':
    import doctest
    r = doctest.testmod()
    print(f"wspr_model: {r.attempted - r.failed}/{r.attempted} doctests passing")
