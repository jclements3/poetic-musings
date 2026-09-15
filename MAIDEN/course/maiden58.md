# maiden58 — Readiness review (CDR+TRR) [desk]

**Sprint goal.** Pass the D5 CDR+TRR self-review as a difficult customer
proxy: every Prototype entry criterion verified with evidence links, D2
baselined, and the commit you will fly tagged — before any campaign field
day.

**Depends on.** maiden29 (CI green on the twin set), maiden46 (three
stations, serials, per-serial cal files), maiden48 (logger flight-ready),
maiden50 (converter proven), maiden57 (`maiden run --session` end-to-end).
Every P1 bench VT sprint must have its evidence in `results/`.

**Read first.** lesson99.md — *Where we are*, Concepts §"Verification
ends; validation begins", Build §1 "Readiness review (one sitting, before
any field day)"; D5 milestone table (Prototype = CDR+TRR).

**Tasks**

- [ ] Create `results/reviews/CDR-TRR.md` from the Build §1 checklist —
      each item restated as a verifiable fact with a repo link, not a vibe.
- [ ] Verify three stations built: serials MAIDEN-STA-001…003 in their
      TMATS records, calibration files versioned per serial (D5 §CM).
- [ ] Audit `results/VT-01…VT-09, VT-13…VT-18`: result sheet plus raw
      evidence present for every P1 bench VT; list any gap as a no-go.
- [ ] Confirm D4, D6, D7 complete; baseline D2 in one commit and note in
      the review that change control now binds (D2 commit + D6/D7 rows).
- [ ] Confirm twin replay is green in CI at the exact commit to be flown;
      record the commit hash in the review.
- [ ] Print ten flight cards (lesson99 Build §5, verbatim) and put the
      consent cards in the case lid per D9.
- [ ] Disposition every unchecked box: fix it or explicitly no-go the
      campaign start; sign and date the review.

**Done when**

- `results/reviews/CDR-TRR.md` is committed with every entry criterion
  checked and linked, signed, dated.
- D2 is baselined and the flight commit is tagged.
- Ten printed flight cards and the consent cards physically exist.
- No unchecked box remains without a written disposition.

**Doc trace.** D5 milestone table (CDR+TRR entry criteria), D5 §CM and
§Tailoring; D2 baseline; D9 (cards); lesson99 Build §1.
