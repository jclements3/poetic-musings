# maiden33 — Decimation audit [desk]

**Sprint goal.** D6's "CIC ↓8" is audited against each band's Doppler
bandwidth, the aliasing problem is caught and written up, and the D6
revision is committed through D5 change control.

**Depends on.** None hardware-side (paper + repo). Best done after
maiden30 so the band context is live; must precede maiden34 (the R
generic default flows from this audit).

**Read first.** lesson17.md § "First, the audit (design friction — do not
skip)" — work the numbers *before* the spoiler line, on paper; then
§ Doc Trace "Revises".

## Tasks

- [x] Compute the unambiguous Doppler span for 48 kS/s ÷ 8 complex
      sampling, convert to m/s for both 24.125 GHz and 10.525 GHz, and
      compare against pattern-ship radial speeds (~30 m/s).
- [x] State the failure: at 24 GHz, 30 m/s ⇒ 4.8 kHz > ±3 kHz — aliases
      to a wrong, possibly wrong-signed velocity. At 10.5 GHz it fits.
- [x] Work the fix: R = 4 at 24 GHz (12 kS/s, ±37 m/s unambiguous,
      23.4 Hz bins ⇒ 0.145 m/s — check this still clears SYS-003's need
      with margin); R = 8 acceptable iff VT-05 settles on the HB100.
- [x] Write the analysis up as `docs/notes/decimation-audit.md` including
      the fold plot you'll generate in maiden34's golden model (leave a
      TODO link; lesson 17 Explore 1 produces the exhibit).
- [x] Revise D6 §FPGA DSP: "CIC ↓8" → "CIC ↓R, R = 4 (24 GHz) / 8
      (10.5 GHz), see ambiguity analysis", citing the note.
- [x] Check D2's GS-002 wording survives unchanged (50 Hz and v_r are
      decimation-independent) and say so in the commit message — the
      commit touches D6 + the note together, per D5 change control.

## Done when

- `docs/notes/decimation-audit.md` exists with the full derivation and
  the per-band decision rule.
- The D6 revision commit is in history, message citing the analysis and
  recording the D2 no-change check.
- You can state from memory why the decimated *complex* rate sets the
  unambiguous span and what R the default build will use pending VT-05.

## Doc trace

GS-002 (wording confirmed intact), SYS-003 (resolution check), D6 §FPGA
DSP (revised), D5 change control + risk R2, VT-05 (pending input to the
final R default).

## Completion notes (executed 2026-08-21)

- Audit note at `results/design-notes/decimation-audit.md` (orchestrator
  directive path; the card's `docs/notes/` was superseded). D6 §FPGA DSP
  revised in both the figure and the prose, citing the note.
- Numbers as derived: ↓8 at 24 GHz → ±18.6 m/s; 30 m/s folds to −7.3 m/s
  (confirmed numerically by the golden chain: −7.28 m/s). R = 4 default.
- D2 GS-002 wording checked: unchanged (50 Hz and v_r are
  decimation-independent). Commits are made by the orchestrator.
