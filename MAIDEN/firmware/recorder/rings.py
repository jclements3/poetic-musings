"""Bounded per-channel ring buffers with the never-drop discipline.

Lesson 19: a full ring increments a per-channel drop counter and
discards the NEWEST item (the capture thread must never block), and the
counters ride in-band in Ch 6 status (see PROTOCOL.md, STATION_STATUS).
High-water marks exist for Explore 1's stall-injection sizing pass.
"""
import threading
from collections import deque


class Ring:
    """FIFO of (rtc, item); push never blocks, overflow drops newest."""

    def __init__(self, name: str, capacity: int):
        if capacity < 1:
            raise ValueError("capacity must be >= 1")
        self.name = name
        self.capacity = capacity
        self.drops = 0
        self.high_water = 0
        self._q: deque = deque()
        self._lock = threading.Lock()

    def push(self, rtc: int, item) -> bool:
        """Append; on overflow count and discard THIS (newest) item."""
        with self._lock:
            if len(self._q) >= self.capacity:
                self.drops += 1
                return False
            self._q.append((rtc, item))
            self.high_water = max(self.high_water, len(self._q))
            return True

    def pop(self):
        with self._lock:
            return self._q.popleft()

    def head_rtc(self):
        with self._lock:
            return self._q[0][0] if self._q else None

    def __len__(self):
        with self._lock:
            return len(self._q)
