"""Golden model for the MAIDEN Doppler DSP chain (lesson 17 / maiden34-35).

Bit-true integer mirror of the RTL: every operation here (wrap widths,
truncating shifts, Q15 twiddles, magnitude approximation, CFAR compare)
matches firmware/doppler/rtl/ exactly, so testbenches compare exact
(the cards' +/-2 LSB tolerance is satisfied with 0 LSB by construction).
A float reference is kept alongside for sanity, not for the TBs.

Fixed seed everywhere: regenerating vectors twice is byte-identical
(SW-005 -- CI regenerates stimulus deterministically).

Usage:
  .venv/bin/python firmware/doppler/golden/model.py --vectors build/vectors
  .venv/bin/python firmware/doppler/golden/model.py --alias-plot results/design-notes/alias-fold.png
"""

from __future__ import annotations

import argparse
import math
import os

import numpy as np

SEED = 20260821

# ---- chain constants (mirror the RTL generics) ----
F_ADC = 48_000  # I/Q sample rate, S/s
N_CIC = 3
R_DEF = 4  # default decimation per the maiden33 audit (24.125 GHz)
NFFT = 512
W_IN = 16
F0_HZ = 24.125e9
C = 299_792_458.0
LAM = C / F0_HZ
HZ_PER_MS = 2.0 / LAM  # ~160.95 Hz per m/s
TRAIN = 8  # per side
GUARD = 2  # per side
N_T = 2 * TRAIN  # total training cells
ALPHA_Q8_1E3 = 2212  # alpha = N_t*(Pfa^(-1/N_t)-1), Pfa=1e-3 -> 8.642
ALPHA_Q8_1E4 = 3187  # Pfa=1e-4 -> 12.451
DC_SKIP = (0, 1, NFFT - 1)  # clutter bins excluded from detection
VCM_PER_BIN_Q8 = 3728  # (F_ADC/R_DEF/NFFT)*(lam/2)*100 cm/s * 256


def _wrap(x: int, bits: int) -> int:
    """Two's-complement wrap to `bits`."""
    m = 1 << bits
    x &= m - 1
    return x - m if x >= (1 << (bits - 1)) else x


def cic_bit_true(iq: list[tuple[int, int]], r: int = R_DEF) -> list[tuple[int, int]]:
    """N=3 integrator-comb, decimate by r, truncate gain back to 16 bits.

    Internal width = W_IN + N*ceil(log2(r)); output = internal >> N*log2(r).
    """
    g = N_CIC * math.ceil(math.log2(r))
    w = W_IN + g
    acc = [[0, 0] for _ in range(N_CIC)]
    prev = [[0, 0] for _ in range(N_CIC)]
    out = []
    for n, (i, q) in enumerate(iq):
        s = [i, q]
        for st in range(N_CIC):
            acc[st][0] = _wrap(acc[st][0] + s[0], w)
            acc[st][1] = _wrap(acc[st][1] + s[1], w)
            s = acc[st][:]
        if (n + 1) % r == 0:
            for st in range(N_CIC):
                d0 = _wrap(s[0] - prev[st][0], w)
                d1 = _wrap(s[1] - prev[st][1], w)
                prev[st] = s[:]
                s = [d0, d1]
            out.append((s[0] >> g, s[1] >> g))
    return out


def _twiddle(k: int) -> tuple[int, int]:
    """Q15 twiddle W_512^k = cos - j sin, rounded, matching the RTL ROM."""
    ang = 2.0 * math.pi * k / NFFT
    return (int(round(32767 * math.cos(ang))), int(round(-32767 * math.sin(ang))))


