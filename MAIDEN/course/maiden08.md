# maiden08 — State-vector interface [desk]

**Sprint goal.** Implement D4 IF-4 verbatim as `maiden/state.py` and pin
its invariants down with the contract tests every future adapter will run
against.

**Depends on:** maiden01 (repo, pytest). Conceptually cites maiden06's
TimeDecoder but shares no code with it.

**Read first:** lesson05.md — all of it (it is short and every section is
load-bearing), especially *Reading the dataclass like an ICD* and the
adapter contract paragraph in *Build*.

## Tasks

- [x] Create `software/maiden/state.py` from the lesson's complete listing:
      `StateSample`, `Event`, `SOURCES`/`STATIONS`, and `validate()`.
      Field names/types match D4 IF-4 exactly — diff against the ICD text.
- [x] Create `software/maiden/adapters.py`: the `@adapter(kind)` decorator
      registry and `get(kind)` with a KeyError that names known kinds.
      Document the adapter contract (path + descriptor in, nondecreasing
      `t_utc` `StateSample`s out, each passing `validate`) in the docstring.
- [x] Write `software/tests/test_state.py`: example-based accept/reject
      cases for every `validate` rule (station samples with `pos_enu` →
      reject, FUSED without `pos_enu`/`vel_enu` → reject, `conf` outside
      [0,1] → reject, TRUTH with `cov` → reject, etc.).
- [x] Add the property-based layer: random samples with fields drawn per
      source kind; assert `validate` accepts exactly the legal combinations
      (hypothesis or a seeded generator — your call, record it).
- [x] Put `check_adapter_stream` in `software/tests/conftest.py` exactly as
      the lesson gives it — this is VT-14's engine, imported by the
      maiden15 and maiden50 test suites unchanged.
- [x] Run the lesson's Explore 3 (hostile adapter: one out-of-order sample
      among 1000) and keep it as a test.

## Done when

- `pytest software/tests/test_state.py` is green, with at least one
  accept and one reject case per `validate` rule.
- `check_adapter_stream` is importable from tests and demonstrably catches
  both an invalid sample and a `t_utc` regression.
- `state.py` deviates from D4 IF-4 in zero fields — or the deviation is a
  committed D4 revision, not a silent local edit.

## Doc trace

SW-001 (data half) · D4 IF-4 (governing, verbatim) · VT-14 (these tests
are its engine) · feeds every lesson ≥ 08.
