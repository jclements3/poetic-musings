# Lesson 14 — maiden.validate [desk]

*Where we are.* The pipeline now produces a FUSED track with covariance
from three stations' worth of Ch. 10 data. The project's central claim —
SYS-002/003/004 accuracy against 6-DOF truth — needs machinery to be
tested at all: something that aligns a truth log with a fused track,
subtracts, and rolls the residuals up into the exact tables D8 publishes.
D7 §2 already drew this machine as a seven-step figure. This lesson
implements it as `maiden.validate`, verifies it on twin sessions where the
truth is perfect and the injected noise is known, and wires its output
into D8's schemas so the validation campaign (lesson 99) fills the report
by running a command, not by hand-editing tables.

## Objectives

- Implement D7's verification-against-truth pipeline, all seven steps, as
  `maiden.validate`.
- Produce per-flight and per-maneuver metrics (RMS, p95, continuity) in
  exactly D8's table schemas, as JSON and markdown.
- Implement the campaign gate: VT-10/11/12 criteria over a set of
  flights, pass ≥ 8 of 10.
- Derive confidence-band parameters from residual statistics and persist
  them for the report pipeline (lesson 24).
- Verify the whole tool against twin sessions: measured residual
  statistics must match the noise the twin injected (VT-17's criterion).

## Concepts

### The seven steps, from the D7 figure

```
station .ch10 ×3      truth .ch10
      │                    │
      ▼                    ▼
 (fuse, L12–13)      (ingest, L08)
      │                    │
      └────► 1 time-align ◄┘        common IRIG-B base + event check
                 2 frame transform   truth LLA → field ENU (L01)
                 3 residuals         per sample: pos, vel, att-if-est
                 4 metrics           RMS · p95 · continuity,
                                     per flight · per maneuver
                 5 gate              pass ≥ 8 of 10 flights
                 6 confidence bands  residual stats → report params
                 7 judge correlation (separate tool, lesson 99)
```

Step 7 needs humans and lives in lesson 99; everything else is pure
computation and gets built today.

### Step 1 — alignment is a *check*, not a knob

Both sides already carry IRIG-B/GPS time (SYS-006, lessons 04 and 22), so
alignment is nominally free. The step exists to *verify* that: find the
sync event (the clap — an accelerometer spike in the truth log, an audio
or video transient at Station A) in both streams and confirm the
timestamps agree within the SYS-006 budget. If they don't, the session is
flagged degraded-sync and the offset is applied and *recorded* — never
silently. D4's fallback discipline, as code.

### Step 2–3 — comparing apples to apples

Truth arrives as GNSS LLA + velocity; transform through
`geo.enu_from_lla` with the session's surveyed origin (from Station A's
TMATS — the descriptor object from lesson 08 carries it). Then
interpolate truth (10 Hz GNSS, 100 Hz IMU) onto the fused 50 Hz epoch
grid — interpolate the *truth*, never the estimate, so filter artifacts
aren't smoothed away. Residuals per sample:

```
r_pos(t) = p_fused(t) − p_truth(t)      (3-vector, ENU)
r_vel(t) = v_fused(t) − v_truth(t)
r_att(t) where the fused track estimates attitude (it doesn't yet; emit
         the column as absent, not zero — D8 says "where estimable")
```

Only epochs where the fused sample is valid (lesson 13's flag) enter the
residual set; invalid time is what the continuity metric already counts.

### Step 4 — rollups, defined precisely

Per flight and per maneuver segment (segment labels come from lesson 23;
until then everything is one segment, `ALL` — design the interface to
accept an optional segment table now so nothing changes later):

```
pos RMS  = √(mean ‖r_pos‖²)      pos p95 = 95th pctile of ‖r_pos‖
vel RMS  = √(mean ‖r_vel‖²)      continuity = valid_time / seq_time
```

Scalar-norm RMS, not per-axis — that is how SYS-002/003 are phrased and
how VT-10/11 will be judged. Keep per-axis breakdowns in the JSON anyway;
they're free and they localize problems (a U-axis bias smells like
survey; an E/N lag smells like sync).

### Steps 5–6 — the gate and the bands

The gate applies the VT-10/11/12 pass criteria per flight, then the
campaign rule: pass on ≥ 8 of 10 flights. It is a pure function from a
list of flight metrics to a verdict — keep it that way, CI calls it
(lesson 15). The confidence bands are D8's forward-carry: from the
campaign residual distributions, extract position p95, speed p95, and the
per-maneuver score band inputs, and persist to
`results/validate/bands.json`. Lesson 24 stamps these onto every
un-instrumented pilot report — the mechanism by which validation flights
earn MAIDEN "the right to score aircraft that carry nothing" (D1 S3).

## Doc Trace

