"""LESSON 4 — folding an event stream into a world model.

Live code uses client.entities.stream_entities() / long_poll_entity_events()
— an infinite iterator of events. Tests simulate that with a finite list.
The PATTERN is what matters and it is pure Python:

    world = {}
    for event in events:           # each event: (kind, entity)
        fold(world, event)         # mutate/replace/delete
    ...answer questions about `world`

Practice muscles: generators, dict folding, max/min with keys, defaultdict.
"""
import os
import random
from collections import defaultdict

from anduril.types import Position, Location, Aliases
import harness

# --- WORKED EXAMPLE ---------------------------------------------------------
def synthetic_events(n_ticks=200, seed=49):
    """A finite fake of stream_entities(): yields (kind, payload) tuples.
    kinds: 'created' | 'moved' | 'expired'."""
    rng = random.Random(seed)
    sts = list(harness.stations())
    live = {}
    for st in sts[:10]:
        eid = f"S{st['station']:02d}"
        live[eid] = (st["lat"], st["lon"])
        yield "created", {"id": eid, "lat": st["lat"], "lon": st["lon"]}
    for _ in range(n_ticks):
        eid = rng.choice(list(live))
        kind = rng.choices(["moved", "expired", "created"], [8, 1, 1])[0]
        if kind == "moved":
            lat, lon = live[eid]
            lat += rng.uniform(-1e-6, 1e-6); lon += rng.uniform(-1e-6, 1e-6)
            live[eid] = (lat, lon)
            yield "moved", {"id": eid, "lat": lat, "lon": lon}
        elif kind == "expired" and len(live) > 2:
            del live[eid]
            yield "expired", {"id": eid}
        else:
            new = f"S{rng.randint(50, 99)}"
            live[new] = harness.HOME
            yield "created", {"id": new, "lat": harness.HOME[0], "lon": harness.HOME[1]}

def fold(world, event):
    kind, p = event
    if kind in ("created", "moved"):
        w = world.setdefault(p["id"], {"updates": 0})
        w.update(lat=p["lat"], lon=p["lon"])
        w["updates"] += 1
    elif kind == "expired":
        world.pop(p["id"], None)

world = {}
for ev in synthetic_events():
    fold(world, ev)
print(f"world holds {len(world)} live entities")
busiest = max(world.items(), key=lambda kv: kv[1]["updates"])
print("busiest entity:", busiest[0], "with", busiest[1]["updates"], "updates")

# --- EXERCISES --------------------------------------------------------------
# E1. Rewrite the consumption as a single function
#     replay(events) -> (world, counters) where counters is a
#     defaultdict(int) of event kinds seen. No globals.
# E2. Add tombstones: expired entities go to world["__dead__"] (a set) and a
#     'created' for a dead id must RESURRECT it (remove from the set).
# E3. Generator chain: write take_until(events, pred) yielding events until
#     pred(event) is True (inclusive), and use it to replay only until the
#     first 'expired'.
# E4. (SDK bridge) Convert one folded world entry back into SDK models:
#     Location(position=Position(...)) — prove types with isinstance.

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def replay(events):
        world, counters = {}, defaultdict(int)
        dead = world.setdefault("__dead__", set())
        for kind, p in events:
            counters[kind] += 1
            if kind in ("created", "moved"):
                dead.discard(p["id"])
                w = world.setdefault(p["id"], {"updates": 0})
                w.update(lat=p["lat"], lon=p["lon"]); w["updates"] += 1
            elif kind == "expired":
                world.pop(p["id"], None); dead.add(p["id"])
        return world, counters

    w2, counts = replay(synthetic_events())
    print("E1/E2:", dict(counts), "| dead:", len(w2["__dead__"]))

    def take_until(events, pred):
        for ev in events:
            yield ev
            if pred(ev):
                return
    upto = list(take_until(synthetic_events(), lambda ev: ev[0] == "expired"))
    print("E3: replayed", len(upto), "events until first expiry")

    some_id, rec = next((k, v) for k, v in w2.items() if k != "__dead__")
    loc = Location(position=Position(latitude_degrees=rec["lat"],
                                     longitude_degrees=rec["lon"]))
    print("E4:", isinstance(loc.position, Position), some_id)
    print("lesson04 solutions OK")
