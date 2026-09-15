"""ks_model -- golden model of PM.Ks (Karplus-Strong string), bit-exact with ksStep.

Contract:  ks(delay, frac, gain, vel, n) -> the first n Signed-16 samples of one
           string plucked at tick 0 with velocity vel (0..255), integer loop
           period `delay` (3..2047), fractional period frac/256 and loop gain
           gain/256.  Loop = ring buffer -> 2-point averager -> first-order
           allpass (0.5 + frac/256 samples) -> gain -> + LFSR noise burst of
           `delay` samples.  Every rounding is round-half-up on the 8-bit
           products, every sum saturates to 16 bits, exactly as the gateware.
Hint:      UNFOLD -- the string is a state machine; take(n, iterate(step, s0)).
           The delay line is a tuple inside the state so step stays pure.

>>> apcoef(0), apcoef(128), apcoef(255)
(85, 0, -51)
>>> lfsr(0xACE1) == 0x59C3
True
>>> ks(8, 0, 0, 255, 3)                       # gain 0: the noise burst alone
[-21196, 22889, -19501]
>>> ks(8, 0, 255, 200, 7) == ks(8, 0, 0, 200, 7)   # loop empty for delay-1 steps
True
>>> ks(8, 0, 255, 200, 8)[7] != ks(8, 0, 0, 200, 8)[7]   # then feedback arrives
True
>>> len(ks(100, 64, 250, 200, 64))
64
>>> ks(40, 0, 255, 0, 40) == [0] * 40         # velocity 0 is silent
True
"""

# -- prelude --
map_      = lambda f, xs: [f(x) for x in xs]

def iterate(f, x):                          # iterate f x = [x, f x, f (f x), ..]
    while True:
        yield x
        x = f(x)

def islice(iterable, stop):                 # take
    it = iter(iterable)
    for _ in range(stop):
        try:
            yield next(it)
        except StopIteration:
            return

take      = lambda n, xs: list(islice(iter(xs), n))           # works on infinite streams

# solution goes here
sat16   = lambda x: max(-32768, min(32767, x))                 # saturate to Signed 16
rnd8    = lambda x: (x + 128) >> 8                             # round-half-up /256 (floor shift)
signed16 = lambda v: v - 65536 if v >= 32768 else v            # Unsigned 16 bits as Signed 16
apcoef  = lambda frac: round(256.0 * (1.0 - d) / (1.0 + d)) if (d := 0.5 + frac / 256.0) else 0
lfsr    = lambda v: ((v << 1) & 0xFFFF) | (((v >> 15) ^ (v >> 13) ^ (v >> 12) ^ (v >> 10)) & 1)

def ks_step(delay, frac, gain, state):
    """One sample: state = (wp, prev, apx, apy, lfsr, burst, vel, line, out, pluck)."""
    wp, prev, apx, apy, lf, burst, vel, line, _, pluck = state
    lr = delay - 1
    if pluck is not None:
        burst, vel = delay, pluck
    rd = line[(wp + 1) % (lr + 1)]                 # written lr steps ago
    avg = (rd + prev + 1) >> 1
    ap = sat16(apx + rnd8(apcoef(frac) * (avg - apy)))
    fb = rnd8(ap * gain)
    noise = rnd8(signed16(lf) * vel) if burst > 0 else 0
    out = sat16(fb + noise)
    line2 = line[:wp] + (out,) + line[wp + 1:]
    return ((wp + 1) % (lr + 1), rd, avg, ap, lfsr(lf), burst - 1 if burst > 0 else 0, vel,
            line2, out, None)

def ks(delay, frac, gain, vel, n):
    """First n samples of a string plucked at tick 0 (see the module doctests)."""
    s0 = (0, 0, 0, 0, 0xACE1, 0, 0, (0,) * delay, 0, vel)
    step = lambda s: ks_step(delay, frac, gain, s)
    return map_(lambda s: s[8], take(n + 1, iterate(step, s0))[1:])


if __name__ == '__main__':
    import sys
    if len(sys.argv) == 6:                       # ks_model.py delay frac gain vel n -> samples
        print(' '.join(map(str, ks(*map(int, sys.argv[1:])))))
    else:
        import doctest
        print(doctest.testmod())
