"""In-memory mock Lattice environment.

make_client() returns a REAL anduril.client.Lattice wired to an httpx
MockTransport, plus the backing store so lessons/tests can assert on it.

Routes implemented (paths captured from the real SDK v4.29.1):
    PUT  /api/v1/entities            -> store entity json, echo it back
    GET  /api/v1/entities/{id}       -> stored json or 404
    POST /api/v1/tasks               -> create task, assign taskId, store
    GET  /api/v1/tasks/{id}          -> stored json or 404
    POST /api/v1/tasks/query         -> {"tasks": [...]}
    PUT/PATCH/POST ...{id}/status    -> merge status into stored task
"""
import json
import re
import uuid

import httpx
from anduril.client import Lattice


class FakeLattice:
    def __init__(self):
        self.entities = {}   # entity_id -> dict (as sent by the SDK)
        self.tasks = {}      # task_id -> dict
        self.requests = []   # (method, path, body) log for assertions

    def handler(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        body = json.loads(request.content.decode()) if request.content else {}
        self.requests.append((request.method, path, body))

        if request.method == "PUT" and path == "/api/v1/entities":
            eid = body.get("entityId") or str(uuid.uuid4())
            body["entityId"] = eid
            self.entities[eid] = body
            return httpx.Response(200, json=body)

        m = re.fullmatch(r"/api/v1/entities/([^/]+)", path)
        if m and request.method == "GET":
            e = self.entities.get(m.group(1))
            return httpx.Response(200, json=e) if e else httpx.Response(
                404, json={"message": f"no entity {m.group(1)}"})

        if request.method == "POST" and path == "/api/v1/tasks":
            tid = str(uuid.uuid4())
            body.setdefault("version", {})["taskId"] = tid
            body.setdefault("status", {"status": "STATUS_CREATED"})
            self.tasks[tid] = body
            return httpx.Response(200, json=body)

        if request.method == "POST" and path == "/api/v1/tasks/query":
            return httpx.Response(200, json={"tasks": list(self.tasks.values())})

        m = re.fullmatch(r"/api/v1/tasks/([^/]+)/status", path)
        if m:
            t = self.tasks.get(m.group(1))
            if not t:
                return httpx.Response(404, json={"message": "no task"})
            t["status"] = {**t.get("status", {}), **body.get("statusUpdate", body)}
            return httpx.Response(200, json=t)

        m = re.fullmatch(r"/api/v1/tasks/([^/]+)", path)
        if m and request.method == "GET":
            t = self.tasks.get(m.group(1))
            return httpx.Response(200, json=t) if t else httpx.Response(
                404, json={"message": "no task"})

        return httpx.Response(404, json={"message": f"unrouted {request.method} {path}"})


def make_client():
    """-> (Lattice, FakeLattice). A real SDK client against the in-memory fake."""
    fake = FakeLattice()
    client = Lattice(
        base_url="https://mock.lattice.local",
        token="offline-lesson-token",
        httpx_client=httpx.Client(transport=httpx.MockTransport(fake.handler)),
    )
    return client, fake


# --- shared data: the Erand49 sensor stations as a "fleet" -------------------
HOME = (34.5031, -86.6153)  # Laceys Spring, AL — the harp's home dock

def stations(csv_path=None):
    """Yield dicts: station, x_mm, z_mm, lat, lon (harp mm -> ~micro-degrees)."""
    import csv, os
    here = os.path.dirname(os.path.abspath(__file__))
    csv_path = csv_path or os.path.join(here, "..", "Erand49", "sensor-stations.csv")
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            x, z = float(row["x_mm"]), float(row["z_mm"])
            yield {
                "station": int(row["station"]),
                "x_mm": x,
                "z_mm": z,
                "yaw_deg": float(row["pair_yaw_deg"]),
                "lat": HOME[0] + z * 1e-6,
                "lon": HOME[1] + x * 1e-6,
            }


if __name__ == "__main__":
    client, fake = make_client()
    e = client.entities.publish_entity(entity_id="smoke", description="harness ok",
                                       is_live=True)
    assert e.entity_id == "smoke" and "smoke" in fake.entities
    got = client.entities.get_entity(entity_id="smoke")
    assert got.description == "harness ok"
    n = sum(1 for _ in stations())
    print(f"harness OK: entity round-trip good, {n} stations loaded")