- **D7 §Verification against 6-DOF truth** — implemented one-to-one; the
  step numbering in the code comments matches the D7 figure.
- **VT-10, VT-11, VT-12** — this tool *is* how those tests will be
  scored in the field; their pass criteria appear here as the gate's
  configuration.
- **VT-17** — the twin gate: this lesson's Verify is that test, run for
  real, results to `results/VT-17/`.
- **D8** — the Accuracy table, By-maneuver table, and §Confidence bands
  are generated by this tool in D8's own schemas; the report template's
  "generated by maiden.validate" note becomes true today.

## Build

`software/maiden/validate.py`, plus CLI wiring. *Skeleton:*

```python
@dataclass
class FlightMetrics:
    flight: str; aircraft: str; sequence: str
    pos_rms: float; pos_p95: float; vel_rms: float
    continuity: float; sync: str          # "ok" | "degraded(+8.2ms)"
    passed: bool

def align(fused: Track, truth: Track, budget_s: float) -> AlignResult: ...
def residuals(fused: Track, truth: Track) -> Residuals: ...
def rollup(res: Residuals, segments: SegmentTable | None) -> ...: ...
def gate(flights: list[FlightMetrics], need: int = 8, of: int = 10) -> bool: ...
def bands(all_res: list[Residuals]) -> BandParams: ...

def run_session(session_dir: Path) -> SessionReport:
    """fuse (or load cached fused.npz), ingest truth, steps 1–6,
    write report.json + report.md into the session dir."""
```

Output contracts, exactly D8's schemas:

- **Accuracy table** columns: `Flight | Aircraft | Sequence | Pos RMS (m)
  | Pos p95 (m) | Vel RMS (m/s) | Continuity | Sync | Pass`.
- **By-maneuver table** columns: `Maneuver | n | Pos RMS (m) | Vel RMS
  (m/s) | Continuity | Notes`, rows for D8's maneuver list plus `ALL`.
- JSON mirrors both tables plus per-axis detail and the band parameters.

CLI: `maiden validate --session DIR` (one session, possibly several
flights) and `maiden validate --campaign DIR` (a directory of sessions →
combined tables + gate verdict). The markdown output should paste
directly into D8 — that is the acceptance test for the format.

Implementation notes: interpolation via `np.interp` per component is
fine for GNSS-rate truth; guard against extrapolation at the ends (trim
to overlap). The clap finder for twin sessions uses the twin's recorded
event time (the twin writes one into its truth sidecar — if your
lesson 07 twin doesn't, add it now; five lines).

## Verify

All of this is VT-17 territory: the twin knows the answers.

- **Zero-noise identity.** Twin with all noise off, fused track replaced
  by truth-resampled-to-epochs: every RMS is ~0, continuity 1.0, gate
  passes. Catches sign errors and interpolation bugs before anything
  subtle.
- **Known-noise consistency.** Twin with noise on: run the real
  pipeline, compare measured pos/vel RMS against the values predicted
  from the injected σ_θ / σ_vr through the D3 geometry (you computed
  these in lessons 12–13). Agreement within ~25% is consistent —
  residuals also carry filter transients; perfect agreement would be
  suspicious. Record the comparison in `results/VT-17/`.
- **Alignment tripwire.** Shift one station's timestamps by +100 ms in a
  copied twin session. The event check must flag it and report the
  offset to within a frame time; the Sync column must read degraded.
- **Gate arithmetic.** Unit-test `gate()` with synthetic metric lists:
  8/10 passes, 7/10 fails, and the boundary where one flight's
  continuity alone fails it.
- **Schema check.** Diff your markdown table headers against D8's
  literally (the D8 HTML is in `docs/`) — column-for-column.

## Explore

- **The 1-meter millisecond.** D3 argues 1/30 s at 30 m/s ≈ 1 m — timing
  masquerades as position error. Sweep injected inter-station offsets
  (1/5/20/50 ms) and plot resulting pos RMS. Where does the SYS-006
  budget of 5 ms sit on that curve, and does it justify itself?
- **p95 vs RMS.** Construct a twin session with one long sun-crossing
  dropout. Which metric moves more, and why does D8 carry both?
- **Band honesty.** Compare bands computed from the EKF's *predicted*
  covariance against bands from *measured* residuals. If the filter were
  perfectly tuned they'd agree; the ratio is your tuning scorecard.

## Checkpoint

- `maiden validate --session <twin dir>` produces `report.json` +
  `report.md` with D8-schema tables and a gate verdict.
- The zero-noise identity test and the alignment tripwire both pass;
  results of the known-noise consistency run are committed under
  `results/VT-17/`.
- The gate function is unit-tested including boundary cases.
- `bands.json` exists from a twin campaign run and lesson 24 has an
  interface to consume it.
- You can explain, without notes, why truth is interpolated to the fused
  epochs and not the other way around.
