# GPS — GPSDO metrology reference pick (Basic Plan input, 2026-09-15)

`DESIGN.md` § Verification 2 needs a reference the disciplined 10 MHz and PPS are measured
against: an order of magnitude better than the < 0.1 ppm target, with both **10 MHz and
1 PPS** outputs so the DPLL (frequency) and the RTC/IRIG layer (phase) are each checked.
Ledger W, ORDERS.md row G2, verification only.

## Name check

"GS-101B" (HANDOFF's wording) is not a Symmetricom, HP or Datum product I can place. What
that line meant is the **HP/Symmetricom 58503A/B** GPS time & frequency reference and its
Lucent-badged siblings **Z3801A / Z3805A / Z3816A** — search those names, not GS-101B.

## Comparison

| Unit | 10 MHz | 1 PPS | Stability (spec/typ.) | Used price | To run it |
|---|---|---|---|---|---|
| **Trimble Thunderbolt E** (2010 rev; original 1998–2005) | 1 × BNC, OCXO | 1 × BNC, ±20 ns to UTC | ADEV ~1e-12 @ 1 s, ~1e-11/day; holdover < 1 µs/2 h | $150–220 as a kit (unit + 24 V PSU + antenna, eBay) | 24 V single supply (original needs +12/−12/+5 — avoid), 5 V active antenna, RS-232 TSIP + **Lady Heather** (free) for lock/holdover logging |
| HP/Symmetricom 58503B · Z3805A | 1–2 × BNC, 10811 OCXO | yes | ~1e-12 @ 1 s, best OCXO of the four | $150–350 | 24 V (Z3805A) or 48 V (Z3801A); Motorola Oncore receiver — GPS-week-rollover era, firmware-dependent; SCPI + SatStat/Lady Heather |
| Leo Bodnar Mini GPSDO | 1 × SMA, programmable 400 Hz–810 MHz (no OCXO — Si clock synth) | **none** (output ≥ 400 Hz; *verify*) | ~1e-9 short-term, no holdover, spurs | £110 / ~$140 new | USB power + USB config app, small active antenna included; a spot-frequency tool, not a phase reference |
| BG7TBL-class Chinese GPSDO (OCXO, LCD) | 2–3 × BNC sine/square | 1 × BNC (often the raw receiver PPS, ~10 ns sawtooth) | claims 1e-11 @ 1 s; unit-to-unit variable | $100–160 new (AliExpress/eBay) | 12 V PSU and SMA antenna in the box; no serial, no logging |

## Pick

**Trimble Thunderbolt E kit, ~$180 used** — search
https://www.ebay.com/sch/i.html?_nkw=trimble+thunderbolt+e+gpsdo (take a listing that
bundles the 24 V supply and the antenna; add an F/SMA adapter for the antenna if the
listing's unit has the F-type jack). Reasons: both outputs with published specs; TSIP +
Lady Heather gives a *logged* lock/holdover history to file beside `GPS/results/` — the
same before/after G's demo shows; huge community record. Known wart: firmware-era GPS
week rollover, which Lady Heather corrects with a week offset. The BG7TBL unit is the
fallback if no kit is under $220; the Bodnar unit is ruled out by the missing PPS.

## How it verifies G's DPLL and I's clock

1. **Frequency (DPLL, 10 MHz):** feed the Thunderbolt 10 MHz to the bench counter's
   external-reference input, count G's 10 MHz with a 10 s gate → 10 digits. Locked target
   **10,000,000.00 ± 1 Hz (< 0.1 ppm)**; expect ±0.01–0.1 Hz once the 100 s loop settles.
   Holdover: log the reading every minute; the slope is the crystal-plus-trim drift rate
   to record (ULX3S 25 MHz xtal, expect ~0.1–0.5 ppm/day after trim, tens of ppm untrimmed).
2. **Frequency without a counter (scope phase comparison):** trigger the scope on the
   Thunderbolt 10 MHz, display G's 10 MHz. The trace walks one cycle (100 ns) every
   1/Δf s: a walk of < 1 cycle/s is < 0.1 ppm; one cycle per 100 s is 1e-9. Count cycles
   walked in a timed minute → Δf = cycles / 60.
3. **Phase (RTC + IRIG layer, "I's clock"):** Thunderbolt PPS on ch 1 (trigger), G's PPS
   and the Phase 2 IRIG-B DCLS P_r marker on ch 2/3, infinite persistence, 24 h. Locked:
   offset stays within one steer step, **< 1 µs over 24 h** (u-blox PPS ~30 ns sawtooth
   plus 100 ns NCO step). Holdover: the offset ramps — 0.5 ppm is 43 ms/day, which is the
   "clock stops drifting" demo. `TIME_MARK` records over N must agree with the same
   offset, which checks the option-2 mapping is drift-free.
4. **Reference quality margin:** the Thunderbolt's 1e-12 class is 10⁴ below the target,
   so every digit measured is G's, not the reference's.
