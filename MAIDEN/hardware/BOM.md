# Hardware BOM — lessons 16–21 (sprints 31–48)

Source: lesson 16 §The shopping list, plus the MCP3202-class ADC line the
lesson 17 chain needs (called out by maiden30 — it is not a separate
table line in lesson 16). Owned items per the theremin course inventory.

Update the Status column on order and again on arrival. Placing orders
and recording order numbers/ETAs is a human task (see card note).

| # | Item | Qty | For (req) | ~Cost | Status | Order # / ETA |
|---|------|-----|-----------|-------|--------|----------------|
| 1 | CDM324 24 GHz Doppler module | 3 + 1 spare | GS-003 radar, all stations (D5 R2: A/B stock) | $40 | TO ORDER | — |
| 2 | HB100 10.5 GHz Doppler module | 2 | GS-003 fallback per VT-05 | $0 | **OWNED** (theremin) | — |
| 3 | NE5532 / MCP6022 op-amps, passives kit, trimmers | kit | LNA + AAF ×3 (GS-002 chain) | $25 | TO ORDER | — |
| 4 | 1080p30 global-shutter USB3 machine-vision camera + lens | 3 (60°, 35°, 60°) | GS-001 — confirm global shutter AND strobe output in the datasheet before ordering; do not cheap out | $450 | TO ORDER (model TBD at order time) | — |
| 5 | u-blox MAX-M10S breakout with PPS pin | 4 (3 stations + logger) | SYS-006, AB-001 | $80 | TO ORDER | — |
| 6 | Raspberry Pi 5 (8 GB) + SSD + SD card | 3 | SYS-005 Ch. 10 recorders | $360 | TO ORDER | — |
| 7 | FPGA dev board — ULX3S 85F, Lattice ECP5 LFE5U-85F (see note A) | 3 | GS-002 DSP + SYS-006 timebase | $315 ea ($315–945) | order of 24 Aug 2026 **canceled 27 Aug**; decision deferred to maiden36 | — |
| 8 | iCEstick + HX8K breakout | 1 + 1 | dev/bring-up boards | $0 | listed owned; **HX8K not located as of 27 Aug 2026** — if it stays lost, replacement is Alchitry Cu V2 (see results/design-notes/ice40-theremin-fit.md) | — |
| 9 | MCP3202-class SPI ADC (2 ch, 12-bit) | 3 + 1 spare | lesson 17 I/Q capture front end | $45 | 1 **OWNED** (theremin), 3 TO ORDER | — |
| 10 | Matek H743 + M10 GNSS | 1 | AB-001 truth logger | $110 | TO ORDER | — |
| 11 | 4S LiFePO₄ 10 Ah pack + buck converters | 3 | GS-007 station power | $270 | TO ORDER | — |
| 12 | Surveyor tripod + leveling head + sighting rail | 3 | GS-004 survey/heading | $300 | TO ORDER | — |
| 13 | Weatherproof case, 74HC14s, corner-reflector foil, checkerboard print | 3 + misc | GS-006 enclosures, calibration targets | $120 | TO ORDER | — |
| 14 | Breadboard, jumpers, headers | kit | bench | $0 | **OWNED** (theremin) | — |

