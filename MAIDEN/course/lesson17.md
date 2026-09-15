# Lesson 17 — FPGA Doppler DSP [bench]

*Where we are.* Lesson 16 left an analog chain that turns a moving target
into two audio-band tones, I and Q, verified by eye on a scope. Now the
theremin course pays off in full: you are going to build, in VHDL, the
signal-processing chain the theremin roadmap only previewed — decimate,
transform, threshold, report. Per D6, the chain is: 16-bit 48 kS/s I/Q →
CIC decimator → 512-point FFT every 20 ms (50 Hz) → CA-CFAR peak →
v_r = f_d·λ/2 with sign from I/Q → out to the recorder, raw I/Q passing
through untouched. One warning up front: D6 contains a mistake in this
section, and part of your job today is to catch it.

## Objectives

- Audit D6's decimation choice against the Doppler bandwidth of each
  candidate band, find the aliasing problem, and fix it through D5 change
  control.
- Design a CIC decimator with the bit-growth analysis written down.
- Understand a serial radix-2 512-point FFT well enough to budget it on
  iCE40 hx8k — and know when to take the ECP5 escape hatch.
- Derive CA-CFAR from first principles: what α buys you in P_fa.
- Build `firmware/doppler/` with self-checking, GS-002-tagged testbenches
  driven by a NumPy golden model; then take it to the bench for VT-04.

## Concepts

### First, the audit (design friction — do not skip)

Work this out on paper before reading past the spoiler line.

The decimated *complex* sample rate sets the unambiguous Doppler span: with
I/Q at f_s, the FFT covers −f_s/2 … +f_s/2. D6 says CIC ↓8, so
48 kS/s / 8 = 6 kS/s → **±3 kHz** unambiguous.

Now the bands, from lesson 16: 24.125 GHz gives ≈ 161 Hz per m/s, 10.525 GHz
gives ≈ 70 Hz per m/s.

*Spoiler line — do the division first.*

- At 24 GHz: ±3 kHz ⇒ **±18.6 m/s** unambiguous. A pattern ship crosses at
  ~30 m/s radial ⇒ 4.8 kHz ⇒ **aliases**, folding onto a wrong, possibly
  wrong-signed velocity. D6's ↓8 is broken for its own baseline module.
- At 10.5 GHz: 30 m/s ⇒ 2.1 kHz < 3 kHz. Fits, with margin for gusts.

The fix is one number: **↓4 for 24 GHz** (12 kS/s, ±37 m/s unambiguous,
bin width 23.4 Hz ⇒ 0.145 m/s — still far finer than SYS-003 needs), or
keep ↓8 *iff* VT-05 (lesson 16) settles on the HB100. Make the decimation a
generic, decide the default when VT-05 reports, and commit the D6 revision —
"CIC ↓8" → "CIC ↓R, R = 4 (24 GHz) / 8 (10.5 GHz), see ambiguity analysis" —
citing this analysis, per D5 change control. This is what the SEMP's
document discipline is *for*: the error was harmless in prose and would have
been a field-day mystery in hardware.

### CIC, with the growth written down

A CIC decimator is N integrators at the fast rate, a rate-drop by R, then N
combs (differentiators) at the slow rate — no multipliers, the reason it
lives at the front of every DDC. Internal word growth is exactly
`N·log2(R·M)` bits (M = differential delay, 1 here). For N = 3, R = 8:
9 bits over the 16-bit input → 25-bit internal registers; R = 4 → 22 bits.
Write the chosen numbers in the entity header comment — that's the
"fixed-point formats written down" habit from the theremin roadmap, now a
review item.

CIC passband droop is real but negligible here: our signal lives well below
the decimated Nyquist and CFAR doesn't care about a fraction of a dB tilt.
Note it, cite it, move on — no compensation FIR needed at 512-point Doppler
resolution.

### The FFT, honestly budgeted

512-point complex FFT, radix-2, fully serial: one butterfly, 9 passes ×
256 butterflies = 2304 butterfly operations per transform. At 50 Hz update
that is ~115k butterflies/s — trivially slow; even a 12 MHz clock gives you
>100 cycles per butterfly. The pressure is not speed, it is **memory and
multipliers**:

- Data RAM: 512 complex × (2×16 bit) = 16 kbit, ping-ponged for
  continuous input = 32 kbit; twiddle ROM (quarter-wave folded, your
  lesson 07 trick) ≈ 4 kbit. hx8k has 32 × 4 kbit EBR = 128 kbit: fits.
