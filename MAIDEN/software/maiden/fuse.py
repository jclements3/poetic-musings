"""maiden.fuse — the 3-station fusion EKF. SYS-001..004; D6 "Fusion EKF".

State x = [E N U vE vN vU] in the field frame (IF-4). Measurements:
station-frame az/el pairs (deg at the IF-4 boundary, radians inside) and
radial velocity v_r with the pinned sign convention: POSITIVE = RECEDING
from the station, h = d(range)/dt — matching the twin's Doppler model
(maiden.twin.sensors.vr_from_state) and, eventually, the bench chain.

Geometry reuses maiden.twin.sensors' helpers (station_azel, vr_from_state,
azel_from_pos are pure geometry, not twin fiction); only the Jacobians are
hand-derived here, per lesson 12/13, and finite-difference-tested.

Validity is a DERIVED property, not an IF-4 field: a FUSED sample is
valid while sqrt(trace(P_pos)) <= VALID_POS_M. VALID_POS_M = 3.0 m is a
course constant (~3x SYS-002) — revisit after the validation campaign.
IF-4 stays frozen; use is_valid(sample).

Thresholds cited from D2 (SYS-002/003/004) are NOT restated here —
they live in config/thresholds.yaml (maiden28); validate.py reads it.
"""

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from maiden.geo import Pose, enu_from_lla
from maiden.state import StateSample
from maiden.twin.sensors import station_azel, vr_from_state

# chi-square 0.999 quantiles, per lesson 13 (m -> gamma_max)
CHI2_GATE = {1: 10.83, 2: 13.82}
VALID_POS_M = 3.0          # course constant; revisit after the campaign
_PARALLEL_EPS = 1e-6       # 1 - c^2 guard for the two-ray initializer


@dataclass
class EkfConfig:
    # sigma_a from the maiden23 sweep over {5, 10, 20, 40} m/s^2 on the
    # clean twin (results/lesson12/rms.txt): 10 and 20 tie within noise;
    # 20 keeps maneuver lag lower on the imperfect run, so 20 it is.
    sigma_a: float = 20.0        # m/s^2 white-accel process noise, per axis
    sigma_theta: float = 0.5e-3  # rad, per D3's error budget
    sigma_vr: float = 0.15       # m/s, twin's injected value; bench at VT-04


@dataclass
class FuseStats:
    n_updates: int = 0
    n_gated: int = 0
    coast_time: float = 0.0     # epoch time published >COAST_GAP after an update
    valid_time: float = 0.0     # epoch time with sqrt(tr(P_pos)) <= VALID_POS_M
    n_epochs: int = 0
    t_first: float | None = None
    t_last: float | None = None

    @property
    def gate_rate(self) -> float:
        n = self.n_updates + self.n_gated
        return self.n_gated / n if n else 0.0


COAST_GAP = 0.2  # s without an applied update before an epoch counts as coasting


# --- geometry ---------------------------------------------------------------

def _station_matrix(pose: Pose) -> np.ndarray:
    """M: ENU -> station frame (xs=right, ys=forward, zs=up). Lesson 12."""
    h = np.radians(pose.heading_deg)
    c, s = np.cos(h), np.sin(h)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def azel_to_unit(az_deg: float, el_deg: float, pose: Pose) -> np.ndarray:
    """Station-frame az/el (deg) -> ENU unit vector. Inverse of h_azel."""
    az = np.radians(az_deg + pose.heading_deg)   # back to true-north az
    el = np.radians(el_deg)
    ce = np.cos(el)
    return np.array([ce * np.sin(az), ce * np.cos(az), np.sin(el)])


def h_azel(p: np.ndarray, pose: Pose) -> np.ndarray:
    """Measurement model: [az, el] radians, az station-frame."""
    az_deg, el_deg = station_azel(p.reshape(1, 3), pose)
    return np.radians([az_deg[0], el_deg[0]])


