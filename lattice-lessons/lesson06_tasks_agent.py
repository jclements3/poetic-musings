"""LESSON 6 — the Tasks API and an agent as a state machine.

Task lifecycle: create_task -> (an agent receives it) -> update_task_status
through a legal state sequence -> done/failed. Live agents use
listen_as_agent()/stream_as_agent(); tests fake the inbox with a queue.

Muscles: enums as data, dict-driven state machines, while-loop agents with
explicit termination, defensive transitions.
"""
import os
from collections import deque

import harness

# Legal transitions (a subset of Lattice's STATUS_* space, enough for tests):
TRANSITIONS = {
    "STATUS_CREATED":   {"STATUS_ACK"},
    "STATUS_ACK":       {"STATUS_WILCO", "STATUS_DECLINED"},
    "STATUS_WILCO":     {"STATUS_EXECUTING"},
    "STATUS_EXECUTING": {"STATUS_DONE_OK", "STATUS_DONE_NOT_OK"},
    "STATUS_DONE_OK": set(), "STATUS_DONE_NOT_OK": set(), "STATUS_DECLINED": set(),
}

def advance(task, new_status):
    cur = task["status"]
    if new_status not in TRANSITIONS[cur]:
        raise ValueError(f"illegal {cur} -> {new_status}")
    task["status"] = new_status
    return task

# --- WORKED EXAMPLE ---------------------------------------------------------
client, fake = harness.make_client()
created = client.tasks.create_task(display_name="Tune string 07",
                                   description="bring c2 to 65.4 Hz")
tid = created.version.task_id
print("created task:", tid[:8], "…")

# a tiny agent: pull work from an inbox, walk it through the machine
def run_agent(inbox, worker):
    """inbox: deque of task dicts; worker(task) -> True (ok) / False."""
    done = []
    while inbox:
        task = inbox.popleft()
        advance(task, "STATUS_ACK")
        advance(task, "STATUS_WILCO")
        advance(task, "STATUS_EXECUTING")
        advance(task, "STATUS_DONE_OK" if worker(task) else "STATUS_DONE_NOT_OK")
        done.append(task)
    return done

inbox = deque([{"id": f"tune-{n:02d}", "status": "STATUS_CREATED"} for n in (1, 2, 3)])
out = run_agent(inbox, worker=lambda t: not t["id"].endswith("2"))
print("agent results:", [(t["id"], t["status"]) for t in out])

# --- EXERCISES --------------------------------------------------------------
# E1. advance() should be forgiving in one specific way tests like:
#     make repeating the CURRENT state a no-op instead of an error.
# E2. Write walk(task, *statuses) that applies advance() over a list and
#     rolls the task back to its original status if ANY step is illegal
#     (all-or-nothing semantics).
# E3. Add a 'declines' policy to run_agent: worker may return None meaning
#     "decline" -> ACK then DECLINED (legal per the table!).
# E4. (SDK bridge) create 3 tasks via client.tasks.create_task, then
#     query_tasks() and print each task's display name from the response.
#     Introspect the returned model with model_dump to find where the name
#     lives — that discovery IS the exercise.

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def advance2(task, new_status):
        cur = task["status"]
        if new_status == cur:
            return task
        if new_status not in TRANSITIONS[cur]:
            raise ValueError(f"illegal {cur} -> {new_status}")
        task["status"] = new_status
        return task
    t = {"id": "x", "status": "STATUS_ACK"}
    advance2(t, "STATUS_ACK")
    print("E1 idempotent repeat OK:", t["status"])

    def walk(task, *statuses):
        original = task["status"]
        try:
            for s in statuses:
                advance2(task, s)
        except ValueError as err:
            task["status"] = original
            return False, str(err)
        return True, task["status"]
    print("E2 legal:", walk({"id": "y", "status": "STATUS_CREATED"},
                            "STATUS_ACK", "STATUS_WILCO"))
    print("E2 rollback:", walk({"id": "z", "status": "STATUS_CREATED"},
                               "STATUS_ACK", "STATUS_EXECUTING"))

    def run_agent2(inbox, worker):
        done = []
        while inbox:
            task = inbox.popleft()
            advance2(task, "STATUS_ACK")
            verdict = worker(task)
            if verdict is None:
                advance2(task, "STATUS_DECLINED")
            else:
                advance2(task, "STATUS_WILCO")
                advance2(task, "STATUS_EXECUTING")
                advance2(task, "STATUS_DONE_OK" if verdict else "STATUS_DONE_NOT_OK")
            done.append(task)
        return done
    inbox = deque([{"id": f"t{n}", "status": "STATUS_CREATED"} for n in range(3)])
    out = run_agent2(inbox, worker=lambda t: None if t["id"] == "t1" else True)
    print("E3:", [(t["id"], t["status"]) for t in out])

    for n in range(3):
        client.tasks.create_task(display_name=f"Calibrate octave {n}")
    page = client.tasks.query_tasks()
    names = []
    for task in page.tasks or []:
        d = task.model_dump(exclude_none=True)
        names.append(d.get("display_name") or d.get("displayName"))
    print("E4 task names:", names)
    print("lesson06 solutions OK")
