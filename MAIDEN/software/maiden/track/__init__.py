"""maiden.track — video tracker (lessons 10-11).

Front half (this sprint, maiden19): candidate generation — SkyModel,
propose(), features. Back half (maiden20-21): detector scoring, 2-D
Kalman tracks, az/el emission.
"""

from maiden.track.candidates import Candidate, SkyModel, propose

__all__ = ["Candidate", "SkyModel", "propose"]