def jac_azel(p: np.ndarray, pose: Pose) -> np.ndarray:
    """Analytic 2x6 Jacobian of h_azel, per lesson 12 'The Jacobian, fully'."""
    m = _station_matrix(pose)
    d = np.asarray(p, float) - np.asarray(pose.pos_enu, float)
    xs, ys, zs = m @ d
    rho2 = xs * xs + ys * ys
    rho = np.sqrt(rho2)
    r2 = rho2 + zs * zs
    j_station = np.array([
        [ys / rho2, -xs / rho2, 0.0],
        [-xs * zs / (r2 * rho), -ys * zs / (r2 * rho), rho / r2],
    ])
    h = np.zeros((2, 6))
    h[:, :3] = j_station @ m
    return h


def h_vr(x: np.ndarray, pose: Pose) -> float:
    """v . u_hat, positive receding — same code path as the twin's model."""
    return float(vr_from_state(x[:3].reshape(1, 3), x[3:].reshape(1, 3),
                               pose)[0])


def jac_vr(x: np.ndarray, pose: Pose) -> np.ndarray:
    """1x6: [ v^T (I - u u^T)/||d||,  u^T ] — position block included."""
    d = x[:3] - np.asarray(pose.pos_enu, float)
    nd = np.linalg.norm(d)
    u = d / nd
    h = np.zeros((1, 6))
    h[0, :3] = x[3:] @ (np.eye(3) - np.outer(u, u)) / nd
    h[0, 3:] = u
    return h


def _wrap_pi(a: float) -> float:
    return (a + np.pi) % (2.0 * np.pi) - np.pi


# --- the filter -------------------------------------------------------------

class Ekf:
    def __init__(self, cfg: EkfConfig | None = None):
        self.cfg = cfg or EkfConfig()
        self.t: float | None = None
        self.x: np.ndarray | None = None    # (6,)
        self.p: np.ndarray | None = None    # (6,6)

    @property
    def state(self) -> np.ndarray:
        return self.x

    @property
    def cov(self) -> np.ndarray:
        return self.p

    def init_two_ray(self, za, zb, pose_a: Pose, pose_b: Pose,
                     t: float) -> bool:
        """Closed-form closest-points init from one A+B az/el pair (deg).

        Returns False (filter untouched) when the rays are near-parallel —
        the baseline-extension singularity the 1-c^2 term guards.
        """
        ua = azel_to_unit(za[0], za[1], pose_a)
        ub = azel_to_unit(zb[0], zb[1], pose_b)
        sa = np.asarray(pose_a.pos_enu, float)
        sb = np.asarray(pose_b.pos_enu, float)
        w = sb - sa
        c = float(ua @ ub)
        denom = 1.0 - c * c
        if denom < _PARALLEL_EPS:
            return False
        ta = (w @ ua - c * (w @ ub)) / denom
        tb = (c * (w @ ua) - w @ ub) / denom
        p0 = 0.5 * (sa + ta * ua + sb + tb * ub)
        # P seed: D3 sigma_range ~ R^2 sigma_theta / B along-range;
        # conservative isotropic position block, sigma_v = 30 m/s velocity.
        rng_m = max(0.5 * (abs(ta) + abs(tb)), 1.0)
        base = max(np.linalg.norm(w), 1.0)
        sig_pos = max(rng_m**2 * self.cfg.sigma_theta / base, 0.5)
        self.x = np.concatenate([p0, np.zeros(3)])
        self.p = np.diag([sig_pos**2] * 3 + [30.0**2] * 3)
        self.t = float(t)
        return True

    def predict(self, t: float) -> None:
        dt = float(t) - self.t
        if dt < 0:
            raise ValueError(f"predict backwards: dt={dt}")
        if dt == 0.0:
            return
        f = np.eye(6)
        f[:3, 3:] = dt * np.eye(3)
        q1 = self.cfg.sigma_a**2
        q = np.zeros((6, 6))
        for i in range(3):
            q[i, i] = q1 * dt**4 / 4.0
            q[i, i + 3] = q[i + 3, i] = q1 * dt**3 / 2.0
            q[i + 3, i + 3] = q1 * dt**2
        self.x = f @ self.x
        self.p = f @ self.p @ f.T + q
        self.t = float(t)

    def gate(self, y: np.ndarray, s: np.ndarray, m: int) -> bool:
        """True = REJECT: gamma = y' S^-1 y beyond the chi2(m) 0.999 cut."""
        gamma = float(y @ np.linalg.solve(s, y))
        return gamma > CHI2_GATE[m]

    def _apply(self, y, h, r):
        s = h @ self.p @ h.T + r
        k = self.p @ h.T @ np.linalg.inv(s)
        self.x = self.x + k @ y
        ikh = np.eye(6) - k @ h
        self.p = ikh @ self.p @ ikh.T + k @ r @ k.T   # Joseph form

    def update_azel(self, z_deg, pose: Pose, *, gated: bool = True) -> bool:
        """z = (az_deg, el_deg) station frame. Returns True if applied."""
        z = np.radians(np.asarray(z_deg, float))
        y = z - h_azel(self.x[:3], pose)
        y[0] = _wrap_pi(y[0])       # the lesson-12 trap: az crosses +-180
        h = jac_azel(self.x[:3], pose)
        r = np.eye(2) * self.cfg.sigma_theta**2
        if gated and self.gate(y, h @ self.p @ h.T + r, 2):
            return False
        self._apply(y, h, r)
        return True

    def update_vr(self, vr: float, pose: Pose,
                  sigma_vr: float | None = None, *, gated: bool = True) -> bool:
        sig = self.cfg.sigma_vr if sigma_vr is None else sigma_vr
        y = np.array([vr - h_vr(self.x, pose)])
        h = jac_vr(self.x, pose)
        r = np.array([[sig**2]])
        if gated and self.gate(y, h @ self.p @ h.T + r, 1):
            return False
        self._apply(y, h, r)
        return True

    def fused_sample(self, valid_hint: bool = True) -> StateSample:
        return StateSample(t_utc=self.t, source="FUSED",
                           pos_enu=tuple(self.x[:3]),
                           vel_enu=tuple(self.x[3:]),
                           cov=self.p.copy())


