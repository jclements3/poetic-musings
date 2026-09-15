# maiden05 — TMATS template & parser [desk]

**Sprint goal.** Put the D4 IF-2 station template under version control and
build the strict-generator / defensive-parser pair that carries survey and
calibration data through every `.ch10` file.

**Depends on.** maiden04 (the writer this sprint feeds real TMATS into).

**Read first.** lesson03.md §Concepts (*The syntax*, *MAIDEN's
attributes*, *Parser posture*) and §Build.

## Tasks

- [x] Transcribe `config/tmats/station.tmt` from D4 IF-2 exactly: `G\`
      block, `R-1\` block with the seven TK1/DSI/CDT channel rows (plus
      TFMT/TSRC/VTF extras), all twelve `C\MAIDEN\` survey/cam/radar
      attributes, keeping the ICD's comment lines.
- [x] Write `software/maiden/tmats.py` from the lesson 03 skeleton:
      `Station` dataclass, `parse_attributes` (comment stripping, `;`
      split, first-`:` split, `__errors__` collection — never raise on
      data), `parse_station` (missing MAIDEN attribute → `None` +
      warning), `render_station` (deterministic order and float
      formatting).
- [x] Write `software/tests/test_tmats.py` — the four lesson-03 tests:
      template parses (spot values: lat 34.6851710, hdg 12.4, fx 1820.4,
      CDM324, 7 channel rows), round-trip stability, degradation on a
      deleted attribute, 200-case seeded fuzz that never raises.
- [x] Wire into maiden04's writer tests: real rendered template as the
      TMATS payload; PyChapter10 still reads the file, body decodes as
      ASCII.
- [x] Decide and document the comment-preservation posture (lesson 03
      §Verify's diff question) in the module docstring.
- [x] Commit: `tmats: station template per D4 IF-2, parser/generator`.

## Done when

- `pytest software/tests/test_tmats.py` green, fuzz included.
- maiden04's round-trip test still green with the real TMATS payload.
- You can parse `R-1\TK1-4:3;` aloud — group, recorder index, attribute,
  row, value — without notes.

## Doc trace

D4 IF-2 (template is the controlled artifact; changes are ICD revisions
per D5 change control) · GS-004/GS-005 (transport of survey/cal values) ·
SW-001 (ingest builds descriptors from this parser; VT-14's
malformed-TMATS clause formalizes at maiden15).
