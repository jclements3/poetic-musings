# Lattice SDK coding-test bootcamp

Eight hands-on lessons that use the real `anduril-lattice-sdk` (v4.29.x, import
name `anduril`) against an **offline mock environment**, so every lesson runs on
this machine with no credentials and no network. The data set is this project:
the Erand49 harp's 49 sensor stations become your entity fleet.

## How to run

The SDK is installed under the system Python 3.10 (not the conda 3.13):

    /usr/bin/python3 lattice-lessons/lesson01_client_and_config.py

Every lesson file has three parts: a WORKED EXAMPLE (runs immediately), numbered
EXERCISES (do them before peeking), and SOLUTIONS at the bottom (run with
`SOLUTIONS=1` in the environment to execute them).

    SOLUTIONS=1 /usr/bin/python3 lattice-lessons/lesson03_publishing.py

## Curriculum

| # | File | You practice |
|---|------|--------------|
| 1 | lesson01_client_and_config.py | client construction, env-var config, twelve-factor defaults |
| 2 | lesson02_models.py | pydantic models, Literal enums, validation errors, serialization |
| 3 | lesson03_publishing.py | publish_entity, idempotent IDs (uuid5), batch + error collection |
| 4 | lesson04_worldmodel.py | iterators/generators, event folding into a world model dict |
| 5 | lesson05_python_drills.py | comprehensions, sorted/key, groupby, csv — pure-Python test muscles |
| 6 | lesson06_tasks_agent.py | task lifecycle, a polling agent as a state machine |
| 7 | lesson07_robustness.py | ApiError handling, retries with backoff, timeouts |
| 8 | test_lesson08.py | pytest + httpx.MockTransport fixtures, asserting request bodies |

Lesson 8 runs with: `/usr/bin/python3 -m pytest lattice-lessons/test_lesson08.py -q`

## The mock environment (harness.py)

`harness.make_client()` returns a real `Lattice` client whose HTTP transport is
an in-memory fake: `PUT /api/v1/entities` stores and echoes, `GET
/api/v1/entities/{id}` returns stored or 404, `POST /api/v1/tasks` creates,
`POST /api/v1/tasks/query` lists. Everything you learn transfers 1:1 to a live
environment — swap `make_client()` for `Lattice(token=..., base_url=...)`.

## Test-day tips

- Read method signatures with `inspect.signature` / `help()` — this SDK is
  keyword-only everywhere, and guessing positionals wastes minutes.
- Literal enums hide in `Model.model_fields[name].annotation`
  (`typing.get_args` them) — lesson 2 drills this.
- `model_dump(exclude_none=True)` is how you diff/print entities sanely.
- When a test gives you no server, build the httpx.MockTransport harness from
  lesson 8 from memory — it is ~15 lines and turns every API question into a
  pure-Python question.
- State machines (lesson 6) and event folding (lesson 4) are the two patterns
  Lattice-flavored tests love most.