def is_valid(sample: StateSample) -> bool:
    """Derived validity flag (IF-4 stays frozen; see module docstring)."""
    return (sample.cov is not None
            and float(np.sqrt(np.trace(sample.cov[:3, :3]))) <= VALID_POS_M)


# --- drivers ----------------------------------------------------------------

FRAME_DT = 1.0 / 30.0   # "within one frame time" for the init pair


def _azel_streams(samples):
    """Sorted az/el measurements as (t, source, az, el) tuples."""
    ms = [(s.t_utc, s.source, s.az_deg, s.el_deg)
          for s in samples if s.az_deg is not None]
    ms.sort(key=lambda m: m[0])
    return ms


def _try_init(ekf, pending, m, stations):
    """Buffer az/el per station; init on an A+B pair within FRAME_DT."""
    _t, src, _az, _el = m
    pending[src] = m
    for a, b in (("A", "B"),):
        if a in pending and b in pending:
            ma, mb = pending[a], pending[b]
            if (abs(ma[0] - mb[0]) <= FRAME_DT
                    and ekf.init_two_ray((ma[2], ma[3]), (mb[2], mb[3]),
                                         stations[a], stations[b],
                                         max(ma[0], mb[0]))):
                return True
    return False


def fuse_azel_only(samples: Iterable[StateSample],
                   stations: dict[str, Pose]) -> list[StateSample]:
    """Lesson 12 driver: A+B angles only, FUSED sample per applied update.

    Kept working verbatim after lesson 13 — CI's degraded-mode test.
    """
    ekf = Ekf()
    out: list[StateSample] = []
    pending: dict[str, tuple] = {}
    for m in _azel_streams(samples):
        t, src, az, el = m
        if src not in ("A", "B"):
            continue
        if ekf.x is None:
            _try_init(ekf, pending, m, stations)
            continue
        ekf.predict(t)
        if ekf.update_azel((az, el), stations[src]):
            out.append(ekf.fused_sample())
    return out


