"""Event-level evaluation. The metric that matters for this product is false alarms per hour of
non-freezing activity; window-level accuracy hides how often a patient would be cued wrongly."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .detector import FoGEvent

MATCH_TOLERANCE_SEC = 2.0


@dataclass
class EvalResult:
    episodes: int = 0
    detected: int = 0
    episodes_long: int = 0
    detected_long: int = 0
    false_alarms: int = 0
    non_fog_hours: float = 0.0
    latencies: list[float] = field(default_factory=list)

    def add(self, other: "EvalResult") -> "EvalResult":
        return EvalResult(
            self.episodes + other.episodes,
            self.detected + other.detected,
            self.episodes_long + other.episodes_long,
            self.detected_long + other.detected_long,
            self.false_alarms + other.false_alarms,
            self.non_fog_hours + other.non_fog_hours,
            self.latencies + other.latencies,
        )

    @property
    def sensitivity(self) -> float:
        return self.detected / self.episodes if self.episodes else float("nan")

    @property
    def sensitivity_long(self) -> float:
        return self.detected_long / self.episodes_long if self.episodes_long else float("nan")

    @property
    def fa_per_hour(self) -> float:
        return self.false_alarms / self.non_fog_hours if self.non_fog_hours else float("nan")

    @property
    def median_latency(self) -> float:
        return float(np.median(self.latencies)) if self.latencies else float("nan")

    def summary(self) -> dict:
        return {
            "episodes": self.episodes,
            "detected": self.detected,
            "sensitivity": round(self.sensitivity, 3),
            "episodes_ge_5s": self.episodes_long,
            "sensitivity_ge_5s": round(self.sensitivity_long, 3),
            "false_alarms": self.false_alarms,
            "non_fog_hours": round(self.non_fog_hours, 2),
            "false_alarms_per_hour": round(self.fa_per_hour, 2),
            "median_latency_s": round(self.median_latency, 2),
        }


def evaluate(events: list[FoGEvent], episodes: list[tuple[float, float]], non_fog_hours: float,
             long_sec: float = 5.0) -> EvalResult:
    """An episode counts as cued if any cue is running at some point inside it (a cue that started
    for an earlier freeze and is still playing does help the patient). A cue is a false alarm if its
    whole run overlaps no episode, with MATCH_TOLERANCE_SEC slack for annotation boundaries."""
    tol = MATCH_TOLERANCE_SEC
    res = EvalResult(episodes=len(episodes), non_fog_hours=non_fog_hours)
    spans = [(ev.confirmed_t, ev.end_t if ev.end_t is not None else ev.confirmed_t) for ev in events]
    for s, e in episodes:
        is_long = (e - s) >= long_sec
        res.episodes_long += int(is_long)
        starts = [a for a, b in spans if a <= e + tol and b >= s - tol]
        if starts:
            res.detected += 1
            res.detected_long += int(is_long)
            res.latencies.append(max(0.0, float(min(starts) - s)))
    for a, b in spans:
        if not any(a <= e + tol and b >= s - tol for s, e in episodes):
            res.false_alarms += 1
    return res