TW = [_twiddle(k) for k in range(NFFT // 2)]


def _brev(x: int, bits: int = 9) -> int:
    r = 0
    for _ in range(bits):
        r = (r << 1) | (x & 1)
        x >>= 1
    return r


def fft_bit_true(samples: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """In-place radix-2 DIT, bit-reversed load, >>1 block scale per pass.

    Butterfly (all truncating arithmetic shifts, matching the RTL):
      t  = (b * W) >> 15      a' = (a + t) >> 1      b' = (a - t) >> 1
    """
    re = [0] * NFFT
    im = [0] * NFFT
    for n in range(NFFT):
        re[_brev(n)], im[_brev(n)] = samples[n]
    half = 1
    while half < NFFT:
        step = NFFT // (2 * half)
        for grp in range(0, NFFT, 2 * half):
            for j in range(half):
                wr, wi = TW[j * step]
                a, b = grp + j, grp + j + half
                tr = (re[b] * wr - im[b] * wi) >> 15
                ti = (re[b] * wi + im[b] * wr) >> 15
                re[a], re[b] = (re[a] + tr) >> 1, (re[a] - tr) >> 1
                im[a], im[b] = (im[a] + ti) >> 1, (im[a] - ti) >> 1
        half *= 2
    return list(zip(re, im))


def mag_approx(i: int, q: int) -> int:
    """max + min/2 magnitude approximation -- no square roots on iCE40."""
    a, b = abs(i), abs(q)
    return max(a, b) + (min(a, b) >> 1)


def cfar_bit_true(mags: list[int], alpha_q8: int = ALPHA_Q8_1E3):
    """CA-CFAR, circular training window, integer compare:
        mag[k] * N_t * 256  >  sum(train) * alpha_q8
    Returns (peak_bin, peak_mag, noise_est, valid); DC_SKIP bins never
    detect. noise_est = training sum >> log2(N_t) at the peak.
    """
    best = (-1, 0, 0)
    for k in range(NFFT):
        if k in DC_SKIP:
            continue
        s = 0
        for d in range(GUARD + 1, GUARD + TRAIN + 1):
            s += mags[(k - d) % NFFT] + mags[(k + d) % NFFT]
        if mags[k] * N_T * 256 > s * alpha_q8 and mags[k] > best[1]:
            best = (k, mags[k], s >> int(math.log2(N_T)))
    return (best[0], best[1], best[2], best[0] >= 0)


def vr_cm(peak_bin: int) -> int:
    """Signed velocity in cm/s from the detected bin (RTL arithmetic)."""
    k = peak_bin - NFFT if peak_bin >= NFFT // 2 else peak_bin
    return (k * VCM_PER_BIN_Q8) >> 8


# ---- stimulus synthesis ----


def synth_iq(n, f_hz, fs=F_ADC, amp=12000, noise=0.0, rng=None, phase0=0.0):
    t = np.arange(n) / fs
    ph = 2 * np.pi * f_hz * t + phase0
    i = amp * np.cos(ph)
    q = amp * np.sin(ph)
    if noise > 0:
        i = i + rng.normal(0, noise, n)
        q = q + rng.normal(0, noise, n)
    return [(int(a), int(b)) for a, b in zip(np.round(i), np.round(q))]


def synth_iq_ramp(dur_s, v0, v1, fs=F_ADC, amp=12000, noise=300.0, rng=None):
    n = int(dur_s * fs)
    v = np.linspace(v0, v1, n)
    f = v * HZ_PER_MS
    ph = np.cumsum(2 * np.pi * f / fs)
    i = amp * np.cos(ph) + rng.normal(0, noise, n)
    q = amp * np.sin(ph) + rng.normal(0, noise, n)
    return [(int(a), int(b)) for a, b in zip(np.round(i), np.round(q))], v


def _wpairs(path, pairs):
    with open(path, "w") as f:
        for a, b in pairs:
            f.write(f"{a} {b}\n")


def _wints(path, xs):
    with open(path, "w") as f:
        for x in xs:
            f.write(f"{x}\n")


def gen_vectors(outdir: str) -> None:
    os.makedirs(outdir, exist_ok=True)
    rng = np.random.default_rng(SEED)

    # 1 -- CIC: 1 kHz tone + noise, 4096 samples, R=4
    stim = synth_iq(4096, 1000.0, noise=200.0, rng=rng)
    _wpairs(f"{outdir}/cic_stim.txt", stim)
    _wpairs(f"{outdir}/cic_exp.txt", cic_bit_true(stim, R_DEF))

    # 2 -- FFT frame A: impulse (flat magnitude, exact)
    imp = [(16384, 0)] + [(0, 0)] * (NFFT - 1)
    _wpairs(f"{outdir}/fft_impulse_in.txt", imp)
    _wints(
        f"{outdir}/fft_impulse_mag.txt",
        [mag_approx(i, q) for i, q in fft_bit_true(imp)],
    )
    # FFT frame B: tone centred on bin +37
    tone = synth_iq(NFFT, 37 * F_ADC / R_DEF / NFFT, fs=F_ADC / R_DEF, amp=12000)
    _wpairs(f"{outdir}/fft_tone_in.txt", tone)
    _wints(
        f"{outdir}/fft_tone_mag.txt",
        [mag_approx(i, q) for i, q in fft_bit_true(tone)],
    )

    # 3 -- CFAR: 8 spectra of exponential noise, peak injected in half of them
    lines = []
    for trial in range(8):
        mags = [int(x) for x in rng.exponential(600.0, NFFT)]
        inj_bin = int(rng.integers(4, NFFT - 4))
        if trial % 2 == 0:
            mags[inj_bin] = 30000 + int(rng.integers(0, 5000))
        pb, pm, ne, valid = cfar_bit_true(mags)
        _wints(f"{outdir}/cfar_spec_{trial}.txt", mags)
        lines.append(f"{pb} {pm} {ne} {int(valid)}")
    with open(f"{outdir}/cfar_exp.txt", "w") as f:
        f.write("\n".join(lines) + "\n")

    # 4 -- integration: 1.0 s ramp 12 -> 18 m/s. 6 m/s^2 keeps the chirp
    # smear inside ~2 bins over the 43 ms window (20 m/s^2 smears ~6 bins
    # and CA-CFAR self-masks -- found the hard way; VT-04's car passes are
    # steady-speed for the same reason). Commanded v per 20 ms epoch,
    # evaluated at the FFT window centre (epoch end - 21 ms).
    ramp, v = synth_iq_ramp(1.00, 12.0, 18.0, rng=rng)
    _wpairs(f"{outdir}/top_stim.txt", ramp)
    epochs = []
    for e in range(int(1.00 / 0.020)):
        t_c = max((e + 1) * 0.020 - 0.021, 0.0)
        idx = min(int(t_c * F_ADC), len(v) - 1)
        epochs.append(int(round(v[idx] * 100)))  # commanded v, cm/s
    _wints(f"{outdir}/top_cmd_cm.txt", epochs)
    print(f"vectors written to {outdir}")


def alias_plot(path: str) -> None:
    """Lesson 17 Explore 1: R=8 with 24 GHz constants folds a 30 m/s target."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rng = np.random.default_rng(SEED)
    vs = np.linspace(2, 36, 60)
    rep = {4: [], 8: []}
    for r in (4, 8):
        fs_d = F_ADC / r
        per_bin_cm = (fs_d / NFFT) * (LAM / 2) * 100
        for v in vs:
            stim = synth_iq(NFFT * r, v * HZ_PER_MS, noise=200.0, rng=rng)
            dec = cic_bit_true(stim, r)[-NFFT:]
            mags = [mag_approx(i, q) for i, q in fft_bit_true(dec)]
            pb, _, _, valid = cfar_bit_true(mags)
            if valid:
                k = pb - NFFT if pb >= NFFT // 2 else pb
                rep[r].append(k * per_bin_cm / 100)
            else:
                rep[r].append(np.nan)
    fig, ax = plt.subplots(figsize=(7, 4.2))
    ax.plot(vs, vs, "k:", lw=1, label="truth")
    ax.plot(vs, rep[4], "o-", ms=3, label="R = 4 (±37.3 m/s unambiguous)")
    ax.plot(vs, rep[8], "s-", ms=3, label="R = 8 (±18.6 m/s — folds)")
    ax.axvline(18.64, color="r", ls="--", lw=1)
    ax.set_xlabel("commanded radial velocity (m/s)")
    ax.set_ylabel("reported velocity (m/s)")
    ax.set_title("24.125 GHz: D6's ↓8 aliases pattern speeds (maiden33 exhibit)")
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fig.savefig(path, dpi=120)
    print(f"alias fold plot -> {path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--vectors")
    ap.add_argument("--alias-plot")
    a = ap.parse_args()
    if a.vectors:
        gen_vectors(a.vectors)
    if a.alias_plot:
        alias_plot(a.alias_plot)
    if not (a.vectors or a.alias_plot):
        ap.error("nothing to do")