def fuse(samples: Iterable[StateSample], stations: dict[str, Pose],
         epoch_hz: float = 50.0) -> tuple[list[StateSample], FuseStats]:
    """Full scheduler per lesson 13: sequential predict-to-measurement
    with gating, coast through gaps, publish on the uniform epoch grid.
    """
    cfg = EkfConfig()
    ekf = Ekf(cfg)
    stats = FuseStats()
    out: list[StateSample] = []
    pending: dict[str, tuple] = {}
    dt_e = 1.0 / epoch_hz

    ms = []
    for s in samples:
        if s.source not in stations:
            continue
        if s.az_deg is not None:
            ms.append((s.t_utc, s.source, "azel", (s.az_deg, s.el_deg)))
        if s.v_r is not None:
            ms.append((s.t_utc, s.source, "vr", s.v_r))
    ms.sort(key=lambda m: m[0])
    if not ms:
        return out, stats
    stats.t_first, stats.t_last = ms[0][0], ms[-1][0]

    next_epoch = None
    t_last_applied = None
    for t, src, kind, z in ms:
        if ekf.x is None:
            if kind == "azel" and _try_init(ekf, pending,
                                            (t, src, z[0], z[1]), stations):
                next_epoch = (np.floor(ekf.t / dt_e) + 1.0) * dt_e
                t_last_applied = ekf.t
            continue
        while next_epoch <= t:
            ekf.predict(next_epoch)
            smp = ekf.fused_sample()
            out.append(smp)
            stats.n_epochs += 1
            if is_valid(smp):
                stats.valid_time += dt_e
            if t_last_applied is None or next_epoch - t_last_applied > COAST_GAP:
                stats.coast_time += dt_e
            next_epoch += dt_e
        ekf.predict(t)
        if kind == "azel":
            ok = ekf.update_azel(z, stations[src])
        else:
            ok = ekf.update_vr(z, stations[src])
        if ok:
            stats.n_updates += 1
            t_last_applied = t
        else:
            stats.n_gated += 1
    return out, stats


# --- session front end ------------------------------------------------------

def poses_from_session(session_dir) -> dict[str, Pose]:
    """Station Poses from the session's own TMATS (works for twin or real).

    Field-frame origin is Station A's survey mark, per IF-4.
    """
    from maiden.ingest import describe
    descs = {}
    for p in sorted(Path(session_dir).glob("STATION_*.ch10")):
        d = describe(p)
        descs[d.id] = d
    if "A" not in descs:
        raise ValueError(f"no STATION_A file in {session_dir}")
    for sid, d in descs.items():
        if d.survey_lla is None or d.heading_deg is None:
            raise ValueError(
                f"station {sid}: TMATS carries no usable survey "
                "(C\\MAIDEN\\SURVEY\\* missing or malformed) — re-record "
                "or fix the TMATS; fusion cannot pose the station")
    origin = descs["A"].survey_lla
    return {sid: Pose(tuple(enu_from_lla(origin, d.survey_lla)),
                      d.heading_deg)
            for sid, d in descs.items()}


def fuse_session(session_dir, epoch_hz: float = 50.0):
    """Ingest every station file in a session directory and fuse."""
    from maiden.ingest import load
    samples = []
    for p in sorted(Path(session_dir).glob("STATION_*.ch10")):
        samples.extend(load(p))
    stations = poses_from_session(session_dir)
    return fuse(samples, stations, epoch_hz=epoch_hz), stations


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(prog="maiden fuse")
    ap.add_argument("--session", required=True)
    ap.add_argument("--epoch-hz", type=float, default=50.0)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    (fused, stats), _ = fuse_session(args.session, epoch_hz=args.epoch_hz)
    out = Path(args.out or Path(args.session) / "fused.npz")
    span = (stats.t_last - stats.t_first) if stats.n_epochs else 0.0
    continuity = min(stats.valid_time / span, 1.0) if span else 0.0
    np.savez(out,
             t_utc=np.array([s.t_utc for s in fused]),
             pos_enu=np.array([s.pos_enu for s in fused]),
             vel_enu=np.array([s.vel_enu for s in fused]),
             cov=np.array([s.cov for s in fused]),
             valid=np.array([is_valid(s) for s in fused]))
    print(f"fused {stats.n_updates} updates ({stats.n_gated} gated, "
          f"rate {100 * stats.gate_rate:.2f}%), {stats.n_epochs} epochs, "
          f"coast {stats.coast_time:.2f}s, continuity {continuity:.4f} "
          f"-> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
