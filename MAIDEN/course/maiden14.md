# maiden14 — Ingest decoders [desk]

**Sprint goal.** Build the streaming half of `maiden.ingest`: packet
walker, TMATS descriptors, time-resolved channel decoders — the one place
in MAIDEN where file formats are allowed to exist.

**Depends on:** maiden05 (TMATS parser), maiden06 (TimeDecoder), maiden08
(`StateSample.validate`), maiden12 (twin files to read).

**Read first:** lesson08.md §Concepts (all three subsections — the
hold-back queue and the payload structs are contractual) and §Build
through step 5.

## Tasks

- [x] Create `software/maiden/ch10/payloads.py` — complete and short:
      `RADAR_V = struct.Struct("<ffHxx")`, `TRACKER =
      struct.Struct("<fff4H")`, pack/unpack helpers, docstring naming
      these as IF-1 payload contracts shared by ingest, recorder, twin.
- [x] Refactor maiden12's twin writer to import from `payloads.py` — no
      private struct copies remain.
- [x] Build `PacketWalker` over PyChapter10 yielding
      `(channel_id, data_type, rtc, payload)`, tolerant of truncation;
      unit-test packet counts and channel ids against a twin station file.
- [x] Implement `describe(path) -> Station | Aircraft` from the TMATS
      packet only: `C\MAIDEN\*` attributes into the descriptor
      dataclasses, source letter from `G\DSI-1`.
- [x] Implement `load(path, *, channels=None)`: feed Ch 1 to the
      TimeDecoder as packets arrive; bounded hold-back deque (~2 s) for
      early data packets, `IngestError` on overflow naming the IF-1
      violation; decode Ch 5 → az/el/conf samples, Ch 4 → v_r samples,
      Ch 6 → STATUS `Event`s via `events(path)`.
- [x] Every yielded sample passes `validate()` before it escapes.
- [x] Write the `--summary` `__main__` (sample counts per channel, time
      span, descriptor).

## Done when

- `python -m maiden.ingest data/twin-ideal/STATION_A_*.ch10 --summary`
  prints counts consistent with what the twin wrote (tracker ≈ frames,
  radar ≈ 50 × duration, deficit ≤ declared dropout rate).
- `describe()` returns correct descriptors for all three stations and the
  TRUTH file.
- Memory stays flat when the session doubles in length (streaming means
  streaming — check with `/usr/bin/time -v`).

## Doc trace

SW-001 (reading half) · IF-1/IF-2/IF-4 · VT-14 (suite completes in
maiden15) · the hold-back rule is a cross-reference maiden40's recorder
must honor.

**Build notes (executed).** `payloads.py` pre-existed from maiden12's
if-first clause with `<ffI`/`<fffHHHH` layouts (same 12/20-byte sizes as
the lesson's `<ffHxx`/`<fff4H`; on-disk contract wins — lesson 08 §Build
differs in padding spelling only). PacketWalker deviation: hand-parsed
streaming headers instead of PyChapter10 (whose typed classes assume
CSDWs IF-1 bodies don't carry); PyChapter10 remains the independent
referee in the tests. TRUTH files decode by TMATS DSI name (GNSS/ATT)
per the payloads.py caveat; ATT rides on the next GNSS sample.
