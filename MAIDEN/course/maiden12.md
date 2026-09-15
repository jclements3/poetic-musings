# maiden12 — Twin → .ch10 [desk]

**Sprint goal.** Marry the packet writer and TMATS generator to the sensor
streams and ship the pinned `maiden twin` CLI writing real, independently
readable `.ch10` session files plus `truth.npz`.

**Depends on:** maiden04 (packet writer), maiden05 (TMATS generator),
maiden06 (the drift you synthesize here is what the TimeDecoder untangles),
maiden11.

**Read first:** lesson07.md §Build (*writer.py* and *The CLI*), §Concepts
(*What the twin honestly is not*), and the format-truth item in §Verify.

## Tasks

- [x] Create `software/maiden/twin/writer.py`: per station, TMATS packet
      first, Ch 1 time packets at 1 Hz, Ch 4 PCM (v_r) and Ch 5 messages
      (az/el/conf) interleaved by RTC, Ch 6 status at 1 Hz with PPS lock
      true. Payload structs come from `maiden/ch10/payloads.py` (created
      in maiden14 — if you get here first, define them there now and note
      it; one definition, three users).
- [x] Write the TRUTH file: GPS/IMU-shaped PCM channels from the truth
      arrays, same time-channel discipline.
- [x] Synthesize per-file RTC with per-station drift of tens of ppm — no
      shared perfect clock.
- [x] Add the `maiden` console-script entry point with the `twin`
      subcommand: `maiden twin --out DIR [--seed N] [--imperfect]`,
      writing the four `.ch10` files + `truth.npz` (arrays + events + a
      sync-event time for lesson 14's alignment tripwire).
- [x] Station poses for the default layout read from
      `config/field/rcrc.yaml`: A at origin, B 75 m down the flight line,
      C at the threshold (D3 Figure 2).
- [x] Date TMATS from the truth epoch, not wall clock — determinism.

## Done when

- `maiden twin --out data/twin-ideal --seed 1` produces five files;
  PyChapter10 (the independent reader, not your writer's inverse) opens
  all four `.ch10` files and sees the IF-1 channels.
- Same `--seed` twice → byte-identical `truth.npz` and identical
  measurement streams.
- The docstring states what the twin does not synthesize (Ch 2 video,
  Ch 3 raw IF) and which lessons close each gap.

## Doc trace

SW-004 complete · IF-1/IF-2 · VT-17 (runnable end-to-end once maiden14–15
land ingest) · rehearses VT-01 at twin scale.

---
*Build note (execution):* payload structs were created in
`maiden/ch10/payloads.py` here (maiden14 will import them, per the task's
if-you-get-here-first clause). The CLI is wired as
`python -m maiden.twin --out DIR [--seed N] [--imperfect]` (a literal
leading `twin` token is also accepted); the `maiden` console-script alias
needs a one-line `[project.scripts]` entry in pyproject, which this sprint
was not permitted to edit — flagged to the orchestrator. File is
`twin/writer.py` per this card and lesson 07 (the batch directive said
`write.py`; the card wins).
