"""Streaming multi-gate FoG detector (reference implementation).

Mirrors `Packages/FoGCore/Sources/FoGCore/FoGDetector.swift` one-to-one. Any change here must be
made there too; `research/export_fixtures.py` produces golden fixtures the Swift tests replay.

Gates (all must pass before a cue fires):
  1. Freeze evidence: the logistic model's FoG probability >= prob_threshold (or, without a
     model, freeze index >= fi_threshold), AND total band power >= stand_power_min so quiet
     standing or sitting can never look like a freeze.
  2. Context (optional, on by default in the conservative profile): sustained gait
     (>= min_walk_sec) ended no more than arm_timeout_sec ago. Removes cues while seated or at
     rest at the cost of missing start-hesitation freezes, which the manual "Help me walk"
     button covers.
  3. Persistence: the evidence holds for >= confirm_sec (max_gap_hops dropout tolerated).
A cue then runs until walking resumes (resume_walk_sec), the person goes still, or max_cue_sec.
A refractory period follows to avoid immediate re-triggering.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum

from .features import WindowFeatures
from .model import ContextFeaturizer, LogisticModel


@dataclass
class DetectorConfig:
    window_sec: float = 3.0
    hop_sec: float = 0.5
    walk_power_min: float = 0.001
    walk_fi_max: float = 2.0
    walk_freq_min: float = 0.6
    walk_freq_max: float = 2.6
    min_walk_sec: float = 3.0
    arm_timeout_sec: float = 5.0
    fi_threshold: float = 3.0
    prob_threshold: float = 0.7
    stand_power_min: float = 0.001
    confirm_sec: float = 1.5
    max_gap_hops: int = 1
    resume_walk_sec: float = 2.0
    still_end_sec: float = 3.0
    max_cue_sec: float = 30.0
    refractory_sec: float = 3.0
    require_prior_walking: bool = True
    use_model: bool = True

    def to_dict(self) -> dict:
        return asdict(self)


class Phase(str, Enum):
    MONITORING = "monitoring"
    CANDIDATE = "candidate"
    CUEING = "cueing"
    REFRACTORY = "refractory"


class EndReason(str, Enum):
    WALKING_RESUMED = "walking_resumed"
    STILL = "still"
    TIMEOUT = "timeout"
    MANUAL = "manual"


@dataclass
class FoGEvent:
    onset_t: float
    confirmed_t: float
    end_t: float | None = None
    end_reason: EndReason | None = None
    peak_score: float = 0.0


@dataclass
class FoGDetector:
    cfg: DetectorConfig = field(default_factory=DetectorConfig)
    model: LogisticModel | None = None
    featurizer: ContextFeaturizer = field(default_factory=ContextFeaturizer)
    phase: Phase = Phase.MONITORING
    walk_run: float = 0.0
    last_sustained_walk_t: float = float("-inf")
    candidate_start: float = 0.0
    candidate_run: float = 0.0
    gap_hops: int = 0
    still_run: float = 0.0
    refractory_until: float = float("-inf")
    last_score: float = 0.0
    active: FoGEvent | None = None
    events: list[FoGEvent] = field(default_factory=list)

    def is_walking(self, f: WindowFeatures) -> bool:
        c = self.cfg
        return (
            f.loco_power >= c.walk_power_min
            and f.freeze_index <= c.walk_fi_max
            and c.walk_freq_min <= f.dominant_freq <= c.walk_freq_max
        )

    def score(self, f: WindowFeatures) -> float:
        """FoG probability from the model, or the raw freeze index when no model is loaded."""
        ctx = self.featurizer.push(f)
        if self.cfg.use_model:
            if self.model is None:
                raise ValueError("use_model is set but no model is loaded")
            return self.model.prob(ctx)
        return f.freeze_index

    def evidence(self, f: WindowFeatures, score: float) -> bool:
        c = self.cfg
        threshold = c.prob_threshold if c.use_model else c.fi_threshold
        return score >= threshold and f.total_power >= c.stand_power_min

    def armed(self, t: float) -> bool:
        if not self.cfg.require_prior_walking:
            return True
        return (t - self.last_sustained_walk_t) <= self.cfg.arm_timeout_sec

    def update(self, f: WindowFeatures, precomputed_score: float | None = None) -> FoGEvent | None:
        """Feed one window. Returns the event when a cue is newly confirmed, else None.

        `precomputed_score` lets offline evaluation vectorise model inference; it must equal
        what `score(f)` would return for the same stream.
        """
        c = self.cfg
        t = f.t_end
        hop = c.hop_sec
        walking = self.is_walking(f)
        s = self.score(f) if precomputed_score is None else precomputed_score
        self.last_score = s
        freeze_like = self.evidence(f, s)

        self.walk_run = self.walk_run + hop if walking else 0.0
        if self.walk_run >= c.min_walk_sec:
            self.last_sustained_walk_t = t

        if self.phase == Phase.REFRACTORY and t >= self.refractory_until:
            self.phase = Phase.MONITORING

        if self.phase == Phase.MONITORING:
            if freeze_like and self.armed(t):
                self.phase = Phase.CANDIDATE
                self.candidate_start = t
                self.candidate_run = hop
                self.gap_hops = 0
                return self._maybe_confirm(t, s)
            return None

        if self.phase == Phase.CANDIDATE:
            if freeze_like:
                self.candidate_run += hop
                self.gap_hops = 0
                return self._maybe_confirm(t, s)
            self.gap_hops += 1
            if self.gap_hops > c.max_gap_hops or walking:
                self.phase = Phase.MONITORING
                self.candidate_run = 0.0
            return None

        if self.phase == Phase.CUEING:
            assert self.active is not None
            self.active.peak_score = max(self.active.peak_score, s)
            quiet = f.total_power < c.stand_power_min
            self.still_run = self.still_run + hop if quiet else 0.0
            if self.walk_run >= c.resume_walk_sec:
                self._end(t, EndReason.WALKING_RESUMED)
                self.last_sustained_walk_t = t
            elif self.still_run >= c.still_end_sec:
                self._end(t, EndReason.STILL)
            elif t - self.active.confirmed_t >= c.max_cue_sec:
                self._end(t, EndReason.TIMEOUT)
        return None

    def _maybe_confirm(self, t: float, s: float) -> FoGEvent | None:
        if self.candidate_run + 1e-9 < self.cfg.confirm_sec:
            return None
        onset = self.candidate_start - self.cfg.hop_sec
        self.active = FoGEvent(onset_t=onset, confirmed_t=t, peak_score=s)
        self.events.append(self.active)
        self.phase = Phase.CUEING
        self.still_run = 0.0
        return self.active

    def _end(self, t: float, reason: EndReason) -> None:
        assert self.active is not None
        self.active.end_t = t
        self.active.end_reason = reason
        self.active = None
        self.phase = Phase.REFRACTORY
        self.refractory_until = t + self.cfg.refractory_sec
        self.candidate_run = 0.0

    def stop_manually(self, t: float) -> None:
        if self.phase == Phase.CUEING:
            self._end(t, EndReason.MANUAL)


def run(features: list[WindowFeatures], cfg: DetectorConfig, model: LogisticModel | None = None,
        scores=None) -> list[FoGEvent]:
    det = FoGDetector(cfg=cfg, model=model)
    for i, f in enumerate(features):
        det.update(f, None if scores is None else float(scores[i]))
    if det.active is not None:
        det._end(features[-1].t_end, EndReason.TIMEOUT)
    return det.events
