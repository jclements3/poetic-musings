# maiden29 — VT-18 red-build drill [desk]

**Sprint goal.** Prove the alarm rings: inject a plausible fusion bug on a
branch, watch CI fail on the accuracy thresholds — not on a crash — and
file the evidence.

**Depends on.** maiden28 (CI green on main). Short sprint; pair it with
the tail of maiden28 if the sitting has room.

**Read first.** lesson15.md — *Concepts* "VT-18: prove the alarm rings"
and the *Verify* section's drill notes.

## Tasks

- [x] Branch (e.g., `vt18-drill`), inject one subtle, plausible fusion
      bug: transpose a Jacobian block, drop the v_r update, or
      off-by-one the epoch grid. It must degrade accuracy, not crash the
      pipeline — a crash-red run doesn't test the *accuracy* gate; pick a
      subtler bug if yours dies loudly.
- [ ] Push; watch the replay job go red on a SYS-002/003/004 threshold
      breach.
- [x] Capture the evidence into `results/VT-18/`: which bug was
      injected, the red run's log excerpt (or screenshot), and which
      threshold caught it.
- [ ] Delete the drill branch. (No branch created — drill ran locally via `make ci`; see notes.)
- [x] Note in `results/VT-18/` the standing rule: repeat this drill after
      any major CI change.
- [ ] Explore — cache poisoning: weaken the cache key to seed-only,
      change the twin's noise model, observe CI wrongly pass, restore
      the source-hash key. Now you've *seen* why maiden28 keyed it that
      way.
- [x] Explore — extend `replay.py` to print percent margin to each
      threshold, not just pass/fail; a 2%-margin pass deserves different
      attention than a 60% one.

## Done when

- `results/VT-18/` contains the injected-bug description, the red-run
  evidence, and the threshold that caught it; main is back green and the
  drill branch is gone.
- The failure was a threshold breach, not an exception.
- The margin report (if built) is in `replay.py` and visible in CI logs.

## Doc trace

VT-18 (D7: inspection — "inject a fusion bug on a branch; build fails on
SYS-002/003/004 thresholds") executed with evidence filed; SW-005's
regression gate demonstrated live, closing the desk software track —
maiden30 opens the hardware track.

---

**Execution notes (maiden29, desk).** Drill performed locally with
`make ci`'s replay as the gate (no branch push — state-changing git is
the orchestrator's; the on-GitHub red run should be repeated once after
the workflow's first push, per the standing rule). Injected bug: v_r
update silently dropped in the epoch scheduler — accuracy-red (SYS-003
BREACH on all 3 seeds, 1.76-2.24 m/s vs 1.0; pipeline never crashed;
SYS-002/004 stayed green). fuse.py restored byte-identically (diff-
verified), green rerun confirmed. Evidence: results/VT-18/drill.md.
Margin report built into replay.py (visible in CI logs). Cache-poisoning
Explore skipped for time — the source-hash key's rationale is recorded
in replay.py and ci.yml comments.
