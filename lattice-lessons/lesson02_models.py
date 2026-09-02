"""LESSON 2 — pydantic models: build, validate, introspect, serialize.

The SDK's 238 types (anduril.types) are pydantic v2 models. Coding tests love:
  * building nested models correctly (keyword-only, snake_case)
  * finding the legal values of Literal enum fields WITHOUT the docs
  * catching ValidationError and reporting which field failed
  * model_dump(exclude_none=True) for clean output/diffing
"""
import os
import typing

from pydantic import ValidationError
from anduril.types import (Position, Location, MilView, Ontology, Aliases,
                           Provenance)

# --- WORKED EXAMPLE ---------------------------------------------------------
# 1. Nested build — the harp's home dock as a Location:
loc = Location(position=Position(latitude_degrees=34.5031,
                                 longitude_degrees=-86.6153,
                                 altitude_hae_meters=180.0))
print("location:", loc.model_dump(exclude_none=True))

# 2. Literal enums live in the field annotation. Memorize this move:
def literal_values(model_cls, field):
    # annotations here are Union[Literal[...], Any, None] — walk one level down
    ann = model_cls.model_fields[field].annotation
    out = []
    for arg in typing.get_args(ann):
        out += [a for a in typing.get_args(arg) if isinstance(a, str)]
    return out

print("dispositions:", literal_values(MilView, "disposition")[:4], "...")

mv = MilView(disposition="DISPOSITION_FRIENDLY", environment="ENVIRONMENT_LAND")

# 3. Validation errors tell you the exact field path:
try:
    Position(latitude_degrees="north-ish")
except ValidationError as err:
    first = err.errors()[0]
    print("validation failed at:", first["loc"], "-", first["msg"][:40])

# --- EXERCISES --------------------------------------------------------------
# E1. Write describe_model(cls) -> dict {field: "type-ish string"} using
#     model_fields; run it on Ontology and Provenance.
# E2. Write safe_build(cls, **kw) that returns (instance, None) or
#     (None, "field.path: message") for the FIRST validation error.
# E3. Round-trip: dump `loc` with model_dump(), rebuild with
#     Location(**dumped["..."]) — prove equality with ==. Careful: nested
#     models dump to dicts; pydantic re-validates them on construction.
# E4. Which MilView environments could describe the harp standing on the
#     floor of a living room? Answer with code, not opinion (filter the
#     literals for 'LAND' or 'SURFACE').

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def describe_model(cls):
        return {name: str(f.annotation).replace("typing.", "")[:60]
                for name, f in cls.model_fields.items()}
    print("E1 Ontology:", describe_model(Ontology))

    def safe_build(cls, **kw):
        try:
            return cls(**kw), None
        except ValidationError as err:
            e = err.errors()[0]
            return None, f"{'.'.join(str(p) for p in e['loc'])}: {e['msg']}"
    ok, msg = safe_build(Position, latitude_degrees=91.0)  # may or may not bound-check
    print("E2:", (ok is not None) or msg)
    _, msg = safe_build(Position, latitude_degrees="north-ish")
    print("E2 first error:", msg)

    dumped = loc.model_dump()
    rebuilt = Location(**dumped)
    print("E3 round-trip equal:", rebuilt == loc)

    envs = [v for v in literal_values(MilView, "environment")
            if "LAND" in v or "SURFACE" in v]
    print("E4:", envs)
    print("lesson02 solutions OK")
