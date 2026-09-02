"""LESSON 3 — publishing entities: idempotent IDs, expiry, batches.

publish_entity is a flat keyword call (every Entity component is a kwarg).
Coding-test staples here:
  * DETERMINISTIC entity IDs (uuid5 on a namespace) so re-runs update
    instead of duplicating
  * is_live + expiry_time hygiene (entities that die when your feed does)
  * batch publishing that collects failures instead of dying on the first
"""
import os
import uuid
from datetime import datetime, timedelta, timezone

from anduril.types import (Position, Location, Aliases, MilView, Ontology,
                           Provenance)
import harness

NS = uuid.uuid5(uuid.NAMESPACE_DNS, "erand49.poetic-musings.local")

def station_entity_kwargs(st):
    """One sensor station -> publish_entity kwargs. Deterministic ID!"""
    now = datetime.now(timezone.utc)
    return dict(
        entity_id=str(uuid.uuid5(NS, f"station-{st['station']:02d}")),
        description=f"Erand49 string sensor station {st['station']:02d}",
        is_live=True,
        expiry_time=now + timedelta(minutes=10),
        location=Location(position=Position(latitude_degrees=st["lat"],
                                            longitude_degrees=st["lon"])),
        aliases=Aliases(name=f"ER49-S{st['station']:02d}"),
        mil_view=MilView(disposition="DISPOSITION_FRIENDLY",
                         environment="ENVIRONMENT_LAND"),
        ontology=Ontology(platform_type="Sensor",
                          specific_type="IR string-vibration station"),
        provenance=Provenance(integration_name="erand49-harp",
                              data_type="sensor-station",
                              source_update_time=now),
    )

# --- WORKED EXAMPLE ---------------------------------------------------------
client, fake = harness.make_client()
first = next(harness.stations())
e = client.entities.publish_entity(**station_entity_kwargs(first))
print("published:", e.aliases.name, "->", e.entity_id[:13], "...")

# same station again -> same ID -> the mock stores ONE entity, not two:
client.entities.publish_entity(**station_entity_kwargs(first))
print("store size after republish:", len(fake.entities), "(idempotent)")

# --- EXERCISES --------------------------------------------------------------
# E1. publish_fleet(client, sts) -> (ok_count, failures) where failures is
#     [(station, error_string)]; it must attempt EVERY station even if some
#     raise. Test it by monkeypatching fake.handler? Easier: temporarily
#     corrupt one station dict (lat="x") so model construction fails.
# E2. The demo ends at a known time. Republish the fleet with expiry_time =
#     top of the next hour (datetime gymnastics; no external libs).
# E3. Prove idempotency at scale: publish the full fleet twice and assert
#     len(fake.entities) == 49.

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def publish_fleet(client, sts):
        ok, failures = 0, []
        for st in sts:
            try:
                client.entities.publish_entity(**station_entity_kwargs(st))
                ok += 1
            except Exception as err:            # noqa: BLE001 — collect, don't die
                failures.append((st.get("station"), str(err)[:60]))
        return ok, failures

    sts = list(harness.stations())
    bad = dict(sts[3]); bad["lat"] = "x"        # poison one
    ok, failures = publish_fleet(client, sts[:3] + [bad] + sts[4:])
    print(f"E1: ok={ok} failures={failures}")

    now = datetime.now(timezone.utc)
    top_of_next_hour = (now.replace(minute=0, second=0, microsecond=0)
                        + timedelta(hours=1))
    kw = station_entity_kwargs(sts[0]); kw["expiry_time"] = top_of_next_hour
    client.entities.publish_entity(**kw)
    print("E2 expiry:", top_of_next_hour.isoformat())

    publish_fleet(client, sts); publish_fleet(client, sts)
    print("E3 store size:", len(fake.entities), "(expect 49)")
    assert len(fake.entities) == 49
    print("lesson03 solutions OK")