**Total to order: ≈ $1,785–2,415** (owned lines excluded; the spread is 1
vs 3 FPGA boards at the firm $315/board quote) — still lesson 16's ~$2k
order of magnitude. Costliest line is cameras
(#4); the lesson's rolling-shutter warning is the reason.

**Note A — FPGA board decision (maiden33 outcome, revised 24 Aug 2026).**
The maiden33/35 audit is already in: the behavioral 512-pt FFT synthesizes
to ~139k LUT4s — far over hx8k even after the planned BRAM-explicit rewrite
it may not fit. Pre-empting the ECP5 escape hatch per the card's option:
**ULX3S 85F ×3 (~$945 at the quoted $315/board)** is the recommended line; final call at maiden36
bench bring-up per the audit note (results/design-notes/decimation-audit.md).

*Revision — the escape hatch does not clear the bar as stated, and the
sizing question is architectural, not a choice of part.*

1. **139k LUT4 does not fit the ECP5 85F either.** The LFE5U-85F has
   **83,640** LUT4s (measured, `nextpnr-ecp5` device utilisation, not a
   datasheet figure). 139k overshoots it by 66%, so the BRAM-explicit
   rewrite would have to find a >40% reduction merely to break even. The
   note reads as though ECP5 resolves the overflow; it does not.

2. **There is no larger ECP5 to escalate to.** The 85F is the top of the
   family. If 139k were a hard floor, the decision would not be
   hx8k → ECP5 but leaving the family entirely (Artix-7 200T class), with
   the toolchain and cost consequences that implies.

3. **139k is an artifact of the implementation, not the transform —
   now measured, not argued.** That figure is the signature of a *fully
   unrolled* behavioral FFT, every butterfly instantiated in parallel, which
   is what synthesis produces when an FFT is written behaviorally and
   flattened. A streaming radix-2 single-delay-feedback (R2SDF) FFT computes
   the same 512-point transform with log2(512) = 9 butterfly stages, one
   complex multiplier per stage in `MULT18X18D`, and the delay lines in
   `DP16KD` block RAM.

   Written in Clash (`theremin/clash/src/Theremin/Fft.hs`) and put through
   `yosys synth_ecp5` + `nextpnr-ecp5` on the LFE5U-85F, CABGA381:

   | Resource | Used | Available | % |
   |---|---|---|---|
   | TRELLIS_COMB (LUT4) | **4,620** | 83,640 | **5.5%** |
   | TRELLIS_FF | 486 | 83,640 | 0.6% |
   | MULT18X18D | 34 | 156 | 22% |
   | DP16KD | 3 | 208 | 1.4% |

   **A 30x reduction against the 139k behavioral figure.** The behavioral
   version overflowed the largest ECP5 by 66%; this one uses 5.5% of it. The
   difference went into the DSP and BRAM columns the behavioral estimate left
   at zero while spending fabric instead.

4. **This lever is also demonstrated on a second block.** `iir_nstage_pow2k`,
   ported to Clash at `theremin/clash/src/Theremin/IirNStage.hs`, gets five
   filter stages out of one adder by time-multiplexing: **175 LUT4 / 67 FF /
   0 BRAM / 132 MHz** measured on the same part, versus five parallel copies.

**Update, 25 Aug 2026 — both caveats on the FFT number are now retired.**
The initial sizing model failed timing (25.5 MHz) and was unverified. It has
since been debugged (four real defects: reversed stage order, delay-line
off-by-one with a same-address BRAM collision, butterfly overflow — fixed
with per-stage 1/2 scaling, divide-by-512 overall — and twiddle gain on the
trivial stages), pipelined, and **verified against a Double-precision
reference DFT**: impulse, single tones at bins 5/100/383, and a two-tone
case, worst component error ~5 LSB, 6/6 tests passing. Re-measured:

   | Resource | Sizing model | Verified + pipelined |
   |---|---|---|
   | TRELLIS_COMB (LUT4) | 4,620 | **3,537 (4.2%)** |
   | TRELLIS_FF | 486 | 3,729 |
   | MULT18X18D | 34 | 28 |
   | DP16KD | 3 | 10 |
   | Fmax @ 100 MHz constraint | 25.5 MHz FAIL | **123.6 MHz PASS** |

   Pipelining *reduced* LUTs while fixing timing, as predicted. Latency is
   547 cycles at one sample per clock. Numbers from the same
   yosys/nextpnr-ecp5 flow; source at `theremin/clash/src/Theremin/Fft.hs`,
   tests at `theremin/clash/test/FftSpec.hs`.

**Consequence for maiden36:** the FFT question is closed — verified,
timing-clean at 123.6 MHz, and 4.2% of the part, so the 85F is not the
constraint and there is no reason to leave the ECP5 family. **The x3 line
should be justified as three stations, not as capacity** — one board is
sufficient for all bring-up work, and the remaining two (~$630) can wait on
the station build.

*Method note: every figure above comes from synthesis and place-and-route
against the vendor device database on a laptop, with no FPGA attached.
Sizing questions do not require buying boards; hardware is for the physical
questions (oscillator startup, antenna behaviour, PPS discipline).*

*(27 Aug: the single-board order was canceled. The theremin de-risking
build proceeds on iCE40 HX8K-class hardware — see
results/design-notes/ice40-theremin-fit.md — and the ECP5 purchase
decision moves wholly to maiden36. The capacity conclusions above are
from synthesis and are unaffected.)*

**Note B — camera model selection.** Global shutter + hardware strobe
out + USB3 + C/CS mount for the three lens fields (60°/35°/60° per D6).
Shortlist at order time; record the chosen model and datasheet link here.