- Multipliers: iCE40 has none. Each butterfly needs 4 real multiplies —
  serialized shift-add at ~20 cycles each still fits the cycle budget, but
  the LUT cost of a pipelined 16×16 is the thing that squeezes hx8k once
  doppler_top, UART, and lesson 18's timebase share the die.

The sanctioned escape hatch, straight from the theremin roadmap: **ECP5
(ULX3S)** — real DSP multipliers, more BRAM, same open toolchain
(`--std=08` GHDL + yosys + nextpnr-ecp5). Decision rule: build for hx8k
first; if `make time` or the stat line says no after doppler_top
integrates, move — the VHDL doesn't change.

One more timing subtlety: 512 samples at 6 kS/s span 85 ms, but the update
period is 20 ms — so consecutive FFTs overlap ~75 % (at ↓4: 43 ms window,
~53 % overlap). That means a circular input buffer with a sliding start
pointer, not a fill-then-dump ping-pong. Overlap is a feature: it smooths
CFAR detections between updates.

### CA-CFAR from first principles

A fixed threshold fails because the noise floor moves — gain, temperature,
clutter. Cell-averaging CFAR estimates the local floor from the target
cell's neighbors: take T training bins either side (skip G guard bins
adjacent to the cell under test), average their magnitudes, multiply by α,
declare detection if the cell exceeds it. For exponentially-distributed
noise power the false-alarm rate is `P_fa = (1 + α/N_t)^(−N_t)` with N_t
total training cells — derive it (it's three lines from the exponential
CDF) and tabulate α for P_fa = 10⁻³ and 10⁻⁴ at N_t = 16. The velocity
report is then the *largest* detected bin's center frequency:
`v_r = f_bin·λ/2`, sign directly from whether the bin sits in the positive
or negative half of the complex spectrum — that is what lesson 16's Q
channel bought you. No detection ⇒ report SNR below threshold and hold
v_r invalid; the recorder logs it and lesson 13's EKF simply skips the
update. Magnitude: use |I|+|Q|/2-style approximation or α-max-plus-β-min —
a square root on iCE40 is a self-inflicted wound.

## Doc Trace

- **Implements:** D6 §FPGA DSP (the whole design element) toward GS-002.
- **Verified by:** VT-04 (bench + car park; the 50 Hz / ≤ 0.3 m/s numbers
  live in D7, not here).
- **Revises:** D6 §FPGA DSP decimation factor (the audit above) — commit
  with the ambiguity analysis, per D5 change control. Check whether D2's
  GS-002 wording survives unchanged (it does — 50 Hz and v_r are
  decimation-independent; say so in the commit message).
- **Risk:** D5 risk R2 — resolution and unambiguous span are the DSP half
  of the range problem.

## Build

All under `firmware/doppler/`, theremin house style: numeric_std only,
synchronous active-high resets, one entity per file, registered outputs,
requirement-tagged asserts. Makefile is the theremin phase1 pattern with
`sim`, `wave`, `synth`, `time` targets.

### 1 · Golden model first (`firmware/doppler/golden/model.py`)

NumPy reference: synthesize I/Q for a target at commanded v_r plus noise at
commanded SNR, run float CIC → FFT → CFAR, and emit (a) stimulus samples as
signed 16-bit text files, (b) expected v_r/SNR/bin per 20 ms epoch. Every
testbench below reads these files — the theremin Phase-5 golden-model
habit. Keep the model in `software/tests/` import reach so CI (lesson 15)
regenerates stimulus deterministically (fixed seed).

### 2 · `cic_dec.vhd`

```
entity cic_dec is
  generic (N : positive := 3; R : positive := 4; W_IN : positive := 16);
  port (clk, rst : in std_logic;
        in_i, in_q   : in  signed(W_IN-1 downto 0);
        in_stb       : in  std_logic;
        out_i, out_q : out signed(W_IN-1 downto 0);
        out_stb      : out std_logic);
end entity;
```

Internal width `W_IN + N*integer(ceil(log2(real(R))))`; truncate back to
16 bits at the output (state the truncation in the header). TB: golden
sine in, compare against model output within ±2 LSB, asserts tagged
`GS-002`.

### 3 · `fft512_serial.vhd` (skeleton provided, you fill the passes)

Port contract — pinned, lesson 19's recorder and this lesson's top both
assume it:

```
entity fft512_serial is
  port (clk, rst : in std_logic;
        sample_i, sample_q : in signed(15 downto 0);
        sample_stb : in std_logic;                    -- decimated rate
        start      : in std_logic;                    -- 50 Hz epoch tick
        mag        : out unsigned(17 downto 0);       -- |X(k)| approx
        mag_bin    : out unsigned(8 downto 0);        -- streamed 0..511
        mag_stb    : out std_logic;
        done       : out std_logic);
end entity;
```

Circular input BRAM (sliding window), ping-pong work BRAM, serialized
shift-add butterfly, quarter-wave twiddle ROM. Bit-reverse on readout.
TB: impulse → flat magnitude; single tone → energy in the right bin,
golden-model comparison within a stated tolerance.

### 4 · `cfar.vhd`

Streaming CA-CFAR over the 512 magnitudes: generics `TRAIN`, `GUARD`,
`ALPHA_Q8` (α in Q8 fixed point); outputs peak bin, peak mag, noise
estimate → SNR. TB drives golden spectra with known injected P_fa targets.

### 5 · `doppler_top.vhd`

Wires ADC interface (SPI master for the lesson-16 chain's ADC — MCP3202-
class for first light, matched to what you bought) → cic_dec → fft512 →
cfar → v_r scaling (`v_r = bin_freq·λ/2`, λ a generic) → UART out
(reuse the theremin `uart_tx` verbatim) at 50 Hz: v_r float32-as-fixed,
SNR, bin. Raw I/Q pass-through to a second interface for the recorder's
Ch 3. 2-FF synchronize anything async. Integration TB: golden I/Q file in,
UART decoded out, v_r tracks commanded velocity ramp — asserts tagged
`GS-002`.

## Verify

1. **Sim, always first.** `make sim` in each block dir then the top:
   all `GS-002 pass:` lines, no failures; golden-model deltas within
   stated tolerances. This is the never-flash-unsimulated rule doing real
   work.
2. **Synthesis budget.** `make synth && make time` for hx8k. Read the stat
   line like the theremin course taught: LUTs, EBR, fmax. Record it in the
   lesson's commit message. If it doesn't close, take the ECP5 hatch and
   say so in D6.
3. **Bench, fan target** — **observe on bench**: lesson 16 chain → ADC →
   board → UART to a laptop. Confirm 50 Hz reports, plausible blade-flash
   velocities, SNR collapsing when you block the horn.
4. **Car test = VT-04** — **observe on bench** (well, car park): steady
   GPS-logged passes at 2–3 speeds. Compare reported v_r to GPS speed;
   pass criterion per D7 (|error| ≤ 0.3 m/s, 50 Hz output). Log UART
   captures, GPS trace, and the comparison notebook to `results/VT-04/`.
   Both directions — the sign must be right.

## Explore

1. **Alias it on purpose.** Set R = 8 with the 24 GHz constants in the
   golden model and drive a 30 m/s target. Watch the reported velocity
   fold. Keep the plot — it's the exhibit for your D6 revision commit.
2. **CFAR knob.** Sweep ALPHA over the golden noise-only set and measure
   empirical P_fa against your derived formula. How close is the
   exponential-noise assumption after an FFT of real ADC samples?
3. **Window or not.** Add a Hann window ROM before the FFT. Measure the
   SNR loss on-bin vs the sidelobe improvement off-bin. Is it worth EBR on
   hx8k? Defensible either way — write down which you shipped and why.
4. **Blade flash vs body.** Feed the fan spectrum from lesson 16's Explore
   into cfar. Does it pick hub or blade line? Reconcile with your
   lesson 16 prediction; note implications for scoring approach speed on a
   prop aircraft (this resurfaces in lesson 24).

## Checkpoint

- The decimation audit is written up; D6 revised (R generic, per-band
  default) in a commit that cites the analysis; D2 checked and confirmed
  untouched.
- `make sim` passes for cic_dec, fft512_serial, cfar, doppler_top with
  GS-002-tagged asserts, all driven by the committed golden model.
- Synthesis + icetime numbers for your chosen board are recorded; if you
  moved to ECP5, D6 says so.
- Fan-target bench run shows live 50 Hz UART velocity reports
  (**observe on bench**).
- VT-04 car-park data is captured to `results/VT-04/` — or scheduled, with
  the rig proven on the fan.
