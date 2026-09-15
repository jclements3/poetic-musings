"""2-D constant-velocity pixel-space Kalman filter (lesson 11, maiden20).

The lesson-12 EKF's little sibling: same predict/update algebra, two
dimensions, linear H — debugged here in pixel space so the innovation
monitoring, gate tuning, and Q-vs-R instincts transfer to ENU.

State x = [u, v, u_dot, v_dot] (px, px/s).  White-acceleration model:

    F = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
    Q = q * [[dt^4/4, dt^3/2],      (per axis, coupled pos/vel block)
             [dt^3/2, dt^2  ]]
    H = [[1,0,0,0],[0,1,0,0]],  R = sigma_px^2 * I2

q has units px^2/s^3 (acceleration PSD); maiden20 computes it from the
twin's worst pixel acceleration (see sweep_detector.py) instead of
guessing — the tuned default rides in TrackerCfg, not here.
"""

import numpy as np


class Kalman2D:
    def __init__(self, dt: float, q: float, sigma_px: float = 1.0):
        self.dt = float(dt)
        self.q = float(q)
        self.F = np.array([[1, 0, dt, 0],
                           [0, 1, 0, dt],
                           [0, 0, 1, 0],
                           [0, 0, 0, 1]], dtype=float)
        d4, d3, d2 = dt**4 / 4.0, dt**3 / 2.0, dt**2
        blk = q * np.array([[d4, d3], [d3, d2]])
        self.Q = np.zeros((4, 4))
        for i in (0, 1):                       # (pos_i, vel_i) coupling
            self.Q[np.ix_([i, i + 2], [i, i + 2])] = blk
        self.H = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=float)
        self.R = np.eye(2) * sigma_px**2
        self.x = np.zeros(4)
        self.P = np.eye(4) * 1e6               # uninitialized until start()
        self._started = False

    def start(self, z, v0=(0.0, 0.0), sigma_v: float = 50.0):
        """Initialize at a measurement with loose velocity."""
        self.x = np.array([z[0], z[1], v0[0], v0[1]], dtype=float)
        self.P = np.diag([self.R[0, 0], self.R[1, 1], sigma_v**2, sigma_v**2])
        self._started = True

    @property
    def uv(self):
        return float(self.x[0]), float(self.x[1])

    def predict(self):
        self.x = self.F @ self.x
        self.P = self.F @ self.P @ self.F.T + self.Q
        return self.uv

    def _innovation(self, z):
        y = np.asarray(z, dtype=float) - self.H @ self.x
        s = self.H @ self.P @ self.H.T + self.R
        return y, s

    def mahalanobis(self, z) -> float:
        """Squared Mahalanobis distance of z to the prediction (2 dof)."""
        y, s = self._innovation(z)
        return float(y @ np.linalg.solve(s, y))

    def update(self, z) -> float:
        """Measurement update; returns the NIS (chi^2, 2 dof) of z."""
        y, s = self._innovation(z)
        nis = float(y @ np.linalg.solve(s, y))
        k = self.P @ self.H.T @ np.linalg.inv(s)
        self.x = self.x + k @ y
        i_kh = np.eye(4) - k @ self.H
        self.P = i_kh @ self.P @ i_kh.T + k @ self.R @ k.T   # Joseph form
        return nis
