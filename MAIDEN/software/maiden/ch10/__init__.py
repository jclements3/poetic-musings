"""maiden.ch10 — minimal IRIG-106 Chapter 10 packet I/O (D4 IF-1 subset)."""

from . import packet
from .reader import Ch10Error, read_packets
from .writer import Ch10Writer

__all__ = ["Ch10Error", "Ch10Writer", "packet", "read_packets"]
