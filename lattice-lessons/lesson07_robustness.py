"""LESSON 7 — errors, retries, timeouts.

The SDK raises anduril.core.api_error.ApiError for non-2xx responses
(status_code + body). Coding tests probe whether you:
  * catch the RIGHT exception narrowly
  * retry with capped exponential backoff (and only on retryable codes)
  * treat 4xx (except 429) as permanent, 5xx/429 as transient
  * pass per-request timeout via request_options
"""
import os
import time

import httpx
from anduril.client import Lattice
from anduril.core.api_error import ApiError

# a transport that fails N times, then succeeds — the classic retry fixture
class Flaky:
    def __init__(self, failures, code=503):
        self.left, self.code, self.calls = failures, code, 0
    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.calls += 1
        if self.left > 0:
            self.left -= 1
            return httpx.Response(self.code, json={"message": "try later"})
        return httpx.Response(200, json={"entityId": "ok-after-retries"})

def make_flaky_client(failures, code=503):
    f = Flaky(failures, code)
    # TRAP the test will poke: the SDK ALSO retries internally (max_retries).
    # Disable it here so OUR backoff wrapper is what's being exercised —
    # in production you pick ONE layer to own retries, never both.
    c = Lattice(base_url="https://mock.local", token="t", max_retries=0,
                httpx_client=httpx.Client(transport=httpx.MockTransport(f)))
    return c, f

# --- WORKED EXAMPLE ---------------------------------------------------------
client, flaky = make_flaky_client(failures=1)
try:
    client.entities.get_entity(entity_id="x")          # SDK may retry internally
    print("got it; transport calls:", flaky.calls)
except ApiError as err:
    print("ApiError:", err.status_code, "after", flaky.calls, "calls")

RETRYABLE = {429, 500, 502, 503, 504}

def with_backoff(fn, *, tries=4, base=0.01, sleep=time.sleep):
    """Run fn(); retry on transient ApiError with 1x,2x,4x... backoff."""
    for attempt in range(tries):
        try:
            return fn()
        except ApiError as err:
            if err.status_code not in RETRYABLE or attempt == tries - 1:
                raise
            sleep(base * (2 ** attempt))

client2, flaky2 = make_flaky_client(failures=2)
e = with_backoff(lambda: client2.entities.get_entity(entity_id="x"))
print("with_backoff won after", flaky2.calls, "transport calls")

# --- EXERCISES --------------------------------------------------------------
# E1. Make with_backoff report: return (result, attempts_used) and record the
#     sleeps it WOULD do by injecting sleep=fake (collect into a list).
# E2. A 404 must NOT be retried. Prove it: flaky client with code=404 and a
#     spy sleep — assert zero sleeps and the ApiError escaping.
# E3. Add jitter: +-25% of each backoff using random.Random(seed) so the test
#     stays deterministic. Print the planned sleep schedule for tries=5.
# E4. Per-request timeout: pass request_options={"timeout_in_seconds": 2}
#     to get_entity (see anduril.core.request_options.RequestOptions).

# --- SOLUTIONS --------------------------------------------------------------
if os.environ.get("SOLUTIONS") == "1":
    def with_backoff2(fn, *, tries=4, base=0.01, sleep=time.sleep):
        for attempt in range(tries):
            try:
                return fn(), attempt + 1
            except ApiError as err:
                if err.status_code not in RETRYABLE or attempt == tries - 1:
                    raise
                sleep(base * (2 ** attempt))

    slept = []
    c3, f3 = make_flaky_client(failures=2)
    res, used = with_backoff2(lambda: c3.entities.get_entity(entity_id="x"),
                              sleep=slept.append)
    print("E1: attempts", used, "sleeps", slept)

    slept2 = []
    c4, f4 = make_flaky_client(failures=5, code=404)
    try:
        with_backoff2(lambda: c4.entities.get_entity(entity_id="x"),
                      sleep=slept2.append)
    except ApiError as err:
        print("E2: 404 escaped immediately, sleeps =", slept2,
              "status", err.status_code)

    import random
    def schedule(tries=5, base=0.01, seed=7):
        rng = random.Random(seed)
        return [round(base * (2 ** a) * rng.uniform(0.75, 1.25), 4)
                for a in range(tries - 1)]
    print("E3 planned sleeps:", schedule())

    c5, _ = make_flaky_client(failures=0)
    got = c5.entities.get_entity(entity_id="x",
                                 request_options={"timeout_in_seconds": 2})
    print("E4 per-request timeout accepted:", got.entity_id)
    print("lesson07 solutions OK")
